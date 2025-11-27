# frozen_string_literal: true

module Aidp
  module Harness
    module UI
      module Navigation
        # Specialized submenu for drill-down functionality
        class SubMenu < MainMenu
          class SubMenuError < MenuError; end

          class InvalidSubMenuError < SubMenuError; end

          def initialize(title, parent_menu = nil, ui_components = {})
            super(ui_components)
            @title = title
            @parent_menu = parent_menu
            @ui_components = ui_components
            @submenu_items = []
            @drill_down_enabled = true
            @max_depth = 5
          end

          attr_reader :title, :parent_menu
          attr_accessor :drill_down_enabled, :max_depth

          def add_submenu_item(item)
            validate_submenu_item(item)
            @submenu_items << item
            add_menu_item(item)
          end

          def add_submenu_items(items)
            validate_submenu_items(items)
            items.each { |item| add_submenu_item(item) }
          end

          def show_submenu
            return unless can_show_submenu?

            display_submenu_header
            display_submenu_items
            handle_submenu_interaction
          rescue => e
            raise SubMenuError, "Failed to show submenu: #{e.message}"
          end

          def can_show_submenu?
            @drill_down_enabled && @submenu_items.any? && within_depth_limit?
          end

          def within_depth_limit?
            @current_level < @max_depth
          end

          def has_parent?
            !@parent_menu.nil?
          end

          def get_parent_path
            return [] unless has_parent?

            path = [@title]
            current_parent = @parent_menu

            while current_parent&.parent_menu
              path.unshift(current_parent.title)
              current_parent = current_parent.parent_menu
            end

            path
          end

          def get_full_path
            parent_path = get_parent_path
            parent_path << @title
            parent_path
          end

          def create_child_submenu(title)
            validate_title(title)
            raise InvalidSubMenuError, "Maximum depth reached" unless within_depth_limit?

            child_submenu = SubMenu.new(title, self, @ui_components)
            child_submenu.max_depth = @max_depth
            child_submenu
          end

          def navigate_to_parent
            return false unless has_parent?

            @parent_menu.show_menu(@parent_menu.title)
            true
          end

          private

          def validate_submenu_item(item)
            validate_menu_item(item)
            raise InvalidSubMenuError, "Submenu items must be MenuItems" unless item.is_a?(MenuItem)
          end

          def validate_submenu_items(items)
            raise InvalidSubMenuError, "Submenu items must be an array" unless items.is_a?(Array)
          end

          def display_submenu_header
            @prompt.say(@formatter.format_submenu_title(@title))
            @prompt.say(@formatter.format_separator)

            if has_parent?
              parent_path = get_parent_path.join(" > ")
              @prompt.say(@formatter.format_parent_path(parent_path))
            end
          end

          def display_submenu_items
            @submenu_items.each_with_index do |item, index|
              formatted_item = @formatter.format_submenu_item(item, index + 1)
              @prompt.say(formatted_item)
            end
          end

          def handle_submenu_interaction
            selection = prompt_for_submenu_selection
            handle_submenu_selection(selection)
          end

          def prompt_for_submenu_selection
            options = build_submenu_options
            @prompt.ask("Select an option:") do |handler|
              options.each { |option| handler.option(option) }
            end
          end

          def build_submenu_options
            options = @submenu_items.map(&:title)
            options << "Back to Parent" if has_parent?
            options << "Back to Main Menu"
            options << "Exit"
            options
          end

          def handle_submenu_selection(selection)
            case selection
            when "Back to Parent"
              navigate_to_parent
            when "Back to Main Menu"
              navigate_to_main_menu
            when "Exit"
              :exit
            else
              handle_item_selection(selection)
            end
          end

          def handle_item_selection(selection)
            selected_item = find_submenu_item(selection)
            return unless selected_item

            execute_submenu_item(selected_item)
          end

          def find_submenu_item(title)
            @submenu_items.find { |item| item.title == title }
          end

          def execute_submenu_item(item)
            case item.type
            when :action
              execute_action(item)
            when :submenu
              navigate_to_child_submenu(item)
            when :workflow
              execute_workflow(item)
            else
              raise InvalidSubMenuError, "Unknown submenu item type: #{item.type}"
            end
          end

          def navigate_to_child_submenu(item)
            child_submenu = create_child_submenu(item.title)
            child_submenu.show_submenu
          end

          def navigate_to_main_menu
            # Navigate to the root menu
            root_menu = find_root_menu
            root_menu&.show_menu
          end

          def find_root_menu
            current = self
            while current.parent_menu
              current = current.parent_menu
            end
            current
          end
        end
      end
    end
  end
end
