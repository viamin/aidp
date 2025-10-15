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
end
