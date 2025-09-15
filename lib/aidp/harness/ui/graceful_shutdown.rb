# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # Graceful shutdown functionality for workflow stop operations
      class GracefulShutdown < Base
        class ShutdownError < StandardError; end
        class ShutdownTimeoutError < ShutdownError; end
        class ShutdownInterruptedError < ShutdownError; end

        def initialize(ui_components = {})
          super()
          @formatter = ui_components[:formatter] || GracefulShutdownFormatter.new
          @shutdown_timeout = ui_components[:shutdown_timeout] || 30
          @shutdown_handlers = []
          @shutdown_history = []
        end

        def graceful_shutdown(workflow_id, shutdown_type = :stop)
          validate_workflow_id(workflow_id)
          validate_shutdown_type(shutdown_type)

          shutdown_result = perform_graceful_shutdown(workflow_id, shutdown_type)
          record_shutdown_event(workflow_id, shutdown_type, shutdown_result)
          shutdown_result
        rescue => e
          raise ShutdownError, "Failed to perform graceful shutdown: #{e.message}"
        end

        def shutdown_with_timeout(workflow_id, shutdown_type = :stop, timeout_seconds = nil)
          timeout_seconds ||= @shutdown_timeout

          Timeout.timeout(timeout_seconds) do
            graceful_shutdown(workflow_id, shutdown_type)
          end
        rescue Timeout::Error
          raise ShutdownTimeoutError, "Shutdown timed out after #{timeout_seconds} seconds"
        end

        def add_shutdown_handler(handler)
          validate_shutdown_handler(handler)
          @shutdown_handlers << handler
        end

        def remove_shutdown_handler(handler)
          @shutdown_handlers.delete(handler)
        end

        def get_shutdown_summary
          {
            total_shutdowns: @shutdown_history.size,
            successful_shutdowns: @shutdown_history.count { |h| h[:success] },
            failed_shutdowns: @shutdown_history.count { |h| !h[:success] },
            shutdown_types: @shutdown_history.map { |h| h[:shutdown_type] }.tally,
            last_shutdown: @shutdown_history.last
          }
        end

        def clear_shutdown_history
          @shutdown_history.clear
        end

        private

        def validate_workflow_id(workflow_id)
          raise ShutdownError, "Workflow ID cannot be empty" if workflow_id.to_s.strip.empty?
        end

        def validate_shutdown_type(shutdown_type)
          valid_types = [:stop, :abort, :terminate, :restart]
          unless valid_types.include?(shutdown_type)
            raise ShutdownError, "Invalid shutdown type: #{shutdown_type}. Must be one of: #{valid_types.join(", ")}"
          end
        end

        def validate_shutdown_handler(handler)
          unless handler.respond_to?(:call)
            raise ShutdownError, "Shutdown handler must respond to :call"
          end
        end

        def perform_graceful_shutdown(workflow_id, shutdown_type)
          shutdown_result = {
            workflow_id: workflow_id,
            shutdown_type: shutdown_type,
            started_at: Time.now,
            success: false,
            phases_completed: [],
            errors: []
          }

          begin
            # Execute shutdown phases
            shutdown_result[:phases_completed] = execute_shutdown_phases(workflow_id, shutdown_type)
            shutdown_result[:success] = true
            shutdown_result[:completed_at] = Time.now
          rescue => e
            shutdown_result[:errors] << e.message
            shutdown_result[:completed_at] = Time.now
          end

          shutdown_result
        end

        def execute_shutdown_phases(workflow_id, shutdown_type)
          completed_phases = []

          # Phase 1: Notify components of shutdown
          completed_phases << execute_shutdown_phase(:notify, workflow_id, shutdown_type)

          # Phase 2: Stop accepting new work
          completed_phases << execute_shutdown_phase(:stop_accepting, workflow_id, shutdown_type)

          # Phase 3: Complete current operations
          completed_phases << execute_shutdown_phase(:complete_current, workflow_id, shutdown_type)

          # Phase 4: Clean up resources
          completed_phases << execute_shutdown_phase(:cleanup, workflow_id, shutdown_type)

          # Phase 5: Execute custom shutdown handlers
          completed_phases << execute_shutdown_phase(:handlers, workflow_id, shutdown_type)

          # Phase 6: Final cleanup
          completed_phases << execute_shutdown_phase(:final_cleanup, workflow_id, shutdown_type)

          completed_phases.compact
        end

        def execute_shutdown_phase(phase, workflow_id, shutdown_type)
          phase_result = {
            phase: phase,
            success: false,
            duration: 0,
            error: nil
          }

          start_time = Time.now

          begin
            case phase
            when :notify
              notify_shutdown(workflow_id, shutdown_type)
            when :stop_accepting
              stop_accepting_new_work(workflow_id)
            when :complete_current
              complete_current_operations(workflow_id)
            when :cleanup
              cleanup_during_shutdown(workflow_id)
            when :handlers
              execute_shutdown_handlers(workflow_id, shutdown_type)
            when :final_cleanup
              final_cleanup(workflow_id)
            end

            phase_result[:success] = true
          rescue => e
            phase_result[:error] = e.message
          ensure
            phase_result[:duration] = Time.now - start_time
          end

          phase_result
        end

        def notify_shutdown(workflow_id, shutdown_type)
          # Notify all components that shutdown is starting
          CLI::UI.puts(@formatter.format_shutdown_notification(workflow_id, shutdown_type))
        end

        def stop_accepting_new_work(workflow_id)
          # Stop accepting new work items
          CLI::UI.puts(@formatter.format_stop_accepting(workflow_id))
        end

        def complete_current_operations(workflow_id)
          # Wait for current operations to complete
          CLI::UI.puts(@formatter.format_completing_operations(workflow_id))

          # Simulate waiting for operations to complete
          sleep(0.1) # Placeholder for actual operation completion logic
        end

        def cleanup_during_shutdown(workflow_id)
          # Clean up resources during shutdown
          CLI::UI.puts(@formatter.format_cleanup_during_shutdown(workflow_id))
        end

        def execute_shutdown_handlers(workflow_id, shutdown_type)
          # Execute custom shutdown handlers
          @shutdown_handlers.each do |handler|
            handler.call(workflow_id, shutdown_type)
          rescue => e
            CLI::UI.puts(@formatter.format_handler_error(handler, e.message))
          end
        end

        def final_cleanup(workflow_id)
          # Final cleanup operations
          CLI::UI.puts(@formatter.format_final_cleanup(workflow_id))
        end

        def record_shutdown_event(workflow_id, shutdown_type, shutdown_result)
          @shutdown_history << {
            workflow_id: workflow_id,
            shutdown_type: shutdown_type,
            timestamp: Time.now,
            success: shutdown_result[:success],
            phases_completed: shutdown_result[:phases_completed]&.size || 0,
            errors: shutdown_result[:errors]&.size || 0,
            duration: shutdown_result[:completed_at] - shutdown_result[:started_at]
          }
        end
      end

      # Formats graceful shutdown display
      class GracefulShutdownFormatter
        def format_shutdown_notification(workflow_id, shutdown_type)
          CLI::UI.fmt("{{yellow:🔔 Shutdown notification for workflow: #{workflow_id}}}")
        end

        def format_stop_accepting(workflow_id)
          CLI::UI.fmt("{{yellow:🚫 Stopping acceptance of new work for workflow: #{workflow_id}}}")
        end

        def format_completing_operations(workflow_id)
          CLI::UI.fmt("{{blue:⏳ Completing current operations for workflow: #{workflow_id}}}")
        end

        def format_cleanup_during_shutdown(workflow_id)
          CLI::UI.fmt("{{blue:🧹 Cleaning up resources for workflow: #{workflow_id}}}")
        end

        def format_final_cleanup(workflow_id)
          CLI::UI.fmt("{{green:✨ Final cleanup for workflow: #{workflow_id}}}")
        end

        def format_handler_error(handler, error_message)
          CLI::UI.fmt("{{red:❌ Shutdown handler error: #{error_message}}}")
        end

        def format_shutdown_success(workflow_id, duration)
          CLI::UI.fmt("{{green:✅ Graceful shutdown completed for workflow: #{workflow_id}}}")
          CLI::UI.fmt("{{dim:Duration: #{duration.round(2)}s}}")
        end

        def format_shutdown_error(workflow_id, error_message)
          CLI::UI.fmt("{{red:❌ Shutdown failed for workflow: #{workflow_id}}}")
          CLI::UI.fmt("{{red:Error: #{error_message}}}")
        end

        def format_shutdown_timeout(workflow_id, timeout_seconds)
          CLI::UI.fmt("{{red:⏰ Shutdown timed out for workflow: #{workflow_id}}}")
          CLI::UI.fmt("{{red:Timeout: #{timeout_seconds} seconds}}")
        end

        def format_shutdown_phase(phase_result)
          status = phase_result[:success] ? "✅" : "❌"
          CLI::UI.fmt("#{status} {{bold:#{phase_result[:phase]}}} ({{dim:#{phase_result[:duration].round(2)}s}})")

          if phase_result[:error]
            CLI::UI.fmt("  {{red:Error: #{phase_result[:error]}}}")
          end
        end

        def format_shutdown_summary(summary)
          CLI::UI.fmt("{{bold:{{blue:📊 Shutdown Summary}}}}")
          CLI::UI.fmt("Total shutdowns: {{bold:#{summary[:total_shutdowns]}}}")
          CLI::UI.fmt("Successful: {{green:#{summary[:successful_shutdowns]}}}")
          CLI::UI.fmt("Failed: {{red:#{summary[:failed_shutdowns]}}}")

          if summary[:shutdown_types].any?
            CLI::UI.fmt("Shutdown types:")
            summary[:shutdown_types].each do |type, count|
              CLI::UI.fmt("  {{dim:#{type}: #{count}}}")
            end
          end
        end
      end
    end
  end
end
