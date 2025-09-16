# frozen_string_literal: true

require "tty-prompt"
require "pastel"
require_relative "../base"
require_relative "menu_item"
require_relative "menu_state"
require_relative "menu_formatter"

module Aidp
  module Harness
    module UI
      module Navigation
        # Main hierarchical navigation menu system
        class MainMenu < Base
          class MenuError < StandardError; end
          class InvalidMenuError < MenuError; end
          class NavigationError < MenuError; end

          def initialize(ui_components = {})
            super()
            @prompt = ui_components[:prompt] || TTY::Prompt.new
            @pastel = Pastel.new
            @formatter = ui_components[:formatter] || MenuFormatter.new
            @state_manager = ui_components[:state_manager] || MenuState.new
            @menu_items = []
            @current_level = 0
            @breadcrumb = []
          end

          def add_menu_item(item)
            validate_menu_item(item)
            @menu_items << item
          end

          def add_menu_items(items)
            validate_menu_items(items)
            items.each { |item| add_menu_item(item) }
          end

          def show_menu(title = "Main Menu")
            validate_title(title)

            loop do
              display_menu_header(title)
              display_breadcrumb
              display_menu_items

              selection = prompt_for_selection
              break if handle_selection(selection) == :exit
            end
          rescue => e
            raise NavigationError, "Failed to show menu: #{e.message}"
          end

          def navigate_to_submenu(submenu_title)
            validate_title(submenu_title)

            submenu = find_submenu(submenu_title)
            raise InvalidMenuError, "Submenu '#{submenu_title}' not found" unless submenu

            @breadcrumb << submenu_title
            @current_level += 1

            submenu.show_menu(submenu_title)
          rescue => e
            raise NavigationError, "Failed to navigate to submenu: #{e.message}"
          end

          def go_back
            return false if @breadcrumb.empty?

            @breadcrumb.pop
            @current_level -= 1
            true
          end

          def current_path
            @breadcrumb.join(" > ")
          end

          def menu_depth
            @current_level
          end

          private

          def validate_menu_item(item)
            raise InvalidMenuError, "Menu item must be a MenuItem" unless item.is_a?(MenuItem)
          end

          def validate_menu_items(items)
            raise InvalidMenuError, "Menu items must be an array" unless items.is_a?(Array)
          end

          def validate_title(title)
            raise InvalidMenuError, "Title cannot be empty" if title.to_s.strip.empty?
          end

          def display_menu_header(title)
            formatted_title = @formatter.format_menu_title(title)
            puts(formatted_title)
            puts(@formatter.format_separator)
          end

          def display_breadcrumb
            return if @breadcrumb.empty?

            breadcrumb_text = @formatter.format_breadcrumb(@breadcrumb)
            puts(breadcrumb_text)
          end

          def display_menu_items
            @menu_items.each_with_index do |item, index|
              formatted_item = @formatter.format_menu_item(item, index + 1)
              puts(formatted_item)
            end
          end

          def prompt_for_selection
            options = build_selection_options
            @prompt.ask("Select an option:") do |handler|
              options.each { |option| handler.option(option) }
            end
          end

          def build_selection_options
            options = @menu_items.map(&:title)
            options << "Back" unless @breadcrumb.empty?
            options << "Exit"
            options
          end

          def handle_selection(selection)
            return :exit if selection == "Exit"
            return :back if selection == "Back"

            selected_item = find_menu_item(selection)
            execute_menu_item(selected_item)
          end

          def find_menu_item(title)
            @menu_items.find { |item| item.title == title }
          end

          def find_submenu(title)
            @menu_items.find { |item| item.submenu? && item.title == title }
          end

          def execute_menu_item(item)
            case item.type
            when :action
              execute_action(item)
            when :submenu
              navigate_to_submenu(item.title)
            when :workflow
              execute_workflow(item)
            else
              raise InvalidMenuError, "Unknown menu item type: #{item.type}"
            end
          end

          def execute_action(item)
            item.action&.call
          end

          def execute_workflow(item)
            item.workflow&.call
          end
        end
      end
    end
  end
end
