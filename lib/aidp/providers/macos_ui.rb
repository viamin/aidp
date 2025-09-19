# frozen_string_literal: true

require_relative "base"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class MacOSUI < Base
      include Aidp::DebugMixin

      def self.available?
        RUBY_PLATFORM.include?("darwin")
      end

      def name
        "macos"
      end

      def send(prompt:, session: nil)
        raise "macOS UI not available on this platform" unless self.class.available?

        debug_provider("macos", "Starting Cursor interaction", {prompt_length: prompt.length})

        # Try to use Cursor's chat interface via AppleScript
        result = interact_with_cursor(prompt)

        if result[:success]
          debug_log("✅ Successfully sent prompt to Cursor", level: :info)
          result[:response]
        else
          debug_log("❌ Failed to interact with Cursor: #{result[:error]}", level: :warn)
          # Fallback to simple dialog
          fallback_dialog(prompt)
        end
      end

      private

      def interact_with_cursor(prompt)
        # Create a temporary script file for the prompt
        temp_file = "/tmp/aidp_cursor_prompt.txt"
        File.write(temp_file, prompt)

        # AppleScript to interact with Cursor
        script = <<~APPLESCRIPT
          tell application "Cursor"
            activate
          end tell

          delay 1

          tell application "System Events"
            -- Open chat panel (Cmd+L)
            keystroke "l" using command down
            delay 2

            -- Type the prompt
            keystroke "#{escape_for_applescript(prompt)}"
            delay 1

            -- Send the message (Enter)
            keystroke (ASCII character 13)
            delay 3

            -- Try to get response (this is tricky without accessibility permissions)
            -- For now, we'll just return success
            return "Prompt sent to Cursor chat"
          end tell
        APPLESCRIPT

        begin
          result = `osascript -e '#{script}'`
          {success: true, response: result.strip}
        rescue => e
          {success: false, error: e.message}
        ensure
          File.delete(temp_file) if File.exist?(temp_file)
        end
      end

      def escape_for_applescript(text)
        # Escape special characters for AppleScript
        # Must escape backslashes first to avoid double-escaping
        text.gsub('\\', '\\\\').gsub('"', '\\"').gsub("'", "\\'").gsub("\n", "\\n")
      end

      def fallback_dialog(prompt)
        # Fallback to simple dialog
        truncated_prompt = (prompt.length > 200) ? prompt[0..200] + "..." : prompt

        script = <<~APPLESCRIPT
          display dialog "#{escape_for_applescript(truncated_prompt)}" with title "Aidp - Cursor Integration" buttons {"OK", "Open Cursor"} default button "Open Cursor"
          set buttonPressed to button returned of result
          if buttonPressed is "Open Cursor" then
            tell application "Cursor" to activate
          end if
        APPLESCRIPT

        system("osascript", "-e", script)
        "Dialog shown - please use Cursor manually"
      end
    end
  end
end
