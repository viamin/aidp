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
end
