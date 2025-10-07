# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/test_prompt"

RSpec.describe Aidp::Workflows::Selector do
  describe "#initialize" do
    it "initializes successfully" do
      selector = described_class.new
      expect(selector).to be_a(described_class)
    end
  end

  describe "#select_workflow" do
    let(:test_prompt) { TestPrompt.new(responses: responses) }
    let(:selector) { described_class.new(prompt: test_prompt) }

    context "for analyze mode with quick_overview" do
      let(:responses) { {select: :quick_overview} }

      it "returns workflow with steps" do
        result = selector.select_workflow(:analyze)

        expect(result).to be_a(Hash)
        expect(result[:workflow_key]).to eq(:quick_overview)
        expect(result[:steps]).to be_an(Array)
        expect(result[:steps]).to include("01_REPOSITORY_ANALYSIS")
      end
    end

    context "for execute mode with exploration" do
      let(:responses) { {select: :exploration} }

      it "returns exploration workflow" do
        result = selector.select_workflow(:execute)

        expect(result[:workflow_key]).to eq(:exploration)
        expect(result[:steps]).to include("00_PRD", "16_IMPLEMENTATION")
      end
    end

    context "for hybrid mode with legacy_modernization" do
      let(:responses) { {select: :legacy_modernization} }

      it "returns hybrid workflow with mixed steps" do
        result = selector.select_workflow(:hybrid)

        expect(result[:workflow_key]).to eq(:legacy_modernization)
        expect(result[:steps]).to include("01_REPOSITORY_ANALYSIS") # analyze
        expect(result[:steps]).to include("00_PRD") # execute
      end
    end

    context "when custom workflow is selected" do
      let(:responses) do
        {
          select: :custom,
          multi_select: ["01_REPOSITORY_ANALYSIS", "03_TEST_ANALYSIS"]
        }
      end

      it "uses custom selected steps" do
        result = selector.select_workflow(:analyze)

        expect(result[:workflow_key]).to eq(:custom)
        expect(result[:steps]).to eq(["01_REPOSITORY_ANALYSIS", "03_TEST_ANALYSIS"])
      end
    end

    context "when no custom steps selected" do
      let(:responses) do
        {
          select: :custom,
          multi_select: []
        }
      end

      it "returns default steps for analyze mode" do
        result = selector.select_workflow(:analyze)

        expect(result[:steps]).to eq(["01_REPOSITORY_ANALYSIS"])
      end
    end
  end

  describe "#select_custom_steps" do
    let(:test_prompt) { TestPrompt.new(responses: responses) }
    let(:selector) { described_class.new(prompt: test_prompt) }

    context "for analyze mode" do
      let(:responses) { {multi_select: ["01_REPOSITORY_ANALYSIS", "06_STATIC_ANALYSIS"]} }

      it "returns selected steps" do
        steps = selector.select_custom_steps(:analyze)

        expect(steps).to include("01_REPOSITORY_ANALYSIS")
        expect(steps).to include("06_STATIC_ANALYSIS")
      end
    end

    context "for execute mode" do
      let(:responses) { {multi_select: ["00_PRD", "16_IMPLEMENTATION"]} }

      it "returns selected execute steps" do
        steps = selector.select_custom_steps(:execute)

        expect(steps).to include("00_PRD")
        expect(steps).to include("16_IMPLEMENTATION")
      end
    end

    context "for hybrid mode" do
      let(:responses) do
        {
          multi_select: ["01_REPOSITORY_ANALYSIS", "00_PRD", "16_IMPLEMENTATION"]
        }
      end

      it "allows mixing analyze and execute steps" do
        steps = selector.select_custom_steps(:hybrid)

        expect(steps).to include("01_REPOSITORY_ANALYSIS") # analyze
        expect(steps).to include("00_PRD") # execute
        expect(steps).to include("16_IMPLEMENTATION") # execute
      end
    end
  end
end
