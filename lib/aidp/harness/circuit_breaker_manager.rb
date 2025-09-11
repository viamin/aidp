# frozen_string_literal: true

require_relative "../output_helper"

module Aidp
  module Harness
    # Circuit breaker pattern implementation for failing providers and models
    class CircuitBreakerManager
      include Aidp::OutputHelper
      def initialize(configuration, error_logger = nil, metrics_manager = nil)
        @configuration = configuration
        @error_logger = error_logger
        @metrics_manager = metrics_manager
        @circuit_breakers = {}
        @failure_counts = {}
        @success_counts = {}
        @last_failure_times = {}
        @state_history = {}
        @circuit_breaker_config = initialize_circuit_breaker_config
        @health_checker = HealthChecker.new
        @recovery_tester = RecoveryTester.new
        @state_notifier = StateNotifier.new
        initialize_circuit_breakers
      end

      # Check if circuit breaker allows request
      def can_execute?(provider, model = nil)
        circuit_breaker = get_circuit_breaker(provider, model)
        return true unless circuit_breaker

        case circuit_breaker[:state]
        when :closed
          true
        when :open
          if check_recovery_timeout(circuit_breaker)
            half_open_circuit_breaker(provider, model, "Recovery timeout reached")
            true
          else
            false
          end
        when :half_open
          true
        else
          false
        end
      end

      # Record successful execution
      def record_success(provider, model = nil)
        circuit_breaker = get_or_create_circuit_breaker(provider, model)

        @success_counts[get_key(provider, model)] ||= 0
        @success_counts[get_key(provider, model)] += 1

        case circuit_breaker[:state]
        when :half_open
          # Check if we have enough successes to close the circuit
          if @success_counts[get_key(provider, model)] >= circuit_breaker[:success_threshold]
            close_circuit_breaker(provider, model, "Recovery successful")
          end
        when :closed
          # Reset failure count on success only if not using failure rate threshold
          # If using failure rate threshold, let it accumulate for rate calculation
          unless circuit_breaker[:failure_rate_threshold] && circuit_breaker[:failure_rate_threshold] > 0
            @failure_counts[get_key(provider, model)] = 0
          end
        end

        # Record in metrics
        @metrics_manager&.record_circuit_breaker_success(provider, model, circuit_breaker[:state])
      end

      # Record failed execution
      def record_failure(provider, model = nil, error = nil)
        circuit_breaker = get_or_create_circuit_breaker(provider, model)

        key = get_key(provider, model)
        @failure_counts[key] ||= 0
        @failure_counts[key] += 1
        @last_failure_times[key] = Time.now

        # Log the failure
        @error_logger&.log_circuit_breaker_event(provider, model, :failure, error&.message, {
          failure_count: @failure_counts[key],
          state: circuit_breaker[:state]
        })

        case circuit_breaker[:state]
        when :closed
          # Check if we should open the circuit
          if should_open_circuit?(circuit_breaker, @failure_counts[key])
            open_circuit_breaker(provider, model, "Failure threshold exceeded")
          end
        when :half_open
          # Any failure in half-open state opens the circuit
          open_circuit_breaker(provider, model, "Failure during recovery")
        end

        # Record in metrics
        @metrics_manager&.record_circuit_breaker_failure(provider, model, circuit_breaker[:state], error)
      end

      # Get circuit breaker state
      def get_state(provider, model = nil)
        circuit_breaker = get_circuit_breaker(provider, model)
        circuit_breaker&.dig(:state) || :closed
      end

      # Get circuit breaker status
      def get_status(provider, model = nil)
        circuit_breaker = get_circuit_breaker(provider, model)
        return nil unless circuit_breaker

        key = get_key(provider, model)
        {
          state: circuit_breaker[:state],
          failure_count: @failure_counts[key] || 0,
          success_count: @success_counts[key] || 0,
          last_failure_time: @last_failure_times[key],
          failure_threshold: circuit_breaker[:failure_threshold],
          success_threshold: circuit_breaker[:success_threshold],
          timeout: circuit_breaker[:timeout],
          next_attempt_time: get_next_attempt_time(circuit_breaker),
          health_score: calculate_health_score(provider, model)
        }
      end

      # Get all circuit breaker states
      def get_all_states
        @circuit_breakers.transform_values do |circuit_breaker|
          provider, model = parse_key(circuit_breaker[:key])
          get_status(provider, model)
        end
      end

      # Manually open circuit breaker
      def open_circuit_breaker(provider, model = nil, reason = "Manual open")
        circuit_breaker = get_or_create_circuit_breaker(provider, model)
        old_state = circuit_breaker[:state]

        circuit_breaker[:state] = :open
        circuit_breaker[:opened_at] = Time.now
        circuit_breaker[:reason] = reason

        # Log state change
        @error_logger&.log_circuit_breaker_event(provider, model, :opened, reason, {
          previous_state: old_state,
          failure_count: @failure_counts[get_key(provider, model)] || 0
        })

        # Record state change
        record_state_change(provider, model, old_state, :open, reason)

        # Notify state change
        @state_notifier.notify_state_change(provider, model, old_state, :open, reason)
      end

      # Manually close circuit breaker
      def close_circuit_breaker(provider, model = nil, reason = "Manual close")
        circuit_breaker = get_or_create_circuit_breaker(provider, model)
        old_state = circuit_breaker[:state]

        circuit_breaker[:state] = :closed
        circuit_breaker[:closed_at] = Time.now
        circuit_breaker[:reason] = reason

        # Reset counters
        key = get_key(provider, model)
        @failure_counts[key] = 0
        @success_counts[key] = 0

        # Log state change
        @error_logger&.log_circuit_breaker_event(provider, model, :closed, reason, {
          previous_state: old_state
        })

        # Record state change
        record_state_change(provider, model, old_state, :closed, reason)

        # Notify state change
        @state_notifier.notify_state_change(provider, model, old_state, :closed, reason)
      end

      # Manually set circuit breaker to half-open
      def half_open_circuit_breaker(provider, model = nil, reason = "Manual half-open")
        circuit_breaker = get_or_create_circuit_breaker(provider, model)
        old_state = circuit_breaker[:state]

        circuit_breaker[:state] = :half_open
        circuit_breaker[:half_opened_at] = Time.now
        circuit_breaker[:reason] = reason

        # Reset success count for half-open testing
        @success_counts[get_key(provider, model)] = 0

        # Log state change
        @error_logger&.log_circuit_breaker_event(provider, model, :half_opened, reason, {
          previous_state: old_state
        })

        # Record state change
        record_state_change(provider, model, old_state, :half_open, reason)

        # Notify state change
        @state_notifier.notify_state_change(provider, model, old_state, :half_open, reason)
      end

      # Reset circuit breaker
      def reset_circuit_breaker(provider, model = nil)
        key = get_key(provider, model)

        # Remove circuit breaker
        @circuit_breakers.delete(key)

        # Reset counters
        @failure_counts.delete(key)
        @success_counts.delete(key)
        @last_failure_times.delete(key)

        # Log reset
        @error_logger&.log_circuit_breaker_event(provider, model, :reset, "Circuit breaker reset", {})

        # Record state change
        record_state_change(provider, model, :unknown, :closed, "Reset")
      end

      # Reset all circuit breakers
      def reset_all_circuit_breakers
        @circuit_breakers.clear
        @failure_counts.clear
        @success_counts.clear
        @last_failure_times.clear
        @state_history.clear

        # Log reset
        @error_logger&.log_circuit_breaker_event(nil, nil, :reset_all, "All circuit breakers reset", {})
      end

      # Get circuit breaker statistics
      def get_statistics
        {
          total_circuit_breakers: @circuit_breakers.size,
          open_circuit_breakers: @circuit_breakers.count { |_, cb| cb[:state] == :open },
          half_open_circuit_breakers: @circuit_breakers.count { |_, cb| cb[:state] == :half_open },
          closed_circuit_breakers: @circuit_breakers.count { |_, cb| cb[:state] == :closed },
          total_failures: @failure_counts.values.sum,
          total_successes: @success_counts.values.sum,
          average_failure_rate: calculate_average_failure_rate,
          most_failing_provider: find_most_failing_provider,
          circuit_breaker_effectiveness: calculate_circuit_breaker_effectiveness
        }
      end

      # Get circuit breaker history
      def get_history(provider = nil, model = nil)
        if provider
          key = get_key(provider, model)
          @state_history[key] || []
        else
          @state_history
        end
      end

      # Configure circuit breaker settings
      def configure_circuit_breaker(provider, model = nil, config)
        circuit_breaker = get_or_create_circuit_breaker(provider, model)

        # Update configuration
        circuit_breaker.merge!(config)

        # Validate configuration
        validate_circuit_breaker_config(circuit_breaker)

        # Log configuration change
        @error_logger&.log_circuit_breaker_event(provider, model, :configured, "Configuration updated", config)
      end

      # Health check for circuit breaker
      def health_check(provider, model = nil)
        circuit_breaker = get_circuit_breaker(provider, model)
        return {healthy: true, reason: "No circuit breaker"} unless circuit_breaker

        case circuit_breaker[:state]
        when :closed
          {healthy: true, reason: "Circuit breaker closed"}
        when :open
          if check_recovery_timeout(circuit_breaker)
            {healthy: true, reason: "Circuit breaker open - ready for recovery"}
          else
            {healthy: false, reason: "Circuit breaker open - recovery timeout not reached"}
          end
        when :half_open
          {healthy: true, reason: "Circuit breaker half-open - testing recovery"}
        else
          {healthy: false, reason: "Unknown circuit breaker state"}
        end
      end

      # Get providers/models that are available (not open)
      def get_available_providers(providers)
        providers.select { |provider| get_state(provider) != :open }
      end

      # Get models that are available for a provider
      def get_available_models(provider, models)
        models.select { |model| get_state(provider, model) != :open }
      end

      private

      def initialize_circuit_breaker_config
        default_config = {
          failure_threshold: 5,
          success_threshold: 3,
          timeout: 60,
          half_open_max_requests: 1,
          failure_rate_threshold: 0.5,
          minimum_requests: 10
        }

        # Override with configuration if available
        if @configuration.respond_to?(:circuit_breaker_config)
          default_config.merge!(@configuration.circuit_breaker_config)
        end

        default_config
      end

      def initialize_circuit_breakers
        # Initialize circuit breakers for configured providers
        if @configuration.respond_to?(:configured_providers)
          @configuration.configured_providers.each do |provider|
            get_or_create_circuit_breaker(provider)
          end
        end
      end

      def get_circuit_breaker(provider, model = nil)
        key = get_key(provider, model)
        @circuit_breakers[key]
      end

      def get_or_create_circuit_breaker(provider, model = nil)
        key = get_key(provider, model)
        @circuit_breakers[key] ||= {
          key: key,
          provider: provider,
          model: model,
          state: :closed,
          failure_threshold: @circuit_breaker_config[:failure_threshold],
          success_threshold: @circuit_breaker_config[:success_threshold],
          timeout: @circuit_breaker_config[:timeout],
          half_open_max_requests: @circuit_breaker_config[:half_open_max_requests],
          failure_rate_threshold: @circuit_breaker_config[:failure_rate_threshold],
          minimum_requests: @circuit_breaker_config[:minimum_requests],
          created_at: Time.now
        }
      end

      def get_key(provider, model = nil)
        model ? "#{provider}:#{model}" : provider
      end

      def parse_key(key)
        if key.include?(":")
          key.split(":", 2)
        else
          [key, nil]
        end
      end

      def should_open_circuit?(circuit_breaker, failure_count)
        # Check failure count threshold
        return true if failure_count >= circuit_breaker[:failure_threshold]

        # Check failure rate threshold
        total_requests = failure_count + (@success_counts[circuit_breaker[:key]] || 0)
        return false if total_requests < circuit_breaker[:minimum_requests]

        failure_rate = failure_count.to_f / total_requests
        failure_rate >= circuit_breaker[:failure_rate_threshold]
      end

      def check_recovery_timeout(circuit_breaker)
        return false unless circuit_breaker[:opened_at]

        Time.now - circuit_breaker[:opened_at] >= circuit_breaker[:timeout]
      end

      def get_next_attempt_time(circuit_breaker)
        return nil unless circuit_breaker[:opened_at]

        circuit_breaker[:opened_at] + circuit_breaker[:timeout]
      end

      def calculate_health_score(provider, model)
        # This would integrate with health metrics
        # For now, return a mock score
        case get_state(provider, model)
        when :closed
          1.0
        when :half_open
          0.5
        when :open
          0.0
        else
          0.0
        end
      end

      def record_state_change(provider, model, from_state, to_state, reason)
        key = get_key(provider, model)
        @state_history[key] ||= []
        @state_history[key] << {
          timestamp: Time.now,
          from_state: from_state,
          to_state: to_state,
          reason: reason,
          provider: provider,
          model: model
        }

        # Keep only last 100 state changes
        @state_history[key] = @state_history[key].last(100)
      end

      def calculate_average_failure_rate
        return 0.0 if @circuit_breakers.empty?

        total_failures = @failure_counts.values.sum
        total_requests = total_failures + @success_counts.values.sum
        return 0.0 if total_requests == 0

        total_failures.to_f / total_requests
      end

      def find_most_failing_provider
        return nil if @failure_counts.empty?

        @failure_counts.max_by { |_, count| count }[0]
      end

      def calculate_circuit_breaker_effectiveness
        return 0.0 if @circuit_breakers.empty?

        # Calculate effectiveness based on how well circuit breakers prevent cascading failures
        open_count = @circuit_breakers.count { |_, cb| cb[:state] == :open }
        total_count = @circuit_breakers.size

        # Higher effectiveness means fewer open circuit breakers
        1.0 - (open_count.to_f / total_count)
      end

      def validate_circuit_breaker_config(config)
        raise ArgumentError, "Failure threshold must be positive" if config[:failure_threshold] <= 0
        raise ArgumentError, "Success threshold must be positive" if config[:success_threshold] <= 0
        raise ArgumentError, "Timeout must be positive" if config[:timeout] <= 0
        raise ArgumentError, "Failure rate threshold must be between 0 and 1" if config[:failure_rate_threshold] < 0 || config[:failure_rate_threshold] > 1
        raise ArgumentError, "Minimum requests must be non-negative" if config[:minimum_requests] < 0
      end

      # Helper classes
      class HealthChecker
        def initialize
          @health_checks = {}
        end

        def check_health(_provider, _model = nil)
          # This would perform actual health checks
          # For now, return a mock health status
          {healthy: true, response_time: 100, last_check: Time.now}
        end

        def get_health_score(_provider, _model = nil)
          # This would calculate health score based on various metrics
          # For now, return a mock score
          0.95
        end
      end

      class RecoveryTester
        def initialize
          @recovery_tests = {}
        end

        def test_recovery(_provider, _model = nil)
          # This would perform recovery tests
          # For now, return a mock test result
          {success: true, response_time: 150, test_time: Time.now}
        end

        def should_attempt_recovery(_provider, _model = nil)
          # This would determine if recovery should be attempted
          # For now, return true
          true
        end
      end

      class StateNotifier
        def initialize
          @notifiers = []
        end

        def notify_state_change(provider, model, from_state, to_state, reason)
          # This would notify external systems of state changes
          # For now, just log the notification
          puts "Circuit breaker state change: #{provider}:#{model} #{from_state} -> #{to_state} (#{reason})"
        end

        def add_notifier(notifier)
          @notifiers << notifier
        end
      end
    end
  end
end
