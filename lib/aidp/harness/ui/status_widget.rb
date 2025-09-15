# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # Handles status display using CLI UI spinners
      class StatusWidget < Base
        def initialize(ui_components = {})
          super()
          @spinner = ui_components[:spinner] || CLI::UI::Spinner
        end

        def show_status(message, &block)
          @spinner.spin(message) do |spinner|
            yield(spinner) if block_given?
          end
        end

        def update_status(spinner, message)
          spinner.update_title(message)
        end
      end
    end
  end
end
