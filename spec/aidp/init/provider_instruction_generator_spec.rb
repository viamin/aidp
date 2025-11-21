# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Aidp::Init::ProviderInstructionGenerator do
  let(:project_dir) { Dir.mktmpdir }
  let(:generator) { described_class.new(project_dir) }
  let(:analysis) do
    {
      languages: {"Ruby" => 1000, "JavaScript" => 500},
      frameworks: [
        {name: "Rails", confidence: 0.9, evidence: ["Gemfile contains rails"]},
        {name: "React", confidence: 0.8, evidence: ["package.json contains react"]}
      ],
      test_frameworks: [],
      tooling: [],
      key_directories: ["lib", "spec"],
      config_files: [],
      repo_stats: {
        total_files: 100,
        total_directories: 20,
        docs_present: true,
        has_ci_config: true,
        has_containerization: false
      }
    }
  end
  let(:preferences) { {} }

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#generate" do
    it "generates instruction files for all providers" do
      generated_files = generator.generate(analysis: analysis, preferences: preferences)

      expect(generated_files).to include(
        "CLAUDE.md",
        ".cursorrules",
        ".github/copilot-instructions.md",
        ".gemini/instructions.md",
        ".kilocode/instructions.md",
        ".aider/instructions.md",
        ".codex/instructions.md",
        ".opencode/instructions.md"
      )
    end

    it "creates parent directories when needed" do
      generator.generate(analysis: analysis, preferences: preferences)

      expect(File.directory?(File.join(project_dir, ".github"))).to be true
      expect(File.directory?(File.join(project_dir, ".gemini"))).to be true
      expect(File.directory?(File.join(project_dir, ".kilocode"))).to be true
      expect(File.directory?(File.join(project_dir, ".aider"))).to be true
      expect(File.directory?(File.join(project_dir, ".codex"))).to be true
      expect(File.directory?(File.join(project_dir, ".opencode"))).to be true
    end

    it "creates files with proper content" do
      generator.generate(analysis: analysis, preferences: preferences)

      claude_file = File.join(project_dir, "CLAUDE.md")
      expect(File.exist?(claude_file)).to be true

      content = File.read(claude_file)
      expect(content).to include("docs/LLM_STYLE_GUIDE.md")
      expect(content).to include("Provider: Aidp::Providers::Anthropic")
      expect(content).to include("**Languages**: Ruby, JavaScript")
      expect(content).to include("**Frameworks**: Rails, React")
    end

    it "references key documentation files" do
      generator.generate(analysis: analysis, preferences: preferences)

      claude_file = File.join(project_dir, "CLAUDE.md")
      content = File.read(claude_file)

      expect(content).to include("docs/LLM_STYLE_GUIDE.md")
      expect(content).to include("docs/PROJECT_ANALYSIS.md")
      expect(content).to include("docs/CODE_QUALITY_PLAN.md")
      expect(content).to include("README.md")
    end

    it "includes generation timestamp" do
      freeze_time = Time.utc(2025, 1, 15, 10, 30, 0)
      allow(Time).to receive(:now).and_return(freeze_time)

      generator.generate(analysis: analysis, preferences: preferences)

      claude_file = File.join(project_dir, "CLAUDE.md")
      content = File.read(claude_file)

      expect(content).to include("2025-01-15T10:30:00Z")
    end

    it "handles projects with no frameworks detected" do
      analysis_no_frameworks = analysis.merge(frameworks: [])

      generator.generate(analysis: analysis_no_frameworks, preferences: preferences)

      claude_file = File.join(project_dir, "CLAUDE.md")
      content = File.read(claude_file)

      expect(content).to include("**Frameworks**: None detected")
    end

    it "uses project directory name as fallback project name" do
      custom_dir = File.join(Dir.tmpdir, "my-awesome-project")
      FileUtils.mkdir_p(custom_dir)

      begin
        custom_generator = described_class.new(custom_dir)
        custom_generator.generate(analysis: analysis, preferences: preferences)

        claude_file = File.join(custom_dir, "CLAUDE.md")
        content = File.read(claude_file)

        expect(content).to include("my-awesome-project")
      ensure
        FileUtils.rm_rf(custom_dir)
      end
    end

    it "logs file generation" do
      expect(Aidp).to receive(:log_info).at_least(:once).with(
        "provider_instruction_generator",
        "generated_file",
        hash_including(:provider, :path)
      )

      generator.generate(analysis: analysis, preferences: preferences)
    end
  end

  describe "content quality" do
    before do
      generator.generate(analysis: analysis, preferences: preferences)
    end

    it "emphasizes checking LLM_STYLE_GUIDE.md" do
      claude_file = File.join(project_dir, "CLAUDE.md")
      content = File.read(claude_file)

      # Should appear multiple times with emphasis
      expect(content.scan("LLM_STYLE_GUIDE.md").count).to be >= 3
      expect(content).to include("MUST read and follow")
    end

    it "provides structured sections" do
      claude_file = File.join(project_dir, "CLAUDE.md")
      content = File.read(claude_file)

      expect(content).to include("## 🎯 Most Important")
      expect(content).to include("## About This Project")
      expect(content).to include("## Working with This Project")
      expect(content).to include("## Quick Reference")
    end

    it "includes actionable guidance" do
      claude_file = File.join(project_dir, "CLAUDE.md")
      content = File.read(claude_file)

      expect(content).to include("Read the style guide first")
      expect(content).to include("Follow existing patterns")
      expect(content).to include("Test your changes")
      expect(content).to include("Document significant changes")
    end
  end
end
