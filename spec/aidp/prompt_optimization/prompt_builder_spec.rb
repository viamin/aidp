# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/aidp/prompt_optimization/prompt_builder"
require_relative "../../../lib/aidp/prompt_optimization/context_composer"
require_relative "../../../lib/aidp/prompt_optimization/relevance_scorer"
require_relative "../../../lib/aidp/prompt_optimization/style_guide_indexer"
require_relative "../../../lib/aidp/prompt_optimization/template_indexer"
require_relative "../../../lib/aidp/prompt_optimization/source_code_fragmenter"

RSpec.describe Aidp::PromptOptimization::PromptBuilder do
  let(:builder) { described_class.new }
  let(:task_context) do
    Aidp::PromptOptimization::TaskContext.new(
      task_type: :feature,
      description: "Add user authentication",
      affected_files: ["lib/user.rb", "lib/auth.rb"],
      step_name: "implementation",
      tags: ["security", "api"]
    )
  end

  describe "#build" do
    context "with mixed fragment types" do
      let(:style_fragment) do
        Aidp::PromptOptimization::Fragment.new(
          id: "security",
          heading: "Security Guidelines",
          level: 2,
          content: "Always validate user input",
          tags: ["security"]
        )
      end

      let(:template_fragment) do
        Aidp::PromptOptimization::TemplateFragment.new(
          id: "implementation/feature",
          name: "Feature Implementation",
          category: "implementation",
          file_path: "/templates/implementation/feature.md",
          content: "## Steps\n1. Write tests\n2. Implement",
          tags: ["implementation"]
        )
      end

      let(:code_fragment) do
        Aidp::PromptOptimization::CodeFragment.new(
          id: "lib/user.rb:User",
          file_path: "/project/lib/user.rb",
          type: :class,
          name: "User",
          content: "class User\n  def authenticate\n  end\nend",
          line_start: 1,
          line_end: 4
        )
      end

      let(:composition_result) do
        Aidp::PromptOptimization::CompositionResult.new(
          selected_fragments: [
            {fragment: style_fragment, score: 0.95, breakdown: {}},
            {fragment: template_fragment, score: 0.85, breakdown: {}},
            {fragment: code_fragment, score: 0.90, breakdown: {}}
          ],
          total_tokens: 500,
          budget: 14000,
          excluded_count: 2,
          average_score: 0.90
        )
      end

      it "returns a PromptOutput object" do
        result = builder.build(task_context, composition_result)
        expect(result).to be_a(Aidp::PromptOptimization::PromptOutput)
      end

      it "includes task section" do
        result = builder.build(task_context, composition_result)
        expect(result.content).to include("# Task")
        expect(result.content).to include("**Type**: feature")
        expect(result.content).to include("Add user authentication")
      end

      it "includes affected files in task section" do
        result = builder.build(task_context, composition_result)
        expect(result.content).to include("## Affected Files")
        expect(result.content).to include("`lib/user.rb`")
        expect(result.content).to include("`lib/auth.rb`")
      end

      it "includes current step in task section" do
        result = builder.build(task_context, composition_result)
        expect(result.content).to include("## Current Step")
        expect(result.content).to include("implementation")
      end

      it "includes style guide section" do
        result = builder.build(task_context, composition_result)
        expect(result.content).to include("# Relevant Style Guidelines")
        expect(result.content).to include("## Security Guidelines")
        expect(result.content).to include("Always validate user input")
      end

      it "includes template section" do
        result = builder.build(task_context, composition_result)
        expect(result.content).to include("# Template Guidance")
        expect(result.content).to include("## Feature Implementation")
        expect(result.content).to include("**Category**: implementation")
      end

      it "includes code section" do
        result = builder.build(task_context, composition_result)
        expect(result.content).to include("# Code Context")
        expect(result.content).to include("class User")
      end

      it "uses section separators" do
        result = builder.build(task_context, composition_result)
        expect(result.content).to include("\n\n---\n\n")
      end

      it "does not include metadata by default" do
        result = builder.build(task_context, composition_result)
        expect(result.content).not_to include("# Prompt Optimization Metadata")
      end

      it "includes metadata when requested" do
        result = builder.build(task_context, composition_result, include_metadata: true)
        expect(result.content).to include("# Prompt Optimization Metadata")
        expect(result.content).to include("## Selection Statistics")
        expect(result.content).to include("**Fragments Selected**: 3")
        expect(result.content).to include("**Fragments Excluded**: 2")
      end
    end

    context "with only style guide fragments" do
      let(:fragment1) do
        Aidp::PromptOptimization::Fragment.new(
          id: "testing",
          heading: "Testing Guidelines",
          level: 2,
          content: "Write comprehensive tests",
          tags: ["testing"]
        )
      end

      let(:composition_result) do
        Aidp::PromptOptimization::CompositionResult.new(
          selected_fragments: [
            {fragment: fragment1, score: 0.95, breakdown: {}}
          ],
          total_tokens: 100,
          budget: 14000,
          excluded_count: 0,
          average_score: 0.95
        )
      end

      it "includes only style guide section" do
        result = builder.build(task_context, composition_result)
        expect(result.content).to include("# Relevant Style Guidelines")
        expect(result.content).not_to include("# Template Guidance")
        expect(result.content).not_to include("# Code Context")
      end
    end

    context "with critical fragments" do
      let(:critical_fragment) do
        Aidp::PromptOptimization::Fragment.new(
          id: "critical",
          heading: "Critical Security",
          level: 2,
          content: "Never store passwords in plain text",
          tags: ["security"]
        )
      end

      let(:composition_result) do
        Aidp::PromptOptimization::CompositionResult.new(
          selected_fragments: [
            {fragment: critical_fragment, score: 0.95, breakdown: {}}
          ],
          total_tokens: 100,
          budget: 14000,
          excluded_count: 0,
          average_score: 0.95
        )
      end

      it "marks critical fragments with relevance score" do
        result = builder.build(task_context, composition_result)
        expect(result.content).to include("_[Critical: Relevance score 95%]_")
      end
    end

    context "with multiple code fragments from same file" do
      let(:fragment1) do
        Aidp::PromptOptimization::CodeFragment.new(
          id: "lib/user.rb:User",
          file_path: "/project/lib/user.rb",
          type: :class,
          name: "User",
          content: "class User\nend",
          line_start: 1,
          line_end: 2
        )
      end

      let(:fragment2) do
        Aidp::PromptOptimization::CodeFragment.new(
          id: "lib/user.rb:authenticate",
          file_path: "/project/lib/user.rb",
          type: :method,
          name: "authenticate",
          content: "def authenticate\nend",
          line_start: 5,
          line_end: 6
        )
      end

      let(:composition_result) do
        Aidp::PromptOptimization::CompositionResult.new(
          selected_fragments: [
            {fragment: fragment1, score: 0.90, breakdown: {}},
            {fragment: fragment2, score: 0.85, breakdown: {}}
          ],
          total_tokens: 200,
          budget: 14000,
          excluded_count: 0,
          average_score: 0.875
        )
      end

      it "groups fragments by file" do
        result = builder.build(task_context, composition_result)
        # Should have one file section with multiple fragments
        file_section_count = result.content.scan(/## `.*\.rb`/).count
        expect(file_section_count).to eq(1)
      end

      it "shows both fragments under same file" do
        result = builder.build(task_context, composition_result)
        expect(result.content).to include("### class: User")
        expect(result.content).to include("### method: authenticate")
      end

      it "shows line numbers for each fragment" do
        result = builder.build(task_context, composition_result)
        expect(result.content).to include("(lines 1-2)")
        expect(result.content).to include("(lines 5-6)")
      end
    end

    context "with empty fragment collections" do
      let(:composition_result) do
        Aidp::PromptOptimization::CompositionResult.new(
          selected_fragments: [],
          total_tokens: 0,
          budget: 14000,
          excluded_count: 0,
          average_score: 0.0
        )
      end

      it "includes only task section" do
        result = builder.build(task_context, composition_result)
        expect(result.content).to include("# Task")
        expect(result.content).not_to include("# Relevant Style Guidelines")
        expect(result.content).not_to include("# Template Guidance")
        expect(result.content).not_to include("# Code Context")
      end
    end
  end
end

RSpec.describe Aidp::PromptOptimization::PromptOutput do
  let(:task_context) do
    Aidp::PromptOptimization::TaskContext.new(
      task_type: :feature,
      description: "Add feature",
      affected_files: ["file.rb"],
      step_name: "implementation"
    )
  end

  let(:fragment) do
    Aidp::PromptOptimization::Fragment.new(
      id: "test",
      heading: "Test",
      level: 2,
      content: "Test content",
      tags: ["test"]
    )
  end

  let(:composition_result) do
    Aidp::PromptOptimization::CompositionResult.new(
      selected_fragments: [{fragment: fragment, score: 0.95, breakdown: {}}],
      total_tokens: 500,
      budget: 14000,
      excluded_count: 2,
      average_score: 0.95
    )
  end

  let(:prompt_output) do
    described_class.new(
      content: "# Task\n\nDescription\n\n---\n\n# Style Guide\n\nGuidelines",
      composition_result: composition_result,
      task_context: task_context,
      metadata: {
        selected_count: 1,
        excluded_count: 2,
        total_tokens: 500,
        budget: 14000,
        utilization: 3.57,
        average_score: 0.95,
        timestamp: "2025-01-15T10:00:00Z",
        include_metadata: false
      }
    )
  end

  describe "#initialize" do
    it "stores content" do
      expect(prompt_output.content).to include("# Task")
    end

    it "stores composition_result" do
      expect(prompt_output.composition_result).to eq(composition_result)
    end

    it "stores task_context" do
      expect(prompt_output.task_context).to eq(task_context)
    end

    it "stores metadata" do
      expect(prompt_output.metadata[:selected_count]).to eq(1)
    end
  end

  describe "#size" do
    it "returns character count" do
      expect(prompt_output.size).to eq(prompt_output.content.length)
    end
  end

  describe "#estimated_tokens" do
    it "estimates tokens from character count" do
      expected = (prompt_output.content.length / 4.0).ceil
      expect(prompt_output.estimated_tokens).to eq(expected)
    end

    it "returns positive integer" do
      expect(prompt_output.estimated_tokens).to be > 0
    end
  end

  describe "#write_to_file" do
    let(:temp_dir) { Dir.mktmpdir }
    let(:file_path) { File.join(temp_dir, "PROMPT.md") }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it "writes content to file" do
      prompt_output.write_to_file(file_path)
      expect(File.exist?(file_path)).to be true
    end

    it "writes correct content" do
      prompt_output.write_to_file(file_path)
      written_content = File.read(file_path)
      expect(written_content).to eq(prompt_output.content)
    end
  end

  describe "#selection_report" do
    it "returns a string report" do
      report = prompt_output.selection_report
      expect(report).to be_a(String)
    end

    it "includes report title" do
      report = prompt_output.selection_report
      expect(report).to include("# Prompt Optimization Report")
    end

    it "includes task context" do
      report = prompt_output.selection_report
      expect(report).to include("## Task Context")
      expect(report).to include("Type: feature")
      expect(report).to include("Step: implementation")
    end

    it "includes composition statistics" do
      report = prompt_output.selection_report
      expect(report).to include("## Composition Statistics")
      expect(report).to include("Selected: 1 fragments")
      expect(report).to include("Excluded: 2 fragments")
      expect(report).to include("Tokens: 500 / 14000")
    end

    it "includes selected fragments list" do
      report = prompt_output.selection_report
      expect(report).to include("## Selected Fragments")
      expect(report).to include("Test (95%)")
    end

    it "includes timestamp" do
      report = prompt_output.selection_report
      expect(report).to include("Generated at:")
      expect(report).to include("2025-01-15T10:00:00Z")
    end
  end

  describe "#to_s" do
    it "returns readable string representation" do
      str = prompt_output.to_s
      expect(str).to include("PromptOutput")
      expect(str).to include("tokens")
      expect(str).to include("fragments")
    end
  end
end
