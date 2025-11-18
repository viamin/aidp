# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/planning/mappers/persona_mapper"

RSpec.describe Aidp::Planning::Mappers::PersonaMapper do
  let(:mock_ai_engine) { double("AIDecisionEngine") }
  let(:mapper) { described_class.new(ai_decision_engine: mock_ai_engine) }
  let(:sample_tasks) do
    [
      {id: "task1", name: "Document requirements", phase: "Requirements", effort: "3 story points"},
      {id: "task2", name: "Design system architecture", phase: "Design", effort: "5 story points"},
      {id: "task3", name: "Implement features", phase: "Implementation", effort: "13 story points"},
      {id: "task4", name: "Write unit tests", phase: "Testing", effort: "8 story points"},
      {id: "task5", name: "Deploy to production", phase: "Deployment", effort: "2 story points"}
    ]
  end

  describe "#assign_personas" do
    before do
      allow(mock_ai_engine).to receive(:decide).and_return("product_strategist")
    end

    it "assigns a persona to each task" do
      result = mapper.assign_personas(sample_tasks)

      expect(result[:assignments]).to be_a(Hash)
      expect(result[:assignments].size).to eq(5)
    end

    it "uses AIDecisionEngine for each assignment" do
      mapper.assign_personas(sample_tasks)

      expect(mock_ai_engine).to have_received(:decide).exactly(5).times
    end

    it "passes task details to AI engine" do
      mapper.assign_personas(sample_tasks)

      expect(mock_ai_engine).to have_received(:decide).with(
        hash_including(
          context: "persona assignment",
          data: hash_including(:task_name, :available_personas)
        )
      )
    end

    it "returns assignments with persona and task info" do
      result = mapper.assign_personas(sample_tasks)

      assignment = result[:assignments]["task1"]
      expect(assignment).to be_a(Hash)
      expect(assignment[:persona]).to eq("product_strategist")
      expect(assignment[:task]).to eq("Document requirements")
      expect(assignment[:phase]).to eq("Requirements")
    end

    it "includes metadata" do
      result = mapper.assign_personas(sample_tasks)

      expect(result[:metadata]).to be_a(Hash)
      expect(result[:metadata][:generated_at]).to be_a(String)
      expect(result[:metadata][:total_assignments]).to eq(5)
      expect(result[:metadata][:personas_used]).to be_an(Array)
    end

    it "tracks unique personas used" do
      allow(mock_ai_engine).to receive(:decide).and_return("architect", "architect", "senior_developer", "qa_engineer", "devops_engineer")

      result = mapper.assign_personas(sample_tasks)

      expect(result[:metadata][:personas_used].size).to eq(4) # 4 unique personas
    end

    context "with custom personas" do
      let(:custom_personas) { ["custom_role1", "custom_role2"] }

      before do
        allow(mock_ai_engine).to receive(:decide).and_return("custom_role1")
      end

      it "uses provided persona list" do
        mapper.assign_personas(sample_tasks, available_personas: custom_personas)

        expect(mock_ai_engine).to have_received(:decide).with(
          hash_including(
            data: hash_including(available_personas: custom_personas)
          )
        )
      end
    end
  end

  describe "#generate_persona_map" do
    let(:assignments) do
      {
        assignments: {
          "task1" => {persona: "product_strategist", task: "Document requirements", phase: "Requirements"},
          "task2" => {persona: "architect", task: "Design system", phase: "Design"}
        },
        metadata: {
          generated_at: Time.now.iso8601,
          total_assignments: 2,
          personas_used: ["product_strategist", "architect"]
        }
      }
    end

    it "generates valid YAML" do
      yaml = mapper.generate_persona_map(assignments)

      expect(yaml).to be_a(String)
      parsed = YAML.safe_load(yaml)
      expect(parsed).to be_a(Hash)
    end

    it "includes version and timestamp" do
      yaml = mapper.generate_persona_map(assignments)
      parsed = YAML.safe_load(yaml)

      expect(parsed["version"]).to eq("1.0")
      expect(parsed["generated_at"]).to be_a(String)
    end

    it "includes all assignments" do
      yaml = mapper.generate_persona_map(assignments)
      parsed = YAML.safe_load(yaml)

      expect(parsed["assignments"]).to be_a(Hash)
      expect(parsed["assignments"].size).to eq(2)
    end

    it "formats assignments correctly" do
      yaml = mapper.generate_persona_map(assignments)
      parsed = YAML.safe_load(yaml)

      task1_assignment = parsed["assignments"]["task1"]
      expect(task1_assignment["persona"]).to eq("product_strategist")
      expect(task1_assignment["task"]).to eq("Document requirements")
      expect(task1_assignment["phase"]).to eq("Requirements")
    end
  end

  describe "Zero Framework Cognition compliance" do
    it "does not use heuristics" do
      # Verify that the PersonaMapper class doesn't contain forbidden patterns
      source_code = File.read("lib/aidp/planning/mappers/persona_mapper.rb")

      # Should NOT contain regex matching on task names
      expect(source_code).not_to match(/task\[:name\]\.match/)
      expect(source_code).not_to match(/task\[:name\]\.include\?/)

      # Should NOT contain keyword checks
      expect(source_code).not_to match(/when.*task\[:name\]/)

      # SHOULD call AIDecisionEngine
      expect(source_code).to include("@ai_decision_engine.decide")
    end

    it "requires AIDecisionEngine" do
      expect {
        described_class.new(ai_decision_engine: nil)
      }.not_to raise_error

      # Mapper can be initialized without AI engine (will fail at runtime if used)
    end

    it "uses AI for semantic decisions" do
      allow(mock_ai_engine).to receive(:decide).and_return("architect")

      mapper.assign_personas([sample_tasks.first])

      # Should pass semantic context to AI
      expect(mock_ai_engine).to have_received(:decide).with(
        hash_including(
          context: "persona assignment",
          prompt: String
        )
      )
    end
  end

  describe "default personas" do
    it "uses sensible default persona list" do
      allow(mock_ai_engine).to receive(:decide).and_return("product_strategist")

      mapper.assign_personas(sample_tasks)

      # Should have used default personas
      expect(mock_ai_engine).to have_received(:decide).with(
        hash_including(
          data: hash_including(
            available_personas: array_including(
              "product_strategist",
              "architect",
              "senior_developer",
              "qa_engineer",
              "devops_engineer"
            )
          )
        )
      )
    end
  end
end
