# frozen_string_literal: true

module Aidp
  module Harness
    module UI
      module Navigation
        # Manages navigation state and history
        class MenuState
          class StateError < StandardError; end
          class InvalidStateError < StateError; end

          def initialize
            @navigation_history = []
            @current_menu = nil
            @menu_stack = []
            @breadcrumbs = []
            @last_selection = nil
          end

          def push_menu(menu_title)
            validate_menu_title(menu_title)

            @menu_stack << menu_title
            @breadcrumbs << menu_title
            @current_menu = menu_title
          end

          def pop_menu
            return nil if @menu_stack.empty?

            @menu_stack.pop
            @breadcrumbs.pop
            @current_menu = @menu_stack.last
            @current_menu
          end

          def set_current_menu(menu_title)
            validate_menu_title(menu_title)
            @current_menu = menu_title
          end

          def record_selection(selection)
            @last_selection = selection
            @navigation_history << {
              menu: @current_menu,
              selection: selection,
              timestamp: Time.now
            }
          end

          def record_workflow_mode_selection(mode)
            @navigation_history << {
              menu: @current_menu,
              selection: "workflow_mode: #{mode}",
              timestamp: Time.now
            }
          end

          def record_keyboard_navigation(key, action)
            @navigation_history << {
              menu: @current_menu,
              selection: "keyboard: #{key} -> #{action}",
              timestamp: Time.now
            }
          end

          def record_progressive_disclosure(level, action)
            @navigation_history << {
              menu: @current_menu,
              selection: "progressive: level #{level} -> #{action}",
              timestamp: Time.now
            }
          end

          def get_navigation_history
            @navigation_history.dup
          end

          def get_breadcrumbs
            @breadcrumbs.dup
          end

          def get_menu_stack
            @menu_stack.dup
          end

          def current_menu
            @current_menu
          end

          def last_selection
            @last_selection
          end

          def menu_depth
            @menu_stack.size
          end

          def can_go_back?
            @menu_stack.size > 1
          end

          def clear_history
            @navigation_history.clear
          end

          def clear_breadcrumbs
            @breadcrumbs.clear
          end

          def clear_menu_stack
            @menu_stack.clear
            @current_menu = nil
          end

          def reset
            clear_history
            clear_breadcrumbs
            clear_menu_stack
            @last_selection = nil
          end

          def export_state
            {
              current_menu: @current_menu,
              menu_stack: @menu_stack,
              breadcrumbs: @breadcrumbs,
              last_selection: @last_selection,
              navigation_history: @navigation_history,
              menu_depth: menu_depth
            }
          end

          private

          def validate_menu_title(menu_title)
            raise InvalidStateError, "Menu title cannot be empty" if menu_title.to_s.strip.empty?
          end
        end
      end
    end
  end
end
