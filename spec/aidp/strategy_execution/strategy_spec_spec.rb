# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::StrategyExecution::StrategySpec do
  describe ".from_hash" do
    it "normalizes strategy data" do
      spec = described_class.from_hash(
        "name" => "recursive_pr_builder_v3",
        "max_depth" => 4,
        "fanout" => 3,
        "agents" => {
          "coder" => [
            {"name" => "fast", "command" => "bin/fast-agent"},
            {"name" => "deep", "command" => "bin/deep-agent"}
          ]
        },
        "evaluators" => [
          {"name" => "tests", "command" => "bin/test-evaluator"}
        ]
      )

      expect(spec.name).to eq("recursive_pr_builder_v3")
      expect(spec.max_depth).to eq(4)
      expect(spec.fanout).to eq(3)
      expect(spec.branch_commands.length).to eq(3)
      expect(spec.branch_commands.first[:command]).to eq("bin/fast-agent")
      expect(spec.branch_commands.last[:command]).to eq("bin/fast-agent")
      expect(spec.evaluator_definitions.first[:name]).to eq("tests")
    end

    it "requires a name" do
      expect {
        described_class.from_hash({})
      }.to raise_error(ArgumentError, /strategy name/)
    end

    it "builds branch commands for a single normalized agent hash" do
      spec = described_class.from_hash(
        "name" => "fanout",
        "fanout" => 2,
        "agents" => {"coder" => "bin/coder"}
      )

      expect(spec.branch_commands).to eq(
        [
          {key: "branch_0", name: "coder", command: "bin/coder"},
          {key: "branch_1", name: "coder", command: "bin/coder"}
        ]
      )
    end

    it "rejects strategies with no runnable agent commands" do
      expect {
        described_class.from_hash(
          "name" => "empty",
          "agents" => {"planner" => ""}
        )
      }.to raise_error(ArgumentError, /requires at least one agent with a non-empty command/)
    end

    it "rejects strategies with an empty agent map" do
      expect {
        described_class.from_hash(
          "name" => "empty",
          "agents" => {}
        )
      }.to raise_error(ArgumentError, /requires at least one agent with a non-empty command/)
    end
  end
end
