# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/prompt_optimization/relevance_scorer"
require_relative "../../../lib/aidp/prompt_optimization/style_guide_indexer"
require_relative "../../../lib/aidp/prompt_optimization/template_indexer"
require_relative "../../../lib/aidp/prompt_optimization/source_code_fragmenter"

RSpec.describe Aidp::PromptOptimization::RelevanceScorer do
  let(:scorer) { described_class.new }

  describe "#initialize" do
    it "initializes with default weights" do
      expect(scorer).to be_a(described_class)
    end

    it "accepts custom weights" do
      custom_scorer = described_class.new(weights: {task_type_match: 0.5})
      expect(custom_scorer).to be_a(described_class)
    end
  end

  describe "#score_fragment" do
    let(:context) do
      Aidp::PromptOptimization::TaskContext.new(
        task_type: :feature,
        affected_files: ["lib/user.rb"],
        step_name: "implementation",
        tags: ["testing", "api"]
      )
    end

    context "with style guide fragment" do
      let(:fragment) do
        Aidp::PromptOptimization::Fragment.new(
          id: "testing-guidelines",
          heading: "Testing Guidelines",
          level: 2,
          content: "Test everything",
          tags: ["testing", "implementation"]
        )
      end

      it "returns a score between 0 and 1" do
        score = scorer.score_fragment(fragment, context)
        expect(score).to be_between(0.0, 1.0)
      end

      it "scores relevant fragments higher" do
        score = scorer.score_fragment(fragment, context)
        expect(score).to be > 0.5
      end
    end

    context "with template fragment" do
      let(:fragment) do
        Aidp::PromptOptimization::TemplateFragment.new(
          id: "analysis/test",
          name: "Test Template",
          category: "analysis",
          file_path: "/templates/analysis/test.md",
          content: "Template content",
          tags: ["testing", "analysis"]
        )
      end

      it "returns a score between 0 and 1" do
        score = scorer.score_fragment(fragment, context)
        expect(score).to be_between(0.0, 1.0)
      end
    end

    context "with code fragment" do
      let(:fragment) do
        Aidp::PromptOptimization::CodeFragment.new(
          id: "lib/user.rb:User",
          file_path: "/project/lib/user.rb",
          type: :class,
          name: "User",
          content: "class User; end",
          line_start: 1,
          line_end: 1
        )
      end

      it "returns a score between 0 and 1" do
        score = scorer.score_fragment(fragment, context)
        expect(score).to be_between(0.0, 1.0)
      end

      it "scores affected file fragments very high" do
        score = scorer.score_fragment(fragment, context)
        expect(score).to be > 0.4 # Should get location match bonus
      end
    end

    context "with irrelevant fragment" do
      let(:fragment) do
        Aidp::PromptOptimization::Fragment.new(
          id: "ui-guidelines",
          heading: "UI Guidelines",
          level: 2,
          content: "UI rules",
          tags: ["ui", "tty"]
        )
      end

      it "scores lower than relevant fragments" do
        score = scorer.score_fragment(fragment, context)
        expect(score).to be < 0.5
      end
    end
  end

  describe "#score_fragments" do
    let(:context) do
      Aidp::PromptOptimization::TaskContext.new(
        task_type: :testing,
        tags: ["testing"]
      )
    end

    let(:fragments) do
      [
        Aidp::PromptOptimization::Fragment.new(
          id: "testing",
          heading: "Testing",
          level: 2,
          content: "Test guidelines",
          tags: ["testing"]
        ),
        Aidp::PromptOptimization::Fragment.new(
          id: "ui",
          heading: "UI",
          level: 2,
          content: "UI guidelines",
          tags: ["ui"]
        )
      ]
    end

    it "scores all fragments" do
      results = scorer.score_fragments(fragments, context)
      expect(results.length).to eq(2)
    end

    it "returns sorted results (highest score first)" do
      results = scorer.score_fragments(fragments, context)
      expect(results.first[:score]).to be >= results.last[:score]
    end

    it "includes fragment in result" do
      results = scorer.score_fragments(fragments, context)
      expect(results.first[:fragment]).to be_a(Aidp::PromptOptimization::Fragment)
    end

    it "includes score in result" do
      results = scorer.score_fragments(fragments, context)
      expect(results.first[:score]).to be_a(Float)
    end

    it "includes breakdown in result" do
      results = scorer.score_fragments(fragments, context)
      expect(results.first[:breakdown]).to be_a(Hash)
      expect(results.first[:breakdown]).to have_key(:task_type)
      expect(results.first[:breakdown]).to have_key(:tags)
    end
  end

  describe "private methods" do
    describe "#task_type_to_tags" do
      it "maps feature to relevant tags" do
        tags = scorer.send(:task_type_to_tags, :feature)
        expect(tags).to include("implementation", "testing")
      end

      it "maps bugfix to relevant tags" do
        tags = scorer.send(:task_type_to_tags, :bugfix)
        expect(tags).to include("testing", "error")
      end

      it "maps refactor to relevant tags" do
        tags = scorer.send(:task_type_to_tags, :refactor)
        expect(tags).to include("refactor", "testing")
      end

      it "returns empty array for unknown types" do
        tags = scorer.send(:task_type_to_tags, :unknown)
        expect(tags).to eq([])
      end
    end

    describe "#step_to_tags" do
      it "extracts planning tags" do
        tags = scorer.send(:step_to_tags, "00_PLANNING")
        expect(tags).to include("planning")
      end

      it "extracts implementation tags" do
        tags = scorer.send(:step_to_tags, "16_IMPLEMENTATION")
        expect(tags).to include("implementation")
      end

      it "extracts testing tags" do
        tags = scorer.send(:step_to_tags, "10_TESTING_STRATEGY")
        expect(tags).to include("testing")
      end

      it "handles lowercase step names" do
        tags = scorer.send(:step_to_tags, "analysis")
        expect(tags).to include("analysis")
      end
    end
  end
