# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../../lib/aidp/skills/wizard/template_library"

RSpec.describe Aidp::Skills::Wizard::TemplateLibrary do
  let(:project_dir) { Dir.mktmpdir }
  let(:library) { described_class.new(project_dir: project_dir) }

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#templates" do
    it "loads template skills from gem directory" do
      templates = library.templates

      expect(templates).to be_an(Array)
      expect(templates).not_to be_empty
      expect(templates.first).to be_a(Aidp::Skills::Skill)
    end

    it "includes built-in templates" do
      templates = library.templates
      template_ids = templates.map(&:id)

      # Check for at least one of the known templates
      expect(template_ids).to include("repository_analyst")
        .or(include("product_strategist"))
        .or(include("architecture_analyst"))
        .or(include("test_analyzer"))
    end

    it "caches templates after first load" do
      first_load = library.templates
      second_load = library.templates

      expect(first_load.object_id).to eq(second_load.object_id)
    end
  end

  describe "#project_skills" do
    context "when no project skills exist" do
      it "returns empty array" do
        project_skills = library.project_skills

        expect(project_skills).to eq([])
      end
    end

    context "when project skills exist" do
      before do
        # Create a test project skill
        skill_dir = File.join(project_dir, ".aidp", "skills", "test_skill")
        FileUtils.mkdir_p(skill_dir)

        skill_content = <<~SKILL
          ---
          id: test_skill
          name: Test Skill
          description: A test skill
          version: 1.0.0
          ---
          You are a test skill.
        SKILL

        File.write(File.join(skill_dir, "SKILL.md"), skill_content)
      end

      it "loads project skills from .aidp/skills" do
        project_skills = library.project_skills

        expect(project_skills.size).to eq(1)
        expect(project_skills.first.id).to eq("test_skill")
        expect(project_skills.first.name).to eq("Test Skill")
      end
    end
  end

  describe "#all" do
    it "returns combined templates and project skills" do
      all_skills = library.all

      expect(all_skills).to be_an(Array)
      expect(all_skills).not_to be_empty
      expect(all_skills).to eq(library.templates + library.project_skills)
    end
  end

  describe "#find" do
    context "when skill exists in templates" do
      it "returns the skill" do
        templates = library.templates
        template_id = templates.first.id

        skill = library.find(template_id)

        expect(skill).not_to be_nil
        expect(skill.id).to eq(template_id)
      end
    end

    context "when skill exists in project" do
      before do
        skill_dir = File.join(project_dir, ".aidp", "skills", "custom_skill")
        FileUtils.mkdir_p(skill_dir)

        skill_content = <<~SKILL
          ---
          id: custom_skill
          name: Custom Skill
          description: A custom skill
          version: 1.0.0
          ---
          Custom content.
        SKILL

        File.write(File.join(skill_dir, "SKILL.md"), skill_content)
      end

      it "returns the skill" do
        skill = library.find("custom_skill")

        expect(skill).not_to be_nil
        expect(skill.id).to eq("custom_skill")
        expect(skill.name).to eq("Custom Skill")
      end
    end

    context "when skill does not exist" do
      it "returns nil" do
        skill = library.find("nonexistent_skill")

        expect(skill).to be_nil
      end
    end
  end

  describe "#exists?" do
    it "returns true for existing template skill" do
      templates = library.templates
      template_id = templates.first.id

      expect(library.exists?(template_id)).to be true
    end

    it "returns false for non-existent skill" do
      expect(library.exists?("nonexistent_skill")).to be false
    end
  end

  describe "#template_list" do
    it "returns list of template metadata" do
      list = library.template_list

      expect(list).to be_an(Array)
      expect(list).not_to be_empty

      first_item = list.first
      expect(first_item).to have_key(:id)
      expect(first_item).to have_key(:name)
      expect(first_item).to have_key(:description)
      expect(first_item[:source]).to eq(:template)
    end
  end

  describe "#project_skill_list" do
    context "with project skills" do
      before do
        skill_dir = File.join(project_dir, ".aidp", "skills", "project_skill")
        FileUtils.mkdir_p(skill_dir)

        skill_content = <<~SKILL
          ---
          id: project_skill
          name: Project Skill
          description: A project skill
          version: 1.0.0
          ---
          Project content.
        SKILL

        File.write(File.join(skill_dir, "SKILL.md"), skill_content)
      end

      it "returns list of project skill metadata" do
        list = library.project_skill_list

        expect(list.size).to eq(1)

        first_item = list.first
        expect(first_item[:id]).to eq("project_skill")
        expect(first_item[:name]).to eq("Project Skill")
        expect(first_item[:source]).to eq(:project)
      end
    end

    context "without project skills" do
      it "returns empty array" do
        list = library.project_skill_list

        expect(list).to eq([])
      end
    end
  end

  describe "#skill_list" do
    it "returns combined list of all skills" do
      list = library.skill_list

      expect(list).to be_an(Array)
      expect(list).not_to be_empty

      # Should have both template and project skills
      sources = list.map { |item| item[:source] }.uniq
      expect(sources).to include(:template)
    end
  end
end
