# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Provider instruction file paths" do
  # Test that all providers define their instruction file paths
  describe "instruction file path specification" do
    let(:providers) do
      [
        Aidp::Providers::Anthropic,
        Aidp::Providers::Cursor,
        Aidp::Providers::GithubCopilot,
        Aidp::Providers::Gemini,
        Aidp::Providers::Kilocode,
        Aidp::Providers::Aider,
        Aidp::Providers::Codex,
        Aidp::Providers::Opencode
      ]
    end

    it "all providers define instruction_file_path method" do
      providers.each do |provider_class|
        expect(provider_class).to respond_to(:instruction_file_path),
          "#{provider_class.name} should implement instruction_file_path class method"
      end
    end

    it "Anthropic returns CLAUDE.md" do
      expect(Aidp::Providers::Anthropic.instruction_file_path).to eq("CLAUDE.md")
    end

    it "Cursor returns .cursorrules" do
      expect(Aidp::Providers::Cursor.instruction_file_path).to eq(".cursorrules")
    end

    it "GitHub Copilot returns .github/copilot-instructions.md" do
      expect(Aidp::Providers::GithubCopilot.instruction_file_path).to eq(".github/copilot-instructions.md")
    end

    it "Gemini returns .gemini/instructions.md" do
      expect(Aidp::Providers::Gemini.instruction_file_path).to eq(".gemini/instructions.md")
    end

    it "Kilocode returns .kilocode/instructions.md" do
      expect(Aidp::Providers::Kilocode.instruction_file_path).to eq(".kilocode/instructions.md")
    end

    it "Aider returns .aider/instructions.md" do
      expect(Aidp::Providers::Aider.instruction_file_path).to eq(".aider/instructions.md")
    end

    it "Codex returns .codex/instructions.md" do
      expect(Aidp::Providers::Codex.instruction_file_path).to eq(".codex/instructions.md")
    end

    it "Opencode returns .opencode/instructions.md" do
      expect(Aidp::Providers::Opencode.instruction_file_path).to eq(".opencode/instructions.md")
    end

    it "instruction file paths are strings or nil" do
      providers.each do |provider_class|
        path = provider_class.instruction_file_path
        expect(path).to be_a(String).or(be_nil),
          "#{provider_class.name}.instruction_file_path should return String or nil, got #{path.class}"
      end
    end

    it "instruction file paths are relative (not absolute)" do
      providers.each do |provider_class|
        path = provider_class.instruction_file_path
        next if path.nil?

        expect(path).not_to start_with("/"),
          "#{provider_class.name}.instruction_file_path should return relative path, got: #{path}"
      end
    end
  end
end
