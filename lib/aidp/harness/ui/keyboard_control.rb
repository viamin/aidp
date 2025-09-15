# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # Keyboard shortcuts for workflow control
      class KeyboardControl < Base
        class KeyboardError < StandardError; end
        class InvalidShortcutError < KeyboardError; end
        class ShortcutConflictError < KeyboardError; end

        DEFAULT_SHORTCUTS = {
          "p" => :pause,
          "r" => :resume,
          "c" => :cancel,
          "s" => :stop,
          "q" => :quit,
          "h" => :help,
          "?" => :help,
          "esc" => :back,
          "ctrl+c" => :interrupt,
          "ctrl+z" => :suspend
        }.freeze

        def initialize(ui_components = {})
          super()
          @formatter = ui_components[:formatter] || KeyboardControlFormatter.new
          @shortcuts = DEFAULT_SHORTCUTS.dup
          @custom_shortcuts = {}
          @shortcut_handlers = {}
          @control_enabled = true
        end

        def register_shortcut(key, action, handler = nil)
          validate_shortcut_key(key)
          validate_shortcut_action(action)

          if @shortcuts.key?(key) || @custom_shortcuts.key?(key)
            raise ShortcutConflictError, "Shortcut '#{key}' is already registered"
          end

          @custom_shortcuts[key] = action
          @shortcut_handlers[action] = handler if handler
        end

        def unregister_shortcut(key)
          validate_shortcut_key(key)

          if @custom_shortcuts.key?(key)
            action = @custom_shortcuts.delete(key)
            @shortcut_handlers.delete(action)
          else
            raise InvalidShortcutError, "Shortcut '#{key}' is not registered"
          end
        end

        def handle_key_input(key)
          return unless @control_enabled

          action = get_action_for_key(key)
          return unless action

          execute_shortcut_action(action, key)
        rescue => e
          raise KeyboardError, "Failed to handle key input: #{e.message}"
        end

        def enable_control
          @control_enabled = true
        end

        def disable_control
          @control_enabled = false
        end

        def control_enabled?
          @control_enabled
        end

        def get_shortcuts
          {
            default: @shortcuts.dup,
            custom: @custom_shortcuts.dup,
            all: @shortcuts.merge(@custom_shortcuts)
          }
        end

        def display_shortcuts_help
          @formatter.display_shortcuts_help(@shortcuts, @custom_shortcuts)
        end

        def get_shortcut_for_action(action)
          all_shortcuts = @shortcuts.merge(@custom_shortcuts)
          all_shortcuts.key(action)
        end

        def has_shortcut?(key)
          @shortcuts.key?(key) || @custom_shortcuts.key?(key)
        end

        private

        def validate_shortcut_key(key)
          raise InvalidShortcutError, "Shortcut key cannot be empty" if key.to_s.strip.empty?
        end

        def validate_shortcut_action(action)
          raise InvalidShortcutError, "Shortcut action cannot be empty" if action.to_s.strip.empty?
        end

        def get_action_for_key(key)
          normalized_key = normalize_key(key)
          @shortcuts[normalized_key] || @custom_shortcuts[normalized_key]
        end

        def normalize_key(key)
          key.to_s.downcase.strip
        end

        def execute_shortcut_action(action, key)
          # Execute default action
          execute_default_action(action, key)

          # Execute custom handler if available
          execute_custom_handler(action, key)
        end

        def execute_default_action(action, key)
          case action
          when :pause
            handle_pause_action(key)
          when :resume
            handle_resume_action(key)
          when :cancel
            handle_cancel_action(key)
          when :stop
            handle_stop_action(key)
          when :quit
            handle_quit_action(key)
          when :help
            handle_help_action(key)
          when :back
            handle_back_action(key)
          when :interrupt
            handle_interrupt_action(key)
          when :suspend
            handle_suspend_action(key)
          else
            handle_unknown_action(action, key)
          end
        end

        def execute_custom_handler(action, key)
          handler = @shortcut_handlers[action]
          if handler&.respond_to?(:call)
            handler.call(action, key)
          end
        end

        def handle_pause_action(key)
          CLI::UI.puts(@formatter.format_shortcut_action("pause", key))
          # Trigger pause workflow
        end

        def handle_resume_action(key)
          CLI::UI.puts(@formatter.format_shortcut_action("resume", key))
          # Trigger resume workflow
        end

        def handle_cancel_action(key)
          CLI::UI.puts(@formatter.format_shortcut_action("cancel", key))
          # Trigger cancel workflow
        end

        def handle_stop_action(key)
          CLI::UI.puts(@formatter.format_shortcut_action("stop", key))
          # Trigger stop workflow
        end

        def handle_quit_action(key)
          CLI::UI.puts(@formatter.format_shortcut_action("quit", key))
          # Trigger quit application
        end

        def handle_help_action(key)
          display_shortcuts_help
        end

        def handle_back_action(key)
          CLI::UI.puts(@formatter.format_shortcut_action("back", key))
          # Trigger back navigation
        end

        def handle_interrupt_action(key)
          CLI::UI.puts(@formatter.format_shortcut_action("interrupt", key))
          # Trigger interrupt signal
        end

        def handle_suspend_action(key)
          CLI::UI.puts(@formatter.format_shortcut_action("suspend", key))
          # Trigger suspend signal
        end

        def handle_unknown_action(action, key)
          CLI::UI.puts(@formatter.format_unknown_action(action, key))
        end
      end

      # Formats keyboard control display
      class KeyboardControlFormatter
        def display_shortcuts_help(default_shortcuts, custom_shortcuts)
          CLI::UI.puts(CLI::UI.fmt("{{bold:{{blue:⌨️ Keyboard Shortcuts Help}}}}"))
          CLI::UI.puts("─" * 50)

          CLI::UI.puts("\n{{bold:Default Shortcuts:}}")
          display_shortcut_section(default_shortcuts)

          if custom_shortcuts.any?
            CLI::UI.puts("\n{{bold:Custom Shortcuts:}}")
            display_shortcut_section(custom_shortcuts)
          end

          CLI::UI.puts("\n{{dim:Press any shortcut key to execute the action}}")
        end

        def display_shortcut_section(shortcuts)
          shortcuts.each do |key, action|
            CLI::UI.puts(format_shortcut_line(key, action))
          end
        end

        def format_shortcut_line(key, action)
          key_display = format_key_display(key)
          action_display = format_action_display(action)
          CLI::UI.fmt("  {{bold:#{key_display}}} - {{dim:#{action_display}}}")
        end

        def format_key_display(key)
          case key
          when "ctrl+c"
            "Ctrl+C"
          when "ctrl+z"
            "Ctrl+Z"
          when "esc"
            "Esc"
          else
            key.upcase
          end
        end

        def format_action_display(action)
          case action
          when :pause
            "Pause workflow"
          when :resume
            "Resume workflow"
          when :cancel
            "Cancel workflow"
          when :stop
            "Stop workflow"
          when :quit
            "Quit application"
          when :help
            "Show help"
          when :back
            "Go back"
          when :interrupt
            "Interrupt signal"
          when :suspend
            "Suspend signal"
          else
            action.to_s.capitalize
          end
        end

        def format_shortcut_action(action, key)
          CLI::UI.fmt("{{green:⚡ #{action.capitalize} triggered by #{key.upcase}}}")
        end

        def format_unknown_action(action, key)
          CLI::UI.fmt("{{yellow:⚠️ Unknown action '#{action}' for key '#{key}'}}")
        end

        def format_shortcut_registered(key, action)
          CLI::UI.fmt("{{green:✅ Shortcut registered: #{key.upcase} → #{action}}}")
        end

        def format_shortcut_unregistered(key)
          CLI::UI.fmt("{{yellow:🗑️ Shortcut unregistered: #{key.upcase}}}")
        end

        def format_shortcut_conflict(key)
          CLI::UI.fmt("{{red:❌ Shortcut conflict: #{key.upcase} is already registered}}")
        end

        def format_control_enabled
          CLI::UI.fmt("{{green:✅ Keyboard control enabled}}")
        end

        def format_control_disabled
          CLI::UI.fmt("{{red:❌ Keyboard control disabled}}")
        end
      end
    end
  end
end
