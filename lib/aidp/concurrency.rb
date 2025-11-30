# frozen_string_literal: true

require "concurrent-ruby"

module Aidp
  # Concurrency utilities for deterministic waiting, retry/backoff, and executor management.
  #
  # This module provides standardized primitives to replace arbitrary sleep() calls with
  # proper synchronization, timeouts, and event-based coordination using concurrent-ruby.
  #
  # @example Wait for a condition
  #   Concurrency::Wait.until(timeout: 30) { File.exist?(path) }
  #
  # @example Retry with backoff
  #   Concurrency::Backoff.retry(max_attempts: 5) { risky_call() }
  #
  # @example Get a named executor
  #   pool = Concurrency::Exec.pool(name: :io_pool, size: 10)
  #   future = Concurrent::Promises.future_on(pool) { fetch_data() }
  module Concurrency
    class Error < StandardError; end
    class TimeoutError < Error; end
    class MaxAttemptsError < Error; end

    # Default configuration for executors and timeouts
    class Configuration
      attr_accessor :default_timeout, :default_interval, :default_max_attempts,
        :default_backoff_base, :default_backoff_max, :default_jitter,
        :log_long_waits_threshold, :log_retries

      def initialize
        @default_timeout = 30.0
        @default_interval = 0.2
        @default_max_attempts = 5
        @default_backoff_base = 0.5
        @default_backoff_max = 30.0
        @default_jitter = 0.2
        @log_long_waits_threshold = 5.0 # Log if wait takes > 5s
        @log_retries = true
      end
    end

    class << self
      attr_writer :configuration

      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
      end

      def logger
        @logger ||= if defined?(Aidp.logger)
          Aidp.logger
        elsif defined?(Rails)
          Rails.logger
        else
          require "logger"
          Logger.new($stdout)
        end
      end

      attr_writer :logger
    end
  end
end
