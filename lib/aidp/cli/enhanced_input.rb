# frozen_string_literal: true

require "tty-prompt"
require "reline"

module Aidp
  class CLI
    # Enhanced input handler with full readline-style key bindings using Reline
    class EnhancedInput
      # Standard key bindings supported by Reline:
      # - Ctrl-A: Move to beginning of line
      # - Ctrl-E: Move to end of line
      # - Ctrl-W: Delete word backward
      # - Ctrl-K: Kill to end of line
      # - Ctrl-U: Kill to beginning of line
      # - Ctrl-D: Delete character forward
      # - Ctrl-H/Backspace: Delete character backward
      # - Left/Right arrows: Move cursor
      # - Alt-F/Alt-B: Move forward/backward by word
      # - Home/End: Jump to beginning/end
      # - Ctrl-T: Transpose characters
      # - And many more Emacs-style bindings

      def initialize(prompt: nil, input: nil, output: nil, use_reline: true)
        @use_reline = use_reline
        @input = input || $stdin
        @output = output || $stdout
        @prompt = prompt || TTY::Prompt.new(
          input: @input,
          output: @output,
          enable_color: true,
          interrupt: :exit
        )
        @show_hints = false
      end

      # Ask a question with full readline support
      # Uses Reline for readline-style editing when use_reline is true
      def ask(question, **options)
        # If reline is enabled and we're in a TTY, use reline for better editing
        if @use_reline && @input.tty?
          default = options[:default]
          required = options[:required] || false

          # Display helpful hint on first use
          if @show_hints
            @output.puts "💡 Hint: Use Ctrl-A (start), Ctrl-E (end), Ctrl-W (delete word), Ctrl-K (kill line)"
            @show_hints = false
          end

          # Use Reline for input with full key binding support
          loop do
            prompt_text = question.to_s
            prompt_text += " (#{default})" if default
            prompt_text += " "

            # Reline provides full readline editing capabilities
            Reline.output = @output
            Reline.input = @input
            Reline.completion_append_character = " "

            answer = Reline.readline(prompt_text, false)

            # Handle Ctrl-D (nil return)
            if answer.nil?
              @output.puts
              raise Interrupt
            end

            answer = answer.strip
            answer = default if answer.empty? && default

            if required && (answer.nil? || answer.empty?)
              @output.puts "  Value required."
              next
            end

            return answer
          end
        else
          # Fall back to TTY::Prompt's ask
          @prompt.ask(question, **options)
        end
      rescue Interrupt
        @output.puts
        raise
      end

      # Enable hints for key bindings
      def enable_hints!
        @show_hints = true
      end

      # Disable Reline (fall back to TTY::Prompt)
      def disable_reline!
        @use_reline = false
      end

      # Enable Reline
      def enable_reline!
        @use_reline = true
      end

      # Delegate other methods to underlying prompt
      def method_missing(method, *args, **kwargs, &block)
        @prompt.send(method, *args, **kwargs, &block)
      end

      def respond_to_missing?(method, include_private = false)
        @prompt.respond_to?(method, include_private) || super
      end
    end
  end
end
