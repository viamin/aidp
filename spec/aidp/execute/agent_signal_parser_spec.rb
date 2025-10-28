# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/agent_signal_parser"

RSpec.describe Aidp::Execute::AgentSignalParser do
  describe ".extract_next_unit" do
    it "parses NEXT_UNIT with colon separator" do
      output = " NEXT_UNIT: run_full_tests "
      expect(described_class.extract_next_unit(output)).to eq(:run_full_tests)
    end

    it "parses NEXT_STEP with equals separator and extra whitespace" do
      output = "noise\nNext_Step   =   decide_whats_next\n"
      expect(described_class.extract_next_unit(output)).to eq(:decide_whats_next)
    end

    it "returns nil when directive is missing" do
      expect(described_class.extract_next_unit("no directive here")).to be_nil
    end
  end

  describe ".parse_task_filing" do
    it "parses single task with description only" do
      output = 'File task: "Add rate limiting to API"'
      result = described_class.parse_task_filing(output)

      expect(result.size).to eq(1)
      expect(result[0][:description]).to eq("Add rate limiting to API")
      expect(result[0][:priority]).to eq(:medium)
      expect(result[0][:tags]).to eq([])
    end

    it "parses task with priority" do
      output = 'File task: "Fix security vulnerability" priority: high'
      result = described_class.parse_task_filing(output)

      expect(result.size).to eq(1)
      expect(result[0][:description]).to eq("Fix security vulnerability")
      expect(result[0][:priority]).to eq(:high)
    end

    it "parses task with tags" do
      output = 'File task: "Update documentation" tags: docs,backend'
      result = described_class.parse_task_filing(output)

      expect(result.size).to eq(1)
      expect(result[0][:description]).to eq("Update documentation")
      expect(result[0][:tags]).to eq(["docs", "backend"])
    end

    it "parses task with priority and tags" do
      output = 'File task: "Implement OAuth flow" priority: high tags: auth,security'
      result = described_class.parse_task_filing(output)

      expect(result.size).to eq(1)
      expect(result[0][:description]).to eq("Implement OAuth flow")
      expect(result[0][:priority]).to eq(:high)
      expect(result[0][:tags]).to eq(["auth", "security"])
    end

    it "parses multiple tasks from output" do
      output = <<~TEXT
        I implemented the authentication feature.
        File task: "Add rate limiting" priority: high
        File task: "Update API docs"
        Also need to test edge cases.
        File task: "Add integration tests" priority: medium tags: testing
      TEXT

      result = described_class.parse_task_filing(output)

      expect(result.size).to eq(3)
      expect(result[0][:description]).to eq("Add rate limiting")
      expect(result[0][:priority]).to eq(:high)
      expect(result[1][:description]).to eq("Update API docs")
      expect(result[1][:priority]).to eq(:medium)
      expect(result[2][:description]).to eq("Add integration tests")
      expect(result[2][:tags]).to eq(["testing"])
    end

    it "handles case-insensitive matching" do
      output = 'FILE TASK: "Something" PRIORITY: LOW'
      result = described_class.parse_task_filing(output)

      expect(result.size).to eq(1)
      expect(result[0][:description]).to eq("Something")
      expect(result[0][:priority]).to eq(:low)
    end

    it "returns empty array when no tasks found" do
      output = "No task filing signals here"
      result = described_class.parse_task_filing(output)

      expect(result).to eq([])
    end

    it "returns empty array for nil output" do
      result = described_class.parse_task_filing(nil)
      expect(result).to eq([])
    end
  end
end
