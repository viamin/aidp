# frozen_string_literal: true

require "spec_helper"
require "aidp/planning/mappers/persona_mapper"

RSpec.describe Aidp::Planning::Mappers::PersonaMapper, "agile mode" do
  let(:ai_decision_engine) { double("AIDecisionEngine") }
  let(:config) { {} }

  describe "agile mode personas" do
    subject(:mapper) do
      described_class.new(
        ai_decision_engine: ai_decision_engine,
        config: config,
        mode: :agile
      )
    end

    it "uses agile personas when mode is :agile" do
      task_list = [
        {id: "1", name: "Define MVP scope", description: "Scope MVP features", phase: "Planning"}
      ]

      allow(ai_decision_engine).to receive(:decide).and_return("product_manager")

      result = mapper.assign_personas(task_list)

      expect(result[:assignments]["1"][:persona]).to eq("product_manager")
    end

    it "has agile-specific personas available" do
      agile_personas = mapper.send(:agile_personas)

      expect(agile_personas).to include("product_manager")
      expect(agile_personas).to include("ux_researcher")
      expect(agile_personas).to include("marketing_strategist")
    end

    it "includes shared personas in agile mode" do
      agile_personas = mapper.send(:agile_personas)

      expect(agile_personas).to include("architect")
      expect(agile_personas).to include("senior_developer")
      expect(agile_personas).to include("qa_engineer")
    end
  end

  describe "waterfall mode personas" do
    subject(:mapper) do
      described_class.new(
        ai_decision_engine: ai_decision_engine,
        config: config,
        mode: :waterfall
      )
    end

    it "uses waterfall personas when mode is :waterfall" do
      waterfall_personas = mapper.send(:waterfall_personas)

      expect(waterfall_personas).to include("product_strategist")
      expect(waterfall_personas).not_to include("product_manager")
      expect(waterfall_personas).not_to include("ux_researcher")
    end
  end

  describe "default mode" do
    subject(:mapper) do
      described_class.new(
        ai_decision_engine: ai_decision_engine,
        config: config
        # mode not specified, should default to waterfall
      )
    end

    it "defaults to waterfall personas when mode not specified" do
      default_personas = mapper.send(:default_personas)
      waterfall_personas = mapper.send(:waterfall_personas)

      expect(default_personas).to eq(waterfall_personas)
    end
  end
end
