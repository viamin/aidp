# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../../lib/aidp/skills/wizard/prompter"
require_relative "../../../../lib/aidp/skills/wizard/template_library"

RSpec.describe Aidp::Skills::Wizard::Prompter do
  let(:prompter) { described_class.new }
  let(:temp_dir) { Dir.mktmpdir }
  let(:template_library) { Aidp::Skills::Wizard::TemplateLibrary.new(project_dir: temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "creates a TTY::Prompt instance" do
      expect(prompter.prompt).to be_a(TTY::Prompt)
    end

    it "stores the prompt as an instance variable" do
      expect(prompter.instance_variable_get(:@prompt)).to be_a(TTY::Prompt)
    end
  end

  describe "#gather_responses" do
    context "with from_template option" do
      it "raises error if template not found" do
        options = {from_template: "nonexistent_template"}
        expect {
          prompter.gather_responses(template_library, options: options)
        }.to raise_error(Aidp::Errors::ValidationError, /Template not found/)
      end

      it "includes validation error message" do
        options = {from_template: "missing"}
        begin
          prompter.gather_responses(template_library, options: options)
        rescue Aidp::Errors::ValidationError => e
          expect(e.message).to include("missing")
        end
      end
    end

    context "with clone option" do
      it "raises error if skill not found" do
        options = {clone: "nonexistent_skill"}
        expect {
          prompter.gather_responses(template_library, options: options)
        }.to raise_error(Aidp::Errors::ValidationError, /Skill not found/)
      end

      it "includes skill ID in error message" do
        options = {clone: "missing_skill"}
        begin
          prompter.gather_responses(template_library, options: options)
        rescue Aidp::Errors::ValidationError => e
          expect(e.message).to include("missing_skill")
        end
      end
    end
  end

  describe "private methods" do
    describe "#slugify" do
      it "converts text to lowercase slug" do
        slug = prompter.send(:slugify, "My Test Skill")
        expect(slug).to eq("my_test_skill")
      end

      it "handles multiple spaces" do
        slug = prompter.send(:slugify, "Test    Multiple    Spaces")
        expect(slug).to match(/test.*multiple.*spaces/)
      end

      it "removes special characters" do
        slug = prompter.send(:slugify, "Test@#$%Skill!")
        expect(slug).not_to include("@", "#", "$", "%", "!")
      end

      it "handles hyphens and underscores" do
        slug = prompter.send(:slugify, "test-with_hyphens")
        expect(slug).to include("_")
      end

      it "squeezes multiple underscores" do
        slug = prompter.send(:slugify, "test___multiple___underscores")
        expect(slug).not_to include("___")
      end
    end

    describe "#generate_default_content" do
      it "generates markdown template with skill name" do
        content = prompter.send(:generate_default_content, "Test Skill")
        expect(content).to include("# Test Skill")
      end

      it "includes core capabilities section" do
        content = prompter.send(:generate_default_content, "My Skill")
        expect(content).to include("## Your Core Capabilities")
      end

      it "includes approach section" do
        content = prompter.send(:generate_default_content, "Another Skill")
        expect(content).to include("## Your Approach")
      end

      it "uses skill name in description" do
        content = prompter.send(:generate_default_content, "Database Expert")
        expect(content).to include("Database Expert")
      end

      it "returns valid markdown" do
        content = prompter.send(:generate_default_content, "Test")
        expect(content).to start_with("#")
        expect(content).to include("-")
      end
    end

    describe "#prompt_content" do
      let(:base_skill) do
        double(
          "Skill",
          name: "Base Skill",
          content: "# Base Content\n\nInherited content"
        )
      end

      context "without base skill" do
        it "prompts for custom content" do
          allow(prompter).to receive(:prompt_custom_content).and_return("Custom content")
          result = prompter.send(:prompt_content, "New Skill", nil)
          expect(result).to eq("Custom content")
        end
      end

      context "with base skill" do
        it "returns base content when user declines customization" do
          allow(prompter.prompt).to receive(:say)
          allow(prompter.prompt).to receive(:yes?).and_return(false)
          result = prompter.send(:prompt_content, "New Skill", base_skill)
          expect(result).to eq(base_skill.content)
        end

        it "prompts for custom content when user accepts customization" do
          allow(prompter.prompt).to receive(:say)
          allow(prompter.prompt).to receive(:yes?).and_return(true)
          allow(prompter).to receive(:prompt_custom_content).and_return("Customized content")
          result = prompter.send(:prompt_content, "New Skill", base_skill)
          expect(result).to eq("Customized content")
        end
      end
    end

    describe "#prompt_custom_content" do
      it "returns user-provided content when lines are entered" do
        allow(prompter.prompt).to receive(:say)
        allow(prompter.prompt).to receive(:multiline).and_return(["Line 1", "Line 2"])
        result = prompter.send(:prompt_custom_content, "Test Skill")
        expect(result).to eq("Line 1\nLine 2")
      end

      it "returns default content when no lines are entered" do
        allow(prompter.prompt).to receive(:say)
        allow(prompter.prompt).to receive(:multiline).and_return([])
        result = prompter.send(:prompt_custom_content, "Test Skill")
        expect(result).to include("# Test Skill")
        expect(result).to include("You are a **Test Skill**")
      end
    end

    describe "#prompt_providers" do
      it "returns empty array for all providers selection" do
        allow(prompter.prompt).to receive(:select).and_return([])
        result = prompter.send(:prompt_providers)
        expect(result).to eq([])
      end

      it "returns selected provider for single selection" do
        allow(prompter.prompt).to receive(:select).and_return(["anthropic"])
        result = prompter.send(:prompt_providers)
        expect(result).to eq(["anthropic"])
      end

      it "prompts for multi-select when custom selection chosen" do
        allow(prompter.prompt).to receive(:select).and_return(:custom)
        allow(prompter.prompt).to receive(:multi_select).and_return(["anthropic", "openai"])
        result = prompter.send(:prompt_providers)
        expect(result).to eq(["anthropic", "openai"])
      end
    end
  end
end
