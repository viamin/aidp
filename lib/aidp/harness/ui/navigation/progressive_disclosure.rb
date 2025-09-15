# frozen_string_literal: true

require_relative "../base"

module Aidp
  module Harness
    module UI
      module Navigation
        # Implements progressive disclosure pattern for navigation
        class ProgressiveDisclosure < Base
          class DisclosureError < StandardError; end
          class InvalidLevelError < DisclosureError; end

          def initialize(ui_components = {})
            super()
            @prompt = ui_components[:prompt] || CLI::UI::Prompt
            @formatter = ui_components[:formatter] || DisclosureFormatter.new
            @disclosure_levels = {}
            @current_level = 0
            @max_visible_level = 2
          end

          def add_disclosure_level(level, items)
            validate_level(level)
            validate_items(items)
            @disclosure_levels[level] = items
          end

          def show_progressive_menu(title)
            display_progressive_header(title)
            display_current_level_items
            handle_progressive_interaction
          rescue StandardError => e
            raise DisclosureError, "Failed to show progressive menu: #{e.message}"
          end

          def expand_level(level)
            validate_level(level)
            return false unless can_expand_level?(level)

            @current_level = level
            display_level_items(level)
            true
          end

          def collapse_level(level)
            validate_level(level)
            return false unless can_collapse_level?(level)

            @current_level = [level - 1, 0].max
            display_current_level_items
            true
          end

          def can_expand_level?(level)
            @disclosure_levels.key?(level) && level <= @max_visible_level
          end

          def can_collapse_level?(level)
            level > 0
          end

          def get_visible_items
            visible_levels = (0..@current_level).select { |level| @disclosure_levels.key?(level) }
            visible_levels.flat_map { |level| @disclosure_levels[level] }
          end

          def get_level_items(level)
            validate_level(level)
            @disclosure_levels[level] || []
          end

          def current_level
            @current_level
          end

          def max_visible_level
            @max_visible_level
          end

          def set_max_visible_level(level)
            validate_level(level)
            @max_visible_level = level
          end

          private

          def validate_level(level)
            raise InvalidLevelError, "Level must be non-negative" unless level >= 0
          end

          def validate_items(items)
            raise InvalidLevelError, "Items must be an array" unless items.is_a?(Array)
          end

          def display_progressive_header(title)
            CLI::UI.puts(@formatter.format_progressive_title(title))
            CLI::UI.puts(@formatter.format_separator)
            CLI::UI.puts(@formatter.format_level_indicator(@current_level))
          end

          def display_current_level_items
            display_level_items(@current_level)
          end

          def display_level_items(level)
            items = get_level_items(level)
            return if items.empty?

            CLI::UI.puts(@formatter.format_level_header(level))
            items.each_with_index do |item, index|
              display_progressive_item(item, index + 1, level)
            end
          end

          def display_progressive_item(item, index, level)
            formatted_item = @formatter.format_progressive_item(item, index, level)
            CLI::UI.puts(formatted_item)

            if has_sub_items?(item)
              display_expand_option(item)
            end
          end

          def display_expand_option(item)
            CLI::UI.puts(@formatter.format_expand_option(item))
          end

          def has_sub_items?(item)
            item.respond_to?(:sub_items) && !item.sub_items.empty?
          end

          def handle_progressive_interaction
            selection = prompt_for_progressive_selection
            handle_progressive_selection(selection)
          end

          def prompt_for_progressive_selection
            options = build_progressive_options
            @prompt.ask("Select an option:") do |handler|
              options.each { |option| handler.option(option) }
            end
          end

          def build_progressive_options
            options = get_visible_items.map(&:title)
            options << "Expand More" if can_expand_more?
            options << "Collapse" if can_collapse?
            options << "Back"
            options << "Exit"
            options
          end

          def can_expand_more?
            @current_level < @max_visible_level && @disclosure_levels.key?(@current_level + 1)
          end

          def can_collapse?
            @current_level > 0
          end

          def handle_progressive_selection(selection)
            case selection
            when "Expand More"
              expand_level(@current_level + 1)
            when "Collapse"
              collapse_level(@current_level)
            when "Back"
              :back
            when "Exit"
              :exit
            else
              handle_item_selection(selection)
            end
          end

          def handle_item_selection(selection)
            selected_item = find_visible_item(selection)
            return unless selected_item

            execute_progressive_item(selected_item)
          end

          def find_visible_item(title)
            get_visible_items.find { |item| item.title == title }
          end

          def execute_progressive_item(item)
            if has_sub_items?(item)
              expand_item_sub_items(item)
            else
              execute_item_action(item)
            end
          end

          def expand_item_sub_items(item)
            # Add sub-items to the next level
            next_level = @current_level + 1
            add_disclosure_level(next_level, item.sub_items)
            expand_level(next_level)
          end

          def execute_item_action(item)
            item.action.call if item.respond_to?(:action) && item.action
          end
        end

        # Formats progressive disclosure display
        class DisclosureFormatter
          def format_progressive_title(title)
            CLI::UI.fmt("{{bold:{{blue:🔍 #{title}}}}}")
          end

          def format_separator
            "─" * 50
          end

          def format_level_indicator(level)
            CLI::UI.fmt("{{dim:Level: #{level}}}")
          end

          def format_level_header(level)
            CLI::UI.fmt("{{bold:{{yellow:📁 Level #{level} Items:}}}}")
          end

          def format_progressive_item(item, index, level)
            indent = "  " * level
            CLI::UI.fmt("#{indent}{{bold:#{index}.}} {{bold:#{item.title}}}")
          end

          def format_expand_option(item)
            CLI::UI.fmt("{{dim:    └─ Has sub-items (expand to see more)}}")
          end

          def format_expand_more_option
            CLI::UI.fmt("{{bold:{{green:➕ Expand More}}}}")
          end

          def format_collapse_option
            CLI::UI.fmt("{{bold:{{yellow:➖ Collapse}}}}")
          end

          def format_back_option
            CLI::UI.fmt("{{bold:{{blue:← Back}}}}")
          end

          def format_exit_option
            CLI::UI.fmt("{{bold:{{red:✗ Exit}}}}")
          end
        end
      end
    end
  end
end
