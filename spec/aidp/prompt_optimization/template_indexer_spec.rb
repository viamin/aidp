# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/aidp/prompt_optimization/template_indexer"

RSpec.describe Aidp::PromptOptimization::TemplateIndexer do
  let(:temp_dir) { Dir.mktmpdir }
  let(:indexer) { described_class.new(project_dir: temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "initializes with project directory" do
      expect(indexer.project_dir).to eq(temp_dir)
    end

    it "initializes with empty templates" do
      expect(indexer.templates).to eq([])
    end
  end

  describe "#index!" do
    context "when templates directory does not exist" do
      it "returns empty array" do
        result = indexer.index!
        expect(result).to eq([])
      end
    end

    context "when templates exist" do
      before do
        create_sample_templates
      end

      it "indexes templates from all categories" do
        indexer.index!
        expect(indexer.templates).not_to be_empty
      end

      it "creates TemplateFragment objects" do
        indexer.index!
        template = indexer.templates.first

        expect(template).to be_a(Aidp::PromptOptimization::TemplateFragment)
        expect(template.id).to be_a(String)
        expect(template.name).to be_a(String)
        expect(template.category).to be_a(String)
        expect(template.content).to be_a(String)
        expect(template.tags).to be_an(Array)
      end

      it "indexes templates from analysis category" do
        indexer.index!
        analysis_templates = indexer.templates.select { |t| t.category == "analysis" }
        expect(analysis_templates).not_to be_empty
      end

      it "indexes templates from planning category" do
        indexer.index!
        planning_templates = indexer.templates.select { |t| t.category == "planning" }
        expect(planning_templates).not_to be_empty
      end

      it "extracts template titles" do
        indexer.index!
        template = indexer.templates.first
        expect(template.name).not_to be_empty
      end

      it "generates unique IDs" do
        indexer.index!
        ids = indexer.templates.map(&:id)
        expect(ids.uniq).to eq(ids)
      end
    end
  end

  describe "#find_templates" do
    before do
      create_sample_templates
      indexer.index!
    end

    it "finds templates by category" do
      results = indexer.find_templates(category: "analysis")
      expect(results).not_to be_empty
      results.each do |template|
        expect(template.category).to eq("analysis")
      end
    end

    it "finds templates by tags" do
      results = indexer.find_templates(tags: ["testing"])
      expect(results).not_to be_empty
    end

    it "finds templates by name pattern" do
      results = indexer.find_templates(name: "test")
      expect(results).not_to be_empty
    end

    it "combines multiple criteria" do
      results = indexer.find_templates(category: "analysis", tags: ["testing"])
      results.each do |template|
        expect(template.category).to eq("analysis")
        expect(template.matches_any_tag?(["testing"])).to be true
      end
    end

    it "returns empty array when no matches" do
      results = indexer.find_templates(category: "nonexistent")
      expect(results).to eq([])
    end
  end

  describe "#all_tags" do
    before do
      create_sample_templates
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

    it "includes category tags" do
      tags = indexer.all_tags
      expect(tags).to include("analysis")
    end
  end

  describe "#categories" do
    before do
      create_sample_templates
      indexer.index!
    end

    it "returns all unique categories" do
      categories = indexer.categories
      expect(categories).to be_an(Array)
      expect(categories.uniq).to eq(categories)
    end

    it "returns sorted categories" do
      categories = indexer.categories
      expect(categories).to eq(categories.sort)
    end
  end

  describe "#find_by_id" do
    before do
      create_sample_templates
      indexer.index!
    end

    it "finds template by ID" do
      template = indexer.templates.first
      result = indexer.find_by_id(template.id)

      expect(result).to eq(template)
    end

    it "returns nil for non-existent ID" do
      result = indexer.find_by_id("nonexistent/template")
      expect(result).to be_nil
    end
  end

  describe "private methods" do
    describe "#extract_title" do
      it "extracts title from first heading" do
        content = "# Test Template\n\nSome content"
        title = indexer.send(:extract_title, content)
        expect(title).to eq("Test Template")
      end

      it "returns nil when no heading found" do
        content = "Some content without heading"
        title = indexer.send(:extract_title, content)
        expect(title).to be_nil
      end
    end

    describe "#titleize" do
      it "converts snake_case to Title Case" do
        result = indexer.send(:titleize, "analyze_functionality")
        expect(result).to eq("Analyze Functionality")
      end

      it "handles single word" do
        result = indexer.send(:titleize, "template")
        expect(result).to eq("Template")
      end
    end

    describe "#extract_tags" do
      it "includes category as tag" do
        tags = indexer.send(:extract_tags, "test_file", "", "analysis")
        expect(tags).to include("analysis")
      end

      it "extracts testing tag from filename" do
        tags = indexer.send(:extract_tags, "analyze_tests", "", "analysis")
        expect(tags).to include("testing")
      end

      it "extracts refactor tag from content" do
        content = "This template helps with refactoring and reducing complexity"
        tags = indexer.send(:extract_tags, "template", content, "implementation")
        expect(tags).to include("refactor")
      end

      it "extracts security tag" do
        tags = indexer.send(:extract_tags, "security_review", "", "planning")
        expect(tags).to include("security")
      end

      it "returns unique tags only" do
        content = "testing strategy test coverage"
        tags = indexer.send(:extract_tags, "test_analysis", content, "analysis")
        expect(tags.count("testing")).to eq(1)
      end
    end
  end

  def create_sample_templates
    # Create analysis templates
    analysis_dir = File.join(temp_dir, "templates", "analysis")
    FileUtils.mkdir_p(analysis_dir)

    File.write(File.join(analysis_dir, "analyze_tests.md"), <<~MARKDOWN)
      # Test Analysis Template

      You are a **Test Analyst**, analyzing test coverage and quality.

      ## Analysis Objectives

      1. Assess test coverage
      2. Evaluate test quality
      3. Identify testing gaps
    MARKDOWN

    File.write(File.join(analysis_dir, "analyze_architecture.md"), <<~MARKDOWN)
      # Architecture Analysis Template

      You are an **Architect**, analyzing system architecture and design patterns.

      ## Analysis Objectives

      1. Review architecture patterns
      2. Assess scalability
      3. Evaluate security
    MARKDOWN

    # Create planning templates
    planning_dir = File.join(temp_dir, "templates", "planning")
    FileUtils.mkdir_p(planning_dir)

    File.write(File.join(planning_dir, "design_api.md"), <<~MARKDOWN)
      # API Design Template

      You are an **API Designer**, creating RESTful API specifications.

      ## Design Objectives

      1. Define endpoints
      2. Specify request/response formats
      3. Document authentication
    MARKDOWN

    # Create implementation templates
    impl_dir = File.join(temp_dir, "templates", "implementation")
    FileUtils.mkdir_p(impl_dir)

    File.write(File.join(impl_dir, "refactor_code.md"), <<~MARKDOWN)
      # Refactoring Template

      You are a **Refactoring Expert**, improving code quality through refactoring.

      ## Refactoring Goals

      1. Reduce complexity
      2. Improve maintainability
      3. Enhance testability
    MARKDOWN
  end
end

RSpec.describe Aidp::PromptOptimization::TemplateFragment do
  let(:template) do
    described_class.new(
      id: "analysis/test_template",
      name: "Test Template",
      category: "analysis",
      file_path: "/path/to/template.md",
      content: "This is test content for the template.",
      tags: ["testing", "analysis"]
    )
  end

  describe "#initialize" do
    it "initializes with all attributes" do
      expect(template.id).to eq("analysis/test_template")
      expect(template.name).to eq("Test Template")
      expect(template.category).to eq("analysis")
      expect(template.file_path).to eq("/path/to/template.md")
      expect(template.content).to eq("This is test content for the template.")
      expect(template.tags).to eq(["testing", "analysis"])
    end
  end

  describe "#matches_any_tag?" do
    it "matches when tag is present" do
      expect(template.matches_any_tag?(["testing"])).to be true
    end

    it "matches case-insensitively" do
      expect(template.matches_any_tag?(["TESTING"])).to be true
    end

    it "returns false when no tags match" do
      expect(template.matches_any_tag?(["nonexistent"])).to be false
    end

    it "matches any of multiple tags" do
      expect(template.matches_any_tag?(["nonexistent", "analysis"])).to be true
    end
  end

  describe "#size" do
    it "returns character count" do
      expect(template.size).to eq(template.content.length)
    end
  end

  describe "#estimated_tokens" do
    it "estimates tokens from character count" do
      expected = (template.content.length / 4.0).ceil
      expect(template.estimated_tokens).to eq(expected)
    end

    it "returns positive integer" do
      expect(template.estimated_tokens).to be > 0
    end
  end

  describe "#summary" do
    it "returns hash with all key information" do
      summary = template.summary

      expect(summary).to be_a(Hash)
      expect(summary[:id]).to eq("analysis/test_template")
      expect(summary[:name]).to eq("Test Template")
      expect(summary[:category]).to eq("analysis")
      expect(summary[:tags]).to eq(["testing", "analysis"])
      expect(summary[:size]).to be_a(Integer)
      expect(summary[:estimated_tokens]).to be_a(Integer)
    end
  end

  describe "#to_s" do
    it "returns readable string representation" do
      expect(template.to_s).to eq("TemplateFragment<analysis/test_template>")
    end
  end

  describe "#inspect" do
    it "returns detailed inspection string" do
      inspection = template.inspect
      expect(inspection).to include("analysis/test_template")
      expect(inspection).to include("Test Template")
      expect(inspection).to include("analysis")
    end
  end
end
