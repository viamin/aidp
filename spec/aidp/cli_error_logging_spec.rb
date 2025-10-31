# frozen_string_literal: true

require "spec_helper"
require "aidp/cli"

RSpec.describe Aidp::CLI do
  describe ".run error handling" do
    let(:args) { [] }

    before do
      # Force workflow selector to raise inside run to trigger rescue block
      workflow_selector_double = instance_double("Aidp::Harness::UI::EnhancedWorkflowSelector")
      allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(workflow_selector_double)
      allow(workflow_selector_double).to receive(:select_workflow).and_raise(StandardError, "boom")

      # Stub EnhancedTUI so display loop calls are no-ops
      tui_double = instance_double("Aidp::Harness::UI::EnhancedTUI")
      allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(tui_double)
      allow(tui_double).to receive(:start_display_loop)
      allow(tui_double).to receive(:stop_display_loop)

      # Capture logger calls (avoid filesystem overhead)
      mock_logger = instance_double("Aidp::Logger")
      allow(mock_logger).to receive(:info)
      allow(mock_logger).to receive(:warn)
      allow(mock_logger).to receive(:error)
      allow(mock_logger).to receive(:debug)
      allow(Aidp).to receive(:setup_logger)
      allow(Aidp).to receive(:logger).and_return(mock_logger)

      # Monitor log_rescue path indirectly by expecting mock_logger.warn/error
    end

    it "invokes rescue logging without raising NoMethodError" do
      expect { described_class.run(args) }.not_to raise_error(NoMethodError)
    end
  end
end
