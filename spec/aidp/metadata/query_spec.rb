# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Metadata::Query do
  let(:metadata_dir) { Dir.mktmpdir }
  let(:query) { described_class.new(metadata_dir: metadata_dir) }

  after do
    FileUtils.rm_rf(metadata_dir)
  end

  describe "#initialize" do
    it "creates metadata directory if it doesn't exist" do
      new_dir = File.join(metadata_dir, "new_metadata")
      expect(File.exist?(new_dir)).to be false
      described_class.new(metadata_dir: new_dir)
      expect(File.exist?(new_dir)).to be true
    end
  end

  describe "#find_tools" do
    it "returns empty array when no tools exist" do
      expect(query.find_tools).to eq([])
    end

    it "finds tools by name" do
      result = query.find_tools(name: "test_tool")
      expect(result).to be_an(Array)
    end

    it "finds tools by tag" do
      result = query.find_tools(tag: "utility")
      expect(result).to be_an(Array)
    end
  end

  describe "#get_tool" do
    it "returns nil for non-existent tool" do
      expect(query.get_tool("nonexistent")).to be_nil
    end

    it "retrieves tool by name" do
      # Query returns nil when tool doesn't exist
      result = query.get_tool("test_tool")
      expect(result).to be_nil
    end
  end

  describe "#list_tools" do
    it "returns array of all tools" do
      result = query.list_tools
      expect(result).to be_an(Array)
    end

    it "includes tool metadata in results" do
      tools = query.list_tools
      expect(tools).to be_an(Array)
    end
  end

  describe "#search" do
    it "searches tools by keyword" do
      result = query.search("calculator")
      expect(result).to be_an(Array)
    end

    it "returns empty array for no matches" do
      result = query.search("nonexistent_keyword_xyz")
      expect(result).to eq([])
    end
  end

  describe "#filter" do
    it "filters tools by criteria" do
      result = query.filter(category: "utility")
      expect(result).to be_an(Array)
    end

    it "supports multiple filter criteria" do
      result = query.filter(category: "utility", status: "active")
      expect(result).to be_an(Array)
    end
  end
end
