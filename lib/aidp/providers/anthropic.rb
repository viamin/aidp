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

        # Use Claude CLI for non-interactive mode
        cmd = ["claude", "compose", "--prompt", prompt]
        system(*cmd)
        :ok
      end
    end
  end
end
