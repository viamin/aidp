# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Execute::Checkpoint do
  let(:temp_dir) { Dir.mktmpdir }
  let(:checkpoint) { described_class.new(temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "sets checkpoint file path" do
      expect(checkpoint.checkpoint_file).to eq(File.join(temp_dir, ".aidp", "checkpoint.yml"))
    end

    it "sets history file path" do
      expect(checkpoint.history_file).to eq(File.join(temp_dir, ".aidp", "checkpoint_history.jsonl"))
    end

    it "creates checkpoint directory when recording" do
      checkpoint.record_checkpoint("test_step", 1)
      expect(File.directory?(File.join(temp_dir, ".aidp"))).to be true
    end
  end

  describe "#record_checkpoint" do
    it "records a checkpoint with step name and iteration" do
      result = checkpoint.record_checkpoint("test_step", 1)

      expect(result).to include(
        step_name: "test_step",
        iteration: 1
      )
      expect(result[:timestamp]).to be_a(String)
      expect(result[:metrics]).to be_a(Hash)
      expect(result[:status]).to be_a(String)
    end

    it "saves checkpoint to file" do
      checkpoint.record_checkpoint("test_step", 1)

      expect(File.exist?(checkpoint.checkpoint_file)).to be true
    end

    it "appends to history file" do
      checkpoint.record_checkpoint("test_step", 1)
      checkpoint.record_checkpoint("test_step", 2)

      history = checkpoint.checkpoint_history
      expect(history.size).to eq(2)
      expect(history[0][:iteration]).to eq(1)
      expect(history[1][:iteration]).to eq(2)
    end

    it "includes custom metrics" do
      custom_metrics = {tests_passing: true, linters_passing: false}
      result = checkpoint.record_checkpoint("test_step", 1, custom_metrics)

      expect(result[:metrics][:tests_passing]).to be true
      expect(result[:metrics][:linters_passing]).to be false
    end
  end

  describe "#latest_checkpoint" do
    it "returns nil when no checkpoint exists" do
      expect(checkpoint.latest_checkpoint).to be_nil
    end

    it "returns the latest checkpoint data" do
      checkpoint.record_checkpoint("test_step", 1)
      checkpoint.record_checkpoint("test_step", 2)

      latest = checkpoint.latest_checkpoint
      expect(latest[:iteration]).to eq(2)
    end
  end

  describe "#checkpoint_history" do
    it "returns empty array when no history exists" do
      expect(checkpoint.checkpoint_history).to eq([])
    end

    it "returns all checkpoint history" do
      3.times { |i| checkpoint.record_checkpoint("test_step", i + 1) }

      history = checkpoint.checkpoint_history
      expect(history.size).to eq(3)
    end

    it "limits history when specified" do
      5.times { |i| checkpoint.record_checkpoint("test_step", i + 1) }

      history = checkpoint.checkpoint_history(limit: 3)
      expect(history.size).to eq(3)
      expect(history.last[:iteration]).to eq(5)
    end
  end

  describe "#progress_summary" do
    it "returns nil when no checkpoint exists" do
      expect(checkpoint.progress_summary).to be_nil
    end

    it "returns summary with current checkpoint" do
      checkpoint.record_checkpoint("test_step", 1)

      summary = checkpoint.progress_summary
      expect(summary[:current]).to be_a(Hash)
      expect(summary[:quality_score]).to be_a(Numeric)
    end

    it "includes trends when multiple checkpoints exist" do
      checkpoint.record_checkpoint("test_step", 1)
      checkpoint.record_checkpoint("test_step", 2)

      summary = checkpoint.progress_summary
      expect(summary[:trends]).to be_a(Hash)
      expect(summary[:previous]).to be_a(Hash)
    end
  end

  describe "#clear" do
    it "removes checkpoint file" do
      checkpoint.record_checkpoint("test_step", 1)
      checkpoint.clear

      expect(File.exist?(checkpoint.checkpoint_file)).to be false
    end

    it "removes history file" do
      checkpoint.record_checkpoint("test_step", 1)
      checkpoint.clear

      expect(File.exist?(checkpoint.history_file)).to be false
    end
  end

  describe "metrics collection" do
    before do
      # Create a simple Ruby file for testing
      FileUtils.mkdir_p(File.join(temp_dir, "lib"))
      File.write(File.join(temp_dir, "lib", "test.rb"), "# Test file\nclass Test\nend\n")
    end

    it "counts lines of code" do
      result = checkpoint.record_checkpoint("test_step", 1)
      expect(result[:metrics][:lines_of_code]).to be > 0
    end

    it "counts project files" do
      result = checkpoint.record_checkpoint("test_step", 1)
      expect(result[:metrics][:file_count]).to be > 0
    end

    it "estimates test coverage" do
      result = checkpoint.record_checkpoint("test_step", 1)
      expect(result[:metrics][:test_coverage]).to be >= 0
      expect(result[:metrics][:test_coverage]).to be <= 100
    end

    it "assesses code quality" do
      result = checkpoint.record_checkpoint("test_step", 1)
      expect(result[:metrics][:code_quality]).to be >= 0
      expect(result[:metrics][:code_quality]).to be <= 100
    end
  end

  describe "status determination" do
    it "marks status as healthy for good metrics" do
      metrics = {test_coverage: 90, code_quality: 90, prd_task_progress: 80}
      result = checkpoint.record_checkpoint("test_step", 1, metrics)

      expect(result[:status]).to eq("healthy")
    end

    it "marks status as warning for moderate metrics" do
      metrics = {test_coverage: 70, code_quality: 65, prd_task_progress: 60}
      result = checkpoint.record_checkpoint("test_step", 1, metrics)

      expect(result[:status]).to eq("warning")
    end

    it "marks status as needs_attention for poor metrics" do
      metrics = {test_coverage: 40, code_quality: 50, prd_task_progress: 30}
      result = checkpoint.record_checkpoint("test_step", 1, metrics)

      expect(result[:status]).to eq("needs_attention")
    end
  end

  describe "trend calculation" do
    it "calculates upward trends" do
      # First checkpoint with lower metrics
      checkpoint.record_checkpoint("test_step", 1, {test_coverage: 50})
      # Second checkpoint with higher metrics
      checkpoint.record_checkpoint("test_step", 2, {test_coverage: 75})

      summary = checkpoint.progress_summary
      trend = summary[:trends][:test_coverage]

      expect(trend[:direction]).to eq("up")
      expect(trend[:change]).to eq(25)
    end

    it "calculates downward trends" do
      checkpoint.record_checkpoint("test_step", 1, {code_quality: 80})
      checkpoint.record_checkpoint("test_step", 2, {code_quality: 60})

      summary = checkpoint.progress_summary
      trend = summary[:trends][:code_quality]

      expect(trend[:direction]).to eq("down")
      expect(trend[:change]).to eq(-20)
    end

    it "marks stable trends when values don't change" do
      checkpoint.record_checkpoint("test_step", 1, {prd_task_progress: 50})
      checkpoint.record_checkpoint("test_step", 2, {prd_task_progress: 50})

      summary = checkpoint.progress_summary
      trend = summary[:trends][:prd_task_progress]

      expect(trend[:direction]).to eq("stable")
      expect(trend[:change]).to eq(0)
    end
  end
end
