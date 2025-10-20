# frozen_string_literal: true

require "net/http"
require_relative "../debug_mixin"
require_relative "../concurrency"

module Aidp
  module Harness
    # Handles error recovery, retry strategies, and fallback mechanisms
    class ErrorHandler
      include Aidp::DebugMixin

      def initialize(provider_manager, configuration, metrics_manager = nil)
        @provider_manager = provider_manager
        @configuration = configuration
        @metrics_manager = metrics_manager
        @retry_strategies = {}
        @retry_counts = {}
        @error_history = []
        @circuit_breakers = {}
        @backoff_calculator = BackoffCalculator.new
        @error_classifier = ErrorClassifier.new
        @recovery_planner = RecoveryPlanner.new
        initialize_retry_strategies
      end

      # Get error statistics
      def error_stats
        {
          total_errors: @error_history.size,
          error_types: @error_history.group_by { |e| e[:error_type] }.transform_values(&:size),
          recent_errors: @error_history.last(10),
          retry_counts: @retry_counts.dup,
          circuit_breaker_states: @circuit_breakers.transform_values { |cb| cb[:state] }
        }
      end

      # Main entry point for error handling
      def handle_error(error, context = {})
        error_info = @error_classifier.classify_error(error, context)

        # Debug logging
        debug_error(error, context)
        debug_log("🔧 ErrorHandler: Processing error", level: :info, data: {
          error_type: error_info[:error_type],
          provider: error_info[:provider],
          model: error_info[:model]
        })

        # Record error in metrics if available
        @metrics_manager&.record_error(error_info[:provider], error_info[:model], error_info)

        # Add to error history
        @error_history << error_info

        # Get retry strategy for this error type
        strategy = retry_strategy(error_info[:error_type])

        # Check if we should retry
        if should_retry?(error_info, strategy)
          debug_log("🔄 ErrorHandler: Attempting retry", level: :info, data: {
            strategy: strategy[:name],
            max_retries: strategy[:max_retries]
          })
          execute_retry(error_info, strategy, context)

        else
          # No retry, attempt recovery
          debug_log("🚨 ErrorHandler: No retry, attempting recovery", level: :warn, data: {
            error_type: error_info[:error_type],
            reason: "Retry not applicable or exhausted"
          })
          if [:authentication, :permission_denied].include?(error_info[:error_type].to_sym)
            # Mark provider unhealthy to avoid immediate re-selection
            begin
              if @provider_manager.respond_to?(:mark_provider_auth_failure)
                @provider_manager.mark_provider_auth_failure(error_info[:provider])
                debug_log("🔐 Marked provider #{error_info[:provider]} unhealthy due to auth error", level: :warn)
              end
            rescue => e
              debug_log("⚠️ Failed to mark provider unhealthy after auth error", level: :warn, data: {error: e.message})
            end
          end
          attempt_recovery(error_info, context)

        end
      end

      # Execute a block with retry logic
      def execute_with_retry(&block)
        providers_tried = []

        loop do
          max_attempts = @configuration.max_retries + 1
          attempt = 0

          begin
            attempt += 1
            return yield
          rescue => error
            current_provider = current_provider_safely

            if attempt < max_attempts
              error_info = {
                error: error,
                provider: current_provider,
                model: current_model_safely,
                error_type: @error_classifier.classify_error(error)
              }

              strategy = retry_strategy(error_info[:error_type])
              if should_retry?(error_info, strategy)
                delay = @backoff_calculator.calculate_delay(attempt, strategy[:backoff_strategy] || :exponential, 1, 10)
                debug_log("🔁 Retry attempt #{attempt} for #{current_provider}", level: :info, data: {delay: delay, error_type: error_info[:error_type]})
                sleep(delay) if delay > 0
                retry
              end
            end

            # Provider exhausted – attempt recovery (may switch provider)
            debug_log("🚫 Exhausted retries for provider, attempting recovery", level: :warn, data: {provider: current_provider, attempt: attempt, max_attempts: max_attempts})
            handle_error(error, {
              provider: current_provider,
              model: current_model_safely,
              exhausted_retries: true
            })

            new_provider = current_provider_safely
            if new_provider != current_provider && !providers_tried.include?(new_provider)
              providers_tried << current_provider
              # Reset retry counts for the new provider
              begin
                reset_retry_counts(new_provider)
              rescue => e
                debug_log("⚠️ Failed to reset retry counts for new provider", level: :warn, data: {error: e.message})
              end
              debug_log("🔀 Switched provider after failure – re-executing block", level: :info, data: {from: current_provider, to: new_provider})
              # Start retry loop fresh for new provider
              next
            end

            # No new provider (or already tried) – return structured failure
            debug_log("❌ No fallback provider available or all tried", level: :error, data: {providers_tried: providers_tried})
            begin
              if @provider_manager.respond_to?(:mark_provider_failure_exhausted)
                @provider_manager.mark_provider_failure_exhausted(current_provider)
                debug_log("🛑 Marked provider #{current_provider} unhealthy due to exhausted retries", level: :warn)
              end
            rescue => e
              debug_log("⚠️ Failed to mark provider failure-exhausted", level: :warn, data: {error: e.message})
            end
            return {
              status: "failed",
              error: error,
              message: error.message,
              provider: current_provider,
              providers_tried: providers_tried.dup
            }
          end
        end
      end

      # Execute a retry with the given strategy
      def execute_retry(error_info, strategy, context = {})
        provider = error_info[:provider]
        model = error_info[:model]
        error_type = error_info[:error_type]

        # Increment retry count
        retry_key = "#{provider}:#{model}:#{error_type}"
        @retry_counts[retry_key] ||= 0
        @retry_counts[retry_key] += 1

        # Check if we've exceeded max retries
        if @retry_counts[retry_key] > strategy[:max_retries]
          return {
            success: false,
            action: :exhausted_retries,
            error: "Max retries exceeded for #{error_type}",
            retry_count: @retry_counts[retry_key],
            next_action: :fallback
          }
        end

        # Calculate backoff delay
        delay = @backoff_calculator.calculate_delay(
          @retry_counts[retry_key],
          strategy[:backoff_strategy],
          strategy[:base_delay],
          strategy[:max_delay]
        )

        # Wait for backoff delay
        if delay > 0
          sleep(delay)
        end

        # Execute the retry
        retry_result = execute_retry_attempt(error_info, strategy, context)

        # Update retry result with metadata
        retry_result.merge!(
          retry_count: @retry_counts[retry_key],
          delay: delay,
          strategy: strategy[:name]
        )

        retry_result
      end

      # Attempt recovery when retries are exhausted or not applicable
      def attempt_recovery(error_info, context = {})
        recovery_plan = @recovery_planner.create_recovery_plan(error_info, context)

        case recovery_plan[:action]
        when :switch_provider
          attempt_provider_switch(error_info, recovery_plan)
        when :switch_model
          attempt_model_switch(error_info, recovery_plan)
        when :circuit_breaker
          open_circuit_breaker(error_info, recovery_plan)
        when :escalate
          escalate_error(error_info, recovery_plan)
        when :abort
          abort_execution(error_info, recovery_plan)
        else
          {
            success: false,
            action: :unknown_recovery,
            error: "Unknown recovery action: #{recovery_plan[:action]}"
          }
        end
      end

      # Get retry strategy for error type
      def retry_strategy(error_type)
        @retry_strategies[error_type] || @retry_strategies[:default]
      end

      # Get maximum retry attempts
      def max_attempts
        @configuration.respond_to?(:max_retries) ? @configuration.max_retries : 3
      end

      # Check if we should retry based on error type and strategy
      def should_retry?(error_info, strategy)
        return false unless strategy[:enabled]
        return false if error_info[:error_type] == :rate_limit
        return false if error_info[:error_type] == :authentication
        return false if error_info[:error_type] == :permission_denied

        # Check circuit breaker
        circuit_breaker_key = "#{error_info[:provider]}:#{error_info[:model]}"
        return false if circuit_breaker_open?(circuit_breaker_key)

        true
      end

      # Reset retry counts for a specific provider/model combination
      def reset_retry_counts(provider, model = nil)
        keys_to_reset = if model
          # Reset specific model
          @retry_counts.keys.select { |k| k.start_with?("#{provider}:#{model}:") }
        else
          # Reset all models for provider
          @retry_counts.keys.select { |k| k.start_with?("#{provider}:") }
        end

        keys_to_reset.each { |key| @retry_counts.delete(key) }
      end

      # Get retry status for a provider/model
      def retry_status(provider, model = nil)
        keys = if model
          @retry_counts.keys.select { |k| k.start_with?("#{provider}:#{model}:") }
        else
          @retry_counts.keys.select { |k| k.start_with?("#{provider}:") }
        end

        status = {}
        keys.each do |key|
          error_type = key.split(":").last
          status[error_type] = {
            retry_count: @retry_counts[key],
            max_retries: retry_strategy(error_type.to_sym)[:max_retries]
          }
        end

        status
      end

      # Get error history
      def error_history(time_range = nil)
        if time_range
          @error_history.select { |e| time_range.include?(e[:timestamp]) }
        else
          @error_history
        end
      end

      # Clear error history
      def clear_error_history
        @error_history.clear
      end

      # Get circuit breaker status
      def circuit_breaker_status
        @circuit_breakers.transform_values do |cb|
          {
            open: cb[:open],
            opened_at: cb[:opened_at],
            failure_count: cb[:failure_count],
            threshold: cb[:threshold]
          }
        end
      end

      # Reset circuit breaker
      def reset_circuit_breaker(provider, model = nil)
        key = model ? "#{provider}:#{model}" : provider
        @circuit_breakers.delete(key)
      end

      # Reset all circuit breakers
      def reset_all_circuit_breakers
        @circuit_breakers.clear
      end

      private

      def initialize_retry_strategies
        @retry_strategies = {
          # Network errors - retry with exponential backoff
          network_error: {
            name: "network_error",
            enabled: true,
            max_retries: 3,
            backoff_strategy: :exponential,
            base_delay: 1.0,
            max_delay: 30.0,
            jitter: true
          },

          # Server errors - retry with linear backoff
          server_error: {
            name: "server_error",
            enabled: true,
            max_retries: 2,
            backoff_strategy: :linear,
            base_delay: 2.0,
            max_delay: 10.0,
            jitter: true
          },

          # Timeout errors - retry with exponential backoff
          timeout: {
            name: "timeout",
            enabled: true,
            max_retries: 2,
            backoff_strategy: :exponential,
            base_delay: 1.0,
            max_delay: 15.0,
            jitter: true
          },

          # Rate limit errors - no retry, immediate switch
          rate_limit: {
            name: "rate_limit",
            enabled: false,
            max_retries: 0,
            backoff_strategy: :none,
            base_delay: 0.0,
            max_delay: 0.0,
            jitter: false
          },

          # Authentication errors - no retry, escalate
          authentication: {
            name: "authentication",
            enabled: false,
            max_retries: 0,
            backoff_strategy: :none,
            base_delay: 0.0,
            max_delay: 0.0,
            jitter: false
          },

          # Permission denied - no retry, escalate
          permission_denied: {
            name: "permission_denied",
            enabled: false,
            max_retries: 0,
            backoff_strategy: :none,
            base_delay: 0.0,
            max_delay: 0.0,
            jitter: false
          },

          # Default strategy for unknown errors
          default: {
            name: "default",
            enabled: true,
            max_retries: 2,
            backoff_strategy: :exponential,
            base_delay: 1.0,
            max_delay: 20.0,
            jitter: true
          }
        }

        # Override with configuration if available
        if @configuration.respond_to?(:retry_config)
          config_strategies = @configuration.retry_config[:strategies] || {}
          config_strategies.each do |error_type, config|
            @retry_strategies[error_type.to_sym] = @retry_strategies[error_type.to_sym].merge(config)
          end
        end
      end

      def execute_retry_attempt(error_info, _strategy, _context)
        # Execute retry attempt with provider
        # TODO: Integrate with actual provider execution
        {
          success: true,
          action: :retry_attempt,
          provider: error_info[:provider],
          model: error_info[:model],
          error_type: error_info[:error_type]
        }
      end

      def attempt_provider_switch(error_info, _recovery_plan)
        new_provider = @provider_manager.switch_provider_for_error(
          error_info[:error_type],
          error_info[:context]
        )

        if new_provider
          {
            success: true,
            action: :provider_switch,
            new_provider: new_provider,
            reason: "Error recovery: #{error_info[:error_type]}"
          }
        else
          {
            success: false,
            action: :provider_switch_failed,
            error: "No available providers for switch"
          }
        end
      end

      def attempt_model_switch(error_info, _recovery_plan)
        new_model = @provider_manager.switch_model_for_error(
          error_info[:error_type],
          error_info[:context]
        )

        if new_model
          {
            success: true,
            action: :model_switch,
            provider: error_info[:provider],
            new_model: new_model,
            reason: "Error recovery: #{error_info[:error_type]}"
          }
        else
          {
            success: false,
            action: :model_switch_failed,
            error: "No available models for switch"
          }
        end
      end

      def open_circuit_breaker(error_info, recovery_plan)
        key = "#{error_info[:provider]}:#{error_info[:model]}"
        @circuit_breakers[key] = {
          open: true,
          opened_at: Time.now,
          failure_count: recovery_plan[:failure_count] || 1,
          threshold: recovery_plan[:threshold] || 5
        }

        {
          success: true,
          action: :circuit_breaker_opened,
          provider: error_info[:provider],
          model: error_info[:model],
          reason: "Circuit breaker opened due to repeated failures"
        }
      end

      def escalate_error(error_info, recovery_plan)
        {
          success: false,
          action: :escalated,
          error: "Error escalated: #{error_info[:error_type]}",
          escalation_reason: recovery_plan[:reason],
          requires_manual_intervention: true
        }
      end

      def abort_execution(error_info, recovery_plan)
        {
          success: false,
          action: :aborted,
          error: "Execution aborted due to: #{error_info[:error_type]}",
          abort_reason: recovery_plan[:reason]
        }
      end

      def circuit_breaker_open?(key)
        cb = @circuit_breakers[key]
        return false unless cb

        if cb[:open]
          # Check if enough time has passed to try half-open
          timeout = @configuration.respond_to?(:circuit_breaker_config) ?
                   @configuration.circuit_breaker_config[:timeout] : 300

          if Time.now - cb[:opened_at] > timeout
            # Try half-open
            cb[:open] = false
            cb[:half_open_calls] = 0
            return false
          end

          return true
        end

        false
      end

      # Helper classes
      class BackoffCalculator
        def calculate_delay(retry_count, strategy, base_delay, max_delay)
          case strategy
          when :exponential
            delay = base_delay * (2**(retry_count - 1))
          when :linear
            delay = base_delay * retry_count
          when :fixed
            delay = base_delay
          when :none
            return 0.0
          else
            delay = base_delay
          end

          # Apply jitter if enabled
          if strategy != :none
            jitter = delay * 0.1 * (rand - 0.5) # ±10% jitter
            delay += jitter
          end

          # Cap at max delay
          [delay, max_delay].min
        end
      end

      class ErrorClassifier
        def classify_error(error, context = {})
          error_type = classify_error_type(error)

          {
            error: error,
            error_type: error_type,
            provider: (context&.is_a?(Hash) && context[:provider]) || "unknown",
            model: (context&.is_a?(Hash) && context[:model]) || "unknown",
            timestamp: Time.now,
            context: context || {},
            message: error&.message || "Unknown error",
            backtrace: error&.backtrace&.first(5)
          }
        end

        private

        def classify_error_type(error)
          return :unknown if error.nil?

          case error
          when Timeout::Error
            :timeout
          when Net::HTTPError
            case error.response.code.to_i
            when 429
              :rate_limit
            when 401, 403
              :authentication
            when 500..599
              :server_error
            else
              :network_error
            end
          when SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            :network_error
          when StandardError
            # Check error message for common patterns
            message = error.message.downcase

            if message.include?("rate limit") || message.include?("quota")
              :rate_limit
            elsif message.include?("timeout")
              :timeout
            elsif message.include?("auth") || message.include?("permission")
              :authentication
            elsif message.include?("server") || message.include?("internal")
              :server_error
            else
              :default
            end
          else
            :default
          end
        end
      end

      class RecoveryPlanner
        def create_recovery_plan(error_info, _context = {})
          error_type = error_info[:error_type]

          case error_type
          when :rate_limit
            {
              action: :switch_provider,
              reason: "Rate limit reached, switching provider",
              priority: :high
            }
          when :authentication, :permission_denied
            # Previously we escalated immediately. Instead, attempt a provider switch
            # so workflows can continue with alternate providers (e.g., Gemini, Cursor)
            # while the user resolves credentials for the failing provider.
            {
              action: :switch_provider,
              reason: "Authentication/permission issue – switching provider to continue",
              priority: :critical
            }
          when :timeout
            {
              action: :switch_model,
              reason: "Timeout error, trying faster model",
              priority: :medium
            }
          when :network_error
            {
              action: :switch_provider,
              reason: "Network error, switching provider",
              priority: :high
            }
          when :server_error
            {
              action: :switch_provider,
              reason: "Server error, switching provider",
              priority: :medium
            }
          else
            {
              action: :switch_provider,
              reason: "Unknown error, attempting provider switch",
              priority: :low
            }
          end
        end
      end

      # Safe access to provider manager methods that may not exist
      def current_provider_safely
        return "unknown" unless @provider_manager
        return "unknown" unless @provider_manager.respond_to?(:current_provider)

        @provider_manager.current_provider || "unknown"
      rescue => e
        debug_log("⚠️ Failed to get current provider", level: :warn, data: {error: e.message})
        "unknown"
      end

      def current_model_safely
        return "unknown" unless @provider_manager
        return "unknown" unless @provider_manager.respond_to?(:current_model)

        @provider_manager.current_model || "unknown"
      rescue => e
        debug_log("⚠️ Failed to get current model", level: :warn, data: {error: e.message})
        "unknown"
      end
    end
  end
end