end

RSpec.describe Aidp::PromptOptimization::TaskContext do
  describe "#initialize" do
    it "initializes with all attributes" do
      context = described_class.new(
        task_type: :feature,
        description: "Add user auth",
        affected_files: ["user.rb"],
        step_name: "implementation",
        tags: ["security"]
      )

      expect(context.task_type).to eq(:feature)
      expect(context.description).to eq("Add user auth")
      expect(context.affected_files).to eq(["user.rb"])
      expect(context.step_name).to eq("implementation")
      expect(context.tags).to include("security")
    end

    it "extracts tags from description" do
      context = described_class.new(
        description: "Add API endpoint with authentication"
      )

      expect(context.tags).to include("api")
      expect(context.tags).to include("security")
    end

    it "handles nil affected_files" do
      context = described_class.new(affected_files: nil)
      expect(context.affected_files).to eq([])
    end

    it "handles nil tags" do
      context = described_class.new(tags: nil)
      expect(context.tags).to eq([])
    end
  end

  describe "#extract_tags_from_description" do
    it "extracts testing tag" do
      context = described_class.new(description: "Add test coverage")
      expect(context.tags).to include("testing")
    end

    it "extracts security tag" do
      context = described_class.new(description: "Improve authentication")
      expect(context.tags).to include("security")
    end

    it "extracts performance tag" do
      context = described_class.new(description: "Optimize query performance")
      expect(context.tags).to include("performance")
    end

    it "extracts database tag" do
      context = described_class.new(description: "Add database migration")
      expect(context.tags).to include("database")
    end

    it "extracts api tag" do
      context = described_class.new(description: "Create REST API")
      expect(context.tags).to include("api")
    end

    it "extracts ui tag" do
      context = described_class.new(description: "Update UI components")
      expect(context.tags).to include("ui")
    end

    it "deduplicates tags" do
      context = described_class.new(
        description: "test test test",
        tags: ["testing"]
      )
      expect(context.tags.count("testing")).to eq(1)
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      context = described_class.new(
        task_type: :feature,
        description: "Test",
        affected_files: ["file.rb"],
        step_name: "step",
        tags: ["tag"]
      )

      hash = context.to_h

      expect(hash).to be_a(Hash)
      expect(hash[:task_type]).to eq(:feature)
      expect(hash[:description]).to eq("Test")
      expect(hash[:affected_files]).to eq(["file.rb"])
      expect(hash[:step_name]).to eq("step")
      expect(hash[:tags]).to include("tag")
    end
  end
end
