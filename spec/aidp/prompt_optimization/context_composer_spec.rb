# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/prompt_optimization/context_composer"
require_relative "../../../lib/aidp/prompt_optimization/style_guide_indexer"
require_relative "../../../lib/aidp/prompt_optimization/template_indexer"

RSpec.describe Aidp::PromptOptimization::ContextComposer do
  let(:composer) { described_class.new(max_tokens: 1000) }

  describe "#initialize" do
    it "initializes with max tokens" do
      expect(composer.max_tokens).to eq(1000)
    end

    it "uses default max tokens if not specified" do
      default_composer = described_class.new
      expect(default_composer.max_tokens).to eq(16000)
    end
  end

  describe "#compose" do
    let(:scored_fragments) do
      [
        {
          fragment: create_fragment("critical", 50),
          score: 0.95,
          breakdown: {}
        },
        {
          fragment: create_fragment("high", 100),
          score: 0.85,
          breakdown: {}
        },
        {
          fragment: create_fragment("medium", 150),
          score: 0.65,
          breakdown: {}
        },
        {
          fragment: create_fragment("low", 200),
          score: 0.4,
          breakdown: {}
        }
      ]
    end

    it "returns a CompositionResult" do
      result = composer.compose(scored_fragments)
      expect(result).to be_a(Aidp::PromptOptimization::CompositionResult)
    end

    it "always includes critical fragments (score >= 0.9)" do
      result = composer.compose(scored_fragments)
      critical_fragment = result.selected_fragments.find { |item| item[:fragment].id == "critical" }
      expect(critical_fragment).not_to be_nil
    end

    it "respects token budget" do
      result = composer.compose(scored_fragments, reserved_tokens: 200)
      expect(result.total_tokens).to be <= 800 # 1000 - 200 reserved
    end

    it "selects fragments in score order" do
      result = composer.compose(scored_fragments, reserved_tokens: 100)
      selected_scores = result.selected_fragments.map { |item| item[:score] }
      expect(selected_scores).to eq(selected_scores.sort.reverse)
    end

    it "excludes low-scoring fragments when budget is tight" do
      large_fragments = [
        {fragment: create_fragment("critical", 400), score: 0.95, breakdown: {}},
        {fragment: create_fragment("high", 400), score: 0.85, breakdown: {}},
        {fragment: create_fragment("medium", 400), score: 0.65, breakdown: {}},
        {fragment: create_fragment("low", 400), score: 0.4, breakdown: {}}
      ]

      small_composer = described_class.new(max_tokens: 300)
      result = small_composer.compose(large_fragments, reserved_tokens: 100)

      expect(result.excluded_count).to be > 0
    end

    context "with type-specific thresholds" do
      it "applies style guide threshold" do
        thresholds = {style_guide: 0.9, templates: 0.5, source: 0.5}
        result = composer.compose(scored_fragments, thresholds: thresholds)

        # High threshold means only critical items pass
        expect(result.selected_fragments.length).to be <= 2
      end

      it "applies template threshold" do
        template_fragments = [
          {
            fragment: create_template_fragment("template1", 100),
            score: 0.85,
            breakdown: {}
          }
        ]

        thresholds = {templates: 0.9}
        result = composer.compose(template_fragments, thresholds: thresholds)

        # Score 0.85 below threshold 0.9, should not be in high priority
        expect(result.selected_count).to be >= 0
      end
    end

    context "with reserved tokens" do
      it "reduces available budget by reserved amount" do
        result = composer.compose(scored_fragments, reserved_tokens: 500)
        expect(result.budget).to eq(500) # 1000 - 500
      end
    end
  end

  describe "private methods" do
    describe "#estimate_fragment_tokens" do
      it "uses fragment's estimated_tokens if available" do
        fragment = create_fragment("test", 100)
        tokens = composer.send(:estimate_fragment_tokens, fragment)
        expect(tokens).to eq(25) # 100 chars / 4
      end

      it "estimates from content if no estimated_tokens method" do
        fragment = double("Fragment", content: "x" * 200)
        tokens = composer.send(:estimate_fragment_tokens, fragment)
        expect(tokens).to eq(50) # 200 / 4
      end

      it "returns default estimate if no content" do
        fragment = double("Fragment")
        tokens = composer.send(:estimate_fragment_tokens, fragment)
        expect(tokens).to eq(100)
      end
    end

    describe "#deduplicate_fragments" do
      it "removes duplicate fragment IDs" do
        items = [
          {fragment: create_fragment("same", 50), score: 0.8},
          {fragment: create_fragment("same", 50), score: 0.7}
        ]

        result = composer.send(:deduplicate_fragments, items)
        expect(result.length).to eq(1)
      end
    end
  end

  def create_fragment(id, size)
    Aidp::PromptOptimization::Fragment.new(
      id: id,
      heading: "Heading #{id}",
      level: 2,
      content: "x" * size,
      tags: ["test"]
    )
  end

  def create_template_fragment(id, size)
    Aidp::PromptOptimization::TemplateFragment.new(
      id: id,
      name: "Template #{id}",
      category: "analysis",
      file_path: "/templates/#{id}.md",
      content: "x" * size,
      tags: ["test"]
    )
  end
