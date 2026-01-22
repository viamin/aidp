# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Activities::BaseActivity do
  let(:activity) { described_class.new }
  let(:mock_context) { instance_double("Temporalio::Activity::Context", info: mock_info) }
  let(:mock_info) { double("ActivityInfo", task_token: "test_token_123") }

  before do
    allow(Temporalio::Activity).to receive(:context).and_return(mock_context)
  end

  describe "#activity_context" do
    it "returns the Temporal activity context" do
      expect(activity.activity_context).to eq(mock_context)
    end
  end

  describe "#heartbeat" do
    it "delegates to Temporalio::Activity.heartbeat" do
      expect(Temporalio::Activity).to receive(:heartbeat).with("progress", 50)

      activity.heartbeat("progress", 50)
    end
  end

  describe "#cancellation_requested?" do
    it "delegates to Temporalio::Activity.cancellation_requested?" do
      expect(Temporalio::Activity).to receive(:cancellation_requested?).and_return(false)

      expect(activity.cancellation_requested?).to be false
    end
  end

  describe "#check_cancellation!" do
    it "does nothing when not canceled" do
      allow(Temporalio::Activity).to receive(:cancellation_requested?).and_return(false)

      expect { activity.check_cancellation! }.not_to raise_error
    end

    it "raises CanceledError when canceled" do
      allow(Temporalio::Activity).to receive(:cancellation_requested?).and_return(true)

      expect { activity.check_cancellation! }.to raise_error(Temporalio::Error::CanceledError)
    end
  end

  describe "#success_result" do
    it "returns success hash with data" do
      result = activity.send(:success_result, foo: "bar")

      expect(result).to eq(success: true, foo: "bar")
    end

    it "returns success hash without data" do
      result = activity.send(:success_result)

      expect(result).to eq(success: true)
    end
  end

  describe "#error_result" do
    it "returns error hash with message" do
      result = activity.send(:error_result, "Something failed")

      expect(result).to eq(success: false, error: "Something failed")
    end

    it "returns error hash with additional data" do
      result = activity.send(:error_result, "Something failed", code: 500)

      expect(result).to eq(success: false, error: "Something failed", code: 500)
    end
  end

  describe "#with_activity_context" do
    it "logs start and completion" do
      allow(Temporalio::Activity).to receive(:context).and_return(mock_context)

      result = activity.send(:with_activity_context) { "test result" }

      expect(result).to eq("test result")
    end

    it "re-raises errors" do
      allow(Temporalio::Activity).to receive(:context).and_return(mock_context)

      expect {
        activity.send(:with_activity_context) { raise "test error" }
      }.to raise_error(RuntimeError, "test error")
    end
  end
end
