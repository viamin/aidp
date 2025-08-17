# frozen_string_literal: true

require_relative "base"

module Aidp
  module Providers
    class MacOSUI < Base
      def self.available?
        RUBY_PLATFORM.include?("darwin")
      end

      def name = "macos"

      def send(prompt:, session: nil)
        raise "macOS UI not available on this platform" unless self.class.available?

        # Use macOS UI for interactive mode
        cmd = ["osascript", "-e", "display dialog \"#{prompt}\" with title \"Aidp\" buttons {\"OK\"} default button \"OK\""]
        system(*cmd)
        :ok
      end
    end
  end
end
