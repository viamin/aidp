# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/aidp/prompt_optimization/style_guide_indexer"

RSpec.describe Aidp::PromptOptimization::StyleGuideIndexer do
  let(:temp_dir) { Dir.mktmpdir }
  let(:indexer) { described_class.new(project_dir: temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "initializes with project directory" do
      expect(indexer.project_dir).to eq(temp_dir)
    end

    it "initializes with empty fragments" do
      expect(indexer.fragments).to eq([])
    end
  end

  describe "#index!" do
    context "when style guide does not exist" do
      it "returns empty array" do
        result = indexer.index!
        expect(result).to eq([])
      end
    end

    context "when style guide exists" do
      before do
        docs_dir = File.join(temp_dir, "docs")
        FileUtils.mkdir_p(docs_dir)
        File.write(File.join(docs_dir, "LLM_STYLE_GUIDE.md"), sample_style_guide)
      end

      it "indexes fragments from the file" do
        indexer.index!
        expect(indexer.fragments).not_to be_empty
      end

      it "creates fragments with correct structure" do
        indexer.index!
        fragment = indexer.fragments.first

        expect(fragment).to be_a(Aidp::PromptOptimization::Fragment)
        expect(fragment.id).to be_a(String)
        expect(fragment.heading).to be_a(String)
        expect(fragment.level).to be_a(Integer)
        expect(fragment.content).to be_a(String)
        expect(fragment.tags).to be_an(Array)
      end

      it "parses different heading levels" do
        indexer.index!

        levels = indexer.fragments.map(&:level).uniq.sort
        expect(levels).to include(1, 2)
      end

      it "extracts content for each fragment" do
        indexer.index!

        fragments_with_content = indexer.fragments.select { |f| f.content.length > 50 }
        expect(fragments_with_content).not_to be_empty
      end
    end
  end

  describe "#find_fragments" do
    before do
      docs_dir = File.join(temp_dir, "docs")
      FileUtils.mkdir_p(docs_dir)
      File.write(File.join(docs_dir, "LLM_STYLE_GUIDE.md"), sample_style_guide)
      indexer.index!
    end

    it "finds fragments by tag" do
      results = indexer.find_fragments(tags: ["testing"])
      expect(results).not_to be_empty
    end

    it "finds fragments by heading pattern" do
      results = indexer.find_fragments(heading: "naming")
      expect(results).not_to be_empty
    end

    it "filters by heading level" do
      results = indexer.find_fragments(min_level: 2, max_level: 2)
      results.each do |fragment|
        expect(fragment.level).to eq(2)
      end
    end

    it "returns empty array when no matches" do
      results = indexer.find_fragments(tags: ["nonexistent_tag"])
      expect(results).to eq([])
    end

    it "combines multiple criteria" do
      results = indexer.find_fragments(tags: ["style"], min_level: 1, max_level: 2)
      results.each do |fragment|
        expect(fragment.level).to be_between(1, 2)
        expect(fragment.matches_any_tag?(["style"])).to be true
      end
    end
  end

  describe "#all_tags" do
    before do
      docs_dir = File.join(temp_dir, "docs")
      FileUtils.mkdir_p(docs_dir)
      File.write(File.join(docs_dir, "LLM_STYLE_GUIDE.md"), sample_style_guide)
      indexer.index!
    end

    it "returns all unique tags" do
      tags = indexer.all_tags
      expect(tags).to be_an(Array)
      expect(tags.uniq).to eq(tags)
    end

    it "returns sorted tags" do
      tags = indexer.all_tags
      expect(tags).to eq(tags.sort)
    end
  end

  describe "#find_by_id" do
    before do
      docs_dir = File.join(temp_dir, "docs")
      FileUtils.mkdir_p(docs_dir)
      File.write(File.join(docs_dir, "LLM_STYLE_GUIDE.md"), sample_style_guide)
      indexer.index!
    end

    it "finds fragment by ID" do
      fragment = indexer.fragments.first
      result = indexer.find_by_id(fragment.id)

      expect(result).to eq(fragment)
    end

    it "returns nil for non-existent ID" do
      result = indexer.find_by_id("non-existent-id")
      expect(result).to be_nil
    end
  end

  describe "private methods" do
    describe "#generate_id" do
      it "creates slug from heading" do
        id = indexer.send(:generate_id, "Zero Framework Cognition (ZFC)")
        expect(id).to eq("zero-framework-cognition-zfc")
      end

      it "handles special characters" do
        id = indexer.send(:generate_id, "Test & Debug: Best Practices!")
        expect(id).to match(/^[a-z0-9-]+$/)
      end

      it "handles multiple spaces" do
        id = indexer.send(:generate_id, "Multiple    Spaces   Here")
        expect(id).not_to include("  ")
      end
    end

    describe "#extract_tags" do
      it "extracts naming tag" do
        tags = indexer.send(:extract_tags, "Naming & Structure", "")
        expect(tags).to include("naming")
      end

      it "extracts testing tag" do
        tags = indexer.send(:extract_tags, "Testing Guidelines", "")
        expect(tags).to include("testing")
      end

      it "extracts zfc tag" do
        tags = indexer.send(:extract_tags, "Zero Framework Cognition", "")
        expect(tags).to include("zfc")
      end

      it "extracts tags from content" do
        tags = indexer.send(:extract_tags, "Example", "RSpec tests describe it")
        expect(tags).to include("testing")
      end

      it "returns unique tags" do
        tags = indexer.send(:extract_tags, "Testing Test Specs", "RSpec test")
        expect(tags.count("testing")).to eq(1)
      end
    end
  end

  def sample_style_guide
    <<~MARKDOWN
      # AIDP LLM Style Guide

      > Quick reference for coding agents.

      ## 1. Core Engineering Rules

      - Small objects, clear roles
      - Methods do one thing
      - Prefer composition over inheritance

      ### Testing Best Practices

      - Write tests first (TDD)
      - Use RSpec for all tests
      - Mock external dependencies

      ## 2. Zero Framework Cognition (ZFC)

      **Rule**: Meaning/decisions → AI. Mechanical/structural → code.

      Use `AIDecisionEngine.decide(...)` for semantic decisions.

      ## 3. Naming & Structure

      - Classes: `PascalCase`
      - Methods: `snake_case`
      - Constants: `SCREAMING_SNAKE_CASE`
    MARKDOWN
  end
end

RSpec.describe Aidp::PromptOptimization::Fragment do
  let(:fragment) do
    described_class.new(
      id: "test-fragment",
      heading: "Test Fragment",
      level: 2,
      content: "This is test content for the fragment.",
      tags: ["testing", "example"]
    )
  end

  describe "#initialize" do
    it "initializes with all attributes" do
      expect(fragment.id).to eq("test-fragment")
      expect(fragment.heading).to eq("Test Fragment")
      expect(fragment.level).to eq(2)
      expect(fragment.content).to eq("This is test content for the fragment.")
      expect(fragment.tags).to eq(["testing", "example"])
    end
  end

  describe "#matches_any_tag?" do
    it "matches when tag is present" do
      expect(fragment.matches_any_tag?(["testing"])).to be true
    end

    it "matches case-insensitively" do
      expect(fragment.matches_any_tag?(["TESTING"])).to be true
    end

    it "returns false when no tags match" do
      expect(fragment.matches_any_tag?(["nonexistent"])).to be false
    end

    it "matches any of multiple tags" do
      expect(fragment.matches_any_tag?(["nonexistent", "example"])).to be true
    end
  end

  describe "#size" do
    it "returns character count" do
      expect(fragment.size).to eq(fragment.content.length)
    end
  end

  describe "#estimated_tokens" do
    it "estimates tokens from character count" do
      expected = (fragment.content.length / 4.0).ceil
      expect(fragment.estimated_tokens).to eq(expected)
    end

    it "returns positive integer" do
      expect(fragment.estimated_tokens).to be > 0
    end
  end

  describe "#summary" do
    it "returns hash with all key information" do
      summary = fragment.summary

      expect(summary).to be_a(Hash)
      expect(summary[:id]).to eq("test-fragment")
      expect(summary[:heading]).to eq("Test Fragment")
      expect(summary[:level]).to eq(2)
      expect(summary[:tags]).to eq(["testing", "example"])
      expect(summary[:size]).to be_a(Integer)
      expect(summary[:estimated_tokens]).to be_a(Integer)
    end
  end

  describe "#to_s" do
    it "returns readable string representation" do
      expect(fragment.to_s).to eq("Fragment<test-fragment>")
    end
  end

  describe "#inspect" do
    it "returns detailed inspection string" do
      inspection = fragment.inspect
      expect(inspection).to include("test-fragment")
      expect(inspection).to include("Test Fragment")
      expect(inspection).to include("2")
    end
  end
end
