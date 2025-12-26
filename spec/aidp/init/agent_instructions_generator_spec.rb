# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Init::AgentInstructionsGenerator do
  let(:temp_dir) { Dir.mktmpdir }
  let(:generator) { described_class.new(temp_dir) }
  let(:analysis) do
    {
      languages: {"Ruby" => 1000, "JavaScript" => 500},
      frameworks: [{name: "Rails", confidence: 0.9}],
      test_frameworks: [{name: "RSpec", confidence: 0.8}],
      tooling: [],
      config_files: [".rubocop.yml"],
      key_directories: ["lib", "spec"],
      repo_stats: {
        total_files: 50,
        total_directories: 10,
        docs_present: true,
        has_ci_config: true,
        has_containerization: false
      }
    }
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "#exists?" do
    it "returns false when AGENTS.md doesn't exist" do
      expect(generator.exists?).to be false
    end

    it "returns true when AGENTS.md exists" do
      File.write(File.join(temp_dir, "AGENTS.md"), "# Test")
      expect(generator.exists?).to be true
    end
  end

  describe "#provider_instruction_files" do
    it "returns an array of file info hashes" do
      files = generator.provider_instruction_files

      expect(files).to be_an(Array)
      expect(files).to all(be_a(Hash))
    end

    it "includes paths from known providers" do
      files = generator.provider_instruction_files
      paths = files.map { |f| f[:path] }

      expect(paths).to include("CLAUDE.md")
      expect(paths).to include(".github/copilot-instructions.md")
    end

    it "includes provider information" do
      files = generator.provider_instruction_files

      expect(files.first).to have_key(:path)
      expect(files.first).to have_key(:description)
      expect(files.first).to have_key(:provider)
    end
  end

  describe "#preview" do
    it "returns preview information" do
      preview = generator.preview

      expect(preview).to be_a(Hash)
      expect(preview).to have_key(:existing)
      expect(preview).to have_key(:to_create)
      expect(preview).to have_key(:to_symlink)
    end

    it "lists AGENTS.md to be created when it doesn't exist" do
      preview = generator.preview

      expect(preview[:to_create]).to include("AGENTS.md")
    end

    it "lists AGENTS.md as existing when it exists" do
      File.write(File.join(temp_dir, "AGENTS.md"), "# Test")
      preview = generator.preview

      expect(preview[:existing]).to include("AGENTS.md")
    end

    it "lists provider files to be symlinked" do
      preview = generator.preview

      expect(preview[:to_symlink]).to include("CLAUDE.md")
    end
  end

  describe "#generate" do
    it "creates AGENTS.md" do
      files = generator.generate(analysis: analysis)

      agents_md = File.join(temp_dir, "AGENTS.md")
      expect(File.exist?(agents_md)).to be true
      expect(files).to include("AGENTS.md")
    end

    it "includes project overview in AGENTS.md" do
      generator.generate(analysis: analysis)

      content = File.read(File.join(temp_dir, "AGENTS.md"))
      expect(content).to include("AI Agent Instructions")
      expect(content).to include("LLM_STYLE_GUIDE.md")
    end

    it "includes detected frameworks in AGENTS.md" do
      generator.generate(analysis: analysis)

      content = File.read(File.join(temp_dir, "AGENTS.md"))
      expect(content).to include("Rails")
    end

    it "includes detected test frameworks in AGENTS.md" do
      generator.generate(analysis: analysis)

      content = File.read(File.join(temp_dir, "AGENTS.md"))
      expect(content).to include("RSpec")
    end

    it "creates symlinks to provider-specific locations" do
      files = generator.generate(analysis: analysis)

      # Check CLAUDE.md symlink was created
      claude_md = File.join(temp_dir, "CLAUDE.md")
      expect(File.symlink?(claude_md)).to be true
      expect(files).to include("CLAUDE.md")
    end

    it "creates parent directories for symlinks" do
      generator.generate(analysis: analysis)

      github_dir = File.join(temp_dir, ".github")
      expect(Dir.exist?(github_dir)).to be true
    end

    it "skips existing files" do
      # Create an existing CLAUDE.md
      File.write(File.join(temp_dir, "CLAUDE.md"), "# Custom Claude Instructions")

      files = generator.generate(analysis: analysis)

      # Original file should be preserved
      content = File.read(File.join(temp_dir, "CLAUDE.md"))
      expect(content).to include("Custom Claude Instructions")

      # File should not be in the generated files list
      expect(files).not_to include("CLAUDE.md")
    end

    it "doesn't create AGENTS.md if it already exists" do
      File.write(File.join(temp_dir, "AGENTS.md"), "# Custom Agents")

      files = generator.generate(analysis: analysis)

      content = File.read(File.join(temp_dir, "AGENTS.md"))
      expect(content).to include("Custom Agents")
      expect(files).not_to include("AGENTS.md")
    end

    it "returns list of generated files" do
      files = generator.generate(analysis: analysis)

      expect(files).to be_an(Array)
      expect(files).to include("AGENTS.md")
    end

    it "symlinks point to AGENTS.md" do
      generator.generate(analysis: analysis)

      claude_md = File.join(temp_dir, "CLAUDE.md")
      expect(File.symlink?(claude_md)).to be true
      expect(File.readlink(claude_md)).to eq("AGENTS.md")
    end

    it "handles nested symlink paths correctly" do
      generator.generate(analysis: analysis)

      copilot_instructions = File.join(temp_dir, ".github", "copilot-instructions.md")
      expect(File.symlink?(copilot_instructions)).to be true

      # Should point to ../AGENTS.md since it's in a subdirectory
      expect(File.readlink(copilot_instructions)).to eq("../AGENTS.md")
    end
  end
end
