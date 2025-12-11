# frozen_string_literal: true

require "spec_helper"
require "aidp/security"

RSpec.describe Aidp::Security::RuleOfTwoEnforcer do
  subject(:enforcer) { described_class.new }

  after do
    enforcer.reset!
  end

  describe "#begin_work_unit" do
    it "creates a new trifecta state for the work unit" do
      state = enforcer.begin_work_unit(work_unit_id: "unit_123")

      expect(state).to be_a(Aidp::Security::TrifectaState)
      expect(state.work_unit_id).to eq("unit_123")
    end

    it "returns existing state if work unit already active" do
      state1 = enforcer.begin_work_unit(work_unit_id: "unit_123")
      state2 = enforcer.begin_work_unit(work_unit_id: "unit_123")

      expect(state2).to be(state1)
    end

    it "tracks multiple work units" do
      enforcer.begin_work_unit(work_unit_id: "unit_1")
      enforcer.begin_work_unit(work_unit_id: "unit_2")

      expect(enforcer.active_count).to eq(2)
    end
  end

  describe "#end_work_unit" do
    it "returns final state summary" do
      state = enforcer.begin_work_unit(work_unit_id: "unit_123")
      state.enable(:untrusted_input, source: "test")

      summary = enforcer.end_work_unit("unit_123")

      expect(summary[:work_unit_id]).to eq("unit_123")
      expect(summary[:untrusted_input]).to be true
    end

    it "removes work unit from active tracking" do
      enforcer.begin_work_unit(work_unit_id: "unit_123")
      enforcer.end_work_unit("unit_123")

      expect(enforcer.active?("unit_123")).to be false
    end

    it "returns nil for unknown work unit" do
      result = enforcer.end_work_unit("unknown")
      expect(result).to be_nil
    end

    it "adds to completed states history" do
      enforcer.begin_work_unit(work_unit_id: "unit_123")
      enforcer.end_work_unit("unit_123")

      log = enforcer.audit_log
      expect(log.size).to eq(1)
      expect(log.first[:work_unit_id]).to eq("unit_123")
    end
  end

  describe "#state_for" do
    it "returns state for active work unit" do
      enforcer.begin_work_unit(work_unit_id: "unit_123")
      state = enforcer.state_for("unit_123")

      expect(state).to be_a(Aidp::Security::TrifectaState)
    end

    it "returns nil for unknown work unit" do
      expect(enforcer.state_for("unknown")).to be_nil
    end
  end

  describe "#active?" do
    it "returns true for active work unit" do
      enforcer.begin_work_unit(work_unit_id: "unit_123")
      expect(enforcer.active?("unit_123")).to be true
    end

    it "returns false for inactive work unit" do
      expect(enforcer.active?("unit_123")).to be false
    end
  end

  describe "#would_allow?" do
    it "returns allowed when no active work unit" do
      result = enforcer.would_allow?("unknown", :egress)
      expect(result[:allowed]).to be true
    end

    it "returns allowed when flag would not create trifecta" do
      enforcer.begin_work_unit(work_unit_id: "unit_123")
      result = enforcer.would_allow?("unit_123", :egress)

      expect(result[:allowed]).to be true
    end

    it "returns not allowed when flag would create trifecta" do
      state = enforcer.begin_work_unit(work_unit_id: "unit_123")
      state.enable(:untrusted_input, source: "issue")
      state.enable(:private_data, source: "env")

      result = enforcer.would_allow?("unit_123", :egress)

      expect(result[:allowed]).to be false
      expect(result[:reason]).to include("trifecta")
    end
  end

  describe "#enforce!" do
    it "enables flag on work unit" do
      state = enforcer.begin_work_unit(work_unit_id: "unit_123")
      enforcer.enforce!(work_unit_id: "unit_123", flag: :egress, source: "git_push")

      expect(state.egress).to be true
    end

    it "raises PolicyViolation when would create trifecta" do
      state = enforcer.begin_work_unit(work_unit_id: "unit_123")
      state.enable(:untrusted_input, source: "issue")
      state.enable(:private_data, source: "env")

      expect {
        enforcer.enforce!(work_unit_id: "unit_123", flag: :egress, source: "push")
      }.to raise_error(Aidp::Security::PolicyViolation)
    end
  end

  describe "#with_work_unit" do
    it "yields the state to the block" do
      enforcer.with_work_unit(work_unit_id: "unit_123") do |state|
        expect(state).to be_a(Aidp::Security::TrifectaState)
        state.enable(:untrusted_input, source: "test")
      end
    end

    it "ends work unit after block completes" do
      enforcer.with_work_unit(work_unit_id: "unit_123") do |_state|
        expect(enforcer.active?("unit_123")).to be true
      end

      expect(enforcer.active?("unit_123")).to be false
    end

    it "ends work unit even if block raises" do
      expect {
        enforcer.with_work_unit(work_unit_id: "unit_123") do
          raise "test error"
        end
      }.to raise_error("test error")

      expect(enforcer.active?("unit_123")).to be false
    end
  end

  describe "#status_summary" do
    it "returns status summary hash" do
      enforcer.begin_work_unit(work_unit_id: "unit_1")
      enforcer.begin_work_unit(work_unit_id: "unit_2")

      summary = enforcer.status_summary

      expect(summary[:enabled]).to be true
      expect(summary[:active_work_units]).to eq(2)
    end
  end

  describe "#reset!" do
    it "clears all state" do
      enforcer.begin_work_unit(work_unit_id: "unit_123")
      enforcer.reset!

      expect(enforcer.active_count).to eq(0)
      expect(enforcer.audit_log).to be_empty
    end
  end
end
