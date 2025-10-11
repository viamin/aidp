#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script showing key binding support in AIDP
# Run this to see all supported key combinations

require_relative "../lib/aidp/cli/enhanced_input"

puts "=" * 60
puts "AIDP Enhanced Input - Key Bindings Demo"
puts "=" * 60
puts
puts "The following key combinations are supported:"
puts
puts "  Cursor Movement:"
puts "    Ctrl-A        → Move to beginning of line"
puts "    Ctrl-E        → Move to end of line"
puts "    Left/Right    → Move cursor left/right"
puts "    Home/End      → Jump to beginning/end"
puts
puts "  Editing:"
puts "    Ctrl-W        → Delete word backward"
puts "    Ctrl-K        → Kill to end of line"
puts "    Ctrl-U        → Kill to beginning of line"
puts "    Ctrl-D        → Delete character forward"
puts "    Backspace     → Delete character backward"
puts
puts "  Other:"
puts "    Ctrl-C        → Cancel input"
puts "    Tab           → Auto-completion (where supported)"
puts
puts "=" * 60
puts

# Create enhanced input handler
input = Aidp::CLI::EnhancedInput.new

# Enable hints for first-time users
input.enable_hints!

# Try it out
answer = input.ask("Enter some text to try the key bindings: ")
puts
puts "You entered: #{answer.inspect}"
puts
puts "Try typing multiple words and using Ctrl-W to delete them!"
