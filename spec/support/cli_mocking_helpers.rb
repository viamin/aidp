# frozen_string_literal: true

# Shared helper for mocking CLI operations in tests
module CliMockingHelpers
  def mock_cli_operations(cli_instance = nil)
    # The CLI class doesn't have analyze/execute instance methods
    # Instead, create a mock that responds to the expected interface
    if cli_instance
      target = allow(cli_instance)
    else
      # Create a mock CLI instance that responds to expected methods
      mock_cli = instance_double(Aidp::CLI)
      allow(Aidp::CLI).to receive(:new).and_return(mock_cli)
      target = allow(mock_cli)
    end

    # Mock the methods that specs expect to exist
    target.to receive(:analyze).and_return({
      status: "success",
      provider: "cursor",
      message: "Step executed successfully",
      output: "Analysis complete",
      next_step: "01_REPOSITORY_ANALYSIS"
    })

    target.to receive(:execute).and_return({
      status: "success",
      provider: "cursor",
      message: "Step executed successfully",
      output: "Execution complete",
      next_step: "00_PRD"
    })

    # Return the mock instance for further customization
    cli_instance || mock_cli
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
