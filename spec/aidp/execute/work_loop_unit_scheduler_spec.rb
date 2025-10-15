# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/work_loop_unit_scheduler"

RSpec.describe Aidp::Execute::WorkLoopUnitScheduler do
  let(:clock) do
    Class.new do
      def initialize
        @now = Time.now
      end

      def advance(seconds)
        @now += seconds
      end

      attr_reader :now
    end.new
  end

  let(:units_config) do
    {
      deterministic: [
        {
          name: "run_full_tests",
          command: "bundle exec rspec",
          next: {success: :agentic, failure: :decide_whats_next},
          min_interval_seconds: 60
        },
        {
          name: "wait_for_github",
          type: :wait,
          next: {event: :agentic, else: :wait_for_github},
          metadata: {interval_seconds: 5}
        }
      ],
      defaults: {
        on_no_next_step: :wait_for_github,
        fallback_agentic: :decide_whats_next,
        max_consecutive_deciders: 1
      }
    }
  end

  subject(:scheduler) { described_class.new(units_config, clock: clock) }

  def make_result(definition, status:, finished_at: clock.now)
    Aidp::Execute::DeterministicUnits::Result.new(
      name: definition.name,
      status: status,
      output_path: nil,
      started_at: finished_at - 1,
      finished_at: finished_at,
      data: {}
    )
  end

  describe "#next_unit" do
    it "returns primary agentic unit by default" do
      unit = scheduler.next_unit
      expect(unit).to be_agentic
      expect(unit.name).to eq(:primary)
    end

    it "schedules requested deterministic unit after agentic run" do
      scheduler.record_agentic_result({status: :completed}, requested_next: :run_full_tests)
      unit = scheduler.next_unit
      expect(unit).to be_deterministic
      expect(unit.definition.name).to eq("run_full_tests")
    end

    it "enforces cooldown before re-running deterministic unit" do
      # Initial agentic pass
      initial_unit = scheduler.next_unit
      expect(initial_unit).to be_agentic

      scheduler.record_agentic_result({status: :completed}, requested_next: :run_full_tests)
      unit = scheduler.next_unit
      definition = unit.definition
      scheduler.record_deterministic_result(definition, make_result(definition, status: :success))

      follow_up_unit = scheduler.next_unit
      expect(follow_up_unit).to be_agentic

      scheduler.record_agentic_result({status: :completed}, requested_next: :run_full_tests)
      next_unit = scheduler.next_unit
      expect(next_unit).to be_agentic
      expect(next_unit.name).to eq(:decide_whats_next)

      # After cooldown elapses, deterministic unit can run again
      clock.advance(definition.min_interval_seconds + 1)
      retry_unit = scheduler.next_unit
      expect(retry_unit).to be_deterministic
    end
  end

  describe "#deterministic_context" do
    it "tracks recent deterministic results" do
      scheduler.record_agentic_result({status: :completed}, requested_next: :run_full_tests)
      unit = scheduler.next_unit
      definition = unit.definition
      scheduler.record_deterministic_result(definition, make_result(definition, status: :failure))

      context = scheduler.deterministic_context
      expect(context.last[:name]).to eq("run_full_tests")
      expect(context.last[:status]).to eq(:failure)
    end
  end
end
