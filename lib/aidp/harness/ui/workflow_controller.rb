# frozen_string_literal: true

require_relative "base"
require_relative "status_manager"
require_relative "frame_manager"

module Aidp
  module Harness
    module UI
      # Workflow control interface for pause/resume/cancel/stop
      class WorkflowController < Base
        class WorkflowError < StandardError; end
        class InvalidStateError < WorkflowError; end
        class ControlError < WorkflowError; end

        WORKFLOW_STATES = {
          running: "Running",
          paused: "Paused",
          cancelled: "Cancelled",
          stopped: "Stopped",
          completed: "Completed"
        }.freeze

        def initialize(ui_components = {})
          super()
          @status_manager = ui_components[:status_manager] || StatusManager.new
          @frame_manager = ui_components[:frame_manager] || FrameManager.new
          @formatter = ui_components[:formatter] || WorkflowControllerFormatter.new

          @current_state = :running
          @state_history = []
          @pause_time = nil
          @control_thread = nil
          @control_mutex = Mutex.new
        end

        def pause_workflow(reason = "User requested pause")
          validate_state_transition(:pause)

          @control_mutex.synchronize do
            @current_state = :paused
            @pause_time = Time.now
            record_state_change(:paused, reason)
            @status_manager.show_warning_status("Workflow paused: #{reason}")
          end
        rescue InvalidStateError => e
          raise e
        rescue => e
          raise ControlError, "Failed to pause workflow: #{e.message}"
        end

        def resume_workflow(reason = "User requested resume")
          validate_state_transition(:resume)

          @control_mutex.synchronize do
            @current_state = :running
            pause_duration = calculate_pause_duration
            record_state_change(:running, reason, pause_duration)
            @status_manager.show_success_status("Workflow resumed: #{reason}")
          end
        rescue InvalidStateError => e
          raise e
        rescue => e
          raise ControlError, "Failed to resume workflow: #{e.message}"
        end

        def cancel_workflow(reason = "User requested cancellation")
          validate_state_transition(:cancel)

          @control_mutex.synchronize do
            @current_state = :cancelled
            record_state_change(:cancelled, reason)
            @status_manager.show_warning_status("Workflow cancelled: #{reason}")
            cleanup_workflow_resources
          end
        rescue InvalidStateError => e
          raise e
        rescue => e
          raise ControlError, "Failed to cancel workflow: #{e.message}"
        end

        def stop_workflow(reason = "User requested stop")
          validate_state_transition(:stop)

          @control_mutex.synchronize do
            @current_state = :stopped
            record_state_change(:stopped, reason)
            @status_manager.show_error_status("Workflow stopped: #{reason}")
            cleanup_workflow_resources
          end
        rescue => e
          raise ControlError, "Failed to stop workflow: #{e.message}"
        end

        def complete_workflow(reason = "Workflow completed successfully")
          validate_state_transition(:complete)

          @control_mutex.synchronize do
            @current_state = :completed
            record_state_change(:completed, reason)
            @status_manager.show_success_status("Workflow completed: #{reason}")
          end
        rescue InvalidStateError => e
          raise e
        rescue => e
          raise ControlError, "Failed to complete workflow: #{e.message}"
        end

        def current_state
          @control_mutex.synchronize { @current_state }
        end

        def running?
          @current_state == :running
        end

        def paused?
          @current_state == :paused
        end

        def cancelled?
          @current_state == :cancelled
        end

        def stopped?
          @current_state == :stopped
        end

        def completed?
          @current_state == :completed
        end

        def can_pause?
          running?
        end

        def can_resume?
          paused?
        end

        def can_cancel?
          running? || paused?
        end

        def can_stop?
          running? || paused?
        end

        def can_complete?
          running?
        end

        def get_workflow_status
          @control_mutex.synchronize do
            {
              state: @current_state,
              state_name: WORKFLOW_STATES[@current_state],
              pause_time: @pause_time,
              state_history: @state_history.dup,
              can_pause: can_pause?,
              can_resume: can_resume?,
              can_cancel: can_cancel?,
              can_stop: can_stop?,
              can_complete: can_complete?
            }
          end
        end

        def display_workflow_status
          @frame_manager.section("Workflow Status") do
            status = get_workflow_status
            display_status_info(status)
          end
        end

        def start_control_interface
          return if @control_thread&.alive?

          @control_thread = Thread.new do
            control_interface_loop
          end
        end

        def stop_control_interface
          @control_thread&.kill
          @control_thread = nil
        end

        private

        def validate_state_transition(action)
          case action
          when :pause
            raise InvalidStateError, "Cannot pause workflow in #{@current_state} state" unless can_pause?
          when :resume
            raise InvalidStateError, "Cannot resume workflow in #{@current_state} state" unless can_resume?
          when :cancel
            raise InvalidStateError, "Cannot cancel workflow in #{@current_state} state" unless can_cancel?
          when :stop
            raise InvalidStateError, "Cannot stop workflow in #{@current_state} state" unless can_stop?
          when :complete
            raise InvalidStateError, "Cannot complete workflow in #{@current_state} state" unless can_complete?
          else
            raise InvalidStateError, "Unknown action: #{action}"
          end
        end

        def record_state_change(new_state, reason, additional_data = nil)
          state_change = {
            from_state: @current_state,
            to_state: new_state,
            reason: reason,
            timestamp: Time.now,
            additional_data: additional_data
          }

          @state_history << state_change
        end

        def calculate_pause_duration
          return nil unless @pause_time
          Time.now - @pause_time
        end

        def cleanup_workflow_resources
          # Placeholder for cleanup logic
          # This would clean up any resources, connections, etc.
        end

        def display_status_info(status)
          ::CLI::UI.puts("Current State: #{@formatter.format_state(status[:state])}")
          ::CLI::UI.puts("State Name: #{status[:state_name]}")

          if status[:pause_time]
            ::CLI::UI.puts("Paused Since: #{status[:pause_time]}")
          end

          ::CLI::UI.puts("\nAvailable Actions:")
          ::CLI::UI.puts("  Pause: #{status[:can_pause] ? "Yes" : "No"}")
          ::CLI::UI.puts("  Resume: #{status[:can_resume] ? "Yes" : "No"}")
          ::CLI::UI.puts("  Cancel: #{status[:can_cancel] ? "Yes" : "No"}")
          ::CLI::UI.puts("  Stop: #{status[:can_stop] ? "Yes" : "No"}")
          ::CLI::UI.puts("  Complete: #{status[:can_complete] ? "Yes" : "No"}")
        end

        def control_interface_loop
          loop do
            handle_control_input
            sleep(0.1) # Small delay to prevent excessive CPU usage
          rescue => e
            @status_manager.show_error_status("Control interface error: #{e.message}")
          end
        end

        def handle_control_input
          # Placeholder for control input handling
          # This would listen for keyboard input or other control signals
        end
      end

      # Formats workflow controller display
      class WorkflowControllerFormatter
        def format_state(state)
          case state
          when :running
            ::CLI::UI.fmt("{{green:🟢 Running}}")
          when :paused
            ::CLI::UI.fmt("{{yellow:🟡 Paused}}")
          when :cancelled
            ::CLI::UI.fmt("{{red:🔴 Cancelled}}")
          when :stopped
            ::CLI::UI.fmt("{{red:⏹️ Stopped}}")
          when :completed
            ::CLI::UI.fmt("{{green:✅ Completed}}")
          else
            ::CLI::UI.fmt("{{dim:❓ #{state.to_s.capitalize}}}")
          end
        end

        def format_state_transition(from_state, to_state)
          ::CLI::UI.fmt("{{bold:{{blue:🔄 #{from_state.to_s.capitalize} → #{to_state.to_s.capitalize}}}}}")
        end

        def format_control_action(action)
          case action
          when :pause
            ::CLI::UI.fmt("{{yellow:⏸️ Pause}}")
          when :resume
            ::CLI::UI.fmt("{{green:▶️ Resume}}")
          when :cancel
            ::CLI::UI.fmt("{{red:❌ Cancel}}")
          when :stop
            ::CLI::UI.fmt("{{red:⏹️ Stop}}")
          when :complete
            ::CLI::UI.fmt("{{green:✅ Complete}}")
          else
            ::CLI::UI.fmt("{{dim:❓ #{action.to_s.capitalize}}}")
          end
        end

        def format_control_help
          ::CLI::UI.fmt("{{bold:{{blue:⌨️ Workflow Control Help}}}}")
        end
      end
    end
  end
end
