# frozen_string_literal: true

module Aidp
  module Harness
    # Handles error classification and recovery strategies
    class ErrorHandler
      def initialize(configuration)
        @configuration = configuration
        @retry_counts = {}
        @error_history = []
      end

      # Execute block with retry logic
      def execute_with_retry(&_block)
        max_retries = @configuration.max_retries
        attempt = 1

        begin
          result = yield

          # Reset retry count on success
          @retry_counts.clear

          result
        rescue => error
          error_type = classify_error(error)

          # Record error
          @error_history << {
            error: error,
            error_type: error_type,
            attempt: attempt,
            timestamp: Time.now
          }

          # Check if we should retry
          if should_retry?(error, attempt, max_retries)
            delay = calculate_retry_delay(error, attempt)

            puts "⚠️  Error (#{error_type}): #{error.message}"
            puts "🔄 Retrying in #{delay} seconds... (attempt #{attempt + 1}/#{max_retries + 1})"

            sleep(delay)
            attempt += 1
            retry
          else
            # Max retries exceeded or non-recoverable error
            puts "❌ Error (#{error_type}): #{error.message}"
            puts "🚫 Max retries exceeded or non-recoverable error"

            raise error
          end
        end
      end

      # Handle error in harness context
      def handle_error(error, harness_runner)
        error_type = classify_error(error)

        case error_type
        when :rate_limit
          handle_rate_limit_error(error, harness_runner)
        when :timeout
          handle_timeout_error(error, harness_runner)
        when :network
          handle_network_error(error, harness_runner)
        when :authentication
          handle_authentication_error(error, harness_runner)
        else
          handle_generic_error(error, harness_runner)
        end
      end

      # Classify error type
      def classify_error(error)
        return :unknown unless error.is_a?(StandardError)

        error_message = error.message.downcase

        case error_message
        when /timeout/i
          :timeout
        when /connection/i, /network/i, /socket/i
          :network
        when /authentication/i, /unauthorized/i, /401/i
          :authentication
        when /permission/i, /forbidden/i, /403/i
          :permission
        when /not found/i, /404/i
          :not_found
        when /server error/i, /500/i, /502/i, /503/i
          :server_error
        when /rate limit/i, /429/i, /too many requests/i
          :rate_limit
        when /quota/i, /limit exceeded/i
          :quota_exceeded
        else
          :unknown
        end
      end

      # Check if error should be retried
      def should_retry?(error, attempt, max_retries)
        return false if attempt > max_retries

        error_type = classify_error(error)

        case error_type
        when :timeout, :network, :server_error
          true
        when :rate_limit, :quota_exceeded
          true
        when :authentication, :permission, :not_found
          false
        else
          # Unknown errors - retry with caution
          attempt <= 2
        end
      end

      # Calculate retry delay
      def calculate_retry_delay(error, attempt)
        error_type = classify_error(error)

        base_delay = {
          timeout: 5,
          network: 10,
          server_error: 15,
          rate_limit: 60,
          quota_exceeded: 60
        }.fetch(error_type, 5)

        # Exponential backoff with jitter
        delay = base_delay * (2 ** (attempt - 1))
        jitter = rand(0.1..0.3) * delay

        delay + jitter
      end

      # Get error statistics
      def error_stats
        error_counts = @error_history.group_by { |entry| entry[:error_type] }
          .transform_values(&:count)

        {
          total_errors: @error_history.size,
          error_counts: error_counts,
          last_error: @error_history.last,
          retry_counts: @retry_counts.dup
        }
      end

      # Clear error history
      def clear_error_history
        @error_history.clear
        @retry_counts.clear
      end

      private

      def handle_rate_limit_error(_error, harness_runner)
        # Rate limit errors should trigger provider switching
        provider_manager = harness_runner.instance_variable_get(:@provider_manager)
        current_provider = provider_manager.current_provider

        # Mark current provider as rate limited
        provider_manager.mark_rate_limited(current_provider)

        puts "🚫 Rate limit hit for #{current_provider}. Switching provider..."
      end

      def handle_timeout_error(_error, _harness_runner)
        # Timeout errors can be retried with the same provider
        puts "⏱️  Timeout occurred. Will retry with same provider..."
      end

      def handle_network_error(_error, _harness_runner)
        # Network errors can be retried
        puts "🌐 Network error occurred. Will retry..."
      end

      def handle_authentication_error(error, _harness_runner)
        # Authentication errors are usually not recoverable
        puts "🔐 Authentication error. Please check your credentials."
        raise error
      end

      def handle_generic_error(error, _harness_runner)
        # Generic error handling
        puts "❌ Unexpected error: #{error.message}"
        puts "🔍 Error type: #{classify_error(error)}"
      end
    end
  end
end
