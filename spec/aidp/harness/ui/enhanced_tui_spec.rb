# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::UI::EnhancedTUI do
  let(:test_prompt) do
    TestPrompt.new(
      responses: {
        select: "Option 1",
        multi_select: [],
        ask: "test input",
        yes?: true,
        no?: false,
        keypress: ""
      }
    )
  end
  let(:tui) do
    # Mock TTY::Screen to avoid ioctl issues in test environment
    allow(TTY::Screen).to receive(:height).and_return(24)
    allow(TTY::Screen).to receive(:width).and_return(80)
    described_class.new(prompt: test_prompt)
  end

  describe "#single_select" do
    it "calls prompt select method" do
      result = tui.single_select("Choose your mode", ["Option 1", "Option 2"], default: 0)
      expect(result).to eq("Option 1")
      expect(test_prompt.selections.length).to eq(1)
      expect(test_prompt.selections.first[:title]).to eq("Choose your mode")
    end
  end

  describe "#multiselect" do
    it "calls prompt multi_select method" do
      result = tui.multiselect("Select items", ["Item 1", "Item 2"], selected: [])
      expect(result).to eq([])
      expect(test_prompt.selections.length).to eq(1)
      expect(test_prompt.selections.first[:multi]).to be true
    end
  end

  describe "#get_user_input" do
    it "calls prompt ask method" do
      result = tui.get_user_input("Test prompt: ")
      expect(result).to eq("test input")
      expect(test_prompt.inputs.length).to eq(1)
      expect(test_prompt.inputs.first[:message]).to eq("Test prompt: ")
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
      # Test that the method doesn't raise an error and records messages
      expect { tui.show_message("Test info message", :info) }.not_to raise_error
      expect { tui.show_message("Test success message", :success) }.not_to raise_error
      expect { tui.show_message("Test warning message", :warning) }.not_to raise_error
      expect { tui.show_message("Test error message", :error) }.not_to raise_error

      # Verify messages were recorded by the test prompt
      expect(test_prompt.messages.length).to eq(4)
    end
  end
end
