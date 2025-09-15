# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # Job error handling and retry logic
      class JobErrorHandler < Base
        class ErrorHandlerError < StandardError; end
        class RetryError < ErrorHandlerError; end
        class RecoveryError < ErrorHandlerError; end

        ERROR_TYPES = {
          network: "Network Error",
          timeout: "Timeout Error",
          validation: "Validation Error",
          permission: "Permission Error",
          resource: "Resource Error",
          unknown: "Unknown Error"
        }.freeze

        RETRY_STRATEGIES = {
          immediate: :immediate,
          exponential_backoff: :exponential_backoff,
          linear_backoff: :linear_backoff,
          fixed_delay: :fixed_delay
        }.freeze

        def initialize(ui_components = {})
          super()
          @formatter = ui_components[:formatter] || JobErrorHandlerFormatter.new
          @max_retries = ui_components[:max_retries] || 3
          @retry_delay = ui_components[:retry_delay] || 1.0
          @retry_strategy = ui_components[:retry_strategy] || :exponential_backoff
          @error_handlers = {}
          @retry_queue = []
          @error_history = []

          setup_default_error_handlers
        end

        def handle_job_error(job_id, error, context = {})
          validate_job_id(job_id)
          validate_error(error)

          error_info = analyze_error(error, context)
          record_error_event(job_id, error_info)

          # Determine if job should be retried
          if should_retry?(error_info)
            schedule_retry(job_id, error_info)
          else
            mark_job_failed(job_id, error_info)
          end

          error_info
        rescue => e
          raise ErrorHandlerError, "Failed to handle job error: #{e.message}"
        end

        def retry_job(job_id, retry_count = nil)
          validate_job_id(job_id)

          retry_count ||= get_retry_count(job_id) + 1

          if retry_count > @max_retries
            raise RetryError, "Maximum retries exceeded for job: #{job_id}"
          end

          retry_info = {
            job_id: job_id,
            retry_count: retry_count,
            scheduled_at: Time.now,
            delay: calculate_retry_delay(retry_count)
          }

          @retry_queue << retry_info
          record_retry_event(job_id, retry_info)

          CLI::UI.puts(@formatter.format_retry_scheduled(job_id, retry_count, retry_info[:delay]))
          retry_info
        rescue => e
          raise RetryError, "Failed to retry job: #{e.message}"
        end

        def process_retry_queue
          current_time = Time.now
          ready_retries = @retry_queue.select { |retry_info| retry_info[:scheduled_at] <= current_time }

          ready_retries.each do |retry_info|
            execute_retry(retry_info)
            @retry_queue.delete(retry_info)
          rescue => e
            CLI::UI.puts(@formatter.format_retry_execution_error(retry_info[:job_id], e.message))
          end

          ready_retries.size
        end

        def get_retry_count(job_id)
          error_events = @error_history.select { |event| event[:job_id] == job_id }
          error_events.count { |event| event[:error_type] == :retry }
        end

        def get_error_summary
          {
            total_errors: @error_history.size,
            errors_by_type: @error_history.map { |event| event[:error_type] }.tally,
            errors_by_job: @error_history.map { |event| event[:job_id] }.tally,
            retry_queue_size: @retry_queue.size,
            max_retries: @max_retries,
            retry_strategy: @retry_strategy
          }
        end

        def display_error_summary
          summary = get_error_summary
          @formatter.display_error_summary(summary)
        end

        def display_retry_queue
          if @retry_queue.empty?
            CLI::UI.puts(@formatter.format_empty_retry_queue)
            return
          end

          @formatter.display_retry_queue(@retry_queue)
        end

        def clear_error_history
          @error_history.clear
          CLI::UI.puts(@formatter.format_error_history_cleared)
        end

        def clear_retry_queue
          @retry_queue.clear
          CLI::UI.puts(@formatter.format_retry_queue_cleared)
        end

        def set_retry_strategy(strategy)
          validate_retry_strategy(strategy)
          @retry_strategy = strategy
          CLI::UI.puts(@formatter.format_retry_strategy_set(strategy))
        end

        def set_max_retries(max_retries)
          validate_max_retries(max_retries)
          @max_retries = max_retries
          CLI::UI.puts(@formatter.format_max_retries_set(max_retries))
        end

        private

        def validate_job_id(job_id)
          raise ErrorHandlerError, "Job ID cannot be empty" if job_id.to_s.strip.empty?
        end

        def validate_error(error)
          raise ErrorHandlerError, "Error cannot be nil" if error.nil?
        end

        def validate_retry_strategy(strategy)
          unless RETRY_STRATEGIES.key?(strategy)
            raise ErrorHandlerError, "Invalid retry strategy: #{strategy}. Must be one of: #{RETRY_STRATEGIES.keys.join(", ")}"
          end
        end

        def validate_max_retries(max_retries)
          raise ErrorHandlerError, "Max retries must be a positive integer" unless max_retries.is_a?(Integer) && max_retries > 0
        end

        def analyze_error(error, context)
          error_type = classify_error(error)
          error_message = extract_error_message(error)
          stack_trace = extract_stack_trace(error)

          {
            error_type: error_type,
            error_message: error_message,
            stack_trace: stack_trace,
            context: context,
            timestamp: Time.now,
            recoverable: is_recoverable_error?(error_type),
            retryable: is_retryable_error?(error_type)
          }
        end

        def classify_error(error)
          case error
          when Net::TimeoutError, Timeout::Error
            :timeout
          when Net::HTTPError, SocketError
            :network
          when ArgumentError, TypeError
            :validation
          when Errno::EACCES, Errno::EPERM
            :permission
          when Errno::ENOSPC, Errno::EMFILE
            :resource
          else
            :unknown
          end
        end

        def extract_error_message(error)
          error.message || error.to_s
        end

        def extract_stack_trace(error)
          return nil unless error.respond_to?(:backtrace)
          error.backtrace&.first(10) # Limit to first 10 lines
        end

        def is_recoverable_error?(error_type)
          recoverable_types = [:network, :timeout, :resource]
          recoverable_types.include?(error_type)
        end

        def is_retryable_error?(error_type)
          retryable_types = [:network, :timeout, :resource]
          retryable_types.include?(error_type)
        end

        def should_retry?(error_info)
          return false unless error_info[:retryable]
          return false if get_retry_count(error_info[:job_id]) >= @max_retries
          true
        end

        def schedule_retry(job_id, error_info)
          retry_count = get_retry_count(job_id) + 1
          retry_info = {
            job_id: job_id,
            retry_count: retry_count,
            scheduled_at: Time.now + calculate_retry_delay(retry_count),
            error_info: error_info
          }

          @retry_queue << retry_info
          record_retry_event(job_id, retry_info)

          CLI::UI.puts(@formatter.format_retry_scheduled(job_id, retry_count, retry_info[:scheduled_at]))
        end

        def mark_job_failed(job_id, error_info)
          record_error_event(job_id, error_info.merge(error_type: :final_failure))
          CLI::UI.puts(@formatter.format_job_failed(job_id, error_info[:error_message]))
        end

        def calculate_retry_delay(retry_count)
          case @retry_strategy
          when :immediate
            0
          when :exponential_backoff
            @retry_delay * (2**(retry_count - 1))
          when :linear_backoff
            @retry_delay * retry_count
          when :fixed_delay
            @retry_delay
          else
            @retry_delay
          end
        end

        def execute_retry(retry_info)
          job_id = retry_info[:job_id]
          retry_count = retry_info[:retry_count]

          CLI::UI.puts(@formatter.format_retry_executing(job_id, retry_count))

          # In a real implementation, this would trigger the actual job retry
          # For now, we'll just simulate it
          simulate_job_retry(job_id, retry_count)

          record_retry_event(job_id, retry_info.merge(executed: true))
        end

        def simulate_job_retry(job_id, retry_count)
          # Simulate job retry execution
          sleep(0.1) # Simulate work

          # Randomly succeed or fail for demonstration
          if rand < 0.7 # 70% success rate
            CLI::UI.puts(@formatter.format_retry_success(job_id, retry_count))
          else
            # Simulate another error
            error = StandardError.new("Retry attempt #{retry_count} failed")
            handle_job_error(job_id, error, {retry_count: retry_count})
          end
        end

        def setup_default_error_handlers
          @error_handlers[:network] = ->(error, context) { handle_network_error(error, context) }
          @error_handlers[:timeout] = ->(error, context) { handle_timeout_error(error, context) }
          @error_handlers[:validation] = ->(error, context) { handle_validation_error(error, context) }
          @error_handlers[:permission] = ->(error, context) { handle_permission_error(error, context) }
          @error_handlers[:resource] = ->(error, context) { handle_resource_error(error, context) }
          @error_handlers[:unknown] = ->(error, context) { handle_unknown_error(error, context) }
        end

        def handle_network_error(error, context)
          CLI::UI.puts(@formatter.format_network_error(error.message))
        end

        def handle_timeout_error(error, context)
          CLI::UI.puts(@formatter.format_timeout_error(error.message))
        end

        def handle_validation_error(error, context)
          CLI::UI.puts(@formatter.format_validation_error(error.message))
        end

        def handle_permission_error(error, context)
          CLI::UI.puts(@formatter.format_permission_error(error.message))
        end

        def handle_resource_error(error, context)
          CLI::UI.puts(@formatter.format_resource_error(error.message))
        end

        def handle_unknown_error(error, context)
          CLI::UI.puts(@formatter.format_unknown_error(error.message))
        end

        def record_error_event(job_id, error_info)
          event = {
            job_id: job_id,
            error_type: error_info[:error_type],
            error_message: error_info[:error_message],
            timestamp: Time.now,
            context: error_info[:context]
          }

          @error_history << event
        end

        def record_retry_event(job_id, retry_info)
          event = {
            job_id: job_id,
            event_type: :retry,
            retry_count: retry_info[:retry_count],
            scheduled_at: retry_info[:scheduled_at],
            timestamp: Time.now
          }

          @error_history << event
        end
      end

      # Formats job error handler display
      class JobErrorHandlerFormatter
        def display_error_summary(summary)
          CLI::UI.puts(CLI::UI.fmt("{{bold:{{blue:📊 Error Handler Summary}}}}"))
          CLI::UI.puts("─" * 50)

          CLI::UI.puts("Total errors: {{bold:#{summary[:total_errors]}}}")
          CLI::UI.puts("Retry queue size: {{bold:#{summary[:retry_queue_size]}}}")
          CLI::UI.puts("Max retries: {{bold:#{summary[:max_retries]}}}")
          CLI::UI.puts("Retry strategy: {{bold:#{summary[:retry_strategy]}}}")

          if summary[:errors_by_type].any?
            CLI::UI.puts("\nErrors by type:")
            summary[:errors_by_type].each do |type, count|
              CLI::UI.puts("  {{dim:#{type}: #{count}}}")
            end
          end

          if summary[:errors_by_job].any?
            CLI::UI.puts("\nErrors by job:")
            summary[:errors_by_job].each do |job_id, count|
              CLI::UI.puts("  {{dim:#{job_id}: #{count}}}")
            end
          end
        end

        def display_retry_queue(retry_queue)
          CLI::UI.puts(CLI::UI.fmt("{{bold:{{blue:🔄 Retry Queue}}}}"))
          CLI::UI.puts("─" * 50)

          retry_queue.each do |retry_info|
            CLI::UI.puts(format_retry_info(retry_info))
          end
        end

        def format_retry_info(retry_info)
          job_id = retry_info[:job_id]
          retry_count = retry_info[:retry_count]
          scheduled_at = retry_info[:scheduled_at]

          CLI::UI.fmt("{{yellow:🔄 #{job_id}}} (attempt #{retry_count}) - {{dim:#{scheduled_at}}}")
        end

        def format_retry_scheduled(job_id, retry_count, delay)
          CLI::UI.fmt("{{yellow:🔄 Retry scheduled for #{job_id}} (attempt #{retry_count}, delay: #{delay}s)")
        end

        def format_retry_executing(job_id, retry_count)
          CLI::UI.fmt("{{blue:🔄 Executing retry for #{job_id}} (attempt #{retry_count})")
        end

        def format_retry_success(job_id, retry_count)
          CLI::UI.fmt("{{green:✅ Retry successful for #{job_id}} (attempt #{retry_count})")
        end

        def format_retry_execution_error(job_id, error_message)
          CLI::UI.fmt("{{red:❌ Retry execution error for #{job_id}: #{error_message}}")
        end

        def format_job_failed(job_id, error_message)
          CLI::UI.fmt("{{red:❌ Job failed: #{job_id}} - {{red:#{error_message}}")
        end

        def format_network_error(error_message)
          CLI::UI.fmt("{{red:🌐 Network error: #{error_message}}")
        end

        def format_timeout_error(error_message)
          CLI::UI.fmt("{{red:⏰ Timeout error: #{error_message}}")
        end

        def format_validation_error(error_message)
          CLI::UI.fmt("{{red:📝 Validation error: #{error_message}}")
        end

        def format_permission_error(error_message)
          CLI::UI.fmt("{{red:🔒 Permission error: #{error_message}}")
        end

        def format_resource_error(error_message)
          CLI::UI.fmt("{{red:💾 Resource error: #{error_message}}")
        end

        def format_unknown_error(error_message)
          CLI::UI.fmt("{{red:❓ Unknown error: #{error_message}}")
        end

        def format_retry_strategy_set(strategy)
          CLI::UI.fmt("{{green:✅ Retry strategy set to: #{strategy}}")
        end

        def format_max_retries_set(max_retries)
          CLI::UI.fmt("{{green:✅ Max retries set to: #{max_retries}}")
        end

        def format_empty_retry_queue
          CLI::UI.fmt("{{dim:Retry queue is empty}}")
        end

        def format_error_history_cleared
          CLI::UI.fmt("{{yellow:🗑️ Error history cleared}}")
        end

        def format_retry_queue_cleared
          CLI::UI.fmt("{{yellow:🗑️ Retry queue cleared}}")
        end
      end
    end
  end
end
