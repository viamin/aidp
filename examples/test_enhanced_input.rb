#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for enhanced input with Reline key bindings
require_relative "../lib/aidp/cli/enhanced_input"

puts "=" * 70
puts "Enhanced Input with Reline Key Bindings - Interactive Test"
puts "=" * 70
puts
puts "This test uses Reline which provides FULL readline-style editing."
puts
puts "Key combinations that work:"
puts "  Ctrl-A        → Move to beginning of line"
puts "  Ctrl-E        → Move to end of line"
puts "  Ctrl-W        → Delete word backward"
puts "  Ctrl-K        → Kill to end of line"
puts "  Ctrl-U        → Kill entire line"
puts "  Ctrl-D        → Delete character forward (or exit if line empty)"
puts "  Ctrl-T        → Transpose characters"
puts "  Alt-F         → Move forward one word"
puts "  Alt-B         → Move backward one word"
puts "  Left/Right    → Move cursor"
puts "  Home/End      → Jump to beginning/end"
puts
puts "=" * 70
puts

# Create enhanced input with Reline enabled
input = Aidp::CLI::EnhancedInput.new

# Test 1: Simple question
puts "\nTest 1: Try the key bindings!"
puts "Type: 'one two three four' then:"
puts "  - Ctrl-W to delete 'four'"
puts "  - Ctrl-W again to delete 'three'"
puts "  - Ctrl-A to go to start, Ctrl-K to kill rest"
puts
answer1 = input.ask("Enter text: ")
puts "You entered: #{answer1.inspect}"

# Test 2: With default value
puts "\nTest 2: With default value"
answer2 = input.ask("Project name: ", default: "my-project")
puts "You entered: #{answer2.inspect}"

# Test 3: Required field
puts "\nTest 3: Required field (try pressing enter without typing)"
answer3 = input.ask("Your goal (required): ", required: true)
puts "You entered: #{answer3.inspect}"

puts "\n✅ All tests complete!"
puts "\nThe key bindings should work perfectly with Reline."
