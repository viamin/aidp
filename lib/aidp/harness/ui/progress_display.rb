# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # Handles progress display using CLI UI progress bars
      class ProgressDisplay < Base
        def initialize(ui_components = {})
          super()
          @progress = ui_components[:progress] || CLI::UI::Progress
        end

        def show_progress(total_steps, &block)
          @progress.progress do |bar|
            total_steps.times do
              yield(bar) if block_given?
              bar.tick
            end
          end
        end

        def update_progress(bar, message = nil)
          bar.tick
          bar.update_title(message) if message
        end
      end
    end
  end
end
