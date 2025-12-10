# frozen_string_literal: true

require "spec_helper"
require "aidp/security"

RSpec.describe Aidp::Security::TrifectaState do
  subject(:state) { described_class.new(work_unit_id: "test_unit") }

  describe "#initialize" do
    it "starts with all flags disabled" do
      expect(state.untrusted_input).to be false
      expect(state.private_data).to be false
      expect(state.egress).to be false
    end

    it "generates a work_unit_id if not provided" do
      state = described_class.new
      expect(state.work_unit_id).to match(/^[a-f0-9]+$/)
    end

    it "stores provided work_unit_id" do
      expect(state.work_unit_id).to eq("test_unit")
    end
  end

  describe "#enable" do
    it "enables untrusted_input flag" do
      state.enable(:untrusted_input, source: "github_issue")
      expect(state.untrusted_input).to be true
      expect(state.untrusted_input_source).to eq("github_issue")
    end

    it "enables private_data flag" do
      state.enable(:private_data, source: "env_var")
      expect(state.private_data).to be true
      expect(state.private_data_source).to eq("env_var")
    end

    it "enables egress flag" do
      state.enable(:egress, source: "git_push")
      expect(state.egress).to be true
      expect(state.egress_source).to eq("git_push")
    end

    it "raises ArgumentError for unknown flag" do
      expect { state.enable(:unknown) }.to raise_error(ArgumentError, /Unknown trifecta flag/)
    end

    it "allows enabling two flags" do
      state.enable(:untrusted_input, source: "issue")
      expect { state.enable(:egress, source: "push") }.not_to raise_error
      expect(state.untrusted_input).to be true
      expect(state.egress).to be true
    end

    it "allows method chaining" do
      result = state.enable(:untrusted_input, source: "test")
      expect(result).to be(state)
    end
  end

  describe "#would_create_trifecta?" do
    context "when no flags are enabled" do
      it "returns false for any flag" do
        expect(state.would_create_trifecta?(:untrusted_input)).to be false
        expect(state.would_create_trifecta?(:private_data)).to be false
        expect(state.would_create_trifecta?(:egress)).to be false
      end
    end

    context "when one flag is enabled" do
      it "returns false for any other flag" do
        state.enable(:untrusted_input, source: "test")
        expect(state.would_create_trifecta?(:private_data)).to be false
        expect(state.would_create_trifecta?(:egress)).to be false
      end
    end

    context "when two flags are enabled" do
      it "returns true for the third flag" do
        state.enable(:untrusted_input, source: "issue")
        state.enable(:private_data, source: "env")
        expect(state.would_create_trifecta?(:egress)).to be true
      end

      it "returns false for already enabled flags" do
        state.enable(:untrusted_input, source: "issue")
        state.enable(:private_data, source: "env")
        expect(state.would_create_trifecta?(:untrusted_input)).to be false
        expect(state.would_create_trifecta?(:private_data)).to be false
      end
    end
  end

  describe "#lethal_trifecta?" do
    it "returns false when no flags enabled" do
      expect(state.lethal_trifecta?).to be false
    end

    it "returns false when one flag enabled" do
      state.enable(:untrusted_input, source: "test")
      expect(state.lethal_trifecta?).to be false
    end

    it "returns false when two flags enabled" do
      state.enable(:untrusted_input, source: "issue")
      state.enable(:private_data, source: "env")
      expect(state.lethal_trifecta?).to be false
    end
  end

  describe "policy violation" do
    it "raises PolicyViolation when enabling third flag would create trifecta" do
      state.enable(:untrusted_input, source: "github_issue")
      state.enable(:private_data, source: "env_var")

      expect {
        state.enable(:egress, source: "git_push")
      }.to raise_error(Aidp::Security::PolicyViolation)
    end

    it "includes detailed message in PolicyViolation" do
      state.enable(:untrusted_input, source: "github_issue")
      state.enable(:private_data, source: "env_var")

      begin
        state.enable(:egress, source: "git_push")
      rescue Aidp::Security::PolicyViolation => e
        expect(e.message).to include("Rule of Two violation")
        expect(e.message).to include("egress")
        expect(e.message).to include("git_push")
        expect(e.flag).to eq(:egress)
        expect(e.source).to eq("git_push")
      end
    end
  end

  describe "#disable" do
    it "disables a flag" do
      state.enable(:untrusted_input, source: "test")
      state.disable(:untrusted_input)
      expect(state.untrusted_input).to be false
      expect(state.untrusted_input_source).to be_nil
    end

    it "allows enabling third flag after disabling one" do
      state.enable(:untrusted_input, source: "issue")
      state.enable(:private_data, source: "env")
      state.disable(:private_data)

      expect { state.enable(:egress, source: "push") }.not_to raise_error
    end
  end

  describe "#enabled_count" do
    it "returns 0 when no flags enabled" do
      expect(state.enabled_count).to eq(0)
    end

    it "returns 1 when one flag enabled" do
      state.enable(:untrusted_input, source: "test")
      expect(state.enabled_count).to eq(1)
    end

    it "returns 2 when two flags enabled" do
      state.enable(:untrusted_input, source: "issue")
      state.enable(:egress, source: "push")
      expect(state.enabled_count).to eq(2)
    end
  end

  describe "#freeze!" do
    it "prevents further modifications" do
      state.enable(:untrusted_input, source: "test")
      state.freeze!

      expect { state.enable(:egress, source: "push") }
        .to raise_error(Aidp::Security::FrozenStateError)
    end

    it "marks state as frozen" do
      state.freeze!
      expect(state.frozen?).to be true
    end
  end

  describe "#to_h" do
    it "exports state as hash" do
      state.enable(:untrusted_input, source: "issue")

      hash = state.to_h

      expect(hash[:work_unit_id]).to eq("test_unit")
      expect(hash[:untrusted_input]).to be true
      expect(hash[:untrusted_input_source]).to eq("issue")
      expect(hash[:private_data]).to be false
      expect(hash[:egress]).to be false
      expect(hash[:enabled_count]).to eq(1)
      expect(hash[:lethal_trifecta]).to be false
    end
  end

  describe "#status_string" do
    it "returns safe message when no flags enabled" do
      expect(state.status_string).to include("No flags enabled")
    end

    it "returns enabled flags info when flags are enabled" do
      state.enable(:untrusted_input, source: "issue")
      expect(state.status_string).to include("untrusted_input")
      expect(state.status_string).to include("1/3")
    end
  end
end
