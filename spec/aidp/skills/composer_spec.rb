# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/skills/composer"
require_relative "../../../lib/aidp/skills/skill"

RSpec.describe Aidp::Skills::Composer do
  subject(:composer) { described_class.new }

  let(:skill) do
    instance_double(
      Aidp::Skills::Skill,
      id: "test_skill",
      name: "Test Skill",
      content: "You are a test assistant with expertise in testing."
    )
  end

  let(:template) { "Analyze the {{target}} and produce {{output}}." }

  before do
    allow(Aidp).to receive(:log_debug)
    allow(Aidp).to receive(:log_warn)
  end

  describe "#compose" do
    context "with skill and template" do
      it "composes skill content with template" do
        result = composer.compose(
          skill: skill,
          template: "Do something"
        )

        expect(result).to include("You are a test assistant")
        expect(result).to include("---")
        expect(result).to include("# Current Task")
        expect(result).to include("Do something")
      end

      it "logs composition with skill" do
        composer.compose(skill: skill, template: "Test task")

        expect(Aidp).to have_received(:log_debug).with(
          "skills",
          "Composing prompt",
          hash_including(skill_id: "test_skill")
        )
        expect(Aidp).to have_received(:log_debug).with(
          "skills",
          "Composed prompt with skill",
          hash_including(skill_id: "test_skill")
        )
      end

      it "includes separator between skill and template" do
        result = composer.compose(skill: skill, template: "Test")
        expect(result).to include("\n\n---\n\n")
      end

      it "adds 'Current Task' header" do
        result = composer.compose(skill: skill, template: "Test")
        expect(result).to include("# Current Task")
      end
    end

    context "without skill (template-only)" do
      it "returns template without skill content" do
        result = composer.compose(template: "Just do this task")

        expect(result).to eq("Just do this task")
        expect(result).not_to include("---")
      end

      it "logs template-only composition" do
        composer.compose(template: "Test task")

        expect(Aidp).to have_received(:log_debug).with(
          "skills",
          "Template-only composition",
          hash_including(template_length: "Test task".length)
        )
      end
    end

    context "with template variables" do
      it "replaces variables from options" do
        result = composer.compose(
          template: template,
          options: {target: "repository", output: "report"}
        )

        expect(result).to eq("Analyze the repository and produce report.")
      end

      it "replaces multiple occurrences of same variable" do
        result = composer.compose(
          template: "{{name}} is {{name}}",
          options: {name: "test"}
        )

        expect(result).to eq("test is test")
      end

      it "converts values to strings" do
        result = composer.compose(
          template: "Count: {{count}}",
          options: {count: 42}
        )

        expect(result).to eq("Count: 42")
      end
    end
  end

  describe "#render_template" do
    context "with no options" do
      it "returns template unchanged" do
        result = composer.render_template("Plain text")
        expect(result).to eq("Plain text")
      end

      it "does not process placeholders" do
        result = composer.render_template("{{untouched}}")
        expect(result).to eq("{{untouched}}")
      end
    end

    context "with options" do
      it "replaces single placeholder" do
        result = composer.render_template(
          "Hello {{name}}",
          options: {name: "World"}
        )
        expect(result).to eq("Hello World")
      end

      it "replaces multiple different placeholders" do
        result = composer.render_template(
          "{{greeting}} {{name}}",
          options: {greeting: "Hello", name: "World"}
        )
        expect(result).to eq("Hello World")
      end

      it "leaves unreplaced placeholders in output" do
        result = composer.render_template(
          "{{replaced}} and {{unreplaced}}",
          options: {replaced: "value"}
        )
        expect(result).to eq("value and {{unreplaced}}")
      end

      it "logs warning for unreplaced placeholders" do
        result = composer.render_template(
          "{{present}} and {{missing}}",
          options: {present: "value"}
        )

        # Verify the placeholder is still in the result
        expect(result).to eq("value and {{missing}}")
        expect(Aidp).to have_received(:log_warn).with(
          "skills",
          "Unreplaced template variables",
          hash_including(placeholders: ["missing"])
        )
      end

      it "does not log warning when all placeholders replaced" do
        composer.render_template(
          "{{name}}",
          options: {name: "value"}
        )

        expect(Aidp).not_to have_received(:log_warn)
      end
    end

    context "with UTF-8 encoding" do
      it "handles UTF-8 template" do
        result = composer.render_template(
          "Hello {{name}} 🎉",
          options: {name: "World"}
        )
        expect(result).to eq("Hello World 🎉")
      end

      it "converts non-UTF-8 template to UTF-8" do
        # Create a string with ASCII-8BIT encoding
        template = "Hello {{name}}".encode("ASCII-8BIT")
        result = composer.render_template(template, options: {name: "World"})
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq("Hello World")
      end

      it "handles strings with replacement characters" do
        # Test a template that already has replacement chars (not truly invalid)
        template = "Test � {{name}}"
        result = composer.render_template(template, options: {name: "value"})
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to include("value")
      end
    end
  end

  describe "#compose_multiple" do
    it "raises NotImplementedError" do
      expect {
        composer.compose_multiple(
          skills: [skill],
          template: "test"
        )
      }.to raise_error(NotImplementedError, /not yet supported/)
    end
  end

  describe "#preview" do
    context "with skill" do
      it "returns preview hash with skill info" do
        preview = composer.preview(
          skill: skill,
          template: "Test task {{var}}",
          options: {var: "value"}
        )

        expect(preview[:skill]).to include(
          id: "test_skill",
          name: "Test Skill",
          content: "You are a test assistant with expertise in testing."
        )
      end

      it "includes rendered template" do
        preview = composer.preview(
          skill: skill,
          template: "{{action}}",
          options: {action: "analyze"}
        )

        expect(preview[:template][:content]).to eq("analyze")
      end

      it "includes composed result" do
        preview = composer.preview(
          skill: skill,
          template: "Test"
        )

        expect(preview[:composed][:content]).to include("You are a test assistant")
        expect(preview[:composed][:content]).to include("Test")
      end

      it "includes metadata" do
        preview = composer.preview(skill: skill, template: "Test")

        expect(preview[:metadata]).to include(
          has_skill: true,
          separator_used: true
        )
      end

      it "includes unreplaced variables in metadata" do
        preview = composer.preview(
          skill: skill,
          template: "{{unreplaced}}",
          options: {}
        )

        expect(preview[:metadata][:unreplaced_vars]).to eq(["unreplaced"])
      end
    end

    context "without skill" do
      it "returns nil for skill info" do
        preview = composer.preview(template: "Test")
        expect(preview[:skill]).to be_nil
      end

      it "sets metadata flags correctly" do
        preview = composer.preview(template: "Test")

        expect(preview[:metadata]).to include(
          has_skill: false,
          separator_used: false
        )
      end
    end

    context "with template variables" do
      it "includes variable keys in template section" do
        preview = composer.preview(
          template: "{{a}} {{b}}",
          options: {a: "1", b: "2"}
        )

        expect(preview[:template][:variables]).to match_array([:a, :b])
      end
    end
  end

  describe "#extract_placeholders (private)" do
    it "extracts single placeholder" do
      result = composer.send(:extract_placeholders, "{{name}}")
      expect(result).to eq(["name"])
    end

    it "extracts multiple placeholders" do
      result = composer.send(:extract_placeholders, "{{first}} and {{second}}")
      expect(result).to eq(["first", "second"])
    end

    it "returns empty array for no placeholders" do
      result = composer.send(:extract_placeholders, "no placeholders here")
      expect(result).to eq([])
    end

    it "returns empty array for nil input" do
      result = composer.send(:extract_placeholders, nil)
      expect(result).to eq([])
    end

    it "returns empty array for empty input" do
      result = composer.send(:extract_placeholders, "")
      expect(result).to eq([])
    end

    it "ignores nested braces" do
      result = composer.send(:extract_placeholders, "{{nested{invalid}}}")
      expect(result).to eq([])
    end

    it "ignores empty placeholders" do
      result = composer.send(:extract_placeholders, "{{}}")
      expect(result).to eq([])
    end

    it "handles UTF-8 content" do
      result = composer.send(:extract_placeholders, "{{emoji}} 🎉")
      expect(result).to eq(["emoji"])
    end

    it "converts non-UTF-8 text to UTF-8" do
      text = "{{test}}".encode("ASCII-8BIT")
      result = composer.send(:extract_placeholders, text)
      expect(result).to eq(["test"])
    end

    it "handles strings with replacement characters" do
      text = "{{test}} �"
      result = composer.send(:extract_placeholders, text)
      expect(result).to eq(["test"])
    end

    it "extracts placeholders with underscores and hyphens" do
      result = composer.send(:extract_placeholders, "{{my_var}} {{my-var}}")
      expect(result).to eq(["my_var", "my-var"])
    end

    it "handles incomplete closing braces" do
      result = composer.send(:extract_placeholders, "{{incomplete")
      expect(result).to eq([])
    end
  end
end
