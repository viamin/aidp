# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::UI::SpinnerGroup do
  let(:spinner_class) { double("SpinnerClass") }
  let(:spinner) { double("Spinner", start: nil, success: nil, error: nil) }
  let(:spinner_group) { described_class.new(spinner_class: spinner_class) }

  before do
    allow(spinner_class).to receive(:new).and_return(spinner)
  end

  describe "#run_concurrent_operations" do
    let(:operations) do
      [
        {title: "Operation 1", block: -> { "result1" }},
        {title: "Operation 2", block: -> { "result2" }}
      ]
    end

    it "creates a spinner for each operation" do
      spinner_group.run_concurrent_operations(operations)

      expect(spinner_class).to have_received(:new).twice
    end

    it "starts all spinners" do
      spinner_group.run_concurrent_operations(operations)

      expect(spinner).to have_received(:start).twice
    end

    it "executes all operation blocks" do
      block1 = double("block1", call: "result1")
      block2 = double("block2", call: "result2")

      ops = [
        {title: "Op 1", block: block1},
        {title: "Op 2", block: block2}
      ]

      spinner_group.run_concurrent_operations(ops)

      expect(block1).to have_received(:call)
      expect(block2).to have_received(:call)
    end

    it "marks successful operations with success" do
      spinner_group.run_concurrent_operations(operations)

      expect(spinner).to have_received(:success).twice
    end

    it "marks failed operations with error" do
      failing_op = {title: "Failing Op", block: -> { raise "Error" }}

      expect {
        spinner_group.run_concurrent_operations([failing_op])
      }.to raise_error(Aidp::Harness::UI::SpinnerGroup::ExecutionError)
    end

    it "validates operations before running" do
      invalid_ops = [{title: "op1"}] # Missing :block

      expect {
        spinner_group.run_concurrent_operations(invalid_ops)
      }.to raise_error(Aidp::Harness::UI::SpinnerGroup::ExecutionError)
    end
  end

  describe "error classes" do
    it "defines SpinnerGroupError" do
      expect(Aidp::Harness::UI::SpinnerGroup::SpinnerGroupError).to be < StandardError
    end

    it "defines InvalidOperationError" do
      expect(Aidp::Harness::UI::SpinnerGroup::InvalidOperationError).to be < Aidp::Harness::UI::SpinnerGroup::SpinnerGroupError
    end

    it "defines ExecutionError" do
      expect(Aidp::Harness::UI::SpinnerGroup::ExecutionError).to be < Aidp::Harness::UI::SpinnerGroup::SpinnerGroupError
    end
  end

  describe "#run_workflow_steps" do
    let(:steps) do
      [
        {name: "Step 1", block: -> { "result1" }},
        {name: "Step 2", block: -> { "result2" }}
      ]
    end

    it "converts and runs workflow steps" do
      expect(spinner_group).to receive(:run_concurrent_operations)
      spinner_group.run_workflow_steps(steps)
    end

    it "validates steps before running" do
      invalid_steps = "not an array"
      expect {
        spinner_group.run_workflow_steps(invalid_steps)
      }.to raise_error(Aidp::Harness::UI::SpinnerGroup::ExecutionError)
    end

    it "raises error for empty steps array" do
      expect {
        spinner_group.run_workflow_steps([])
      }.to raise_error(Aidp::Harness::UI::SpinnerGroup::ExecutionError)
    end
  end

  describe "#run_analysis_tasks" do
    let(:tasks) do
      [
        {name: "Task 1", block: -> { "result1" }},
        {name: "Task 2", block: -> { "result2" }}
      ]
    end

    it "converts and runs analysis tasks" do
      expect(spinner_group).to receive(:run_concurrent_operations)
      spinner_group.run_analysis_tasks(tasks)
    end

    it "validates tasks before running" do
      invalid_tasks = "not an array"
      expect {
        spinner_group.run_analysis_tasks(invalid_tasks)
      }.to raise_error(Aidp::Harness::UI::SpinnerGroup::ExecutionError)
    end

    it "raises error for empty tasks array" do
      expect {
        spinner_group.run_analysis_tasks([])
      }.to raise_error(Aidp::Harness::UI::SpinnerGroup::ExecutionError)
    end
  end

  describe "#run_provider_operations" do
    let(:provider_ops) do
      [
        {provider: "anthropic", operation: "test", block: -> { "result1" }},
        {provider: "openai", operation: "test", block: -> { "result2" }}
      ]
    end

    it "converts and runs provider operations" do
      expect(spinner_group).to receive(:run_concurrent_operations)
      spinner_group.run_provider_operations(provider_ops)
    end

    it "validates provider operations before running" do
      invalid_ops = "not an array"
      expect {
        spinner_group.run_provider_operations(invalid_ops)
      }.to raise_error(Aidp::Harness::UI::SpinnerGroup::ExecutionError)
    end

    it "raises error for empty provider operations array" do
      expect {
        spinner_group.run_provider_operations([])
      }.to raise_error(Aidp::Harness::UI::SpinnerGroup::ExecutionError)
    end
  end

  describe "SpinnerGroupFormatter" do
    let(:formatter) { Aidp::Harness::UI::SpinnerGroupFormatter.new }

    it "formats operation title" do
      result = formatter.format_operation_title("Test Operation")
      expect(result).to include("Test Operation")
    end

    it "formats step title" do
      result = formatter.format_step_title("Test Step")
      expect(result).to include("Test Step")
    end

    it "formats task title" do
      result = formatter.format_task_title("Test Task")
      expect(result).to include("Test Task")
    end

    it "formats provider title" do
      result = formatter.format_provider_title("anthropic", "test")
      expect(result).to include("anthropic")
      expect(result).to include("test")
    end

    it "formats error title" do
      result = formatter.format_error_title("Original", "Error message")
      expect(result).to include("Original")
      expect(result).to include("Error message")
    end

    it "formats success title" do
      result = formatter.format_success_title("Completed")
      expect(result).to include("Completed")
    end

    it "formats progress title" do
      result = formatter.format_progress_title("Progress", 5, 10)
      expect(result).to include("Progress")
      expect(result).to include("5")
      expect(result).to include("10")
    end
  end

  describe "validation edge cases" do
    it "raises error for operation without title" do
      ops = [{block: -> { "test" }}]
      expect {
        spinner_group.run_concurrent_operations(ops)
      }.to raise_error(Aidp::Harness::UI::SpinnerGroup::ExecutionError)
    end

    it "raises error for operation with empty title" do
      ops = [{title: "", block: -> { "test" }}]
      expect {
        spinner_group.run_concurrent_operations(ops)
      }.to raise_error(Aidp::Harness::UI::SpinnerGroup::ExecutionError)
    end

    it "raises error for operation with whitespace-only title" do
      ops = [{title: "   ", block: -> { "test" }}]
      expect {
        spinner_group.run_concurrent_operations(ops)
      }.to raise_error(Aidp::Harness::UI::SpinnerGroup::ExecutionError)
    end

    it "raises error for operation with non-callable block" do
      ops = [{title: "Test", block: "not callable"}]
      expect {
        spinner_group.run_concurrent_operations(ops)
      }.to raise_error(Aidp::Harness::UI::SpinnerGroup::ExecutionError)
    end

    it "raises error for non-hash operation" do
      ops = ["not a hash"]
      expect {
        spinner_group.run_concurrent_operations(ops)
      }.to raise_error(Aidp::Harness::UI::SpinnerGroup::ExecutionError)
    end
  end
end
