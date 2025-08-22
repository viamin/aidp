# frozen_string_literal: true

module Aidp
  class CLI
    class TerminalIO
      def initialize(input = $stdin, output = $stdout)
        @input = input
        @output = output
      end

      def ready?
        return false if @input.closed?
        return true if @input.is_a?(StringIO)
        @input.ready?
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
