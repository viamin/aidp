# frozen_string_literal: true

require "stringio"

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
