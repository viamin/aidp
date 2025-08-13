# frozen_string_literal: true

require_relative 'base'
require_relative '../util'
require 'tempfile'

module Aidp
  module Providers
    class MacOSUI < Base
      def self.available?
        Util.macos? && Util.which('osascript')
      end

      def name = 'macos'

      def send(prompt:, session: nil)
        # Minimal AppleScript: open Cursor and paste prompt into chat (Ctrl+Cmd+I is a common chat shortcut; users may adjust).
        script = <<~APPLESCRIPT
          on run argv
            set p to item 1 of argv
            tell application "Cursor" to activate
            delay 0.4
            tell application "System Events"
              keystroke "i" using {control down, command down}
              delay 0.2
              keystroke p
              key code 36
            end tell
          end run
        APPLESCRIPT
        Tempfile.create(['aidp', '.applescript']) do |f|
          f.write(script)
          f.flush
          system('osascript', f.path, prompt) or raise 'osascript failed'
        end
        :ok
      end
    end
  end
end
