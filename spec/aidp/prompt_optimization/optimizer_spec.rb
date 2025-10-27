# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/aidp/prompt_optimization/optimizer"

RSpec.describe Aidp::PromptOptimization::Optimizer do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config) do
    {
      enabled: true,
      max_tokens: 8000,
      include_threshold: {
        style_guide: 0.75,
        templates: 0.8,
        source: 0.7
      },
      dynamic_adjustment: false,
      log_selected_fragments: false
    }
  end
  let(:optimizer) { described_class.new(project_dir: temp_dir, config: config) }

  before do
    # Create minimal file structure
    FileUtils.mkdir_p(File.join(temp_dir, "docs"))
    FileUtils.mkdir_p(File.join(temp_dir, "templates", "analysis"))
    FileUtils.mkdir_p(File.join(temp_dir, "templates", "planning"))
    FileUtils.mkdir_p(File.join(temp_dir, "templates", "implementation"))
    FileUtils.mkdir_p(File.join(temp_dir, "lib"))

    # Create sample style guide
    File.write(
      File.join(temp_dir, "docs", "LLM_STYLE_GUIDE.md"),
      sample_style_guide
    )

    # Create sample template
    File.write(
      File.join(temp_dir, "templates", "implementation", "feature.md"),
      sample_template
    )

    # Create sample source file
    File.write(
      File.join(temp_dir, "lib", "user.rb"),
      sample_source_file
    )
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "initializes with project directory" do
      expect(optimizer.project_dir).to eq(temp_dir)
    end

    it "initializes with config" do
      expect(optimizer.config).to eq(config)
    end

    it "uses default config when none provided" do
      opt = described_class.new(project_dir: temp_dir)
      expect(opt.config[:enabled]).to eq(false)
      expect(opt.config[:max_tokens]).to eq(16000)
    end

    it "initializes stats tracker" do
      expect(optimizer.stats).to be_a(Aidp::PromptOptimization::OptimizerStats)
    end
  end

  describe "#optimize_prompt" do
    it "returns a PromptOutput" do
      result = optimizer.optimize_prompt(
        task_type: :feature,
        description: "Add user authentication",
        affected_files: ["lib/user.rb"],
        step_name: "implementation"
      )

      expect(result).to be_a(Aidp::PromptOptimization::PromptOutput)
    end

    it "includes task section in output" do
      result = optimizer.optimize_prompt(
        task_type: :feature,
        description: "Add user authentication",
        affected_files: ["lib/user.rb"],
        step_name: "implementation"
      )

      expect(result.content).to include("# Task")
      expect(result.content).to include("Add user authentication")
    end

    it "includes style guide fragments when relevant" do
      result = optimizer.optimize_prompt(
        task_type: :feature,
        description: "Add testing for authentication",
        affected_files: ["lib/user.rb"],
        step_name: "implementation",
        tags: ["testing"]
      )

      expect(result.content).to include("# Relevant Style Guidelines")
    end

    it "includes template fragments when relevant" do
      result = optimizer.optimize_prompt(
        task_type: :feature,
        description: "Implement new feature",
        affected_files: ["lib/user.rb"],
        step_name: "implementation"
      )

      expect(result.content).to include("# Template Guidance")
    end

    it "includes code fragments from affected files" do
      result = optimizer.optimize_prompt(
        task_type: :feature,
        description: "Update User class",
        affected_files: ["lib/user.rb"],
        step_name: "implementation"
      )

      expect(result.content).to include("# Code Context")
      expect(result.content).to include("class User")
    end

    it "respects max_tokens option" do
      result = optimizer.optimize_prompt(
        task_type: :feature,
        description: "Add feature",
        affected_files: ["lib/user.rb"],
        step_name: "implementation",
        options: {max_tokens: 2000}
      )

      expect(result.composition_result.budget).to be <= 2000
    end

    it "includes metadata when requested" do
      result = optimizer.optimize_prompt(
        task_type: :feature,
        description: "Add feature",
        affected_files: ["lib/user.rb"],
        step_name: "implementation",
        options: {include_metadata: true}
      )

      expect(result.content).to include("# Prompt Optimization Metadata")
    end

    it "updates statistics" do
      expect {
        optimizer.optimize_prompt(
          task_type: :feature,
          description: "Add feature",
          affected_files: ["lib/user.rb"],
          step_name: "implementation"
        )
      }.to change { optimizer.stats.runs_count }.by(1)
    end

    it "records fragments indexed" do
      optimizer.optimize_prompt(
        task_type: :feature,
        description: "Add feature",
        affected_files: ["lib/user.rb"],
        step_name: "implementation"
      )

      expect(optimizer.stats.total_fragments_indexed).to be > 0
    end

    it "records fragments selected" do
      optimizer.optimize_prompt(
        task_type: :feature,
        description: "Add feature",
        affected_files: ["lib/user.rb"],
        step_name: "implementation"
      )

      expect(optimizer.stats.total_fragments_selected).to be > 0
    end

    it "records optimization time" do
      optimizer.optimize_prompt(
        task_type: :feature,
        description: "Add feature",
        affected_files: ["lib/user.rb"],
        step_name: "implementation"
      )

      expect(optimizer.stats.total_optimization_time).to be > 0
    end
  end

  describe "#clear_cache" do
    it "resets cached indexers" do
      # First optimization to populate cache
      optimizer.optimize_prompt(
        task_type: :feature,
        description: "Add feature",
        affected_files: ["lib/user.rb"]
      )

      expect(optimizer.stats.runs_count).to eq(1)

      optimizer.clear_cache

      expect(optimizer.stats.runs_count).to eq(0)
    end
  end

  describe "#statistics" do
    it "returns statistics hash" do
      optimizer.optimize_prompt(
        task_type: :feature,
        description: "Add feature",
        affected_files: ["lib/user.rb"]
      )

      stats = optimizer.statistics

      expect(stats).to be_a(Hash)
      expect(stats[:runs_count]).to eq(1)
      expect(stats[:total_fragments_indexed]).to be > 0
      expect(stats[:average_optimization_time_ms]).to be > 0
    end
  end

  def sample_style_guide
    <<~MARKDOWN
      # LLM Style Guide

      ## Testing Guidelines

      Write comprehensive tests for all code.

      ## Implementation Best Practices

      Follow Ruby conventions and keep methods small.
    MARKDOWN
  end

  def sample_template
    <<~MARKDOWN
      # Feature Implementation Template

      Use this template for implementing new features.

      ## Steps
      1. Write tests
      2. Implement feature
      3. Refactor
    MARKDOWN
  end

  def sample_source_file
    <<~RUBY
      # frozen_string_literal: true

      class User
        attr_reader :name, :email

        def initialize(name, email)
          @name = name
          @email = email
        end

        def valid?
          !name.empty? && email.include?("@")
        end
      end
    RUBY
  end
