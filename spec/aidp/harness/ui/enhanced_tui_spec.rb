# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::UI::EnhancedTUI do
  let(:tui) do
    # Mock TTY::Screen to avoid ioctl issues in test environment
    allow(TTY::Screen).to receive(:height).and_return(24)
    allow(TTY::Screen).to receive(:width).and_return(80)
    described_class.new
  end

  describe "#single_select" do
    it "calls TTY::Prompt select method" do
      # Mock the TTY::Prompt to avoid actual interactive prompts
      mock_prompt = instance_double(TTY::Prompt)
      allow(TTY::Prompt).to receive(:new).and_return(mock_prompt)
      allow(mock_prompt).to receive(:select).with("Choose your mode", ["Option 1", "Option 2"], default: 0, cycle: true).and_return("Option 1")

      # Create a new TUI instance with the mocked prompt
      tui_with_mock = described_class.new

      result = tui_with_mock.single_select("Choose your mode", ["Option 1", "Option 2"], default: 0)
      expect(result).to eq("Option 1")
    end
  end

  describe "#multiselect" do
    it "calls TTY::Prompt multi_select method" do
      # Mock the TTY::Prompt to avoid actual interactive prompts
      mock_prompt = instance_double(TTY::Prompt)
      allow(TTY::Prompt).to receive(:new).and_return(mock_prompt)
      allow(mock_prompt).to receive(:multi_select).with("Select items", ["Item 1", "Item 2"], default: []).and_return(["Item 1"])

      # Create a new TUI instance with the mocked prompt
      tui_with_mock = described_class.new

      result = tui_with_mock.multiselect("Select items", ["Item 1", "Item 2"], selected: [])
      expect(result).to eq(["Item 1"])
    end
  end

  describe "#get_user_input" do
    it "calls TTY::Prompt ask method" do
      # Mock the TTY::Prompt to avoid actual interactive input
      mock_prompt = instance_double(TTY::Prompt)
      allow(TTY::Prompt).to receive(:new).and_return(mock_prompt)
      allow(mock_prompt).to receive(:ask).with("Test prompt: ").and_return("test input")

      # Create a new TUI instance with the mocked prompt
      tui_with_mock = described_class.new

      result = tui_with_mock.get_user_input("Test prompt: ")
      expect(result).to eq("test input")
    end
  end

  describe "display loop control" do
    it "has simple display methods" do
      # Simple display methods without background threads
      expect { tui.start_display_loop }.not_to raise_error
      expect { tui.stop_display_loop }.not_to raise_error
    end
  end

  describe "#show_message" do
    it "displays messages with appropriate formatting" do
      # Mock TTY::Prompt to verify the correct say calls are made
      mock_prompt = instance_double(TTY::Prompt)
      allow(TTY::Prompt).to receive(:new).and_return(mock_prompt)

      # Create a new TUI instance with the mocked prompt
      tui_with_mock = described_class.new

      # Test that show_message calls the correct TTY::Prompt.say methods
      expect(mock_prompt).to receive(:say).with("ℹ Test info message", color: :blue)
      tui_with_mock.show_message("Test info message", :info)

      expect(mock_prompt).to receive(:say).with("✓ Test success message", color: :green)
      tui_with_mock.show_message("Test success message", :success)

      expect(mock_prompt).to receive(:say).with("⚠ Test warning message", color: :yellow)
      tui_with_mock.show_message("Test warning message", :warning)

      expect(mock_prompt).to receive(:say).with("✗ Test error message", color: :red)
      tui_with_mock.show_message("Test error message", :error)
    end
  end
end
