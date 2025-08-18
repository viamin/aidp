# frozen_string_literal: true

require_relative "base"

module Aidp
  module Providers
    class Anthropic < Base
      def self.available?
        !!Aidp::Util.which("claude")
      end

      def name = "anthropic"

      def send(prompt:, session: nil)
        raise "claude CLI not available" unless self.class.available?

        require "open3"

        # Use Claude CLI for non-interactive mode
        cmd = ["claude", "--print"]

        puts "📝 Sending prompt to claude..."

        Open3.popen3(*cmd) do |stdin, stdout, stderr, wait|
          # Send the prompt to stdin
          stdin.puts prompt
          stdin.close

          # Wait for completion
          result = wait.value

          if result.success?
            output = stdout.read
            puts "✅ Claude analysis completed"
            return output.empty? ? :ok : output
          else
            error_output = stderr.read
            raise "claude failed with exit code #{result.exitstatus}: #{error_output}"
          end
        end
      end
    end
  end
end
