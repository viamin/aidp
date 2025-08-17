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

        # Use Gemini CLI for non-interactive mode
        cmd = ["gemini", "chat", "--prompt", prompt]
        system(*cmd)
        :ok
      end
    end
  end
end
