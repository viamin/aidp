# frozen_string_literal: true

# Shared helper for mocking CLI operations in tests
module CliMockingHelpers
  def mock_cli_operations(cli_instance = nil)
    target = cli_instance || allow_any_instance_of(Aidp::CLI)

    target.to receive(:analyze).and_return({
      status: "completed",
      provider: "cursor",
      message: "Step executed successfully",
      output: "Analysis complete"
    })

    target.to receive(:execute).and_return({
      status: "completed",
      provider: "cursor",
      message: "Step executed successfully",
      output: "Execution complete"
    })

    target.to receive(:help).and_return(nil)
    target.to receive(:version).and_return("test-version")
  end

  def mock_workflow_selector
    mock_selector = instance_double(Aidp::Execute::WorkflowSelector)
    allow(Aidp::Execute::WorkflowSelector).to receive(:new).and_return(mock_selector)
    allow(mock_selector).to receive(:select_workflow).and_return({
      workflow_type: :exploration,
      steps: ["00_PRD", "16_IMPLEMENTATION"],
      user_input: {project_description: "Test project"}
    })
    mock_selector
  end

  def mock_harness_runner
    mock_runner = double("harness_runner")
    allow(Aidp::Harness::Runner).to receive(:new).and_return(mock_runner)
    allow(mock_runner).to receive(:run).and_return({status: "completed"})
    allow(mock_runner).to receive(:detailed_status).and_return({
      harness: {state: "completed"},
      configuration: {default_provider: "cursor"}
    })
    mock_runner
  end
end

RSpec.configure do |config|
  config.include CliMockingHelpers
end
