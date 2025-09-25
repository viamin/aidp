# frozen_string_literal: true

require "tty-prompt"
require "pastel"
require_relative "../base"
require_relative "menu_item"

module Aidp
  module Harness
    module UI
      module Navigation
        # Handles workflow mode selection (simple vs advanced)
        class WorkflowSelector < Base
          class WorkflowError < StandardError; end
          class InvalidModeError < WorkflowError; end
          class SelectionError < WorkflowError; end

          WORKFLOW_MODES = {
            simple: {
              name: "Simple Mode",
              description: "Predefined workflows with guided templates",
              icon: "🚀"
            },
            advanced: {
              name: "Advanced Mode",
              description: "Custom workflow configuration",
              icon: "⚙️"
            }
          }.freeze

          def initialize(ui_components = {}, prompt: nil)
            super()
            @prompt = prompt || ui_components[:prompt] || TTY::Prompt.new
            @pastel = Pastel.new
            @formatter = ui_components[:formatter] || WorkflowFormatter.new
            @state_manager = ui_components[:state_manager]
          end

          def select_workflow_mode
            display_mode_selection
            selection = prompt_for_mode_selection
            validate_selection(selection)

            selected_mode = parse_selection(selection)
            record_selection(selected_mode)
            selected_mode
          rescue => e
            raise SelectionError, "Failed to select workflow mode: #{e.message}"
          end

          def show_mode_description(mode)
            validate_mode(mode)

            mode_info = WORKFLOW_MODES[mode]
            display_mode_info(mode_info)
          end

          def get_available_modes
            WORKFLOW_MODES.keys
          end

          def get_mode_info(mode)
            validate_mode(mode)
            WORKFLOW_MODES[mode]
          end

          def is_simple_mode?(mode)
            mode == :simple
          end

          def is_advanced_mode?(mode)
            mode == :advanced
          end

          private

          def display_mode_selection
            @prompt.say(@formatter.format_selector_title)
            @prompt.say(@formatter.format_separator)

            WORKFLOW_MODES.each_with_index do |(key, info), index|
              display_mode_option(key, info, index + 1)
            end

            @prompt.say(@formatter.format_separator)
          end

          def display_mode_option(mode_key, mode_info, index)
            formatted_option = @formatter.format_mode_option(mode_key, mode_info, index)
            @prompt.say(formatted_option)
          end

          def display_mode_info(mode_info)
            @prompt.say(@formatter.format_mode_info(mode_info))
          end

          def prompt_for_mode_selection
            options = build_mode_options
            @prompt.ask("Select workflow mode:") do |handler|
              options.each { |option| handler.option(option) }
            end
          end

          def build_mode_options
            WORKFLOW_MODES.map { |key, info| "#{info[:icon]} #{info[:name]}" }
          end

          def validate_selection(selection)
            raise InvalidModeError, "Selection cannot be empty" if selection.to_s.strip.empty?
          end

          def parse_selection(selection)
            WORKFLOW_MODES.each do |key, info|
              return key if selection.include?(info[:name])
            end

            raise InvalidModeError, "Invalid selection: #{selection}"
          end

          def validate_mode(mode)
            unless WORKFLOW_MODES.key?(mode)
              raise InvalidModeError, "Invalid mode: #{mode}. Must be one of: #{WORKFLOW_MODES.keys.join(", ")}"
            end
          end

          def record_selection(mode)
            @state_manager&.record_workflow_mode_selection(mode)
          end
        end

        # Formats workflow selection display
        class WorkflowFormatter
          def initialize
            @pastel = Pastel.new
          end

          def format_selector_title
            @pastel.bold(@pastel.blue("🎯 Workflow Mode Selection"))
          end

          def format_separator
            "─" * 60
          end

          def format_mode_option(mode_key, mode_info, index)
            icon = mode_info[:icon]
            name = mode_info[:name]
            description = mode_info[:description]

            "#{@pastel.bold("#{index}.")} #{@pastel.bold("#{icon} #{name}")}\n   #{@pastel.dim(description)}"
          end

          def format_mode_info(mode_info)
            icon = mode_info[:icon]
            name = mode_info[:name]
            description = mode_info[:description]

            "#{@pastel.bold(@pastel.green("#{icon} #{name}"))}\n#{@pastel.dim(description)}"
          end

          def format_selected_mode(mode)
            mode_info = WorkflowSelector::WORKFLOW_MODES[mode]
            "#{@pastel.green("✓ Selected:")} #{@pastel.bold("#{mode_info[:icon]} #{mode_info[:name]}")}"
          end

          def format_mode_switch(from_mode, to_mode)
            from_info = WorkflowSelector::WORKFLOW_MODES[from_mode]
            to_info = WorkflowSelector::WORKFLOW_MODES[to_mode]

            "#{@pastel.yellow("🔄 Switching from")} #{@pastel.bold(from_info[:name])} #{@pastel.yellow("to")} #{@pastel.bold(to_info[:name])}"
          end
        end
      end
    end
  end
end
