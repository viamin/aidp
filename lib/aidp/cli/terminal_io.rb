# frozen_string_literal: true

require "stringio"
require "tty-reader"

module Aidp
  class CLI
    class TerminalIO
      def initialize(input: nil, output: nil)
        @input = input || $stdin
        @output = output || $stdout
      end

      def ready?
        return false if @input.closed?
        return true if @input.is_a?(StringIO)
        # For regular IO, we can't easily check if data is ready
        # So we'll assume it's always ready for non-blocking operations
        true
      end

      def getch
        return nil unless ready?
        if @input.is_a?(StringIO)
          char = @input.getc
          char&.chr || ""
        else
          @input.getch
        end
      end

      def gets
        @input.gets
      end

      # Enhanced readline-style input with standard key combinations
      # Supports: Ctrl-A (beginning), Ctrl-E (end), Ctrl-W (delete word), etc.
      def readline(prompt = "", default: nil)
        # Use StringIO for testing, otherwise use TTY::Reader for real input
        if @input.is_a?(StringIO)
          @output.print(prompt)
          @output.flush
          line = @input.gets
          return line&.chomp if line
          return default
        end

        reader = TTY::Reader.new(
          input: @input,
          output: @output,
          interrupt: :exit
        )

        # Read line with full readline support (Ctrl-A, Ctrl-E, Ctrl-W, etc.)
        result = reader.read_line(prompt, default: default || "")
        result&.chomp
      rescue TTY::Reader::InputInterrupt
        raise Interrupt
      end

      def write(str)
        @output.write(str)
      end

      def puts(str = "")
        @output.puts(str)
      end

      def print(str)
        @output.print(str)
      end

      def flush
        @output.flush
      end
    end
  end
end
