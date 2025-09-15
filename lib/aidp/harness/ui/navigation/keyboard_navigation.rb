# frozen_string_literal: true

require_relative "../base"

module Aidp
  module Harness
    module UI
      module Navigation
        # Handles keyboard navigation for menu systems
        class KeyboardNavigation < Base
          class KeyboardError < StandardError; end
          class InvalidKeyError < KeyboardError; end

          KEYBOARD_SHORTCUTS = {
            "j" => :down,
            "k" => :up,
            "h" => :left,
            "l" => :right,
            "enter" => :select,
            "space" => :select,
            "q" => :quit,
            "esc" => :back,
            "b" => :back,
            "r" => :refresh,
            "?" => :help,
            "tab" => :next,
            "shift+tab" => :previous
          }.freeze

          def initialize(ui_components = {})
            super()
            @key_handler = ui_components[:key_handler] || default_key_handler
            @formatter = ui_components[:formatter] || KeyboardFormatter.new
            @current_selection = 0
            @menu_items = []
            @navigation_enabled = true
          end

          def enable_keyboard_navigation
            @navigation_enabled = true
          end

          def disable_keyboard_navigation
            @navigation_enabled = false
          end

          def set_menu_items(items)
            validate_menu_items(items)
            @menu_items = items
            @current_selection = 0
          end

          def handle_key_input(key)
            return unless @navigation_enabled

            action = parse_key_action(key)
            execute_key_action(action)
          rescue => e
            raise KeyboardError, "Failed to handle key input: #{e.message}"
          end

          def get_current_selection
            @current_selection
          end

          def set_current_selection(index)
            validate_selection_index(index)
            @current_selection = index
          end

          def move_selection(direction)
            case direction
            when :up
              move_up
            when :down
              move_down
            when :left
              move_left
            when :right
              move_right
            else
              raise InvalidKeyError, "Invalid direction: #{direction}"
            end
          end

          def display_keyboard_help
            CLI::UI.puts(@formatter.format_help_header)
            CLI::UI.puts(@formatter.format_help_separator)
            display_help_shortcuts
          end

          private

          def validate_menu_items(items)
            raise InvalidKeyError, "Menu items must be an array" unless items.is_a?(Array)
          end

          def validate_selection_index(index)
            raise InvalidKeyError, "Selection index must be within bounds" unless (0...@menu_items.size).cover?(index)
          end

          def parse_key_action(key)
            normalized_key = normalize_key(key)
            KEYBOARD_SHORTCUTS[normalized_key] || :unknown
          end

          def normalize_key(key)
            key.to_s.downcase
          end

          def execute_key_action(action)
            case action
            when :up
              move_up
            when :down
              move_down
            when :left
              move_left
            when :right
              move_right
            when :select
              select_current_item
            when :quit
              :quit
            when :back
              :back
            when :refresh
              :refresh
            when :help
              display_keyboard_help
            when :next
              move_down
            when :previous
              move_up
            when :unknown
              handle_unknown_key
            else
              raise InvalidKeyError, "Unknown action: #{action}"
            end
          end

          def move_up
            @current_selection = [@current_selection - 1, 0].max
            highlight_current_selection
          end

          def move_down
            @current_selection = [@current_selection + 1, @menu_items.size - 1].min
            highlight_current_selection
          end

          def move_left
            # Left navigation logic (could be used for submenu navigation)
            :left
          end

          def move_right
            # Right navigation logic (could be used for submenu navigation)
            :right
          end

          def select_current_item
            return nil if @menu_items.empty?

            @menu_items[@current_selection]
          end

          def highlight_current_selection
            return if @menu_items.empty?

            # Clear previous highlights and highlight current selection
            display_menu_with_highlight
          end

          def display_menu_with_highlight
            @menu_items.each_with_index do |item, index|
              if index == @current_selection
                display_highlighted_item(item, index)
              else
                display_normal_item(item, index)
              end
            end
          end

          def display_highlighted_item(item, index)
            formatted_item = @formatter.format_highlighted_item(item, index + 1)
            CLI::UI.puts(formatted_item)
          end

          def display_normal_item(item, index)
            formatted_item = @formatter.format_normal_item(item, index + 1)
            CLI::UI.puts(formatted_item)
          end

          def handle_unknown_key
            # Could display a brief "unknown key" message
            CLI::UI.puts(@formatter.format_unknown_key_message)
          end

          def display_help_shortcuts
            KEYBOARD_SHORTCUTS.each do |key, action|
              CLI::UI.puts(@formatter.format_help_shortcut(key, action))
            end
          end

          def default_key_handler
            # Default key handler implementation
            ->(key) { key }
          end
        end

        # Formats keyboard navigation display
        class KeyboardFormatter
          def format_help_header
            CLI::UI.fmt("{{bold:{{blue:⌨️  Keyboard Navigation Help}}}}")
          end

          def format_help_separator
            "─" * 40
          end

          def format_help_shortcut(key, action)
            action_name = format_action_name(action)
            CLI::UI.fmt("{{bold:#{key}}} - {{dim:#{action_name}}}")
          end

          def format_action_name(action)
            case action
            when :up
              "Move up"
            when :down
              "Move down"
            when :left
              "Move left"
            when :right
              "Move right"
            when :select
              "Select item"
            when :quit
              "Quit"
            when :back
              "Go back"
            when :refresh
              "Refresh"
            when :help
              "Show help"
            when :next
              "Next item"
            when :previous
              "Previous item"
            else
              action.to_s.capitalize
            end
          end

          def format_highlighted_item(item, index)
            CLI::UI.fmt("{{bold:{{green:► #{index}. #{item.title}}}}}")
          end

          def format_normal_item(item, index)
            CLI::UI.fmt("{{bold:#{index}.}} {{dim:#{item.title}}}")
          end

          def format_unknown_key_message
            CLI::UI.fmt("{{yellow:⚠ Unknown key. Press ? for help.}}")
          end

          def format_navigation_prompt
            CLI::UI.fmt("{{dim:Use arrow keys or j/k to navigate, Enter to select, ? for help}}")
          end
        end
      end
    end
  end
end
