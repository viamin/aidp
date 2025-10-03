# frozen_string_literal: true

require "tty-spinner"
require "pastel"

module Aidp
  module Harness
    module UI
      # Unified spinner helper that automatically manages TTY::Spinner lifecycle
      # Usage: with_spinner("Loading...") { some_operation }
      class SpinnerHelper
        class SpinnerError < StandardError; end

        def initialize
          @pastel = Pastel.new
          @active_spinners = []
        end

        # Main method: automatically manages spinner around a block
        def with_spinner(message, format: :dots, success_message: nil, error_message: nil, &block)
          raise ArgumentError, "Block required for with_spinner" unless block

          spinner = create_spinner(message, format)
          start_spinner(spinner)

          begin
            result = yield(spinner)
            success_spinner(spinner, success_message || message)
            result
          rescue => e
            error_spinner(spinner, error_message || "Failed: #{e.message}")
            raise e
          ensure
            cleanup_spinner(spinner)
          end
        end

        # Convenience methods for common patterns
        def with_loading_spinner(message, &block)
          with_spinner("⏳ #{message}", format: :dots, &block)
        end

        def with_processing_spinner(message, &block)
          with_spinner("🔄 #{message}", format: :pulse, &block)
        end

        def with_saving_spinner(message, &block)
          with_spinner("💾 #{message}", format: :dots, &block)
        end

        def with_analyzing_spinner(message, &block)
          with_spinner("🔍 #{message}", format: :dots, &block)
        end

        def with_building_spinner(message, &block)
          with_spinner("🏗️ #{message}", format: :dots, &block)
        end

        # For operations that might take a while
        def with_long_operation_spinner(message, &block)
          with_spinner("⏳ #{message}", format: :pulse, &block)
        end

        # For quick operations
        def with_quick_spinner(message, &block)
          with_spinner("⚡ #{message}", format: :dots, &block)
        end

        # Update spinner message during operation
        def update_spinner_message(spinner, new_message)
          spinner.update_title(new_message)
        end

        # Check if any spinners are active
        def any_active?
          @active_spinners.any?(&:spinning?)
        end

        # Get count of active spinners
        def active_count
          @active_spinners.count(&:spinning?)
        end

        # Force stop all spinners (emergency cleanup)
        def stop_all
          @active_spinners.each do |spinner|
            spinner.stop if spinner.spinning?
          end
          @active_spinners.clear
        end

        private

        def create_spinner(message, format)
          TTY::Spinner.new(
            "#{message} :spinner",
            format: format,
            success_mark: @pastel.green("✓"),
            error_mark: @pastel.red("✗"),
            hide_cursor: true
          )
        end

        def start_spinner(spinner)
          @active_spinners << spinner
          spinner.start
        end

        def success_spinner(spinner, message)
          spinner.success(@pastel.green("✓ #{message}"))
        end

        def error_spinner(spinner, message)
          spinner.error(@pastel.red("✗ #{message}"))
        end

        def cleanup_spinner(spinner)
          @active_spinners.delete(spinner)
          # TTY::Spinner handles its own cleanup
        end
      end

      # Global instance for easy access
      SPINNER = SpinnerHelper.new

      # Convenience methods for global access
      def self.with_spinner(message, **options, &block)
        SPINNER.with_spinner(message, **options, &block)
      end

      def self.with_loading_spinner(message, &block)
        SPINNER.with_loading_spinner(message, &block)
      end

      def self.with_processing_spinner(message, &block)
        SPINNER.with_processing_spinner(message, &block)
      end

      def self.with_saving_spinner(message, &block)
        SPINNER.with_saving_spinner(message, &block)
      end

      def self.with_analyzing_spinner(message, &block)
        SPINNER.with_analyzing_spinner(message, &block)
      end

      def self.with_building_spinner(message, &block)
        SPINNER.with_building_spinner(message, &block)
      end
    end
  end
end
