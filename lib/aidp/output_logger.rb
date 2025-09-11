# frozen_string_literal: true

require "stringio"

module Aidp
  # Centralized output logger that can be configured to suppress output during tests
  class OutputLogger
    class << self
      # Configuration options
      attr_accessor :enabled, :output_stream, :test_mode

      # Initialize with default settings
      def initialize
        @enabled = true
        @output_stream = $stdout
        @test_mode = false
      end

      # Check if we're in test mode (RSpec environment)
      def test_mode?
        @test_mode
      end

      # Main output method - replaces puts
      def puts(*args)
        return if !enabled? || test_mode?

        if args.empty?
          @output_stream.puts
        else
          args.each { |arg| @output_stream.puts(arg) }
        end
      end

      # Print without newline - replaces print
      def print(*args)
        return if !enabled? || test_mode?

        args.each { |arg| @output_stream.print(arg) }
      end

      # Flush output buffer
      def flush
        return if !enabled? || test_mode?

        @output_stream.flush
      end

      # Check if output is enabled
      def enabled?
        @enabled
      end

      # Disable all output
      def disable!
        @enabled = false
      end

      # Enable output
      def enable!
        @enabled = true
      end

      # Set test mode (suppresses output)
      def test_mode!
        @test_mode = true
      end

      # Exit test mode
      def normal_mode!
        @test_mode = false
      end

      # Redirect output to a different stream
      def redirect_to(stream)
        @output_stream = stream
      end

      # Reset to default settings
      def reset!
        @enabled = true
        @output_stream = $stdout
        @test_mode = false
      end

      # Capture output to a string (useful for testing)
      def capture_output
        original_stream = @output_stream
        captured = StringIO.new
        @output_stream = captured
        yield
        captured.string
      ensure
        @output_stream = original_stream
      end

      # Conditional output based on verbosity level
      def verbose_puts(*args)
        return if !enabled? || test_mode? || !verbose_mode?
        puts(*args)
      end

      # Check if verbose mode is enabled
      def verbose_mode?
        ENV['AIDP_VERBOSE'] == 'true' || ENV['VERBOSE'] == 'true'
      end

      # Debug output (only in debug mode)
      def debug_puts(*args)
        return if !enabled? || test_mode? || !debug_mode?
        puts(*args)
      end

      # Check if debug mode is enabled
      def debug_mode?
        ENV['AIDP_DEBUG'] == 'true' || ENV['DEBUG'] == 'true'
      end

      # Error output (always shown unless completely disabled)
      def error_puts(*args)
        return if !enabled? || test_mode?
        puts(*args)
      end

      # Warning output
      def warning_puts(*args)
        return if !enabled? || test_mode?
        puts(*args)
      end

      # Success output
      def success_puts(*args)
        return if !enabled? || test_mode?
        puts(*args)
      end

      # Info output
      def info_puts(*args)
        return if !enabled? || test_mode?
        puts(*args)
      end
    end

    # Initialize the singleton instance
    initialize
  end
end
