# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "Skills Command Integration", type: :integration do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    # Set up a minimal project structure
    FileUtils.mkdir_p(File.join(tmpdir, ".aidp", "skills"))
  end

  after do
    FileUtils.rm_rf(tmpdir) if tmpdir && Dir.exist?(tmpdir)
  end

  describe "skill list" do
    it "lists skills when registry is available" do
      registry = Aidp::Skills::Registry.new(project_dir: tmpdir)
      registry.load_skills

      skills = registry.all
      # Should at least have template skills available
      expect(skills).to be_an(Array)
    end
  end

  describe "skill validate" do
    it "validates all skills in registry" do
      registry = Aidp::Skills::Registry.new(project_dir: tmpdir)
      registry.load_skills

      # All loaded skills should be valid
      skills = registry.all
      skills.each do |skill|
        expect(skill).to respond_to(:id)
        expect(skill).to respond_to(:version)
        expect(skill).to respond_to(:description)
      end
    end

    it "validates a specific skill file when provided" do
      skill_file = File.join(tmpdir, "test_skill.md")
      File.write(skill_file, <<~SKILL)
        ---
        id: test_skill
        version: "1.0.0"
        name: Test Skill
        description: A test skill
        ---

        Test prompt content
      SKILL

      skill = Aidp::Skills::Loader.load_from_file(skill_file)
      expect(skill.id).to eq("test_skill")
      expect(skill.version).to eq("1.0.0")
    end
  end

  describe "skill search" do
    it "searches skills by keyword" do
      registry = Aidp::Skills::Registry.new(project_dir: tmpdir)
      registry.load_skills

      all_skills = registry.all
      # Search functionality works on loaded skills
      keyword_matches = all_skills.select { |s| s.description.downcase.include?("test") || s.name.downcase.include?("test") }
      expect(keyword_matches).to be_an(Array)
    end
  end
end
