# frozen_string_literal: true

module Aidp
  module Harness
    module UI
      module Navigation
        # Represents a single menu item in the navigation system
        class MenuItem
          class MenuItemError < StandardError; end
          class InvalidTypeError < MenuItemError; end

          VALID_TYPES = [:action, :submenu, :workflow, :separator].freeze

          def initialize(title, type = :action, options = {})
            @title = title
            @type = type
            @action = options[:action]
            @workflow = options[:workflow]
            @submenu = options[:submenu]
            @description = options[:description]
            @shortcut = options[:shortcut]
            @enabled = options.fetch(:enabled, true)
            @visible = options.fetch(:visible, true)

            validate_attributes
          end

          attr_reader :title, :type, :action, :workflow, :submenu, :description, :shortcut
          attr_accessor :enabled, :visible

          def action?
            @type == :action
          end

          def submenu?
            @type == :submenu
          end

          def workflow?
            @type == :workflow
          end

          def separator?
            @type == :separator
          end

          def enabled?
            @enabled
          end

          def visible?
            @visible
          end

          def disabled?
            !enabled?
          end

          def hidden?
            !visible?
          end

          def execute
            case @type
            when :action
              execute_action
            when :workflow
              execute_workflow
            when :submenu
              execute_submenu
            when :separator
              execute_separator
            else
              raise InvalidTypeError, "Unknown menu item type: #{@type}"
            end
          end

          def to_s
            "#{@title} (#{@type})"
          end

          private

          def validate_attributes
            validate_title
            validate_type
            validate_type_specific_attributes
          end

          def validate_title
            raise MenuItemError, "Title cannot be empty" if @title.to_s.strip.empty?
          end

          def validate_type
            unless VALID_TYPES.include?(@type)
              raise InvalidTypeError, "Invalid type: #{@type}. Must be one of: #{VALID_TYPES.join(', ')}"
            end
          end

          def validate_type_specific_attributes
            case @type
            when :action
              validate_action_attributes
            when :workflow
              validate_workflow_attributes
            when :submenu
              validate_submenu_attributes
            end
          end

          def validate_action_attributes
            raise MenuItemError, "Action items must have an action" unless @action.respond_to?(:call)
          end

          def validate_workflow_attributes
            raise MenuItemError, "Workflow items must have a workflow" unless @workflow.respond_to?(:call)
          end

          def validate_submenu_attributes
            raise MenuItemError, "Submenu items must have a submenu" unless @submenu.is_a?(MainMenu)
          end

          def execute_action
            @action.call if @action
          end

          def execute_workflow
            @workflow.call if @workflow
          end

          def execute_submenu
            @submenu.show_menu(@title) if @submenu
          end

          def execute_separator
            # Separators don't execute anything
          end
        end
      end
    end
  end
end
