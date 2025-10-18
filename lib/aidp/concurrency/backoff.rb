# frozen_string_literal: true

require "concurrent-ruby"

module Aidp
  module Concurrency
    # Retry logic with exponential backoff and jitter.
    #
    # Replaces ad-hoc retry loops that use sleep() with a standardized,
    # configurable retry mechanism that includes backoff strategies and jitter.
    #
    # @example Simple retry
    #   Backoff.retry(max_attempts: 5) { call_external_api() }
    #
    # @example Custom backoff strategy
    #   Backoff.retry(max_attempts: 10, base: 1.0, strategy: :linear) do
    #     unstable_operation()
    #   end
    #
    # @example With error filtering
    #   Backoff.retry(max_attempts: 3, on: [Net::ReadTimeout, Errno::ECONNREFUSED]) do
    #     http_request()
    #   end
    module Backoff
      class << self
        # Retry a block with exponential backoff and jitter.
        #
        # @param max_attempts [Integer] Maximum number of attempts (default: from config)
        # @param base [Float] Base delay in seconds (default: from config)
        # @param max_delay [Float] Maximum delay between retries (default: from config)
        # @param jitter [Float] Jitter factor 0.0-1.0 (default: from config)
        # @param strategy [Symbol] Backoff strategy :exponential, :linear, or :constant
        # @param on [Array<Class>] Array of exception classes to retry (default: StandardError)
        # @yield Block to retry
        # @return [Object] Result of the block
        # @raise [Concurrency::MaxAttemptsError] if all attempts fail
        #
        # @example
        #   result = Backoff.retry(max_attempts: 5, base: 0.5, jitter: 0.2) do
        #     api_client.fetch_data
        #   end
        def retry(max_attempts: nil, base: nil, max_delay: nil, jitter: nil,
          strategy: :exponential, on: [StandardError], &block)
          max_attempts ||= Concurrency.configuration.default_max_attempts
          base ||= Concurrency.configuration.default_backoff_base
          max_delay ||= Concurrency.configuration.default_backoff_max
          jitter ||= Concurrency.configuration.default_jitter

          raise ArgumentError, "Block required" unless block_given?
          raise ArgumentError, "max_attempts must be >= 1" if max_attempts < 1

          on = Array(on)
          last_error = nil
          attempt = 0

          while attempt < max_attempts
            attempt += 1

            begin
              result = block.call
              log_retry_success(attempt) if attempt > 1
              return result
            rescue => e
              last_error = e

              # Re-raise if error is not in the retry list
              raise unless on.any? { |klass| e.is_a?(klass) }

              # Re-raise on last attempt
              if attempt >= max_attempts
                log_max_attempts_exceeded(attempt, e)
                raise Concurrency::MaxAttemptsError, "Max attempts (#{max_attempts}) exceeded: #{e.class} - #{e.message}"
              end

              # Calculate delay and wait
              delay = calculate_delay(attempt, strategy, base, max_delay, jitter)
              log_retry_attempt(attempt, max_attempts, delay, e)
              sleep(delay) if delay > 0
            end
          end

          # Should never reach here, but just in case
          raise Concurrency::MaxAttemptsError, "Max attempts (#{max_attempts}) exceeded: #{last_error&.class} - #{last_error&.message}"
        end

        # Calculate backoff delay for a given attempt.
        #
        # @param attempt [Integer] Current attempt number (1-indexed)
        # @param strategy [Symbol] :exponential, :linear, or :constant
        # @param base [Float] Base delay in seconds
        # @param max_delay [Float] Maximum delay cap
        # @param jitter [Float] Jitter factor 0.0-1.0
        # @return [Float] Delay in seconds
        def calculate_delay(attempt, strategy, base, max_delay, jitter)
          delay = case strategy
          when :exponential
            base * (2**(attempt - 1))
          when :linear
            base * attempt
          when :constant
            base
          else
            raise ArgumentError, "Unknown strategy: #{strategy}"
          end

          # Cap at max_delay
          delay = [delay, max_delay].min

          # Add jitter: randomize between (1-jitter)*delay and delay
          # e.g., with jitter=0.2, delay is reduced by 0-20%
          if jitter > 0
            jitter_amount = delay * jitter * rand
            delay -= jitter_amount
          end

          delay
        end

        private

        def log_retry_attempt(attempt, max_attempts, delay, error)
          return unless Concurrency.configuration.log_retries

          Concurrency.logger&.info(
            "concurrency_retry",
            "Retry attempt #{attempt}/#{max_attempts} after #{delay.round(2)}s: #{error.class} - #{error.message}"
          )
        end

        def log_retry_success(attempt)
          return unless Concurrency.configuration.log_retries

          Concurrency.logger&.info(
            "concurrency_retry",
            "Retry succeeded on attempt #{attempt}"
          )
        end

        def log_max_attempts_exceeded(attempt, error)
          Concurrency.logger&.error(
            "concurrency_retry",
            "Max attempts (#{attempt}) exceeded: #{error.class} - #{error.message}"
          )
        end
      end
    end
  end
end
