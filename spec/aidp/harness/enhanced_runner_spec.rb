# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/enhanced_runner"

RSpec.describe Aidp::Harness::EnhancedRunner do
  let(:project_dir) { Dir.mktmpdir }
  let(:options) { {selected_steps: ["step1", "step2"], workflow_type: :default} }

  before do
    # Stub out heavy dependencies inside initializer so we don't need a real config file
    allow(Aidp.logger).to receive(:info)
    allow(Aidp.logger).to receive(:error)
    allow(Aidp::Harness::UI).to receive(:with_processing_spinner).and_yield

    mock_config = double("Configuration")
    allow(Aidp::Harness::Configuration).to receive(:new).and_return(mock_config)
    allow(Aidp::Harness::StateManager).to receive(:new).and_return(double("StateManager"))
    allow(Aidp::Harness::ConditionDetector).to receive(:new).and_return(double("ConditionDetector",
      needs_user_feedback?: false,
      extract_questions: [],
      is_rate_limited?: false))
    allow(Aidp::Harness::ProviderManager).to receive(:new).and_return(double("ProviderManager", current_provider: "test"))
    allow(Aidp::Harness::ErrorHandler).to receive(:new).and_return(double("ErrorHandler", execute_with_retry: {status: "completed"}))
    allow(Aidp::Harness::CompletionChecker).to receive(:new).and_return(double("CompletionChecker", completion_status: {all_complete: true}))
  end

  after { FileUtils.rm_rf(project_dir) }

  def build_runner(mode = :analyze)
    r = described_class.new(project_dir, mode, options)
    tui = r.instance_variable_get(:@tui)
    tui.instance_variable_set(:@jobs, {"main_workflow" => {}})
    r
  end

  describe "#status" do
    it "returns a hash with state info" do
      runner = build_runner
      st = runner.status
      expect(st).to include(:state, :mode, :current_step, :jobs_count)
    end
  end

  describe "#calculate_progress_percentage" do
    it "returns 0 when no steps" do
      runner = build_runner
      fake_mode_runner = double("ModeRunner", all_steps: [], progress: double(completed_steps: []))
      pct = runner.send(:calculate_progress_percentage, fake_mode_runner)
      expect(pct).to eq(0)
    end

    it "calculates percentage when steps present" do
      runner = build_runner
      fake_mode_runner = double("ModeRunner", all_steps: ["a", "b"], progress: double(completed_steps: ["a"]))
      pct = runner.send(:calculate_progress_percentage, fake_mode_runner)
      expect(pct).to eq(50.0)
    end
  end

  describe "#get_mode_runner" do
    it "raises for unsupported mode" do
      bad = build_runner(:unknown)
      expect { bad.send(:get_mode_runner) }.to raise_error(ArgumentError)
    end
  end

  describe "control methods" do
    it "can stop runner" do
      runner = build_runner
      expect { runner.stop }.not_to raise_error
      expect(runner.status[:state]).to eq("stopped")
    end
  end
end
