# frozen_string_literal: true

require "concurrent-ruby"

module Aidp
  module Concurrency
    # Deterministic condition waiting with timeouts and intervals.
    #
    # Replaces sleep-based polling loops with proper timeout enforcement
    # and early exit on condition satisfaction.
    #
    # @example Wait for file to exist
    #   Wait.until(timeout: 30, interval: 0.2) { File.exist?("/tmp/ready") }
    #
    # @example Wait for port to open
    #   Wait.until(timeout: 60, interval: 1) do
    #     TCPSocket.new("localhost", 8080).close rescue false
    #   end
    #
    # @example Custom error message
    #   Wait.until(timeout: 10, message: "Service failed to start") do
    #     service_ready?
    #   end
    module Wait
      class << self
        # Wait until a condition becomes true, with timeout and interval polling.
        #
        # @param timeout [Float] Maximum seconds to wait (default: from config)
        # @param interval [Float] Seconds between condition checks (default: from config)
        # @param message [String] Custom error message on timeout
        # @yield Block that returns truthy when condition is met
        # @return [Object] The truthy value from the block
        # @raise [Concurrency::TimeoutError] if timeout is reached before condition is met
        #
        # @example
        #   result = Wait.until(timeout: 5, interval: 0.1) { expensive_check() }
        def until(timeout: nil, interval: nil, message: nil, &block)
          timeout ||= Concurrency.configuration.default_timeout
          interval ||= Concurrency.configuration.default_interval
          message ||= "Condition not met within #{timeout}s"

          raise ArgumentError, "Block required" unless block_given?

          start_time = monotonic_time
          deadline = start_time + timeout
          elapsed = 0.0

          loop do
            result = block.call
            if result
              log_wait_completion(elapsed) if should_log_wait?(elapsed)
              return result
            end

            elapsed = monotonic_time - start_time
            remaining = deadline - monotonic_time

            if remaining <= 0
              log_timeout(elapsed, message)
              raise Concurrency::TimeoutError, message
            end

            # Sleep for interval or remaining time, whichever is shorter
            sleep_duration = [interval, remaining].min
            sleep(sleep_duration) if sleep_duration > 0
          end
        end

        # Wait for a file to exist.
        #
        # @param path [String] File path to check
        # @param timeout [Float] Maximum seconds to wait
        # @param interval [Float] Seconds between checks
        # @return [String] The file path if it exists
        # @raise [Concurrency::TimeoutError] if file doesn't appear in time
        def for_file(path, timeout: nil, interval: nil)
          self.until(
            timeout: timeout,
            interval: interval,
            message: "File not found: #{path} (waited #{timeout || Concurrency.configuration.default_timeout}s)"
          ) { File.exist?(path) }
          path
        end

        # Wait for a TCP port to be open.
        #
        # @param host [String] Hostname or IP
        # @param port [Integer] Port number
        # @param timeout [Float] Maximum seconds to wait
        # @param interval [Float] Seconds between checks
        # @return [Boolean] true if port is open
        # @raise [Concurrency::TimeoutError] if port doesn't open in time
        def for_port(host, port, timeout: nil, interval: nil)
          require "socket"
          self.until(
            timeout: timeout,
            interval: interval,
            message: "Port #{host}:#{port} not open (waited #{timeout || Concurrency.configuration.default_timeout}s)"
          ) do
            socket = TCPSocket.new(host, port)
            socket.close
            true
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT
            false
          end
        end

        # Wait for a process to exit.
        #
        # @param pid [Integer] Process ID
        # @param timeout [Float] Maximum seconds to wait
        # @param interval [Float] Seconds between checks
        # @return [Process::Status] The process exit status
        # @raise [Concurrency::TimeoutError] if process doesn't exit in time
        def for_process_exit(pid, timeout: nil, interval: nil)
          status = nil
          self.until(
            timeout: timeout,
            interval: interval,
            message: "Process #{pid} did not exit (waited #{timeout || Concurrency.configuration.default_timeout}s)"
          ) do
            _, status = Process.waitpid2(pid, Process::WNOHANG)
            status # Returns truthy when process has exited
          end
          status
        end

        private

        def monotonic_time
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def should_log_wait?(elapsed)
          elapsed >= Concurrency.configuration.log_long_waits_threshold
        end

        def log_wait_completion(elapsed)
          Concurrency.logger&.info("concurrency_wait", "Long wait completed: #{elapsed.round(2)}s")
        end

        def log_timeout(elapsed, message)
          Concurrency.logger&.warn("concurrency_timeout", "Wait timeout: #{message} (elapsed: #{elapsed.round(2)}s)")
        end
      end
    end
  end
end
