# frozen_string_literal: true

require_relative "base"

module Aidp
  module Providers
    class Gemini < Base
      def self.available?
        !!Aidp::Util.which("gemini")
      end

      def name = "gemini"

      def send(prompt:, session: nil)
        raise "gemini CLI not available" unless self.class.available?

        require "open3"

        # Use Gemini CLI for non-interactive mode
        cmd = ["gemini", "chat"]

        puts "📝 Sending prompt to gemini..."

        Open3.popen3(*cmd) do |stdin, stdout, stderr, wait|
          # Send the prompt to stdin
          stdin.puts prompt
          stdin.close

          # Wait for completion
          result = wait.value

          if result.success?
            output = stdout.read
            puts "✅ Gemini analysis completed"
            return output.empty? ? :ok : output
          else
            error_output = stderr.read
            raise "gemini failed with exit code #{result.exitstatus}: #{error_output}"
          end
        end
      end
    end
  end
end
