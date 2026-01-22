# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Activities::DiagnoseFailureActivity do
  let(:activity) { described_class.new }
  let(:project_dir) { Dir.mktmpdir }
  let(:mock_context) { instance_double("Temporalio::Activity::Context", info: mock_info) }
  let(:mock_info) { double("ActivityInfo", task_token: "test_token_123") }
  let(:mock_prompt_manager) { double("PromptManager", prompt_path: "#{project_dir}/PROMPT.md") }

  before do
    allow(Temporalio::Activity).to receive(:context).and_return(mock_context)
    allow(Aidp::Execute::PromptManager).to receive(:new).and_return(mock_prompt_manager)
    allow(mock_prompt_manager).to receive(:read).and_return("# Existing prompt")
    allow(mock_prompt_manager).to receive(:write)
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#execute" do
    let(:base_input) do
      {
        project_dir: project_dir,
        iteration: 1,
        test_result: {
          results: {
            test: {success: true, output: "OK"},
            lint: {success: true, output: "OK"}
          }
        }
      }
    end

    it "returns success result with diagnosis" do
      result = activity.execute(base_input)

      expect(result[:success]).to be true
      expect(result[:iteration]).to eq(1)
      expect(result[:diagnosis]).to be_a(Hash)
    end

    context "with test failures" do
      let(:failing_input) do
        base_input.merge(
          test_result: {
            results: {
              test: {
                success: false,
                output: "FAIL test_example\nExpected: 1\nGot: 2\n\nFailed."
              }
            }
          }
        )
      end

      it "extracts test failures" do
        result = activity.execute(failing_input)

        expect(result[:diagnosis][:failure_count]).to be > 0
        expect(result[:diagnosis][:failures]).to be_an(Array)
      end

      it "generates recommendations for test failures" do
        result = activity.execute(failing_input)

        expect(result[:diagnosis][:recommendations]).to include(
          "Review failing test assertions and update implementation"
        )
      end
    end

    context "with lint failures" do
      let(:lint_input) do
        base_input.merge(
          test_result: {
            results: {
              lint: {
                success: false,
                output: "lib/test.rb:10:5: Error: extra space"
              }
            }
          }
        )
      end

      it "extracts lint failures" do
        result = activity.execute(lint_input)

        expect(result[:diagnosis][:failures].any? { |f| f[:type] == :lint }).to be true
      end

      it "generates recommendations for lint failures" do
        result = activity.execute(lint_input)

        expect(result[:diagnosis][:recommendations]).to include(
          "Fix code style issues to match project standards"
        )
      end
    end

    context "with typecheck failures" do
      let(:typecheck_input) do
        base_input.merge(
          test_result: {
            results: {
              typecheck: {
                success: false,
                output: "Type error: expected String but got Integer"
              }
            }
          }
        )
      end

      it "extracts typecheck failures" do
        result = activity.execute(typecheck_input)

        expect(result[:diagnosis][:failures].any? { |f| f[:type] == :typecheck }).to be true
      end

      it "generates recommendations for typecheck failures" do
        result = activity.execute(typecheck_input)

        expect(result[:diagnosis][:recommendations]).to include(
          "Fix type errors to ensure type safety"
        )
      end
    end

    context "with unknown phase failures" do
      let(:unknown_input) do
        base_input.merge(
          test_result: {
            results: {
              custom: {
                success: false,
                output: "Something went wrong"
              }
            }
          }
        )
      end

      it "handles unknown phases gracefully" do
        result = activity.execute(unknown_input)

        expect(result[:success]).to be true
        expect(result[:diagnosis][:failures].any? { |f| f[:type] == :unknown }).to be true
      end
    end
  end

  describe "#build_failure_summary (private)" do
    it "returns 'No failures found' for empty array" do
      result = activity.send(:build_failure_summary, [])
      expect(result).to eq("No failures found")
    end

    it "summarizes failures by type" do
      failures = [
        {type: :test, message: "fail 1"},
        {type: :test, message: "fail 2"},
        {type: :lint, message: "lint fail"}
      ]

      result = activity.send(:build_failure_summary, failures)

      expect(result).to include("2 test failure(s)")
      expect(result).to include("1 lint failure(s)")
    end
  end

  describe "#generate_recommendations (private)" do
    it "returns empty array when no failures" do
      result = activity.send(:generate_recommendations, [])
      expect(result).to eq([])
    end

    it "includes test recommendation for test failures" do
      failures = [{type: :test}]
      result = activity.send(:generate_recommendations, failures)
      expect(result).to include("Review failing test assertions and update implementation")
    end

    it "includes lint recommendation for lint failures" do
      failures = [{type: :lint}]
      result = activity.send(:generate_recommendations, failures)
      expect(result).to include("Fix code style issues to match project standards")
    end

    it "includes typecheck recommendation for typecheck failures" do
      failures = [{type: :typecheck}]
      result = activity.send(:generate_recommendations, failures)
      expect(result).to include("Fix type errors to ensure type safety")
    end

    it "includes all recommendations for mixed failures" do
      failures = [{type: :test}, {type: :lint}, {type: :typecheck}]
      result = activity.send(:generate_recommendations, failures)
      expect(result.length).to eq(3)
    end
  end

  describe "#extract_failures (private)" do
    it "limits failures to 20" do
      output = (1..30).map { |i| "FAIL test_#{i}\n\n" }.join
      result = activity.send(:extract_failures, :test, {output: output})
      expect(result.length).to be <= 20
    end

    it "handles nil output" do
      result = activity.send(:extract_failures, :test, {})
      expect(result).to be_an(Array)
    end
  end

  describe "#update_prompt_with_diagnosis (private)" do
    let(:diagnosis) do
      {
        summary: "1 test failure(s)",
        failures: [{type: :test, message: "FAIL"}],
        recommendations: ["Fix tests"]
      }
    end

    it "appends diagnosis to prompt" do
      expect(mock_prompt_manager).to receive(:write) do |content|
        expect(content).to include("Test/Lint Failures")
        expect(content).to include("1 test failure(s)")
      end

      activity.send(:update_prompt_with_diagnosis, project_dir, diagnosis)
    end

    it "does nothing when no existing prompt" do
      allow(mock_prompt_manager).to receive(:read).and_return(nil)
      expect(mock_prompt_manager).not_to receive(:write)

      activity.send(:update_prompt_with_diagnosis, project_dir, diagnosis)
    end
  end

  describe "#build_failure_section (private)" do
    it "includes summary" do
      diagnosis = {summary: "Test summary", failures: [], recommendations: []}
      result = activity.send(:build_failure_section, diagnosis)
      expect(result).to include("Test summary")
    end

    it "includes failure details" do
      diagnosis = {
        summary: "",
        failures: [{type: :test, message: "Error message"}],
        recommendations: []
      }
      result = activity.send(:build_failure_section, diagnosis)
      expect(result).to include("Error message")
      expect(result).to include("Failure 1 (test)")
    end

    it "limits failures to 10" do
      failures = (1..15).map { |i| {type: :test, message: "fail #{i}"} }
      diagnosis = {summary: "", failures: failures, recommendations: []}
      result = activity.send(:build_failure_section, diagnosis)
      expect(result).not_to include("Failure 11")
    end

    it "includes recommendations" do
      diagnosis = {
        summary: "",
        failures: [],
        recommendations: ["Fix tests", "Fix lint"]
      }
      result = activity.send(:build_failure_section, diagnosis)
      expect(result).to include("- Fix tests")
      expect(result).to include("- Fix lint")
    end
  end
end
