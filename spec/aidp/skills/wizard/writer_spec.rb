# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../../lib/aidp/skills/wizard/writer"
require_relative "../../../../lib/aidp/skills/skill"

RSpec.describe Aidp::Skills::Wizard::Writer do
  let(:project_dir) { Dir.mktmpdir }
  let(:writer) { described_class.new(project_dir: project_dir) }
  let(:skill) do
    Aidp::Skills::Skill.new(
      id: "test_skill",
      name: "Test Skill",
      description: "A test skill",
      version: "1.0.0",
      content: "You are a test skill.",
      source_path: "<pending>"
    )
  end
  let(:skill_content) do
    <<~SKILL
      ---
      id: test_skill
      name: Test Skill
      description: A test skill
      version: 1.0.0
      ---
      You are a test skill.
    SKILL
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#write" do
    it "writes skill to .aidp/skills directory" do
      path = writer.write(skill, content: skill_content)

      expect(File.exist?(path)).to be true
      expect(File.read(path)).to eq(skill_content)
    end

    it "creates parent directories if they don't exist" do
      path = writer.write(skill, content: skill_content)
      skill_dir = File.dirname(path)

      expect(Dir.exist?(skill_dir)).to be true
    end

    it "returns the path to the written file" do
      path = writer.write(skill, content: skill_content)

      expect(path).to eq(File.join(project_dir, ".aidp", "skills", "test_skill", "SKILL.md"))
    end

    context "when dry_run is true" do
      it "does not write the file" do
        path = writer.write(skill, content: skill_content, dry_run: true)

        expect(File.exist?(path)).to be false
      end

      it "still returns the path" do
        path = writer.write(skill, content: skill_content, dry_run: true)

        expect(path).to eq(File.join(project_dir, ".aidp", "skills", "test_skill", "SKILL.md"))
      end
    end

    context "when skill file already exists" do
      before do
        # Write initial skill
        writer.write(skill, content: skill_content)
      end

      it "overwrites the existing file" do
        new_content = skill_content.gsub("test skill", "updated skill")
        path = writer.write(skill, content: new_content)

        expect(File.read(path)).to eq(new_content)
      end

      context "with backup enabled" do
        it "creates a backup file" do
          new_content = skill_content.gsub("test skill", "updated skill")
          path = writer.write(skill, content: new_content, backup: true)

          backup_path = "#{path}.backup"
          expect(File.exist?(backup_path)).to be true
        end

        it "creates a timestamped backup file" do
          new_content = skill_content.gsub("test skill", "updated skill")
          skill_dir = File.dirname(writer.path_for_skill(skill.id))

          writer.write(skill, content: new_content, backup: true)

          backup_files = Dir.glob(File.join(skill_dir, "*.backup"))
          timestamped_backups = backup_files.select { |f| f.match?(/\d{8}_\d{6}\.backup$/) }

          expect(timestamped_backups).not_to be_empty
        end

        it "preserves original content in backup" do
          new_content = skill_content.gsub("test skill", "updated skill")
          path = writer.write(skill, content: new_content, backup: true)

          backup_path = "#{path}.backup"
          expect(File.read(backup_path)).to eq(skill_content)
        end
      end

      context "with backup disabled" do
        it "does not create backup file" do
          new_content = skill_content.gsub("test skill", "updated skill")
          path = writer.write(skill, content: new_content, backup: false)

          backup_path = "#{path}.backup"
          expect(File.exist?(backup_path)).to be false
        end
      end
    end
  end

  describe "#path_for_skill" do
    it "returns the correct path for a skill ID" do
      path = writer.path_for_skill("my_skill")

      expect(path).to eq(File.join(project_dir, ".aidp", "skills", "my_skill", "SKILL.md"))
    end

    it "constructs path in .aidp/skills directory" do
      path = writer.path_for_skill("another_skill")

      expect(path).to include(".aidp/skills/another_skill")
    end
  end

  describe "#exists?" do
    context "when skill file exists" do
      before do
        writer.write(skill, content: skill_content)
      end

      it "returns true" do
        expect(writer.exists?("test_skill")).to be true
      end
    end

    context "when skill file does not exist" do
      it "returns false" do
        expect(writer.exists?("nonexistent_skill")).to be false
      end
    end
  end
end
