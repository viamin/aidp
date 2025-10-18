# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/skills/skill"

RSpec.describe Aidp::Skills::Skill do
  let(:valid_attributes) do
    {
      id: "test_skill",
      name: "Test Skill",
      description: "A test skill for testing",
      version: "1.0.0",
      expertise: ["testing", "validation"],
      keywords: ["test", "spec"],
      when_to_use: ["Testing the system"],
      when_not_to_use: ["Production use"],
      compatible_providers: ["anthropic", "openai"],
      content: "# Test Skill\n\nThis is a test skill.",
      source_path: "/path/to/skill.md"
    }
  end

  describe "#initialize" do
    it "creates a skill with valid attributes" do
      skill = described_class.new(**valid_attributes)

      expect(skill.id).to eq("test_skill")
      expect(skill.name).to eq("Test Skill")
      expect(skill.description).to eq("A test skill for testing")
      expect(skill.version).to eq("1.0.0")
      expect(skill.expertise).to eq(["testing", "validation"])
      expect(skill.keywords).to eq(["test", "spec"])
      expect(skill.when_to_use).to eq(["Testing the system"])
      expect(skill.when_not_to_use).to eq(["Production use"])
      expect(skill.compatible_providers).to eq(["anthropic", "openai"])
      expect(skill.content).to include("Test Skill")
      expect(skill.source_path).to eq("/path/to/skill.md")
    end

    it "converts arrays to arrays for optional fields" do
      skill = described_class.new(
        **valid_attributes.merge(
          expertise: "single expertise",
          keywords: "single keyword"
        )
      )

      expect(skill.expertise).to eq(["single expertise"])
      expect(skill.keywords).to eq(["single keyword"])
    end

    context "validation" do
      it "raises error when id is missing" do
        expect {
          described_class.new(**valid_attributes.merge(id: nil))
        }.to raise_error(Aidp::Errors::ValidationError, /id is required/)
      end

      it "raises error when id is empty" do
        expect {
          described_class.new(**valid_attributes.merge(id: ""))
        }.to raise_error(Aidp::Errors::ValidationError, /id is required/)
      end

      it "raises error when name is missing" do
        expect {
          described_class.new(**valid_attributes.merge(name: nil))
        }.to raise_error(Aidp::Errors::ValidationError, /name is required/)
      end

      it "raises error when description is missing" do
        expect {
          described_class.new(**valid_attributes.merge(description: nil))
        }.to raise_error(Aidp::Errors::ValidationError, /description is required/)
      end

      it "raises error when version is missing" do
        expect {
          described_class.new(**valid_attributes.merge(version: nil))
        }.to raise_error(Aidp::Errors::ValidationError, /version is required/)
      end

      it "raises error when content is missing" do
        expect {
          described_class.new(**valid_attributes.merge(content: nil))
        }.to raise_error(Aidp::Errors::ValidationError, /content is required/)
      end

      it "raises error when source_path is missing" do
        expect {
          described_class.new(**valid_attributes.merge(source_path: nil))
        }.to raise_error(Aidp::Errors::ValidationError, /source_path is required/)
      end

      it "raises error when version format is invalid" do
        expect {
          described_class.new(**valid_attributes.merge(version: "invalid"))
        }.to raise_error(Aidp::Errors::ValidationError, /version must be in format X.Y.Z/)
      end

      it "raises error when id contains uppercase letters" do
        expect {
          described_class.new(**valid_attributes.merge(id: "TestSkill"))
        }.to raise_error(Aidp::Errors::ValidationError, /id must be lowercase/)
      end

      it "raises error when id contains spaces" do
        expect {
          described_class.new(**valid_attributes.merge(id: "test skill"))
        }.to raise_error(Aidp::Errors::ValidationError, /id must be lowercase/)
      end

      it "accepts id with underscores" do
        expect {
          described_class.new(**valid_attributes.merge(id: "test_skill_name"))
        }.not_to raise_error
      end
    end
  end

  describe "#compatible_with?" do
    let(:skill) { described_class.new(**valid_attributes) }

    it "returns true for compatible provider" do
      expect(skill.compatible_with?("anthropic")).to be true
      expect(skill.compatible_with?("openai")).to be true
    end

    it "returns false for incompatible provider" do
      expect(skill.compatible_with?("cursor")).to be false
      expect(skill.compatible_with?("unknown")).to be false
    end

    it "is case-insensitive" do
      expect(skill.compatible_with?("ANTHROPIC")).to be true
      expect(skill.compatible_with?("Anthropic")).to be true
    end

    it "returns true when no providers specified (all compatible)" do
      skill_any_provider = described_class.new(
        **valid_attributes.merge(compatible_providers: [])
      )

      expect(skill_any_provider.compatible_with?("anthropic")).to be true
      expect(skill_any_provider.compatible_with?("cursor")).to be true
      expect(skill_any_provider.compatible_with?("anything")).to be true
    end
  end

  describe "#matches?" do
    let(:skill) { described_class.new(**valid_attributes) }

    it "matches by id" do
      expect(skill.matches?("test_skill")).to be true
      expect(skill.matches?("test")).to be true
    end

    it "matches by name" do
      expect(skill.matches?("Test Skill")).to be true
      expect(skill.matches?("Skill")).to be true
    end

    it "matches by description" do
      expect(skill.matches?("testing")).to be true
    end

    it "matches by keywords" do
      expect(skill.matches?("test")).to be true
      expect(skill.matches?("spec")).to be true
    end

    it "matches by expertise" do
      expect(skill.matches?("validation")).to be true
    end

    it "is case-insensitive" do
      expect(skill.matches?("TEST")).to be true
      expect(skill.matches?("VALIDATION")).to be true
    end

    it "returns false for non-matching query" do
      expect(skill.matches?("nonexistent")).to be false
    end

    it "returns true for nil or empty query" do
      expect(skill.matches?(nil)).to be true
      expect(skill.matches?("")).to be true
      expect(skill.matches?("  ")).to be true
    end
  end

  describe "#summary" do
    let(:skill) { described_class.new(**valid_attributes) }

    it "returns a summary hash" do
      summary = skill.summary

      expect(summary[:id]).to eq("test_skill")
      expect(summary[:name]).to eq("Test Skill")
      expect(summary[:description]).to eq("A test skill for testing")
      expect(summary[:version]).to eq("1.0.0")
      expect(summary[:expertise_areas]).to eq(2)
      expect(summary[:keywords]).to eq(["test", "spec"])
      expect(summary[:providers]).to eq("anthropic, openai")
    end

    it "shows 'all' for providers when empty" do
      skill = described_class.new(**valid_attributes.merge(compatible_providers: []))
      summary = skill.summary

      expect(summary[:providers]).to eq("all")
    end
  end

  describe "#details" do
    let(:skill) { described_class.new(**valid_attributes) }

    it "returns detailed information" do
      details = skill.details

      expect(details[:id]).to eq("test_skill")
      expect(details[:name]).to eq("Test Skill")
      expect(details[:description]).to eq("A test skill for testing")
      expect(details[:version]).to eq("1.0.0")
      expect(details[:expertise]).to eq(["testing", "validation"])
      expect(details[:keywords]).to eq(["test", "spec"])
      expect(details[:when_to_use]).to eq(["Testing the system"])
      expect(details[:when_not_to_use]).to eq(["Production use"])
      expect(details[:compatible_providers]).to eq(["anthropic", "openai"])
      expect(details[:source]).to eq("/path/to/skill.md")
      expect(details[:content_length]).to be > 0
    end
  end

  describe "#to_s" do
    let(:skill) { described_class.new(**valid_attributes) }

    it "returns a string representation" do
      expect(skill.to_s).to eq("Skill[test_skill](Test Skill v1.0.0)")
    end
  end

  describe "#inspect" do
    let(:skill) { described_class.new(**valid_attributes) }

    it "returns an inspection string" do
      expect(skill.inspect).to include("Aidp::Skills::Skill")
      expect(skill.inspect).to include("id=test_skill")
      expect(skill.inspect).to include("name=\"Test Skill\"")
      expect(skill.inspect).to include("version=1.0.0")
      expect(skill.inspect).to include("source=/path/to/skill.md")
    end
  end
end
