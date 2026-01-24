# frozen_string_literal: true

module Aidp
  module Interfaces
    # UiInterface defines the contract for user interface operations.
    # This interface abstracts TTY-based UI components for extraction
    # into the agent-harness gem, allowing different UI implementations.
    #
    # The interface covers two main areas:
    # 1. Message display - showing status messages to users
    # 2. Spinner/progress - showing activity indicators
    #
    # @example Implementing the interface
    #   class MyUI
    #     include Aidp::Interfaces::UiInterface
    #
    #     def say(message, type: :info)
    #       puts "[#{type.upcase}] #{message}"
    #     end
    #
    #     def with_spinner(title:, &block)
    #       puts "Starting: #{title}"
    #       result = yield
    #       puts "Done: #{title}"
    #       result
    #     end
    #   end
    #
    # @example Using an injected UI
    #   class Provider
    #     def initialize(ui: NullUI.new)
    #       @ui = ui
    #     end
    #
    #     def process
    #       @ui.say("Starting process", type: :info)
    #       @ui.with_spinner(title: "Processing") do
    #         # do work
    #       end
    #     end
    #   end
    #
    module UiInterface
      # Message types for display_message
      MESSAGE_TYPES = [:info, :success, :warning, :error, :highlight, :muted].freeze

      # Display a message to the user.
      #
      # @param message [String] the message to display
      # @param type [Symbol] one of MESSAGE_TYPES (:info, :success, :warning, :error, :highlight, :muted)
      # @return [void]
      def say(message, type: :info)
        raise NotImplementedError, "#{self.class} must implement #say"
      end

      # Execute a block with a spinner indicator.
      #
      # @param title [String] the spinner title
      # @yield the block to execute
      # @return [Object] the result of the block
      def with_spinner(title:)
        raise NotImplementedError, "#{self.class} must implement #with_spinner"
      end

      # Create a spinner for manual control.
      # Returns an object that responds to :auto_spin, :success, :error, and :update_title
      #
      # @param title [String] initial spinner title
      # @return [SpinnerInterface] a spinner object
      def spinner(title:)
        raise NotImplementedError, "#{self.class} must implement #spinner"
      end

      # Check if we're in quiet mode (suppress non-critical messages).
      #
      # @return [Boolean] true if non-critical messages should be suppressed
      def quiet?
        false
      end
    end

    # SpinnerInterface defines the contract for spinner objects.
    module SpinnerInterface
      # Start the spinner animation.
      # @return [void]
      def auto_spin
        raise NotImplementedError, "#{self.class} must implement #auto_spin"
      end

      # Stop the spinner with a success indicator.
      # @param message [String, nil] optional success message
      # @return [void]
      def success(message = nil)
        raise NotImplementedError, "#{self.class} must implement #success"
      end

      # Stop the spinner with an error indicator.
      # @param message [String, nil] optional error message
      # @return [void]
      def error(message = nil)
        raise NotImplementedError, "#{self.class} must implement #error"
      end

      # Update the spinner title.
      # @param title [String] new title
      # @return [void]
      def update_title(title)
        raise NotImplementedError, "#{self.class} must implement #update_title"
      end
    end

    # NullUI is a no-op implementation.
    # Useful for testing or non-interactive environments.
    #
    class NullUI
      include UiInterface

      def say(message, type: :info)
        # no-op
      end

      def with_spinner(title:)
        yield
      end

      def spinner(title:)
        NullSpinner.new
      end

      def quiet?
        true
      end
    end

    # NullSpinner is a no-op spinner implementation.
    #
    class NullSpinner
      include SpinnerInterface

      def auto_spin
        # no-op
      end

      def success(message = nil)
        # no-op
      end

      def error(message = nil)
        # no-op
      end

      def update_title(title)
        # no-op
      end
    end

    # TtyUI wraps TTY::Prompt and TTY::Spinner for UI operations.
    # This is the standard implementation used by AIDP.
    #
    # @example Creating a TtyUI
    #   ui = TtyUI.new
    #   ui.say("Hello", type: :success)
    #   ui.with_spinner(title: "Working") { sleep(1) }
    #
    class TtyUI
      include UiInterface

      COLOR_MAP = {
        info: :blue,
        success: :green,
        warning: :yellow,
        error: :red,
        highlight: :cyan,
        muted: :bright_black
      }.freeze

      CRITICAL_TYPES = [:error, :warning, :success].freeze

      # @param prompt [TTY::Prompt, nil] optional pre-configured prompt
      # @param quiet [Boolean] whether to suppress non-critical messages
      def initialize(prompt: nil, quiet: false)
        @prompt = prompt
        @quiet = quiet
      end

      def say(message, type: :info)
        return if @quiet && !CRITICAL_TYPES.include?(type)

        prompt.say(message.to_s, color: COLOR_MAP.fetch(type, :white))
      end

      def with_spinner(title:)
        require "tty-spinner"
        spin = TTY::Spinner.new("[:spinner] #{title}", format: :dots, hide_cursor: true)
        spin.auto_spin

        begin
          result = yield
          spin.success("done")
          result
        rescue
          spin.error("failed")
          raise
        end
      end

      def spinner(title:)
        require "tty-spinner"
        TtySpinnerWrapper.new(title: title)
      end

      def quiet?
        @quiet
      end

      private

      def prompt
        @prompt ||= begin
          require "tty-prompt"
          TTY::Prompt.new
        end
      end
    end

    # TtySpinnerWrapper wraps TTY::Spinner to implement SpinnerInterface.
    #
    class TtySpinnerWrapper
      include SpinnerInterface

      def initialize(title:)
        require "tty-spinner"
        @spinner = TTY::Spinner.new("[:spinner] :title", format: :dots, hide_cursor: true)
        @spinner.update(title: title)
      end

      def auto_spin
        @spinner.auto_spin
      end

      def success(message = nil)
        @spinner.success(message || "done")
      end

      def error(message = nil)
        @spinner.error(message || "failed")
      end

      def update_title(title)
        @spinner.update(title: title)
      end
    end
  end
end
