# frozen_string_literal: true

require "spec_helper"
require "aidp/prompts/template_version_manager"
require "aidp/database"

RSpec.describe Aidp::Prompts::TemplateVersionManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:manager) { described_class.new(project_dir: temp_dir) }
  let(:template_id) { "work_loop/decide_whats_next" }
  let(:non_versionable_id) { "decision_engine/condition_detection" }

  # Create a mock template file
  before do
    Aidp::Database.connection(temp_dir)
    Aidp::Database::Migrations.run!(temp_dir)

    # Create built-in template directory
    template_dir = File.join(temp_dir, ".aidp", "prompts", "work_loop")
    FileUtils.mkdir_p(template_dir)

    File.write(File.join(template_dir, "decide_whats_next.yml"), <<~YAML)
      name: Decide What's Next
      version: "1.0.0"
      prompt: |
        # Test prompt
        {{VARIABLE}}
    YAML
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.rm_rf(temp_dir)
  end

  describe "#versionable?" do
    it "returns true for work_loop templates" do
      expect(manager.versionable?("work_loop/decide_whats_next")).to be true
    end

    it "returns false for non-versionable categories" do
      expect(manager.versionable?("decision_engine/condition_detection")).to be false
    end
  end

  describe "#initialize_versioning" do
    it "imports current template as version 1" do
      result = manager.initialize_versioning(template_id: template_id)

      expect(result[:success]).to be true
      expect(result[:version_number]).to eq(1)
    end

    it "returns already_versioned for subsequent calls" do
      manager.initialize_versioning(template_id: template_id)
      result = manager.initialize_versioning(template_id: template_id)

      expect(result[:already_versioned]).to be true
    end

    it "returns error for non-versionable templates" do
      result = manager.initialize_versioning(template_id: non_versionable_id)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Template not versionable")
    end
  end

  describe "#record_positive_feedback" do
    it "records positive vote for active version" do
      manager.initialize_versioning(template_id: template_id)

      result = manager.record_positive_feedback(template_id: template_id)

      expect(result[:success]).to be true
    end

    it "increments positive vote count" do
      manager.initialize_versioning(template_id: template_id)

      manager.record_positive_feedback(template_id: template_id)
      manager.record_positive_feedback(template_id: template_id)

      active = manager.active_version(template_id: template_id)
      expect(active[:positive_votes]).to eq(2)
    end

    it "auto-initializes versioning if needed" do
      result = manager.record_positive_feedback(template_id: template_id)

      expect(result[:success]).to be true
    end
  end

  describe "#record_negative_feedback" do
    it "records negative vote for active version" do
      manager.initialize_versioning(template_id: template_id)

      result = manager.record_negative_feedback(
        template_id: template_id,
        suggestions: ["Be more specific"]
      )

      expect(result[:success]).to be true
    end

    it "marks evolution as pending" do
      manager.initialize_versioning(template_id: template_id)

      result = manager.record_negative_feedback(
        template_id: template_id,
        suggestions: ["Be more specific"]
      )

      expect(result[:evolution_pending]).to be true
      expect(result[:suggestions]).to include("Be more specific")
    end

    it "increments negative vote count" do
      manager.initialize_versioning(template_id: template_id)

      manager.record_negative_feedback(template_id: template_id)

      active = manager.active_version(template_id: template_id)
      expect(active[:negative_votes]).to eq(1)
    end

    it "can skip evolution trigger" do
      manager.initialize_versioning(template_id: template_id)

      result = manager.record_negative_feedback(
        template_id: template_id,
        evolve_on_negative: false
      )

      expect(result[:evolution_pending]).to be_nil
    end
  end

  describe "#create_evolved_version" do
    it "creates new version from evolved content" do
      manager.initialize_versioning(template_id: template_id)
      active = manager.active_version(template_id: template_id)

      new_content = <<~YAML
        name: Evolved Template
        version: "1.0.1"
        prompt: |
          # Improved prompt
          {{VARIABLE}}
      YAML

      result = manager.create_evolved_version(
        template_id: template_id,
        new_content: new_content,
        parent_version_id: active[:id]
      )

      expect(result[:success]).to be true
      expect(result[:version_number]).to eq(2)
    end

    it "sets new version as active" do
      manager.initialize_versioning(template_id: template_id)
      active = manager.active_version(template_id: template_id)

      new_content = "evolved: true"

      manager.create_evolved_version(
        template_id: template_id,
        new_content: new_content,
        parent_version_id: active[:id]
      )

      new_active = manager.active_version(template_id: template_id)
      expect(new_active[:version_number]).to eq(2)
    end
  end

  describe "#best_version" do
    it "returns version with most positive votes" do
      manager.initialize_versioning(template_id: template_id)
      first_active = manager.active_version(template_id: template_id)

      # Give first version positive votes
      3.times { manager.record_positive_feedback(template_id: template_id) }

      # Create second version
      manager.create_evolved_version(
        template_id: template_id,
        new_content: "second: true",
        parent_version_id: first_active[:id]
      )
      manager.record_positive_feedback(template_id: template_id)

      best = manager.best_version(template_id: template_id)
      expect(best[:id]).to eq(first_active[:id])
    end
  end

  describe "#list_versions" do
    it "returns all versions for a template" do
      manager.initialize_versioning(template_id: template_id)
      active = manager.active_version(template_id: template_id)

      manager.create_evolved_version(
        template_id: template_id,
        new_content: "v2",
        parent_version_id: active[:id]
      )

      versions = manager.list_versions(template_id: template_id)

      expect(versions.size).to eq(2)
    end

    it "returns empty array for non-versionable templates" do
      versions = manager.list_versions(template_id: non_versionable_id)

      expect(versions).to eq([])
    end
  end

  describe "#version_stats" do
    it "returns statistics for a template" do
      manager.initialize_versioning(template_id: template_id)
      manager.record_positive_feedback(template_id: template_id)
      manager.record_positive_feedback(template_id: template_id)
      manager.record_negative_feedback(template_id: template_id)

      stats = manager.version_stats(template_id: template_id)

      expect(stats[:template_id]).to eq(template_id)
      expect(stats[:total_versions]).to eq(1)
      expect(stats[:total_positive_votes]).to eq(2)
      expect(stats[:total_negative_votes]).to eq(1)
    end
  end

  describe "#render_versioned" do
    it "renders template with variable substitution" do
      manager.initialize_versioning(template_id: template_id)

      result = manager.render_versioned(template_id, VARIABLE: "test value")

      expect(result).to include("test value")
    end

    it "returns nil for non-versionable templates" do
      result = manager.render_versioned(non_versionable_id, foo: "bar")

      expect(result).to be_nil
    end
  end
end
