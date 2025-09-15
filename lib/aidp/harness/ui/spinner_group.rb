# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # Handles concurrent operations using CLI UI spinner groups
      class SpinnerGroup < Base
        def initialize(ui_components = {})
          super()
          @spin_group = ui_components[:spin_group] || CLI::UI::SpinGroup
        end

        def run_concurrent_operations(operations)
          @spin_group.new do |spin_group|
            operations.each do |operation|
              add_operation(spin_group, operation)
            end
          end
        end

        private

        def add_operation(spin_group, operation)
          spin_group.add(operation[:title]) do |spinner|
            operation[:block].call(spinner)
          end
        end
      end
    end
  end
end
