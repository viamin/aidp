# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/ui/navigation/workflow_selector"

RSpec.describe Aidp::Harness::UI::Navigation::WorkflowSelector do
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:formatter) { instance_double(Aidp::Harness::UI::Navigation::WorkflowFormatter) }
  let(:state_manager) { instance_double("StateManager") }
  let(:ui_components) { {prompt: prompt, formatter: formatter, state_manager: state_manager} }
  let(:selector) { described_class.new(ui_components) }

  before do
    allow(formatter).to receive(:format_selector_title).and_return("Workflow Selection")
    allow(formatter).to receive(:format_separator).and_return("---")
    allow(formatter).to receive(:format_mode_option).and_return("Option")
    allow(formatter).to receive(:format_mode_info).and_return("Mode Info")
    allow(prompt).to receive(:say)
    allow(state_manager).to receive(:record_workflow_mode_selection)
  end

  describe "#initialize" do
    it "accepts ui_components" do
      expect { described_class.new(ui_components) }.not_to raise_error
    end

    it "creates default prompt when not provided" do
      selector = described_class.new({})
      expect(selector.prompt).to be_a(TTY::Prompt)
    end
  end

  describe "::WORKFLOW_MODES" do
    it "defines simple mode" do
      expect(described_class::WORKFLOW_MODES).to have_key(:simple)
    end

    it "defines advanced mode" do
      expect(described_class::WORKFLOW_MODES).to have_key(:advanced)
    end

    it "includes mode metadata" do
      simple_mode = described_class::WORKFLOW_MODES[:simple]
      expect(simple_mode).to have_key(:name)
      expect(simple_mode).to have_key(:description)
      expect(simple_mode).to have_key(:icon)
    end
  end

  describe "#select_workflow_mode" do
    before do
      allow(prompt).to receive(:ask).and_return("🚀 Simple Mode")
    end

    it "displays mode selection" do
      expect(prompt).to receive(:say).at_least(:once)
      selector.select_workflow_mode
    end

    it "returns selected mode" do
      result = selector.select_workflow_mode
      expect(result).to be_a(Symbol)
      expect([:simple, :advanced]).to include(result)
    end

    it "records selection" do
      expect(state_manager).to receive(:record_workflow_mode_selection).with(:simple)
      selector.select_workflow_mode
    end

    it "raises error for invalid selection" do
      allow(prompt).to receive(:ask).and_return("")
      expect { selector.select_workflow_mode }.to raise_error(Aidp::Harness::UI::Navigation::WorkflowSelector::SelectionError)
    end
  end

  describe "#show_mode_description" do
    it "displays description for valid mode" do
      expect(prompt).to receive(:say)
      selector.show_mode_description(:simple)
    end

    it "raises error for invalid mode" do
      expect { selector.show_mode_description(:invalid) }.to raise_error(Aidp::Harness::UI::Navigation::WorkflowSelector::InvalidModeError)
    end
  end

  describe "#get_available_modes" do
    it "returns array of mode keys" do
      modes = selector.get_available_modes
      expect(modes).to be_an(Array)
      expect(modes).to include(:simple, :advanced)
    end
  end

  describe "#get_mode_info" do
    it "returns info for valid mode" do
      info = selector.get_mode_info(:simple)
      expect(info).to be_a(Hash)
      expect(info).to have_key(:name)
      expect(info).to have_key(:description)
    end

    it "raises error for invalid mode" do
      expect { selector.get_mode_info(:invalid) }.to raise_error(Aidp::Harness::UI::Navigation::WorkflowSelector::InvalidModeError)
    end
  end

  describe "#is_simple_mode?" do
    it "returns true for simple mode" do
      expect(selector.is_simple_mode?(:simple)).to be true
    end

    it "returns false for other modes" do
      expect(selector.is_simple_mode?(:advanced)).to be false
    end
  end

  describe "#is_advanced_mode?" do
    it "returns true for advanced mode" do
      expect(selector.is_advanced_mode?(:advanced)).to be true
    end

    it "returns false for other modes" do
      expect(selector.is_advanced_mode?(:simple)).to be false
    end
  end
end

RSpec.describe Aidp::Harness::UI::Navigation::WorkflowFormatter do
  let(:formatter) { described_class.new }

  describe "#initialize" do
    it "creates a pastel instance" do
      expect(formatter.pastel).not_to be_nil
    end
  end

  describe "#format_selector_title" do
    it "returns formatted title" do
      result = formatter.format_selector_title
      expect(result).to be_a(String)
      expect(result).to include("Workflow Mode Selection")
    end
  end

  describe "#format_separator" do
    it "returns separator line" do
      result = formatter.format_separator
      expect(result).to be_a(String)
      expect(result.length).to eq(60)
    end
  end

  describe "#format_mode_option" do
    let(:mode_info) do
      {
        name: "Simple Mode",
        description: "Easy workflow",
        icon: "🚀"
      }
    end

    it "formats mode option" do
      result = formatter.format_mode_option(:simple, mode_info, 1)
      expect(result).to be_a(String)
    end
  end

  describe "#format_mode_info" do
    let(:mode_info) do
      {
        name: "Simple Mode",
        description: "Easy workflow",
        icon: "🚀"
      }
    end

    it "formats mode info" do
      result = formatter.format_mode_info(mode_info)
      expect(result).to be_a(String)
    end
  end
end
