# frozen_string_literal: true

require "spec_helper"
require "aidp/prompts/template_evolver"
require "aidp/database"

RSpec.describe Aidp::Prompts::TemplateEvolver do
  let(:temp_dir) { Dir.mktmpdir }
  let(:template_id) { "work_loop/decide_whats_next" }

  # Create a mock config that supports AIDecisionEngine
  let(:mock_config) do
    instance_double("Aidp::Configuration", default_provider: nil)
  end

  # Create a mock AI decision engine
  let(:mock_ai_engine) do
    instance_double("Aidp::Harness::AIDecisionEngine")
  end

  # Create a mock version manager
  let(:mock_version_manager) do
    instance_double("Aidp::Prompts::TemplateVersionManager")
  end

  let(:evolver) do
    described_class.new(
      mock_config,
      version_manager: mock_version_manager,
      ai_decision_engine: mock_ai_engine,
      project_dir: temp_dir
    )
  end

  let(:active_version) do
    {
      id: 1,
      template_id: template_id,
      version_number: 1,
      content: <<~YAML,
        name: Test Template
        version: "1.0.0"
        description: Original template
        prompt: |
          # Original prompt
          {{VARIABLE}}
        variables:
          - VARIABLE
      YAML
      positive_votes: 5,
      negative_votes: 2
    }
  end

  before do
    Aidp::Database.connection(temp_dir)
    Aidp::Database::Migrations.run!(temp_dir)
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.rm_rf(temp_dir)
  end

  describe "#evolve" do
    context "when AI engine is available" do
      before do
        allow(mock_version_manager).to receive(:active_version)
          .with(template_id: template_id)
          .and_return(active_version)

        allow(mock_ai_engine).to receive(:decide)
          .with(:template_evolution, anything)
          .and_return({
            improved_prompt: "# Improved prompt\nMore specific {{VARIABLE}}",
            changes: ["Made prompt more specific", "Added clearer guidance"],
            reasoning: "Addressed user feedback"
          })

        allow(mock_version_manager).to receive(:create_evolved_version)
          .and_return({success: true, id: 2, version_number: 2})
      end

      it "generates improved template" do
        result = evolver.evolve(
          template_id: template_id,
          suggestions: ["Be more specific"]
        )

        expect(result[:success]).to be true
        expect(result[:new_version_id]).to eq(2)
      end

      it "passes suggestions to AI" do
        expect(mock_ai_engine).to receive(:decide) do |decision_type, options|
          expect(decision_type).to eq(:template_evolution)
          expect(options[:context][:prompt]).to include("Be more specific")
        end.and_return({
          improved_prompt: "improved",
          changes: []
        })

        allow(mock_version_manager).to receive(:create_evolved_version)
          .and_return({success: true, id: 2, version_number: 2})

        evolver.evolve(
          template_id: template_id,
          suggestions: ["Be more specific"]
        )
      end

      it "creates evolved version with parent reference" do
        expect(mock_version_manager).to receive(:create_evolved_version)
          .with(hash_including(
            template_id: template_id,
            parent_version_id: active_version[:id]
          ))
          .and_return({success: true, id: 2, version_number: 2})

        evolver.evolve(template_id: template_id)
      end

      it "includes changes in result" do
        result = evolver.evolve(template_id: template_id)

        expect(result[:changes]).to include("Made prompt more specific")
      end
    end

    context "when no active version exists" do
      before do
        allow(mock_version_manager).to receive(:active_version)
          .and_return(nil)
      end

      it "returns error" do
        result = evolver.evolve(template_id: template_id)

        expect(result[:success]).to be false
        expect(result[:error]).to eq("No active version to evolve")
      end
    end

    context "when AI engine is unavailable" do
      let(:evolver_without_ai) do
        described_class.new(
          mock_config,
          version_manager: mock_version_manager,
          ai_decision_engine: nil,
          project_dir: temp_dir
        )
      end

      before do
        allow(mock_version_manager).to receive(:active_version)
          .and_return(active_version)
      end

      it "returns error" do
        result = evolver_without_ai.evolve(template_id: template_id)

        expect(result[:success]).to be false
        expect(result[:error]).to eq("AI decision engine not available")
      end
    end

    context "when AI call fails" do
      before do
        allow(mock_version_manager).to receive(:active_version)
          .and_return(active_version)

        allow(mock_ai_engine).to receive(:decide)
          .and_raise(StandardError.new("API error"))
      end

      it "returns error" do
        result = evolver.evolve(template_id: template_id)

        expect(result[:success]).to be false
        expect(result[:error]).to include("AI evolution failed")
      end
    end
  end

  describe "#evolve_all_pending" do
    let(:pending_versions) do
      [
        {
          template_id: "work_loop/decide_whats_next",
          id: 1,
          negative_votes: 2,
          metadata: {suggestions: ["Improve clarity"]}
        },
        {
          template_id: "work_loop/diagnose_failures",
          id: 2,
          negative_votes: 1,
          metadata: {suggestions: ["Add more context"]}
        }
      ]
    end

    before do
      allow(mock_version_manager).to receive(:versions_needing_evolution)
        .and_return(pending_versions)

      allow(mock_version_manager).to receive(:active_version)
        .and_return(active_version)

      allow(mock_ai_engine).to receive(:decide)
        .and_return({
          improved_prompt: "improved",
          changes: ["improvement"]
        })

      allow(mock_version_manager).to receive(:create_evolved_version)
        .and_return({success: true, id: 3, version_number: 2})
    end

    it "evolves all pending versions" do
      results = evolver.evolve_all_pending

      expect(results.size).to eq(2)
    end

    it "includes template_id in results" do
      results = evolver.evolve_all_pending

      template_ids = results.map { |r| r[:template_id] }
      expect(template_ids).to include("work_loop/decide_whats_next")
      expect(template_ids).to include("work_loop/diagnose_failures")
    end
  end
end
