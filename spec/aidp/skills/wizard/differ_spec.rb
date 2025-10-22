# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/skills/wizard/differ"
require_relative "../../../../lib/aidp/skills/wizard/builder"
require_relative "../../../../lib/aidp/skills/skill"

RSpec.describe Aidp::Skills::Wizard::Differ do
  let(:differ) { described_class.new }

  describe "#diff" do
    context "with identical skills" do
      let(:skill) do
        Aidp::Skills::Skill.new(
          id: "test_skill",
          name: "Test Skill",
          description: "A test skill",
          version: "1.0.0",
          content: "You are a test skill.",
          source_path: "/tmp/test.md"
        )
      end

      it "reports no changes" do
        diff = differ.diff(skill, skill)

        expect(diff[:has_changes]).to be false
      end

      it "returns equal content" do
        diff = differ.diff(skill, skill)

        expect(diff[:original]).to eq(diff[:modified])
      end
    end

    context "with different skills" do
      let(:original_skill) do
        Aidp::Skills::Skill.new(
          id: "original",
          name: "Original",
          description: "Original description",
          version: "1.0.0",
          expertise: ["ruby"],
          content: "Original content.",
          source_path: "/tmp/original.md"
        )
      end

      let(:modified_skill) do
        Aidp::Skills::Skill.new(
          id: "modified",
          name: "Modified",
          description: "Modified description",
          version: "2.0.0",
          expertise: ["ruby", "testing"],
          content: "Modified content.",
          source_path: "/tmp/modified.md"
        )
      end

      it "reports changes" do
        diff = differ.diff(original_skill, modified_skill)

        expect(diff[:has_changes]).to be true
      end

      it "returns both original and modified content" do
        diff = differ.diff(original_skill, modified_skill)

        expect(diff[:original]).to be_a(String)
        expect(diff[:modified]).to be_a(String)
        expect(diff[:original]).not_to eq(diff[:modified])
      end

      it "generates line diff information" do
        diff = differ.diff(original_skill, modified_skill)

        expect(diff[:lines]).to be_an(Array)
        expect(diff[:lines]).not_to be_empty
        expect(diff[:lines].first).to have_key(:type)
        expect(diff[:lines].first).to have_key(:line)
      end
    end

    context "with string content" do
      let(:original) { "Line 1\nLine 2\nLine 3" }
      let(:modified) { "Line 1\nModified Line 2\nLine 3" }

      it "diffs string content directly" do
        diff = differ.diff(original, modified)

        expect(diff[:has_changes]).to be true
        expect(diff[:lines]).to be_an(Array)
      end
    end
  end

  describe "#display" do
    let(:output) { StringIO.new }

    context "with no changes" do
      let(:diff) do
        {
          original: "Same content",
          modified: "Same content",
          lines: [],
          has_changes: false
        }
      end

      it "displays 'No differences found'" do
        differ.display(diff, output: output)

        expect(output.string).to include("No differences found")
      end
    end

    context "with changes" do
      let(:diff) do
        {
          original: "Original\nContent",
          modified: "Modified\nContent",
          lines: [
            {type: :remove, line: "Original"},
            {type: :add, line: "Modified"},
            {type: :context, line: "Content"}
          ],
          has_changes: true
        }
      end

      it "displays diff header" do
        differ.display(diff, output: output)

        expect(output.string).to include("Skill Diff")
        expect(output.string).to include("=" * 60)
      end

      it "displays removed lines with -" do
        differ.display(diff, output: output)

        expect(output.string).to include("- Original")
      end

      it "displays added lines with +" do
        differ.display(diff, output: output)

        expect(output.string).to include("+ Modified")
      end

      it "displays context lines with spaces" do
        differ.display(diff, output: output)

        expect(output.string).to include("  Content")
      end
    end
  end

  describe "#unified_diff" do
    let(:original_skill) do
      Aidp::Skills::Skill.new(
        id: "original",
        name: "Original",
        description: "Original",
        version: "1.0.0",
        content: "Line 1\nLine 2\nLine 3",
        source_path: "/tmp/original.md"
      )
    end

    let(:modified_skill) do
      Aidp::Skills::Skill.new(
        id: "modified",
        name: "Modified",
        description: "Modified",
        version: "1.0.0",
        content: "Line 1\nModified Line 2\nLine 3",
        source_path: "/tmp/modified.md"
      )
    end

    it "returns unified diff format" do
      diff_string = differ.unified_diff(original_skill, modified_skill)

      expect(diff_string).to include("--- original")
      expect(diff_string).to include("+++ modified")
    end

    it "marks removed lines with -" do
      diff_string = differ.unified_diff(original_skill, modified_skill)

      expect(diff_string).to match(/-.*Line 2/)
    end

    it "marks added lines with +" do
      diff_string = differ.unified_diff(original_skill, modified_skill)

      expect(diff_string).to match(/\+.*Modified Line 2/)
    end

    it "marks unchanged lines with space" do
      diff_string = differ.unified_diff(original_skill, modified_skill)

      expect(diff_string).to match(/ .*Line 1/)
      expect(diff_string).to match(/ .*Line 3/)
    end
  end

  describe "#compare_with_template" do
    let(:template_skill) do
      Aidp::Skills::Skill.new(
        id: "template",
        name: "Template Skill",
        description: "Template description",
        version: "1.0.0",
        expertise: ["base"],
        keywords: ["template"],
        when_to_use: ["Always"],
        content: "Template content.",
        source_path: "/tmp/template.md"
      )
    end

    let(:project_skill) do
      Aidp::Skills::Skill.new(
        id: "template",
        name: "Project Skill",
        description: "Project description",
        version: "2.0.0",
        expertise: ["base", "custom"],
        keywords: ["template", "project"],
        when_to_use: ["Always", "In projects"],
        content: "Project content.",
        source_path: "/tmp/project.md"
      )
    end

    it "returns comparison information" do
      comparison = differ.compare_with_template(project_skill, template_skill)

      expect(comparison).to have_key(:skill_id)
      expect(comparison).to have_key(:overrides)
      expect(comparison).to have_key(:additions)
      expect(comparison).to have_key(:diff)
    end

    it "detects field overrides" do
      comparison = differ.compare_with_template(project_skill, template_skill)

      expect(comparison[:overrides]).to have_key(:name)
      expect(comparison[:overrides]).to have_key(:description)
      expect(comparison[:overrides]).to have_key(:version)
      expect(comparison[:overrides]).to have_key(:content)
    end

    it "detects added expertise" do
      comparison = differ.compare_with_template(project_skill, template_skill)

      expect(comparison[:additions][:expertise]).to include("custom")
    end

    it "detects added keywords" do
      comparison = differ.compare_with_template(project_skill, template_skill)

      expect(comparison[:additions][:keywords]).to include("project")
    end

    it "detects added when_to_use" do
      comparison = differ.compare_with_template(project_skill, template_skill)

      expect(comparison[:additions][:when_to_use]).to include("In projects")
    end

    it "includes full diff" do
      comparison = differ.compare_with_template(project_skill, template_skill)

      expect(comparison[:diff]).to be_a(Hash)
      expect(comparison[:diff][:has_changes]).to be true
    end

    context "with no overrides" do
      let(:identical_skill) { template_skill.dup }

      it "returns empty overrides" do
        comparison = differ.compare_with_template(identical_skill, template_skill)

        expect(comparison[:overrides]).to be_empty
      end
    end

    context "with no additions" do
      let(:minimal_skill) do
        Aidp::Skills::Skill.new(
          id: "minimal",
          name: "Minimal",
          description: "Minimal",
          version: "1.0.0",
          expertise: ["base"],
          keywords: ["template"],
          when_to_use: ["Always"],
          content: "Minimal content.",
          source_path: "/tmp/minimal.md"
        )
      end

      it "returns empty additions for arrays with same items" do
        comparison = differ.compare_with_template(minimal_skill, template_skill)

        expect(comparison[:additions][:expertise]).to be_nil
        expect(comparison[:additions][:keywords]).to be_nil
        expect(comparison[:additions][:when_to_use]).to be_nil
      end
    end
  end

  describe "line-by-line diff generation" do
    let(:original) { "Line 1\nLine 2\nLine 3" }
    let(:modified) { "Line 1\nModified\nLine 3\nLine 4" }

    it "identifies matching lines as context" do
      diff = differ.diff(original, modified)

      context_lines = diff[:lines].select { |l| l[:type] == :context }
      expect(context_lines.map { |l| l[:line] }).to include("Line 1", "Line 3")
    end

    it "identifies removed lines" do
      diff = differ.diff(original, modified)

      removed_lines = diff[:lines].select { |l| l[:type] == :remove }
      expect(removed_lines.map { |l| l[:line] }).to include("Line 2")
    end

    it "identifies added lines" do
      diff = differ.diff(original, modified)

      added_lines = diff[:lines].select { |l| l[:type] == :add }
      expect(added_lines.map { |l| l[:line] }).to include("Modified", "Line 4")
    end

    it "handles additions at the end" do
      original_text = "Line 1"
      modified_text = "Line 1\nLine 2"

      diff = differ.diff(original_text, modified_text)

      added_lines = diff[:lines].select { |l| l[:type] == :add }
      expect(added_lines.size).to eq(1)
      expect(added_lines.first[:line]).to eq("Line 2")
    end

    it "handles removals at the end" do
      original_text = "Line 1\nLine 2"
      modified_text = "Line 1"

      diff = differ.diff(original_text, modified_text)

      removed_lines = diff[:lines].select { |l| l[:type] == :remove }
      expect(removed_lines.size).to eq(1)
      expect(removed_lines.first[:line]).to eq("Line 2")
    end
  end
end
