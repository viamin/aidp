# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/aidp/style_guide/selector"

RSpec.describe Aidp::StyleGuide::Selector do
  let(:temp_dir) { Dir.mktmpdir }
  let(:selector) { described_class.new(project_dir: temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "initializes with project directory" do
      expect(selector.project_dir).to eq(temp_dir)
    end
  end

  describe "#provider_needs_style_guide?" do
    context "when provider has instruction file" do
      it "returns false for claude" do
        expect(selector.provider_needs_style_guide?("claude")).to be false
      end

      it "returns false for anthropic" do
        expect(selector.provider_needs_style_guide?("anthropic")).to be false
      end

      it "returns false for github_copilot" do
        expect(selector.provider_needs_style_guide?("github_copilot")).to be false
      end

      it "returns false for cursor" do
        expect(selector.provider_needs_style_guide?("cursor")).to be false
      end

      it "returns false for gemini" do
        expect(selector.provider_needs_style_guide?("gemini")).to be false
      end

      it "returns true for opencode (no instruction files)" do
        expect(selector.provider_needs_style_guide?("opencode")).to be true
      end

      it "returns true for kilocode (no instruction files)" do
        expect(selector.provider_needs_style_guide?("kilocode")).to be true
      end

      it "returns false for codex" do
        expect(selector.provider_needs_style_guide?("codex")).to be false
      end

      it "returns false for aider" do
        expect(selector.provider_needs_style_guide?("aider")).to be false
      end

      it "handles case insensitivity" do
        expect(selector.provider_needs_style_guide?("CLAUDE")).to be false
        expect(selector.provider_needs_style_guide?("Claude")).to be false
      end

      it "handles whitespace" do
        expect(selector.provider_needs_style_guide?("  claude  ")).to be false
      end
    end

    context "when provider is unknown or nil" do
      it "returns true for unknown provider" do
        expect(selector.provider_needs_style_guide?("unknown_provider")).to be true
      end

      it "returns true for nil provider" do
        expect(selector.provider_needs_style_guide?(nil)).to be true
      end
    end
  end

  describe "#style_guide_exists?" do
    context "when style guide does not exist" do
      it "returns false" do
        expect(selector.style_guide_exists?).to be false
      end
    end

    context "when style guide exists" do
      before do
        docs_dir = File.join(temp_dir, "docs")
        FileUtils.mkdir_p(docs_dir)
        File.write(File.join(docs_dir, "STYLE_GUIDE.md"), sample_style_guide)
      end

      it "returns true" do
        expect(selector.style_guide_exists?).to be true
      end
    end
  end

  describe "#select_sections" do
    context "when style guide does not exist" do
      it "returns empty string" do
        content = selector.select_sections(keywords: ["testing"])
        expect(content).to eq("")
      end
    end

    context "when style guide exists" do
      before do
        docs_dir = File.join(temp_dir, "docs")
        FileUtils.mkdir_p(docs_dir)
        File.write(File.join(docs_dir, "STYLE_GUIDE.md"), sample_style_guide)
      end

      it "returns content for matching keywords" do
        content = selector.select_sections(keywords: ["testing"])
        expect(content).not_to be_empty
      end

      it "includes core sections by default" do
        content = selector.select_sections(keywords: [])
        expect(content).not_to be_empty
      end

      it "can exclude core sections" do
        content_with_core = selector.select_sections(keywords: [], include_core: true)
        content_without_core = selector.select_sections(keywords: [], include_core: false)

        expect(content_with_core.length).to be > content_without_core.length
      end

      it "respects max_lines limit" do
        content = selector.select_sections(keywords: [], include_core: true, max_lines: 10)
        expect(content.lines.count).to be <= 10
      end

      it "adds section comments to output" do
        content = selector.select_sections(keywords: ["testing"])
        expect(content).to include("<!-- Section:")
      end
    end
  end

  describe "#extract_keywords" do
    it "extracts keywords from string" do
      keywords = selector.extract_keywords("We need to add testing for error handling")
      expect(keywords).to include("testing")
      expect(keywords).to include("error")
    end

    it "extracts keywords from hash" do
      keywords = selector.extract_keywords({
        description: "Add error handling",
        notes: "Security considerations"
      })
      expect(keywords).to include("error")
      expect(keywords).to include("security")
    end

    it "returns unique keywords" do
      keywords = selector.extract_keywords("testing test tests")
      expect(keywords.count("testing")).to be <= 1
    end

    it "returns empty array for empty input" do
      keywords = selector.extract_keywords("")
      expect(keywords).to eq([])
    end

    it "handles nil input" do
      keywords = selector.extract_keywords(nil)
      expect(keywords).to eq([])
    end
  end

  describe "#available_keywords" do
    it "returns all section mapping keys" do
      keywords = selector.available_keywords
      expect(keywords).to be_an(Array)
      expect(keywords).not_to be_empty
    end

    it "returns sorted keywords" do
      keywords = selector.available_keywords
      expect(keywords).to eq(keywords.sort)
    end

    it "includes common keywords" do
      keywords = selector.available_keywords
      expect(keywords).to include("testing")
      expect(keywords).to include("error")
      expect(keywords).to include("zfc")
      expect(keywords).to include("tty")
    end
  end

  describe "#preview_selection" do
    before do
      docs_dir = File.join(temp_dir, "docs")
      FileUtils.mkdir_p(docs_dir)
      File.write(File.join(docs_dir, "STYLE_GUIDE.md"), sample_style_guide)
    end

    it "returns section info for keywords" do
      preview = selector.preview_selection(["testing"])
      expect(preview).to be_an(Array)
    end

    it "includes line range information" do
      preview = selector.preview_selection(["testing"])
      next if preview.empty?

      first_section = preview.first
      expect(first_section).to have_key(:start_line)
      expect(first_section).to have_key(:end_line)
      expect(first_section).to have_key(:description)
      expect(first_section).to have_key(:estimated_lines)
    end

    it "returns empty array for non-matching keywords" do
      preview = selector.preview_selection(["nonexistent_keyword_xyz"])
      expect(preview).to eq([])
    end
  end

  describe "SECTION_MAPPING" do
    it "contains expected keywords" do
      expect(described_class::SECTION_MAPPING).to have_key("testing")
      expect(described_class::SECTION_MAPPING).to have_key("error")
      expect(described_class::SECTION_MAPPING).to have_key("zfc")
      expect(described_class::SECTION_MAPPING).to have_key("tty")
      expect(described_class::SECTION_MAPPING).to have_key("logging")
    end

    it "has valid line ranges for all entries" do
      described_class::SECTION_MAPPING.each do |keyword, sections|
        sections.each do |start_line, end_line, description|
          expect(start_line).to be_a(Integer), "Invalid start_line for #{keyword}"
          expect(end_line).to be_a(Integer), "Invalid end_line for #{keyword}"
          expect(start_line).to be > 0, "start_line must be positive for #{keyword}"
          expect(end_line).to be >= start_line, "end_line must be >= start_line for #{keyword}"
          expect(description).to be_a(String), "description must be a string for #{keyword}"
        end
      end
    end
  end

  describe "PROVIDERS_WITH_INSTRUCTION_FILES" do
    it "includes claude" do
      expect(described_class::PROVIDERS_WITH_INSTRUCTION_FILES).to include("claude")
    end

    it "includes anthropic" do
      expect(described_class::PROVIDERS_WITH_INSTRUCTION_FILES).to include("anthropic")
    end

    it "includes github_copilot" do
      expect(described_class::PROVIDERS_WITH_INSTRUCTION_FILES).to include("github_copilot")
    end
  end

  describe "CORE_SECTIONS" do
    it "is not empty" do
      expect(described_class::CORE_SECTIONS).not_to be_empty
    end

    it "has valid structure" do
      described_class::CORE_SECTIONS.each do |start_line, end_line, description|
        expect(start_line).to be_a(Integer)
        expect(end_line).to be_a(Integer)
        expect(description).to be_a(String)
      end
    end
  end

  def sample_style_guide
    # Create a sample with line numbers that match some expected ranges
    lines = Array.new(3000) { |i| "Line #{i + 1}: Sample content\n" }

    # Add some section markers at expected positions
    lines[24] = "## Code Organization\n"
    lines[50] = "### Naming Conventions\n"
    lines[216] = "## Sandi Metz Rules\n"
    lines[286] = "### Logging Practices\n"
    lines[499] = "## Zero Framework Cognition (ZFC)\n"
    lines[855] = "## TTY Toolkit Guidelines\n"
    lines[1872] = "## Testing Guidelines\n"
    lines[2112] = "## Error Handling\n"

    lines.join
  end
end
