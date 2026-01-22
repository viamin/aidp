# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Activities::RunTestsActivity do
  let(:activity) { described_class.new }
  let(:project_dir) { "/tmp/test_project" }
  let(:mock_context) { instance_double("Temporalio::Activity::Context", info: mock_info) }
  let(:mock_info) { double("ActivityInfo", task_token: "test_token_123") }
  let(:mock_config) { {} }
  let(:mock_test_runner) { double("TestRunner") }

  before do
    allow(Temporalio::Activity).to receive(:context).and_return(mock_context)
    allow(Temporalio::Activity).to receive(:heartbeat)
    allow(Temporalio::Activity).to receive(:cancellation_requested?).and_return(false)
    allow(Aidp::Config).to receive(:load_harness_config).and_return(mock_config)
    allow(Aidp::Harness::TestRunner).to receive(:new).and_return(mock_test_runner)
  end

  describe "#execute" do
    context "when all phases pass" do
      before do
        allow(mock_test_runner).to receive(:run_tests).and_return(success: true, output: "OK")
        allow(mock_test_runner).to receive(:run_lint).and_return(success: true, output: "OK")
      end

      it "returns all_passing true" do
        result = activity.execute(
          project_dir: project_dir,
          iteration: 1,
          phases: [:test, :lint]
        )

        expect(result[:success]).to be true
        expect(result[:all_passing]).to be true
      end

      it "returns results for each phase" do
        result = activity.execute(
          project_dir: project_dir,
          iteration: 1,
          phases: [:test, :lint]
        )

        expect(result[:results][:test][:success]).to be true
        expect(result[:results][:lint][:success]).to be true
      end
    end

    context "when some phases fail" do
      before do
        allow(mock_test_runner).to receive(:run_tests).and_return(success: false, output: "FAILED")
        allow(mock_test_runner).to receive(:run_lint).and_return(success: true, output: "OK")
      end

      it "returns all_passing false" do
        result = activity.execute(
          project_dir: project_dir,
          iteration: 1,
          phases: [:test, :lint]
        )

        expect(result[:all_passing]).to be false
      end

      it "returns partial_pass true when at least one phase passes" do
        result = activity.execute(
          project_dir: project_dir,
          iteration: 1,
          phases: [:test, :lint]
        )

        expect(result[:partial_pass]).to be true
      end

      it "includes failed phases in summary" do
        result = activity.execute(
          project_dir: project_dir,
          iteration: 1,
          phases: [:test, :lint]
        )

        expect(result[:summary][:failed_phases]).to eq([:test])
      end
    end

    context "with different phase types" do
      it "handles typecheck phase" do
        allow(mock_test_runner).to receive(:run_typecheck).and_return(success: true, output: "OK")

        result = activity.execute(
          project_dir: project_dir,
          iteration: 1,
          phases: [:typecheck]
        )

        expect(result[:results][:typecheck][:success]).to be true
      end

      it "handles build phase" do
        allow(mock_test_runner).to receive(:run_build).and_return(success: true, output: "OK")

        result = activity.execute(
          project_dir: project_dir,
          iteration: 1,
          phases: [:build]
        )

        expect(result[:results][:build][:success]).to be true
      end

      it "handles unknown phase" do
        result = activity.execute(
          project_dir: project_dir,
          iteration: 1,
          phases: [:unknown]
        )

        expect(result[:results][:unknown][:success]).to be false
        expect(result[:results][:unknown][:output]).to include("Unknown phase")
      end

      it "handles string phase names" do
        allow(mock_test_runner).to receive(:run_tests).and_return(success: true, output: "OK")

        result = activity.execute(
          project_dir: project_dir,
          iteration: 1,
          phases: ["test"]
        )

        expect(result[:results]["test"][:success]).to be true
      end
    end

    context "when phase raises an error" do
      before do
        allow(mock_test_runner).to receive(:run_tests).and_raise(StandardError.new("Test runner crashed"))
      end

      it "catches the error and marks phase as failed" do
        result = activity.execute(
          project_dir: project_dir,
          iteration: 1,
          phases: [:test]
        )

        expect(result[:results][:test][:success]).to be false
        expect(result[:results][:test][:output]).to include("Test runner crashed")
        expect(result[:results][:test][:exit_code]).to eq(-1)
      end
    end

    context "when using default phases" do
      before do
        allow(mock_test_runner).to receive(:run_tests).and_return(success: true, output: "OK")
        allow(mock_test_runner).to receive(:run_lint).and_return(success: true, output: "OK")
      end

      it "uses test and lint as defaults" do
        result = activity.execute(
          project_dir: project_dir,
          iteration: 1
        )

        expect(result[:results].keys).to contain_exactly(:test, :lint)
      end
    end
  end
end
