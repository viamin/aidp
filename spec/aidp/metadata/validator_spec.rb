# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Metadata::Validator do
  let(:validator) { described_class.new }

  describe "#validate" do
    it "validates complete metadata" do
      metadata = {
        name: "test_tool",
        description: "Test description",
        parameters: {},
        tags: []
      }

      result = validator.validate(metadata)
      expect(result[:valid]).to be true
    end

    it "rejects metadata with missing name" do
      metadata = {
        description: "Test description"
      }

      result = validator.validate(metadata)
      expect(result[:valid]).to be false
      expect(result[:errors]).to include(/name/i)
    end

    it "rejects metadata with empty name" do
      metadata = {
        name: "",
        description: "Test"
      }

      result = validator.validate(metadata)
      expect(result[:valid]).to be false
    end
  end

  describe "#validate_name" do
    it "accepts valid names" do
      expect(validator.validate_name("test_tool")).to be true
      expect(validator.validate_name("calculator_v2")).to be true
    end

    it "rejects invalid names" do
      expect(validator.validate_name("")).to be false
      expect(validator.validate_name(nil)).to be false
      expect(validator.validate_name("invalid name")).to be false
    end

    it "rejects names with special characters" do
      expect(validator.validate_name("tool@name")).to be false
      expect(validator.validate_name("tool name")).to be false
    end
  end

  describe "#validate_parameters" do
    it "accepts valid parameter definitions" do
      params = {
        x: {type: "Integer", description: "First number"},
        y: {type: "Integer", description: "Second number"}
      }

      expect(validator.validate_parameters(params)).to be true
    end

    it "accepts empty parameters" do
      expect(validator.validate_parameters({})).to be true
    end

    it "rejects invalid parameter structure" do
      params = {x: "invalid"}
      expect(validator.validate_parameters(params)).to be false
    end
  end

  describe "#validate_tags" do
    it "accepts array of tags" do
      expect(validator.validate_tags(["utility", "math"])).to be true
    end

    it "accepts empty tag array" do
      expect(validator.validate_tags([])).to be true
    end

    it "rejects non-array tags" do
      expect(validator.validate_tags("tag")).to be false
      expect(validator.validate_tags({tag: "value"})).to be false
    end

    it "rejects invalid tag names" do
      expect(validator.validate_tags(["valid", "invalid tag"])).to be false
    end
  end

  describe "#errors" do
    it "returns empty array for valid metadata" do
      metadata = {
        name: "test_tool",
        description: "Test"
      }

      validator.validate(metadata)
      expect(validator.errors).to be_empty
    end

    it "returns array of error messages for invalid metadata" do
      metadata = {description: "Test"}
      validator.validate(metadata)
      expect(validator.errors).not_to be_empty
    end
  end
end