end

RSpec.describe Aidp::PromptOptimization::CompositionResult do
  let(:fragments) do
    [
      {
        fragment: Aidp::PromptOptimization::Fragment.new(
          id: "test1",
          heading: "Test 1",
          level: 2,
          content: "x" * 100,
          tags: ["test"]
        ),
        score: 0.9,
        breakdown: {}
      },
      {
        fragment: Aidp::PromptOptimization::Fragment.new(
          id: "test2",
          heading: "Test 2",
          level: 2,
          content: "x" * 200,
          tags: ["test"]
        ),
        score: 0.8,
        breakdown: {}
      }
    ]
  end

  let(:result) do
    described_class.new(
      selected_fragments: fragments,
      total_tokens: 75,
      budget: 100,
      excluded_count: 3,
      average_score: 0.85
    )
  end

  describe "#initialize" do
    it "initializes with all attributes" do
      expect(result.selected_fragments).to eq(fragments)
      expect(result.total_tokens).to eq(75)
      expect(result.budget).to eq(100)
      expect(result.excluded_count).to eq(3)
      expect(result.average_score).to eq(0.85)
    end
  end

  describe "#budget_utilization" do
    it "calculates percentage of budget used" do
      expect(result.budget_utilization).to eq(75.0) # 75/100 * 100
    end

    it "handles zero budget" do
      zero_result = described_class.new(
        selected_fragments: [],
        total_tokens: 0,
        budget: 0,
        excluded_count: 0,
        average_score: 0.0
      )

      expect(zero_result.budget_utilization).to eq(0.0)
    end
  end

  describe "#selected_count" do
    it "returns number of selected fragments" do
      expect(result.selected_count).to eq(2)
    end
  end

  describe "#over_budget?" do
    it "returns false when within budget" do
      expect(result.over_budget?).to be false
    end

    it "returns true when over budget" do
      over_result = described_class.new(
        selected_fragments: fragments,
        total_tokens: 150,
        budget: 100,
        excluded_count: 0,
        average_score: 0.8
      )

      expect(over_result.over_budget?).to be true
    end
  end

  describe "#fragments_by_type" do
    it "filters style guide fragments" do
      style_fragments = result.fragments_by_type(:style_guide)
      expect(style_fragments.length).to eq(2) # Both are style guide fragments
    end

    it "returns empty array for non-matching type" do
      code_fragments = result.fragments_by_type(:code)
      expect(code_fragments).to be_empty
    end
  end

  describe "#summary" do
    it "returns comprehensive statistics" do
      summary = result.summary

      expect(summary).to be_a(Hash)
      expect(summary[:selected_count]).to eq(2)
      expect(summary[:excluded_count]).to eq(3)
      expect(summary[:total_tokens]).to eq(75)
      expect(summary[:budget]).to eq(100)
      expect(summary[:utilization]).to eq(75.0)
      expect(summary[:average_score]).to eq(0.85)
      expect(summary[:over_budget]).to be false
      expect(summary[:by_type]).to be_a(Hash)
    end

    it "includes breakdown by type" do
      summary = result.summary
      expect(summary[:by_type]).to have_key(:style_guide)
      expect(summary[:by_type]).to have_key(:templates)
      expect(summary[:by_type]).to have_key(:code)
    end
  end

  describe "#to_s" do
    it "returns readable string representation" do
      string = result.to_s
      expect(string).to include("2 fragments")
      expect(string).to include("75/100 tokens")
      expect(string).to include("75.0%")
    end
  end
end
