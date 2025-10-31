# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/prompt_manager"
require "fileutils"
require "tmpdir"

RSpec.describe Aidp::Execute::PromptManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:manager) { described_class.new(temp_dir) }
  let(:prompt_path) { File.join(temp_dir, "PROMPT.md") }
  let(:archive_dir) { File.join(temp_dir, ".aidp", "prompt_archive") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#write" do
    it "creates PROMPT.md with content" do
      content = "# Test Prompt\n\nSome content"
      manager.write(content)

      expect(File.exist?(prompt_path)).to be true
      expect(File.read(prompt_path)).to eq content
    end

    it "overwrites existing PROMPT.md" do
      manager.write("Original content")
      manager.write("New content")

      expect(File.read(prompt_path)).to eq "New content"
    end
  end

  describe "#read" do
    it "returns nil when PROMPT.md doesn't exist" do
      expect(manager.read).to be_nil
    end

    it "returns content when PROMPT.md exists" do
      content = "# Test Content"
      File.write(prompt_path, content)

      expect(manager.read).to eq content
    end
  end

  describe "#exists?" do
    it "returns false when PROMPT.md doesn't exist" do
      expect(manager.exists?).to be false
    end

    it "returns true when PROMPT.md exists" do
      File.write(prompt_path, "content")
      expect(manager.exists?).to be true
    end
  end

  describe "#archive" do
    let(:step_name) { "test_step" }

    it "returns nil when PROMPT.md doesn't exist" do
      expect(manager.archive(step_name)).to be_nil
    end

    it "creates archive directory if it doesn't exist" do
      File.write(prompt_path, "content")
      manager.archive(step_name)

      expect(Dir.exist?(archive_dir)).to be true
    end

    it "copies PROMPT.md to archive with timestamp and step name" do
      content = "# Archived Content"
      File.write(prompt_path, content)

      archive_path = manager.archive(step_name)

      expect(File.exist?(archive_path)).to be true
      expect(File.read(archive_path)).to eq content
      expect(File.basename(archive_path)).to match(/^\d{8}_\d{6}_#{step_name}_PROMPT\.md$/)
    end

    it "doesn't delete original PROMPT.md" do
      File.write(prompt_path, "content")
      manager.archive(step_name)

      expect(File.exist?(prompt_path)).to be true
    end
  end

  describe "#delete" do
    it "does nothing when PROMPT.md doesn't exist" do
      expect { manager.delete }.not_to raise_error
    end

    it "deletes PROMPT.md when it exists" do
      File.write(prompt_path, "content")
      manager.delete

      expect(File.exist?(prompt_path)).to be false
    end
  end

  describe "#path" do
    it "returns the full path to PROMPT.md" do
      expect(manager.path).to eq prompt_path
    end
  end

  context "with optimization enabled" do
    let(:mock_stats) do
      double(
        selected_count: 2,
        excluded_count: 3,
        total_tokens: 500,
        budget: 1000,
        budget_utilization: 50.0,
        average_score: 0.85,
        selected_fragments: [
          {fragment: double(heading: "Style Guide"), score: 0.92},
          {fragment: double(heading: "API Contract"), score: 0.78}
        ]
      )
    end

    let(:mock_result) do
      double(
        composition_result: mock_stats,
        estimated_tokens: 520
      ).tap do |d|
        allow(d).to receive(:write_to_file) do |path|
          File.write(path, "# Optimized Prompt\nContent")
          true
        end
      end
    end

    let(:mock_optimizer) do
      double(optimize_prompt: mock_result, statistics: {invocations: 1})
    end

    let(:config) do
      double(
        prompt_optimization_enabled?: true,
        prompt_optimization_config: {budget: 1000}
      )
    end

    before do
      allow(Aidp::PromptOptimization::Optimizer).to receive(:new).and_return(mock_optimizer)
    end

    it "initializes optimizer when enabled" do
      pm = described_class.new(temp_dir, config: config)
      expect(pm.optimization_enabled?).to be true
    end

    it "writes optimized prompt and sets stats" do
      pm = described_class.new(temp_dir, config: config)
      used = pm.write_optimized({task_type: :feature, description: "Add login"})
      expect(used).to be true
      expect(pm.last_optimization_stats).to eq(mock_stats)
      expect(pm.optimizer_stats).to eq({invocations: 1})
      expect(File.exist?(prompt_path)).to be true
    end

    it "builds optimization report" do
      pm = described_class.new(temp_dir, config: config)
      pm.write_optimized({task_type: :feature, description: "Add login"})
      report = pm.optimization_report
      expect(report).to include("Prompt Optimization Report")
      expect(report).to include("Selected Fragments")
      expect(report).to include("Style Guide")
    end

    it "falls back when optimization raises" do
      failing_optimizer = double
      allow(failing_optimizer).to receive(:optimize_prompt).and_raise(StandardError.new("boom"))
      allow(Aidp::PromptOptimization::Optimizer).to receive(:new).and_return(failing_optimizer)
      pm = described_class.new(temp_dir, config: config)
      used = pm.write_optimized({task_type: :bugfix, description: "Fix crash"})
      expect(used).to be false
      expect(pm.last_optimization_stats).to be_nil
    end
  end

  context "without optimization enabled" do
    it "returns false for optimization_enabled?" do
      expect(manager.optimization_enabled?).to be false
    end

    it "write_optimized returns false and warns" do
      expect(manager.write_optimized({task_type: :feature, description: "Test"})).to be false
    end

    it "optimization_report returns nil" do
      expect(manager.optimization_report).to be_nil
    end
  end
end
