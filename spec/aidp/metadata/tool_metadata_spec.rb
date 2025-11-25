# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Metadata::ToolMetadata do
  describe ".from_hash" do
    it "creates instance from hash" do
      hash = {
        name: "test_tool",
        description: "Test tool",
        parameters: {},
        tags: ["test"]
      }

      metadata = described_class.from_hash(hash)
      expect(metadata).to be_a(described_class)
      expect(metadata.name).to eq("test_tool")
    end

    it "handles missing optional fields" do
      hash = {name: "minimal_tool"}
      metadata = described_class.from_hash(hash)
      expect(metadata.name).to eq("minimal_tool")
    end
  end

  describe "#initialize" do
    it "accepts name and description" do
      metadata = described_class.new(
        name: "calculator",
        description: "Performs calculations"
      )

      expect(metadata.name).to eq("calculator")
      expect(metadata.description).to eq("Performs calculations")
    end

    it "accepts optional parameters" do
      metadata = described_class.new(
        name: "tool",
        parameters: {x: "Integer", y: "Integer"}
      )

      expect(metadata.parameters).to eq({x: "Integer", y: "Integer"})
    end

    it "accepts tags" do
      metadata = described_class.new(
        name: "tool",
        tags: ["utility", "math"]
      )

      expect(metadata.tags).to contain_exactly("utility", "math")
    end
  end

  describe "#to_h" do
    it "converts to hash representation" do
      metadata = described_class.new(
        name: "test_tool",
        description: "Test description",
        tags: ["test"]
      )

      hash = metadata.to_h
      expect(hash).to be_a(Hash)
      expect(hash[:name]).to eq("test_tool")
      expect(hash[:description]).to eq("Test description")
    end

    it "includes all fields in hash" do
      metadata = described_class.new(
        name: "tool",
        description: "desc",
        parameters: {x: "String"},
        tags: ["tag1"]
      )

      hash = metadata.to_h
      expect(hash.keys).to include(:name, :description, :parameters, :tags)
    end
  end

  describe "#valid?" do
    it "returns true for valid metadata" do
      metadata = described_class.new(
        name: "valid_tool",
        description: "Valid description"
      )

      expect(metadata.valid?).to be true
    end

    it "returns false for missing required fields" do
      metadata = described_class.new(name: "")
      expect(metadata.valid?).to be false
    end
  end

  describe "#add_parameter" do
    it "adds parameter to metadata" do
      metadata = described_class.new(name: "tool")
      metadata.add_parameter("x", type: "Integer", description: "First number")

      expect(metadata.parameters).to have_key("x")
    end
  end

  describe "#add_tag" do
    it "adds tag to metadata" do
      metadata = described_class.new(name: "tool", tags: [])
      metadata.add_tag("utility")

      expect(metadata.tags).to include("utility")
    end

    it "doesn't duplicate tags" do
      metadata = described_class.new(name: "tool", tags: ["utility"])
      metadata.add_tag("utility")

      expect(metadata.tags.count("utility")).to eq(1)
    end
  end
end
