# frozen_string_literal: true

require "spec_helper"
require "aidp/database/repositories/template_version_repository"
require "aidp/database"

RSpec.describe Aidp::Database::Repositories::TemplateVersionRepository do
  let(:temp_dir) { Dir.mktmpdir }
  let(:repository) { described_class.new(project_dir: temp_dir) }
  let(:template_id) { "work_loop/decide_whats_next" }
  let(:template_content) do
    <<~YAML
      name: Test Template
      version: "1.0.0"
      prompt: |
        Test prompt with {{VARIABLE}}
    YAML
  end

  before do
    Aidp::Database.connection(temp_dir)
    Aidp::Database::Migrations.run!(temp_dir)
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.rm_rf(temp_dir)
  end

  describe "#create" do
    it "creates a new version" do
      result = repository.create(
        template_id: template_id,
        content: template_content
      )

      expect(result[:success]).to be true
      expect(result[:id]).to be_a(Integer)
      expect(result[:version_number]).to eq(1)
    end

    it "increments version number for subsequent versions" do
      repository.create(template_id: template_id, content: template_content)
      result = repository.create(template_id: template_id, content: "updated content")

      expect(result[:version_number]).to eq(2)
    end

    it "deactivates previous versions when creating new one" do
      first_result = repository.create(template_id: template_id, content: template_content)
      repository.create(template_id: template_id, content: "updated content")

      first_version = repository.find(id: first_result[:id])
      expect(first_version[:is_active]).to be false
    end

    it "sets the new version as active" do
      result = repository.create(template_id: template_id, content: template_content)
      version = repository.find(id: result[:id])

      expect(version[:is_active]).to be true
    end

    it "stores parent_version_id for evolved versions" do
      first_result = repository.create(template_id: template_id, content: template_content)
      second_result = repository.create(
        template_id: template_id,
        content: "evolved content",
        parent_version_id: first_result[:id]
      )

      second_version = repository.find(id: second_result[:id])
      expect(second_version[:parent_version_id]).to eq(first_result[:id])
    end

    it "stores metadata" do
      result = repository.create(
        template_id: template_id,
        content: template_content,
        metadata: {source: "test", suggestions: ["improve clarity"]}
      )

      version = repository.find(id: result[:id])
      expect(version[:metadata][:source]).to eq("test")
      expect(version[:metadata][:suggestions]).to include("improve clarity")
    end
  end

  describe "#active_version" do
    it "returns the active version" do
      repository.create(template_id: template_id, content: template_content)

      active = repository.active_version(template_id: template_id)

      expect(active).not_to be_nil
      expect(active[:is_active]).to be true
      expect(active[:template_id]).to eq(template_id)
    end

    it "returns nil when no versions exist" do
      active = repository.active_version(template_id: "nonexistent")

      expect(active).to be_nil
    end
  end

  describe "#find" do
    it "returns a version by ID" do
      result = repository.create(template_id: template_id, content: template_content)
      version = repository.find(id: result[:id])

      expect(version[:id]).to eq(result[:id])
      expect(version[:template_id]).to eq(template_id)
      expect(version[:content]).to eq(template_content)
    end

    it "returns nil for nonexistent ID" do
      version = repository.find(id: 99999)

      expect(version).to be_nil
    end
  end

  describe "#list" do
    before do
      3.times { |i| repository.create(template_id: template_id, content: "content #{i}") }
    end

    it "returns all versions for a template" do
      versions = repository.list(template_id: template_id)

      expect(versions.size).to eq(3)
    end

    it "returns versions sorted by version_number descending" do
      versions = repository.list(template_id: template_id)

      expect(versions.first[:version_number]).to eq(3)
      expect(versions.last[:version_number]).to eq(1)
    end

    it "respects limit parameter" do
      versions = repository.list(template_id: template_id, limit: 2)

      expect(versions.size).to eq(2)
    end
  end

  describe "#record_positive_vote" do
    it "increments positive votes" do
      result = repository.create(template_id: template_id, content: template_content)

      repository.record_positive_vote(id: result[:id])
      repository.record_positive_vote(id: result[:id])

      version = repository.find(id: result[:id])
      expect(version[:positive_votes]).to eq(2)
    end
  end

  describe "#record_negative_vote" do
    it "increments negative votes" do
      result = repository.create(template_id: template_id, content: template_content)

      repository.record_negative_vote(id: result[:id])

      version = repository.find(id: result[:id])
      expect(version[:negative_votes]).to eq(1)
    end
  end

  describe "#activate" do
    it "activates a specific version" do
      first = repository.create(template_id: template_id, content: "first")
      repository.create(template_id: template_id, content: "second")

      result = repository.activate(id: first[:id])

      expect(result[:success]).to be true
      expect(repository.find(id: first[:id])[:is_active]).to be true
    end

    it "deactivates other versions" do
      first = repository.create(template_id: template_id, content: "first")
      second = repository.create(template_id: template_id, content: "second")

      repository.activate(id: first[:id])

      expect(repository.find(id: second[:id])[:is_active]).to be false
    end

    it "returns error for nonexistent version" do
      result = repository.activate(id: 99999)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Version not found")
    end
  end

  describe "#best_version" do
    it "returns version with highest positive votes" do
      first = repository.create(template_id: template_id, content: "first")
      second = repository.create(template_id: template_id, content: "second")

      # Give first version more positive votes
      3.times { repository.record_positive_vote(id: first[:id]) }
      repository.record_positive_vote(id: second[:id])

      best = repository.best_version(template_id: template_id)

      expect(best[:id]).to eq(first[:id])
    end

    it "uses version_number as tiebreaker" do
      repository.create(template_id: template_id, content: "first")
      second = repository.create(template_id: template_id, content: "second")

      best = repository.best_version(template_id: template_id)

      expect(best[:id]).to eq(second[:id])
    end
  end

  describe "#versions_needing_evolution" do
    it "returns versions with negative votes" do
      first = repository.create(template_id: template_id, content: "first")
      repository.create(template_id: "work_loop/other", content: "other")

      repository.record_negative_vote(id: first[:id])

      needing = repository.versions_needing_evolution

      expect(needing.size).to eq(1)
      expect(needing.first[:id]).to eq(first[:id])
    end

    it "filters by template_id" do
      first = repository.create(template_id: template_id, content: "first")
      other = repository.create(template_id: "work_loop/other", content: "other")

      repository.record_negative_vote(id: first[:id])
      repository.record_negative_vote(id: other[:id])

      needing = repository.versions_needing_evolution(template_id: template_id)

      expect(needing.size).to eq(1)
      expect(needing.first[:template_id]).to eq(template_id)
    end
  end

  describe "#prune_old_versions" do
    it "keeps at least MIN_VERSIONS" do
      7.times { repository.create(template_id: template_id, content: "content") }

      result = repository.prune_old_versions(template_id: template_id)

      expect(result[:success]).to be true
      expect(repository.count(template_id: template_id)).to eq(5)
    end

    it "keeps positive-feedback versions" do
      7.times do |i|
        res = repository.create(template_id: template_id, content: "content #{i}")
        repository.record_positive_vote(id: res[:id]) if i < 2
      end

      repository.prune_old_versions(template_id: template_id)

      versions = repository.list(template_id: template_id)
      positive_count = versions.count { |v| v[:positive_votes].positive? }
      expect(positive_count).to be >= 2
    end

    it "never prunes the active version" do
      7.times { repository.create(template_id: template_id, content: "content") }
      active = repository.active_version(template_id: template_id)

      repository.prune_old_versions(template_id: template_id)

      expect(repository.find(id: active[:id])).not_to be_nil
    end
  end

  describe "#count" do
    it "returns version count for a template" do
      3.times { repository.create(template_id: template_id, content: "content") }

      expect(repository.count(template_id: template_id)).to eq(3)
    end
  end

  describe "#any?" do
    it "returns false when no versions exist" do
      expect(repository.any?(template_id: template_id)).to be false
    end

    it "returns true when versions exist" do
      repository.create(template_id: template_id, content: template_content)

      expect(repository.any?(template_id: template_id)).to be true
    end
  end

  describe "#template_ids" do
    it "returns all unique template IDs" do
      repository.create(template_id: "work_loop/first", content: "content")
      repository.create(template_id: "work_loop/second", content: "content")
      repository.create(template_id: "work_loop/first", content: "more content")

      ids = repository.template_ids

      expect(ids).to contain_exactly("work_loop/first", "work_loop/second")
    end
  end
end
