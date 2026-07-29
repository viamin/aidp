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
  end
end
