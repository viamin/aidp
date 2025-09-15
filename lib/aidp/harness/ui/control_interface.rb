# frozen_string_literal: true

require_relative "base"
require_relative "workflow_controller"
require_relative "keyboard_control"
require_relative "frame_manager"

module Aidp
  module Harness
    module UI
      # Control interface status display and management
      class ControlInterface < Base
        class ControlError < StandardError; end
        class InterfaceError < ControlError; end

        def initialize(ui_components = {})
          super()
          @workflow_controller = ui_components[:workflow_controller] || WorkflowController.new
          @keyboard_control = ui_components[:keyboard_control] || KeyboardControl.new
          @frame_manager = ui_components[:frame_manager] || FrameManager.new
          @formatter = ui_components[:formatter] || ControlInterfaceFormatter.new

          @interface_active = false
          @status_display_enabled = true
          @auto_refresh_interval = 1.0
          @refresh_thread = nil
        end

        def start_control_interface
          return if @interface_active

          @interface_active = true
          @workflow_controller.start_control_interface
          start_status_refresh

          CLI::UI.puts(@formatter.format_interface_started)
        rescue => e
          raise InterfaceError, "Failed to start control interface: #{e.message}"
        end

        def stop_control_interface
          return unless @interface_active

          @interface_active = false
          stop_status_refresh
          @workflow_controller.stop_control_interface

          CLI::UI.puts(@formatter.format_interface_stopped)
        rescue => e
          raise InterfaceError, "Failed to stop control interface: #{e.message}"
        end

        def display_control_status
          @frame_manager.section("Control Interface Status") do
            display_interface_status
            display_workflow_status
            display_keyboard_shortcuts
            display_control_options
          end
        end

        def enable_status_display
          @status_display_enabled = true
          CLI::UI.puts(@formatter.format_status_display_enabled)
        end

        def disable_status_display
          @status_display_enabled = false
          CLI::UI.puts(@formatter.format_status_display_disabled)
        end

        def set_auto_refresh_interval(interval_seconds)
          validate_refresh_interval(interval_seconds)
          @auto_refresh_interval = interval_seconds
          CLI::UI.puts(@formatter.format_refresh_interval_set(interval_seconds))
        end

        def handle_control_input(input)
          return unless @interface_active

          case input.downcase
          when "status", "s"
            display_control_status
          when "help", "h", "?"
            display_control_help
          when "pause", "p"
            handle_pause_request
          when "resume", "r"
            handle_resume_request
          when "cancel", "c"
            handle_cancel_request
          when "stop", "st"
            handle_stop_request
          when "quit", "q"
            handle_quit_request
          when "refresh", "rf"
            display_control_status
          else
            CLI::UI.puts(@formatter.format_unknown_command(input))
          end
        end

        def interface_active?
          @interface_active
        end

        def status_display_enabled?
          @status_display_enabled
        end

        private

        def validate_refresh_interval(interval_seconds)
          raise ControlError, "Refresh interval must be positive" unless interval_seconds > 0
        end

        def start_status_refresh
          return unless @status_display_enabled

          @refresh_thread = Thread.new do
            loop do
              break unless @interface_active

              display_control_status if @status_display_enabled
              sleep(@auto_refresh_interval)
            end
          end
        end

        def stop_status_refresh
          @refresh_thread&.kill
          @refresh_thread = nil
        end

        def display_interface_status
          CLI::UI.puts("Interface Status:")
          CLI::UI.puts("  Active: #{@interface_active ? "Yes" : "No"}")
          CLI::UI.puts("  Status Display: #{@status_display_enabled ? "Enabled" : "Disabled"}")
          CLI::UI.puts("  Auto Refresh: #{@auto_refresh_interval}s")
        end

        def display_workflow_status
          workflow_status = @workflow_controller.get_workflow_status

          CLI::UI.puts("\nWorkflow Status:")
          CLI::UI.puts("  State: #{@formatter.format_workflow_state(workflow_status[:state])}")
          CLI::UI.puts("  Can Pause: #{workflow_status[:can_pause] ? "Yes" : "No"}")
          CLI::UI.puts("  Can Resume: #{workflow_status[:can_resume] ? "Yes" : "No"}")
          CLI::UI.puts("  Can Cancel: #{workflow_status[:can_cancel] ? "Yes" : "No"}")
          CLI::UI.puts("  Can Stop: #{workflow_status[:can_stop] ? "Yes" : "No"}")
        end

        def display_keyboard_shortcuts
          shortcuts = @keyboard_control.get_shortcuts[:default]

          CLI::UI.puts("\nKeyboard Shortcuts:")
          shortcuts.each do |key, action|
            CLI::UI.puts("  #{key.upcase}: #{action.to_s.capitalize}")
          end
        end

        def display_control_options
          CLI::UI.puts("\nControl Options:")
          CLI::UI.puts("  status/s - Show this status")
          CLI::UI.puts("  help/h/? - Show help")
          CLI::UI.puts("  pause/p - Pause workflow")
          CLI::UI.puts("  resume/r - Resume workflow")
          CLI::UI.puts("  cancel/c - Cancel workflow")
          CLI::UI.puts("  stop/st - Stop workflow")
          CLI::UI.puts("  quit/q - Quit interface")
        end

        def display_control_help
          @frame_manager.section("Control Interface Help") do
            CLI::UI.puts("The control interface allows you to manage workflow execution.")
            CLI::UI.puts("\nAvailable Commands:")
            display_control_options
            CLI::UI.puts("\nKeyboard Shortcuts:")
            @keyboard_control.display_shortcuts_help
          end
        end

        def handle_pause_request
          if @workflow_controller.can_pause?
            @workflow_controller.pause_workflow("User requested via control interface")
          else
            CLI::UI.puts(@formatter.format_action_not_available("pause"))
          end
        end

        def handle_resume_request
          if @workflow_controller.can_resume?
            @workflow_controller.resume_workflow("User requested via control interface")
          else
            CLI::UI.puts(@formatter.format_action_not_available("resume"))
          end
        end

        def handle_cancel_request
          if @workflow_controller.can_cancel?
            @workflow_controller.cancel_workflow("User requested via control interface")
          else
            CLI::UI.puts(@formatter.format_action_not_available("cancel"))
          end
        end

        def handle_stop_request
          if @workflow_controller.can_stop?
            @workflow_controller.stop_workflow("User requested via control interface")
          else
            CLI::UI.puts(@formatter.format_action_not_available("stop"))
          end
        end

        def handle_quit_request
          CLI::UI.puts(@formatter.format_quit_request)
          stop_control_interface
        end
      end

      # Formats control interface display
      class ControlInterfaceFormatter
        def format_interface_started
          CLI::UI.fmt("{{green:✅ Control interface started}}")
        end

        def format_interface_stopped
          CLI::UI.fmt("{{red:❌ Control interface stopped}}")
        end

        def format_status_display_enabled
          CLI::UI.fmt("{{green:✅ Status display enabled}}")
        end

        def format_status_display_disabled
          CLI::UI.fmt("{{red:❌ Status display disabled}}")
        end

        def format_refresh_interval_set(interval_seconds)
          CLI::UI.fmt("{{blue:🔄 Auto refresh interval set to #{interval_seconds}s}}")
        end

        def format_workflow_state(state)
          case state
          when :running
            CLI::UI.fmt("{{green:🟢 Running}}")
          when :paused
            CLI::UI.fmt("{{yellow:🟡 Paused}}")
          when :cancelled
            CLI::UI.fmt("{{red:🔴 Cancelled}}")
          when :stopped
            CLI::UI.fmt("{{red:⏹️ Stopped}}")
          when :completed
            CLI::UI.fmt("{{green:✅ Completed}}")
          else
            CLI::UI.fmt("{{dim:❓ #{state.to_s.capitalize}}}")
          end
        end

        def format_action_not_available(action)
          CLI::UI.fmt("{{yellow:⚠️ Action '#{action}' is not available in current workflow state}}")
        end

        def format_unknown_command(command)
          CLI::UI.fmt("{{yellow:⚠️ Unknown command: '#{command}'. Type 'help' for available commands.}}")
        end

        def format_quit_request
          CLI::UI.fmt("{{blue:👋 Quitting control interface...}}")
        end

        def format_control_prompt
          CLI::UI.fmt("{{bold:{{blue:🎮 Control Interface}}} {{dim:(type 'help' for commands)}}}")
        end
      end
    end
  end
end
