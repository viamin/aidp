# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Workflows::BaseWorkflow do
  describe "class methods" do
    describe ".workflow_name" do
      it "converts class name to workflow name" do
        # Create a test subclass
        test_class = Class.new(described_class)
        allow(test_class).to receive(:name).and_return("Aidp::Temporal::Workflows::TestWorkflow")

        expect(test_class.workflow_name).to eq("test")
      end

      it "handles camelcase conversion" do
        test_class = Class.new(described_class)
        allow(test_class).to receive(:name).and_return("Aidp::Temporal::Workflows::IssueToPrWorkflow")

        expect(test_class.workflow_name).to eq("issue_to_pr")
      end
    end

    describe ".activity_options" do
      it "returns default options" do
        options = described_class.activity_options

        expect(options[:start_to_close_timeout]).to eq(600)
        expect(options[:heartbeat_timeout]).to eq(60)
        expect(options[:retry_policy]).to be_a(Hash)
      end

      it "merges overrides with defaults" do
        options = described_class.activity_options(start_to_close_timeout: 300)

        expect(options[:start_to_close_timeout]).to eq(300)
        expect(options[:heartbeat_timeout]).to eq(60)
      end
    end
  end

  describe "DEFAULT_ACTIVITY_OPTIONS" do
    it "has expected defaults" do
      defaults = described_class::DEFAULT_ACTIVITY_OPTIONS

      expect(defaults[:start_to_close_timeout]).to eq(600)
      expect(defaults[:heartbeat_timeout]).to eq(60)
      expect(defaults[:retry_policy][:initial_interval]).to eq(1)
      expect(defaults[:retry_policy][:backoff_coefficient]).to eq(2.0)
      expect(defaults[:retry_policy][:maximum_interval]).to eq(60)
      expect(defaults[:retry_policy][:maximum_attempts]).to eq(3)
    end

    it "is frozen" do
      expect(described_class::DEFAULT_ACTIVITY_OPTIONS).to be_frozen
    end
  end

  describe "instance methods" do
    let(:workflow) { described_class.new }
    let(:mock_workflow_info) { double("WorkflowInfo", workflow_id: "test-123", run_id: "run-456") }

    before do
      allow(Temporalio::Workflow).to receive(:info).and_return(mock_workflow_info)
    end

    describe "#workflow_info" do
      it "returns workflow info" do
        expect(workflow.send(:workflow_info)).to eq(mock_workflow_info)
      end
    end

    describe "#workflow_sleep" do
      it "delegates to Temporalio::Workflow.sleep" do
        expect(Temporalio::Workflow).to receive(:sleep).with(10)

        workflow.send(:workflow_sleep, 10)
      end
    end

    describe "#cancellation_requested?" do
      it "delegates to Temporalio::Workflow.cancellation_pending?" do
        expect(Temporalio::Workflow).to receive(:cancellation_pending?).and_return(false)

        expect(workflow.send(:cancellation_requested?)).to be false
      end
    end

    describe "#build_retry_policy" do
      it "creates retry policy from config" do
        mock_policy = double("RetryPolicy")
        expect(Temporalio::RetryPolicy).to receive(:new).with(
          initial_interval: 2,
          backoff_coefficient: 1.5,
          maximum_interval: 30,
          maximum_attempts: 5
        ).and_return(mock_policy)

        config = {
          initial_interval: 2,
          backoff_coefficient: 1.5,
          maximum_interval: 30,
          maximum_attempts: 5
        }

        result = workflow.send(:build_retry_policy, config)

        expect(result).to eq(mock_policy)
      end

      it "uses defaults for missing config values" do
        mock_policy = double("RetryPolicy")
        expect(Temporalio::RetryPolicy).to receive(:new).with(
          initial_interval: 1,
          backoff_coefficient: 2.0,
          maximum_interval: 60,
          maximum_attempts: 3
        ).and_return(mock_policy)

        workflow.send(:build_retry_policy, {})
      end
    end
  end
end
