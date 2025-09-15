# frozen_string_literal: true

require "cli/ui"

module Aidp
  module Harness
    module UI
      # Base class for all CLI UI components
      # Provides common functionality and ensures CLI UI is properly initialized
      class Base
        def initialize
          ensure_cli_ui_enabled
        end

        private

        def ensure_cli_ui_enabled
          return if ::CLI::UI::StdoutRouter.enabled?

          ::CLI::UI::StdoutRouter.enable
        end
      end
    end
  end
end
