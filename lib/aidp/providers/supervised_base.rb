# frozen_string_literal: true

require_relative "agent_supervisor"

module Aidp
  module Providers
    # Base class for providers that use the agent supervisor
    class SupervisedBase
      attr_reader :name, :last_execution_result, :metrics

      def initialize
        @last_execution_result = nil
        @metrics = {
          total_executions: 0,
          successful_executions: 0,
          timeout_count: 0,
          failure_count: 0,
          average_duration: 0.0,
          total_duration: 0.0
        }
        @job_context = nil
      end

      # Abstract method - must be implemented by subclasses
      def command
        raise NotImplementedError, "#{self.class} must implement #command"
      end

      # Abstract method - must be implemented by subclasses
      def provider_name
        raise NotImplementedError, "#{self.class} must implement #provider_name"
      end

      # Set job context for background execution
      def set_job_context(job_id:, execution_id:, job_manager:)
        @job_context = {
          job_id: job_id,
          execution_id: execution_id,
          job_manager: job_manager
        }
      end

      # Execute with supervision and recovery
      def send(prompt:, session: nil)
        timeout_seconds = calculate_timeout
        debug = ENV["AIDP_DEBUG"] == "1"

        log_info("Executing with #{provider_name} provider (timeout: #{timeout_seconds}s)")

        # Create supervisor
        supervisor = AgentSupervisor.new(
          command,
          timeout_seconds: timeout_seconds,
          debug: debug
        )

        begin
          # Execute with supervision
          result = supervisor.execute(prompt)

          # Update metrics
          update_metrics(supervisor, result)

          # Store result for debugging
          @last_execution_result = result

          if result[:success]
            log_info("#{provider_name} completed successfully in #{format_duration(result[:duration])}")
            result[:output]
          else
            handle_execution_failure(result, supervisor)
          end
        rescue => e
          log_error("#{provider_name} execution error: #{e.message}")

          # Try to kill the process if it's still running
          supervisor.kill! if supervisor.active?

          raise
        end
      end

      # Get execution statistics
      def stats
        @metrics.dup
      end

      # Reset statistics
      def reset_stats!
        @metrics = {
          total_executions: 0,
          successful_executions: 0,
          timeout_count: 0,
          failure_count: 0,
          average_duration: 0.0,
          total_duration: 0.0
        }
      end

      # Check if provider supports activity monitoring
      def supports_activity_monitoring?
        true # Supervised providers always support activity monitoring
      end

      # Get activity summary for metrics (compatibility with old interface)
      def activity_summary
        return {} unless @last_execution_result

        {
          provider: provider_name,
          step_name: ENV["AIDP_CURRENT_STEP"],
          start_time: @last_execution_result[:start_time],
          end_time: @last_execution_result[:end_time],
          duration: @last_execution_result[:duration],
          final_state: @last_execution_result[:state],
          stuck_detected: false, # Supervisor handles this differently
          output_count: @last_execution_result[:output_count] || 0
        }
      end

      # Compatibility methods for old activity monitoring interface
      def setup_activity_monitoring(step_name, callback = nil, timeout = nil)
        # No-op for supervised providers - supervisor handles this
      end

      def record_activity(message = nil)
        # No-op for supervised providers - supervisor handles this
      end

      def mark_completed
        # No-op for supervised providers - supervisor handles this
      end

      def mark_failed(message = nil)
        # No-op for supervised providers - supervisor handles this
      end

      private

      def calculate_timeout
        # Priority order for timeout calculation:
        # 1. Quick mode (for testing)
        # 2. Environment variable override
        # 3. Adaptive timeout based on step type
        # 4. Default timeout

        if ENV["AIDP_QUICK_MODE"]
          log_info("Quick mode enabled - 2 minute timeout")
          return 120
        end

        provider_timeout_var = "AIDP_#{provider_name.upcase}_TIMEOUT"
        if ENV[provider_timeout_var]
          return ENV[provider_timeout_var].to_i
        end

        # Adaptive timeout based on step type
        step_timeout = get_adaptive_timeout
        if step_timeout
          log_info("Using adaptive timeout: #{step_timeout} seconds")
          return step_timeout
        end

        # Default timeout (5 minutes for interactive use)
        log_info("Using default timeout: 5 minutes")
        300
      end

      def get_adaptive_timeout
        # Try to get timeout recommendations from metrics storage
        begin
          require_relative "../analyze/metrics_storage"
          storage = Aidp::Analyze::MetricsStorage.new(Dir.pwd)
          recommendations = storage.calculate_timeout_recommendations

          # Get current step name from environment or context
          step_name = ENV["AIDP_CURRENT_STEP"] || "unknown"

          if recommendations[step_name]
            recommended = recommendations[step_name][:recommended_timeout]
            # Add 20% buffer for safety
            return (recommended * 1.2).ceil
          end
        rescue => e
          log_warning("Could not get adaptive timeout: #{e.message}") if ENV["AIDP_DEBUG"]
        end

        # Fallback timeouts based on step type patterns
        step_name = ENV["AIDP_CURRENT_STEP"] || ""

        case step_name
        when /REPOSITORY_ANALYSIS/
          180  # 3 minutes - repository analysis can be quick
        when /ARCHITECTURE_ANALYSIS/
          600  # 10 minutes - architecture analysis needs more time
        when /TEST_ANALYSIS/
          300  # 5 minutes - test analysis is moderate
        when /FUNCTIONALITY_ANALYSIS/
          600  # 10 minutes - functionality analysis is complex
        when /DOCUMENTATION_ANALYSIS/
          300  # 5 minutes - documentation analysis is moderate
        when /STATIC_ANALYSIS/
          450  # 7.5 minutes - static analysis can be intensive
        when /REFACTORING_RECOMMENDATIONS/
          600  # 10 minutes - refactoring recommendations are complex
        else
          nil  # Use default
        end
      end

      def update_metrics(supervisor, result)
        @metrics[:total_executions] += 1
        @metrics[:total_duration] += supervisor.duration
        @metrics[:average_duration] = @metrics[:total_duration] / @metrics[:total_executions]

        case result[:state]
        when :completed
          @metrics[:successful_executions] += 1
        when :timeout
          @metrics[:timeout_count] += 1
        when :failed, :killed
          @metrics[:failure_count] += 1
        end

        # Log metrics update if in job context
        if @job_context
          @job_context[:job_manager].log_message(
            @job_context[:job_id],
            @job_context[:execution_id],
            "Updated execution metrics",
            "debug",
            @metrics
          )
        end
      end

      def handle_execution_failure(result, supervisor)
        case result[:reason]
        when "user_aborted"
          message = "#{provider_name} was aborted by user after #{format_duration(result[:duration])}"
          log_error(message)
          raise Interrupt, message
        when "non_zero_exit"
          error_msg = result[:error_output].empty? ? "Unknown error" : result[:error_output].strip
          message = "#{provider_name} failed with exit code #{result[:exit_code]}: #{error_msg}"
          log_error(message)
          raise message
        else
          message = "#{provider_name} failed: #{result[:reason] || "Unknown error"}"
          log_error(message)
          raise message
        end
      end

      def format_duration(seconds)
        minutes = (seconds / 60).to_i
        secs = (seconds % 60).to_i

        if minutes > 0
          "#{minutes}m #{secs}s"
        else
          "#{secs}s"
        end
      end

      def log_info(message)
        if @job_context
          @job_context[:job_manager].log_message(
            @job_context[:job_id],
            @job_context[:execution_id],
            message,
            "info"
          )
        else
          puts message
        end
      end

      def log_warning(message)
        if @job_context
          @job_context[:job_manager].log_message(
            @job_context[:job_id],
            @job_context[:execution_id],
            message,
            "warning"
          )
        else
          puts "⚠️  #{message}"
        end
      end

      def log_error(message)
        if @job_context
          @job_context[:job_manager].log_message(
            @job_context[:job_id],
            @job_context[:execution_id],
            message,
            "error"
          )
        else
          puts "❌ #{message}"
        end
      end
    end
  end
end
