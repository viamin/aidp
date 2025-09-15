# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # Handles nested framing using CLI UI frames
      class FrameManager < Base
        def initialize(ui_components = {})
          super()
          @frame = ui_components[:frame] || CLI::UI::Frame
        end

        def open_frame(title, &block)
          @frame.open(title) do
            yield if block_given?
          end
        end

        def divider(text)
          @frame.divider(text)
        end
      end
    end
  end
end
