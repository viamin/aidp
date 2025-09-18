# frozen_string_literal: true

require "logger"

module Aidp
  module Analyze
    # Comprehensive error handling system for analyze mode
    class ErrorHandler
      attr_reader :logger, :error_counts, :recovery_strategies

      def initialize(log_file: nil, verbose: false)
        @logger = setup_logger(log_file, verbose)
        @error_counts = Hash.new(0)
        @recovery_strategies = setup_recovery_strategies
        @error_history = []
      end

      # Handle errors with appropriate recovery strategies
      def handle_error(error, context: {}, step: nil, retry_count: 0)
        error_info = {
          error: error,
          context: context,
          step: step,
          retry_count: retry_count,
          timestamp: Time.current
        }

        log_error(error_info)
        increment_error_count(error.class)
        add_to_history(error_info)

        recovery_strategy = determine_recovery_strategy(error, context)
        apply_recovery_strategy(recovery_strategy, error_info)
      end

      # Handle specific error types with custom logic

      # Recovery strategies
      def retry_with_backoff(operation, max_retries: 3, base_delay: 1)
        retry_count = 0
        begin
          operation.call
        rescue => e
          retry_count += 1
          if retry_count <= max_retries
            delay = base_delay * (2**(retry_count - 1))
            logger.warn("Retrying operation in #{delay} seconds (attempt #{retry_count}/#{max_retries})")
            Async::Task.current.sleep(delay)
            retry
          else
            logger.error("Operation failed after #{max_retries} retries: #{e.message}")
            raise e
          end
        end
      end

      def skip_step_with_warning(step_name, error)
        logger.warn("Skipping step '#{step_name}' due to error: #{error.message}")
        {
          status: "skipped",
          reason: error.message,
          timestamp: Time.current
        }
      end

      def continue_with_partial_data(operation, partial_data_handler)
        operation.call
      end

      # Error reporting and statistics
      def get_error_summary
        {
          total_errors: @error_counts.values.sum,
          error_breakdown: @error_counts,
          recent_errors: @error_history.last(10),
          recovery_success_rate: calculate_recovery_success_rate
        }
      end

      # Cleanup and resource management
      def cleanup
        logger.info("Cleaning up error handler resources")
        @error_history.clear
        @error_counts.clear
      end

      private

      def setup_logger(log_file, verbose)
        logger = Logger.new(log_file || $stdout)
        logger.level = verbose ? Logger::DEBUG : Logger::INFO
        logger.formatter = proc do |severity, datetime, progname, msg|
          "#{datetime.strftime("%Y-%m-%d %H:%M:%S")} [#{severity}] #{msg}\n"
        end
        logger
      end

      def setup_recovery_strategies
        {
          Net::TimeoutError => :retry_with_backoff,
          Net::HTTPError => :retry_with_backoff,
          SocketError => :retry_with_backoff,
          Errno::ENOENT => :skip_step_with_warning,
          Errno::EACCES => :skip_step_with_warning,
          Errno::ENOSPC => :critical_error,
          SQLite3::BusyException => :retry_with_backoff,
          SQLite3::CorruptException => :critical_error,
          AnalysisTimeoutError => :chunk_and_retry,
          AnalysisDataError => :continue_with_partial_data,
          AnalysisToolError => :log_and_continue
        }
      end

      def log_error(error_info)
        error = error_info[:error]
        context = error_info[:context]
        step = error_info[:step]

        logger.error("Error in step '#{step}': #{error.class} - #{error.message}")
        logger.error("Context: #{context}") unless context.empty?
        logger.error("Backtrace: #{error.backtrace.first(5).join("\n")}") if error.backtrace
      end

      def increment_error_count(error_class)
        @error_counts[error_class] += 1
      end

      def add_to_history(error_info)
        @error_history << error_info
        @error_history.shift if @error_history.length > 100
      end

      def determine_recovery_strategy(error, context)
        strategy = @recovery_strategies[error.class] || :log_and_continue

        # Override strategy based on context
        strategy = :critical_error if context[:critical] && strategy == :skip_step_with_warning

        strategy = :retry_with_backoff if context[:retryable] && strategy == :log_and_continue

        strategy
      end

      def apply_recovery_strategy(strategy, error_info)
        case strategy
        when :retry_with_backoff
          retry_operation(error_info)
        when :skip_step_with_warning
          skip_step(error_info)
        when :critical_error
          raise_critical_error(error_info)
        when :chunk_and_retry
          chunk_and_retry(error_info)
        when :continue_with_partial_data
          continue_with_partial(error_info)
        when :log_and_continue
          log_and_continue(error_info)
        else
          log_and_continue(error_info)
        end
      end

      # Specific error handlers
      def handle_timeout_error(error, context)
        logger.warn("Network timeout: #{error.message}")
        if context[:retryable]
          retry_with_backoff(-> { context[:operation].call }, max_retries: 2)
        else
          skip_step_with_warning(context[:step], error)
        end
      end

      def handle_http_error(error, context)
        logger.warn("HTTP error: #{error.message}")
        case error.response&.code
        when "429" # Rate limited
          Async::Task.current.sleep(60) # Wait 1 minute
          retry_with_backoff(-> { context[:operation].call }, max_retries: 2)
        when "500".."599" # Server errors
          retry_with_backoff(-> { context[:operation].call }, max_retries: 3)
        else
          skip_step_with_warning(context[:step], error)
        end
      end

      def handle_socket_error(error, context)
        logger.warn("Socket error: #{error.message}")
        if context[:network_required]
          raise_critical_error({error: error, context: context})
        else
          logger.error("Network connection error: #{error.message}")
          raise error
        end
      end

      def handle_file_not_found(error, context)
        logger.warn("File not found: #{error.message}")
        if context[:required]
          raise_critical_error({error: error, context: context})
        else
          skip_step_with_warning(context[:step], error)
        end
      end

      def handle_permission_denied(error, context)
        logger.error("Permission denied: #{error.message}")
        raise_critical_error({error: error, context: context})
      end

      def handle_disk_full(error, context)
        logger.error("Disk full: #{error.message}")
        raise_critical_error({error: error, context: context})
      end

      def handle_database_busy(error, context)
        logger.warn("Database busy: #{error.message}")
        retry_with_backoff(-> { context[:operation].call }, max_retries: 5, base_delay: 0.5)
      end

      def handle_database_corrupt(error, context)
        logger.error("Database corrupt: #{error.message}")
        raise_critical_error({error: error, context: context})
      end

      def handle_database_readonly(error, context)
        logger.error("Database read-only: #{error.message}")
        raise_critical_error({error: error, context: context})
      end

      def handle_analysis_timeout(error, context)
        logger.warn("Analysis timeout: #{error.message}")
        if context[:chunkable]
          chunk_and_retry({error: error, context: context})
        else
          skip_step_with_warning(context[:step], error)
        end
      end

      def handle_analysis_data_error(error, context)
        logger.warn("Analysis data error: #{error.message}")
        continue_with_partial_data(
          -> { context[:operation].call },
          ->(e) { context[:partial_data_handler]&.call(e) || {} }
        )
      end

      def handle_analysis_tool_error(error, context)
        logger.error("Analysis tool error: #{error.message}")
        tool_name = context[:tool_name] || "analysis tool"
        error_msg = "#{tool_name} failed: #{error.message}"

        if context[:installation_guide]
          error_msg += "\n\nTo install #{tool_name}:\n#{context[:installation_guide]}"
        end

        raise AnalysisToolError.new(error_msg)
      end

      # Recovery strategy implementations
      def retry_operation(error_info)
        operation = error_info[:context][:operation]
        max_retries = error_info[:context][:max_retries] || 3
        base_delay = error_info[:context][:base_delay] || 1

        retry_with_backoff(operation, max_retries: max_retries, base_delay: base_delay)
      end

      def skip_step(error_info)
        step = error_info[:step]
        error = error_info[:error]
        skip_step_with_warning(step, error)
      end

      def raise_critical_error(error_info)
        error = error_info[:error]
        context = error_info[:context]

        logger.error("Critical error: #{error.message}")
        logger.error("Context: #{context}")

        raise CriticalAnalysisError.new(error.message, error_info)
      end

      def chunk_and_retry(error_info)
        context = error_info[:context]
        chunker = context[:chunker]
        operation = context[:operation]

        logger.info("Chunking analysis and retrying")

        chunks = chunker.chunk_repository("size_based")
        results = []

        chunks[:chunks].each do |chunk|
          result = operation.call(chunk)
          results << result
        rescue => e
          logger.warn("Chunk failed: #{e.message}")
          results << {status: "failed", error: e.message}
        end

        results
      end

      def continue_with_partial(error_info)
        context = error_info[:context]
        operation = context[:operation]
        partial_handler = context[:partial_data_handler]

        continue_with_partial_data(operation, partial_handler)
      end

      def log_and_continue(error_info)
        error = error_info[:error]
        logger.warn("Continuing after error: #{error.message}")
        {status: "continued_with_error", error: error.message}
      end

      def calculate_recovery_success_rate
        return 0.0 if @error_history.empty?

        successful_recoveries = @error_history.count do |error_info|
          error_info[:recovery_successful]
        end

        (successful_recoveries.to_f / @error_history.length * 100).round(2)
      end
    end

    # Custom error classes
    class CriticalAnalysisError < StandardError
      attr_reader :error_info

      def initialize(message, error_info = {})
        super(message)
        @error_info = error_info
      end
    end

    class AnalysisTimeoutError < StandardError; end

    class AnalysisDataError < StandardError; end

    class AnalysisToolError < StandardError; end
  end
end
