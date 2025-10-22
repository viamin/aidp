# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/skills/wizard/builder"
require_relative "../../../../lib/aidp/skills/skill"

RSpec.describe Aidp::Skills::Wizard::Builder do
  describe "#build" do
    context "without a base skill" do
      let(:builder) { described_class.new }
      let(:responses) do
        {
          id: "test_skill",
          name: "Test Skill",
          description: "A test skill for testing",
          version: "1.0.0",
          expertise: ["testing", "ruby"],
          keywords: ["test", "spec"],
          when_to_use: ["When writing tests"],
          when_not_to_use: ["When not testing"],
          compatible_providers: ["anthropic"],
          content: "You are a test skill."
        }
      end

      it "builds a skill from responses" do
        skill = builder.build(responses)

        expect(skill).to be_a(Aidp::Skills::Skill)
        expect(skill.id).to eq("test_skill")
        expect(skill.name).to eq("Test Skill")
        expect(skill.description).to eq("A test skill for testing")
        expect(skill.version).to eq("1.0.0")
      end

      it "sets expertise and keywords" do
        skill = builder.build(responses)

        expect(skill.expertise).to eq(["testing", "ruby"])
        expect(skill.keywords).to eq(["test", "spec"])
      end

      it "sets when_to_use and when_not_to_use" do
        skill = builder.build(responses)

        expect(skill.when_to_use).to eq(["When writing tests"])
        expect(skill.when_not_to_use).to eq(["When not testing"])
      end

      it "sets compatible_providers" do
        skill = builder.build(responses)

        expect(skill.compatible_providers).to eq(["anthropic"])
      end

      it "sets content" do
        skill = builder.build(responses)

        expect(skill.content).to eq("You are a test skill.")
      end

      it "defaults version to 1.0.0 if not provided" do
        responses_without_version = responses.dup
        responses_without_version.delete(:version)

        skill = builder.build(responses_without_version)

        expect(skill.version).to eq("1.0.0")
      end
    end

    context "with a base skill" do
      let(:base_skill) do
        Aidp::Skills::Skill.new(
          id: "base_skill",
          name: "Base Skill",
          description: "A base skill",
          version: "1.0.0",
          expertise: ["base", "foundation"],
          keywords: ["base"],
          when_to_use: ["Always"],
          when_not_to_use: ["Never"],
          compatible_providers: ["anthropic", "openai"],
          content: "You are a base skill.",
          source_path: "/tmp/base.md"
        )
      end

      let(:builder) { described_class.new(base_skill: base_skill) }

      let(:responses) do
        {
          id: "derived_skill",
          name: "Derived Skill",
          description: "A derived skill",
          expertise: ["derived"],
          keywords: ["new"]
        }
      end

      it "merges expertise from base and responses" do
        skill = builder.build(responses)

        expect(skill.expertise).to include("base", "foundation", "derived")
      end

      it "merges keywords from base and responses" do
        skill = builder.build(responses)

        expect(skill.keywords).to include("base", "new")
      end

      it "merges when_to_use from base and responses" do
        responses_with_when = responses.merge(when_to_use: ["Sometimes"])
        skill = builder.build(responses_with_when)

        expect(skill.when_to_use).to include("Always", "Sometimes")
      end

      it "uses base content if not provided in responses" do
        skill = builder.build(responses)

        expect(skill.content).to eq("You are a base skill.")
      end

      it "overrides content if provided in responses" do
        responses_with_content = responses.merge(content: "You are derived.")
        skill = builder.build(responses_with_content)

        expect(skill.content).to eq("You are derived.")
      end

      it "uses base compatible_providers if not provided" do
        skill = builder.build(responses)

        expect(skill.compatible_providers).to eq(["anthropic", "openai"])
      end

      it "overrides compatible_providers if provided" do
        responses_with_providers = responses.merge(compatible_providers: ["cursor"])
        skill = builder.build(responses_with_providers)

        expect(skill.compatible_providers).to eq(["cursor"])
      end

      it "deduplicates merged arrays" do
        responses_with_duplicates = responses.merge(
          expertise: ["base", "new"],  # "base" is duplicate
          keywords: ["base", "another"]  # "base" is duplicate
        )

        skill = builder.build(responses_with_duplicates)

        expect(skill.expertise.count("base")).to eq(1)
        expect(skill.keywords.count("base")).to eq(1)
      end
    end
  end

  describe "#to_skill_md" do
    let(:builder) { described_class.new }
    let(:skill) do
      Aidp::Skills::Skill.new(
        id: "test_skill",
        name: "Test Skill",
        description: "A test skill",
        version: "1.0.0",
        expertise: ["testing"],
        keywords: ["test"],
        when_to_use: ["When testing"],
        when_not_to_use: ["When not testing"],
        compatible_providers: ["anthropic"],
        content: "You are a test skill.",
        source_path: "/tmp/test.md"
      )
    end

    it "generates valid SKILL.md content" do
      content = builder.to_skill_md(skill)

      expect(content).to start_with("---\n")
      expect(content).to include("id: test_skill")
      expect(content).to include("name: Test Skill")
      expect(content).to include("description: A test skill")
      expect(content).to include("version: 1.0.0")
      expect(content).to end_with("You are a test skill.")
    end

    it "includes expertise array" do
      content = builder.to_skill_md(skill)

      expect(content).to include("expertise:")
      expect(content).to include("- testing")
    end

    it "includes keywords array" do
      content = builder.to_skill_md(skill)

      expect(content).to include("keywords:")
      expect(content).to include("- test")
    end

    it "includes when_to_use array" do
      content = builder.to_skill_md(skill)

      expect(content).to include("when_to_use:")
      expect(content).to include("- When testing")
    end

    it "includes when_not_to_use array" do
      content = builder.to_skill_md(skill)

      expect(content).to include("when_not_to_use:")
      expect(content).to include("- When not testing")
    end

    it "includes compatible_providers array" do
      content = builder.to_skill_md(skill)

      expect(content).to include("compatible_providers:")
      expect(content).to include("- anthropic")
    end

    it "omits empty arrays" do
      minimal_skill = Aidp::Skills::Skill.new(
        id: "minimal",
        name: "Minimal",
        description: "Minimal skill",
        version: "1.0.0",
        content: "Content.",
        source_path: "/tmp/minimal.md"
      )

      content = builder.to_skill_md(minimal_skill)

      expect(content).not_to include("expertise:")
      expect(content).not_to include("keywords:")
      expect(content).not_to include("when_to_use:")
      expect(content).not_to include("when_not_to_use:")
      expect(content).not_to include("compatible_providers:")
    end

    it "produces valid YAML frontmatter" do
      content = builder.to_skill_md(skill)

      # Extract frontmatter
      lines = content.lines
      frontmatter_lines = []
      in_frontmatter = false

      lines.each do |line|
        if line.strip == "---"
          if in_frontmatter
            break
          else
            in_frontmatter = true
            next
          end
        end

        frontmatter_lines << line if in_frontmatter
      end

      # Parse YAML to verify it's valid
      yaml_content = frontmatter_lines.join
      parsed = YAML.safe_load(yaml_content, permitted_classes: [Symbol])

      expect(parsed).to be_a(Hash)
      expect(parsed["id"]).to eq("test_skill")
    end
  end
end