end

RSpec.describe Aidp::PromptOptimization::OptimizerStats do
  let(:stats) { described_class.new }

  describe "#initialize" do
    it "starts with zero runs" do
      expect(stats.runs_count).to eq(0)
    end

    it "starts with zero fragments" do
      expect(stats.total_fragments_indexed).to eq(0)
      expect(stats.total_fragments_selected).to eq(0)
    end
  end

  describe "#record_fragments_indexed" do
    it "increments total indexed" do
      expect {
        stats.record_fragments_indexed(10)
      }.to change { stats.total_fragments_indexed }.by(10)
    end
  end

  describe "#record_fragments_scored" do
    it "increments total scored" do
      expect {
        stats.record_fragments_scored(8)
      }.to change { stats.total_fragments_scored }.by(8)
    end
  end

  describe "#record_fragments_selected" do
    it "increments total selected" do
      expect {
        stats.record_fragments_selected(5)
      }.to change { stats.total_fragments_selected }.by(5)
    end

    it "increments runs count" do
      expect {
        stats.record_fragments_selected(5)
      }.to change { stats.runs_count }.by(1)
    end
  end

  describe "#record_fragments_excluded" do
    it "increments total excluded" do
      expect {
        stats.record_fragments_excluded(3)
      }.to change { stats.total_fragments_excluded }.by(3)
    end
  end

  describe "#record_tokens_used" do
    it "increments total tokens" do
      expect {
        stats.record_tokens_used(5000)
      }.to change { stats.total_tokens_used }.by(5000)
    end
  end

  describe "#record_budget_utilization" do
    it "records utilization percentage" do
      stats.record_budget_utilization(75.5)
      expect(stats.average_budget_utilization).to eq(75.5)
    end
  end

  describe "#record_optimization_time" do
    it "increments total time" do
      expect {
        stats.record_optimization_time(0.123)
      }.to change { stats.total_optimization_time }.by(0.123)
    end
  end

  describe "#average_budget_utilization" do
    it "returns 0.0 when no runs" do
      expect(stats.average_budget_utilization).to eq(0.0)
    end

    it "calculates average utilization" do
      stats.record_budget_utilization(60.0)
      stats.record_budget_utilization(80.0)
      expect(stats.average_budget_utilization).to eq(70.0)
    end
  end

  describe "#average_optimization_time" do
    it "returns 0.0 when no runs" do
      expect(stats.average_optimization_time).to eq(0.0)
    end

    it "calculates average time" do
      stats.record_fragments_selected(5) # Triggers run count
      stats.record_optimization_time(0.1)
      stats.record_fragments_selected(5)
      stats.record_optimization_time(0.2)

      expect(stats.average_optimization_time).to eq(0.15)
    end
  end

  describe "#average_fragments_selected" do
    it "returns 0.0 when no runs" do
      expect(stats.average_fragments_selected).to eq(0.0)
    end

    it "calculates average fragments" do
      stats.record_fragments_selected(10)
      stats.record_fragments_selected(20)

      expect(stats.average_fragments_selected).to eq(15.0)
    end
  end

  describe "#reset!" do
    before do
      stats.record_fragments_indexed(10)
      stats.record_fragments_selected(5)
      stats.record_tokens_used(1000)
      stats.record_optimization_time(0.5)
    end

    it "resets all counters" do
      stats.reset!

      expect(stats.runs_count).to eq(0)
      expect(stats.total_fragments_indexed).to eq(0)
      expect(stats.total_fragments_selected).to eq(0)
      expect(stats.total_tokens_used).to eq(0)
      expect(stats.total_optimization_time).to eq(0.0)
    end
  end

  describe "#summary" do
    before do
      stats.record_fragments_indexed(20)
      stats.record_fragments_scored(15)
      stats.record_fragments_selected(10)
      stats.record_fragments_excluded(5)
      stats.record_tokens_used(5000)
      stats.record_budget_utilization(62.5)
      stats.record_optimization_time(0.05)
    end

    it "returns comprehensive summary hash" do
      summary = stats.summary

      expect(summary[:runs_count]).to eq(1)
      expect(summary[:total_fragments_indexed]).to eq(20)
      expect(summary[:total_fragments_scored]).to eq(15)
      expect(summary[:total_fragments_selected]).to eq(10)
      expect(summary[:total_fragments_excluded]).to eq(5)
      expect(summary[:total_tokens_used]).to eq(5000)
      expect(summary[:average_fragments_selected]).to eq(10.0)
      expect(summary[:average_budget_utilization]).to eq(62.5)
      expect(summary[:average_optimization_time_ms]).to eq(50.0)
    end
  end

  describe "#to_s" do
    it "returns readable string representation" do
      stats.record_fragments_selected(10)
      stats.record_optimization_time(0.025)

      expect(stats.to_s).to include("OptimizerStats")
      expect(stats.to_s).to include("1 runs")
    end
  end
end
