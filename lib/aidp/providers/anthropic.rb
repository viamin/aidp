# frozen_string_literal: true

require_relative "base"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class Anthropic < Base
      include Aidp::DebugMixin

      def self.available?
        !!Aidp::Util.which("claude")
      end

      def name
        "anthropic"
      end

      def available?
        self.class.available?
      end

      def send(prompt:, session: nil)
        raise "claude CLI not available" unless self.class.available?

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        debug_provider("claude", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to claude...", level: :info)

        begin
          # Use debug_execute_command for better debugging
          result = debug_execute_command("claude", args: ["--print"], input: prompt, timeout: timeout_seconds)

          # Log the results
          debug_command("claude", args: ["--print"], input: prompt, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            result.out
          else
            debug_error(StandardError.new("claude failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "claude failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          debug_error(e, {provider: "claude", prompt_length: prompt.length})
          raise
        end
      end

      private

      def calculate_timeout
        # Priority order for timeout calculation:
        # 1. Quick mode (for testing)
        # 2. Environment variable override
        # 3. Adaptive timeout based on step type
        # 4. Default timeout

        if ENV["AIDP_QUICK_MODE"]
          puts "⚡ Quick mode enabled - 2 minute timeout"
          return 120
        end

        if ENV["AIDP_ANTHROPIC_TIMEOUT"]
          return ENV["AIDP_ANTHROPIC_TIMEOUT"].to_i
        end

        # Adaptive timeout based on step type
        step_timeout = get_adaptive_timeout
        if step_timeout
          puts "🧠 Using adaptive timeout: #{step_timeout} seconds"
          return step_timeout
        end

        # Default timeout (5 minutes for interactive use)
        puts "📋 Using default timeout: 5 minutes"
        300
      end

      def get_adaptive_timeout
        # Timeout recommendations based on step type patterns
        step_name = ENV["AIDP_CURRENT_STEP"] || ""

        case step_name
        when /REPOSITORY_ANALYSIS/
          180  # 3 minutes - repository analysis can be quick
        when /ARCHITECTURE_ANALYSIS/
          600  # 10 minutes - architecture analysis needs more time
        when /TEST_ANALYSIS/
          300  # 5 minutes - test analysis is moderate
        when /FUNCTIONALITY_ANALYSIS/
          600  # 10 minutes - functionality analysis is complex
        when /DOCUMENTATION_ANALYSIS/
          300  # 5 minutes - documentation analysis is moderate
        when /STATIC_ANALYSIS/
          450  # 7.5 minutes - static analysis can be intensive
        when /REFACTORING_RECOMMENDATIONS/
          600  # 10 minutes - refactoring recommendations are complex
        else
          nil  # Use default
        end
      end
    end
  end
end
