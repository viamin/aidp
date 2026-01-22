# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Activities::RecordCheckpointActivity do
  let(:activity) { described_class.new }
  let(:project_dir) { "/tmp/test_project" }
  let(:mock_context) { instance_double("Temporalio::Activity::Context", info: mock_info) }
  let(:mock_info) { double("ActivityInfo", task_token: "test_token_123") }
  let(:mock_checkpoint) { instance_double(Aidp::Execute::Checkpoint) }

  before do
    allow(Temporalio::Activity).to receive(:context).and_return(mock_context)
    allow(Aidp::Execute::Checkpoint).to receive(:new).and_return(mock_checkpoint)
    allow(mock_checkpoint).to receive(:record_checkpoint)
  end

  describe "#execute" do
    let(:base_input) do
      {
        project_dir: project_dir,
        step_name: "test_step",
        iteration: 1,
        state: "running"
      }
    end

    context "with test results" do
      let(:test_results) do
        {
          results: {
            test: {success: true, duration: 1.5},
            lint: {success: false, duration: 0.5}
          }
        }
      end

      it "records checkpoint with metrics" do
        expect(mock_checkpoint).to receive(:record_checkpoint).with(
          "test_step",
          1,
          hash_including(
            state: "running",
            workflow_type: "temporal"
          )
        )

        activity.execute(base_input.merge(test_results: test_results))
      end

      it "calculates pass rate correctly" do
        result = activity.execute(base_input.merge(test_results: test_results))

        expect(result[:success]).to be true
        expect(result[:step_name]).to eq("test_step")
        expect(result[:iteration]).to eq(1)
      end
    end

    context "without test results" do
      it "handles nil test_results" do
        result = activity.execute(base_input.merge(test_results: nil))

        expect(result[:success]).to be true
      end

      it "handles missing test_results" do
        result = activity.execute(base_input)

        expect(result[:success]).to be true
      end
    end

    context "with empty test results" do
      let(:test_results) { {results: {}} }

      it "handles empty results hash" do
        result = activity.execute(base_input.merge(test_results: test_results))

        expect(result[:success]).to be true
      end
    end

    context "with results that have no results key" do
      let(:test_results) { {} }

      it "handles missing results key" do
        result = activity.execute(base_input.merge(test_results: test_results))

        expect(result[:success]).to be true
      end
    end
  end
end
