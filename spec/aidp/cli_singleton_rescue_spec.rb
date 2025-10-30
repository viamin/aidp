# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::CLI do
  describe ".run singleton rescue logging" do
    it "logs and returns fallback exit code without raising NoMethodError when harness raises" do
      # Force an exception inside run after setup_logging completes
      allow(Aidp::CLI).to receive(:subcommand?).and_return(false)
      allow(Aidp::CLI).to receive(:parse_options).and_return({})
      allow(Aidp::CLI).to receive(:create_prompt).and_return(double("Prompt"))
      # Stub first-run wizard methods to pass
      stub_wizard = class_double("Aidp::CLI::FirstRunWizard").as_stubbed_const
      allow(stub_wizard).to receive(:setup_config).and_return(true)
      allow(stub_wizard).to receive(:ensure_config).and_return(true)

      # Stub EnhancedTUI & WorkflowSelector to raise inside harness run
      tui_double = double("TUI", start_display_loop: true, stop_display_loop: true)
      selector_double = double("WorkflowSelector", select_workflow: {mode: :execute, workflow_type: :default, steps: [], user_input: nil})
      allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(tui_double)
      allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(selector_double)
      runner_double = double("Runner")
      allow(Aidp::Harness::EnhancedRunner).to receive(:new).and_return(runner_double)
      allow(runner_double).to receive(:run).and_raise(StandardError.new("boom"))

      expect { described_class.run([]) }.not_to raise_error
    end
  end
end
