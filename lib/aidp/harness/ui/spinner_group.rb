# frozen_string_literal: true

require "tty-spinner"
require_relative "base"

module Aidp
  module Harness
    module UI
      # Handles concurrent operations using CLI UI spinner groups
      class SpinnerGroup < Base
        class SpinnerGroupError < StandardError; end

        class InvalidOperationError < SpinnerGroupError; end

        class ExecutionError < SpinnerGroupError; end

        def initialize(ui_components = {})
          super()
          @spinner_class = ui_components[:spinner_class] || TTY::Spinner
          @formatter = ui_components[:formatter] || SpinnerGroupFormatter.new
          @spinners = {}
        end

        def run_concurrent_operations(operations)
          validate_operations(operations)

          # Create individual spinners for each operation
          operations.each do |operation|
            spinner = @spinner_class.new(
              "#{operation[:name]}...",
              format: :dots,
              success_mark: "✓",
              error_mark: "✗"
            )
            @spinners[operation[:id]] = spinner
            spinner.start
          end

          # Execute operations
          operations.each do |operation|
            operation[:block].call
            @spinners[operation[:id]].success(operation[:name])
          rescue => e
            @spinners[operation[:id]].error(operation[:name])
            raise e
          end
        rescue => e
          raise ExecutionError, "Failed to run concurrent operations: #{e.message}"
        end

        def run_workflow_steps(steps)
          validate_steps(steps)

          operations = convert_steps_to_operations(steps)
          run_concurrent_operations(operations)
        rescue => e
          raise ExecutionError, "Failed to run workflow steps: #{e.message}"
        end

        def run_analysis_tasks(tasks)
          validate_tasks(tasks)

          operations = convert_tasks_to_operations(tasks)
          run_concurrent_operations(operations)
        rescue => e
          raise ExecutionError, "Failed to run analysis tasks: #{e.message}"
        end

        def run_provider_operations(provider_operations)
          validate_provider_operations(provider_operations)

          operations = convert_provider_operations(provider_operations)
          run_concurrent_operations(operations)
        rescue => e
          raise ExecutionError, "Failed to run provider operations: #{e.message}"
        end

        private

        def validate_operations(operations)
          raise InvalidOperationError, "Operations must be an array" unless operations.is_a?(Array)
          raise InvalidOperationError, "Operations array cannot be empty" if operations.empty?

          operations.each_with_index do |operation, index|
            validate_operation(operation, index)
          end
        end

        def validate_operation(operation, index)
          raise InvalidOperationError, "Operation #{index} must be a hash" unless operation.is_a?(Hash)
          raise InvalidOperationError, "Operation #{index} must have :title" unless operation.key?(:title)
          raise InvalidOperationError, "Operation #{index} must have :block" unless operation.key?(:block)
          raise InvalidOperationError, "Operation #{index} title cannot be empty" if operation[:title].to_s.strip.empty?
          raise InvalidOperationError, "Operation #{index} block must be callable" unless operation[:block].respond_to?(:call)
        end

        def validate_steps(steps)
          raise InvalidOperationError, "Steps must be an array" unless steps.is_a?(Array)
          raise InvalidOperationError, "Steps array cannot be empty" if steps.empty?
        end

        def validate_tasks(tasks)
          raise InvalidOperationError, "Tasks must be an array" unless tasks.is_a?(Array)
          raise InvalidOperationError, "Tasks array cannot be empty" if tasks.empty?
        end

        def validate_provider_operations(provider_operations)
          raise InvalidOperationError, "Provider operations must be an array" unless provider_operations.is_a?(Array)
          raise InvalidOperationError, "Provider operations array cannot be empty" if provider_operations.empty?
        end

        def add_operation(spin_group, operation)
          formatted_title = @formatter.format_operation_title(operation[:title])
          spin_group.add(formatted_title) do |spinner|
            execute_operation_with_error_handling(operation, spinner)
          end
        end

        def execute_operation_with_error_handling(operation, spinner)
          operation[:block].call(spinner)
        rescue => e
          spinner.update_title(@formatter.format_error_title(operation[:title], e.message))
          raise
        end

        def convert_steps_to_operations(steps)
          steps.map do |step|
            {
              title: @formatter.format_step_title(step[:name]),
              block: step[:block]
            }
          end
        end

        def convert_tasks_to_operations(tasks)
          tasks.map do |task|
            {
              title: @formatter.format_task_title(task[:name]),
              block: task[:block]
            }
          end
        end

        def convert_provider_operations(provider_operations)
          provider_operations.map do |op|
            {
              title: @formatter.format_provider_title(op[:provider], op[:operation]),
              block: op[:block]
            }
          end
        end
      end

      # Formats spinner group display text
      class SpinnerGroupFormatter
        def format_operation_title(title)
          "🔄 #{title}"
        end

        def format_step_title(step_name)
          "⚡ #{step_name}"
        end

        def format_task_title(task_name)
          "📋 #{task_name}"
        end

        def format_provider_title(provider_name, operation)
          "🤖 #{provider_name}: #{operation}"
        end

        def format_error_title(original_title, error_message)
          "❌ #{original_title} (Error: #{error_message})"
        end

        def format_success_title(original_title)
          "✅ #{original_title}"
        end

        def format_progress_title(title, current, total)
          "📊 #{title} (#{current}/#{total})"
        end
      end
    end
  end
end
