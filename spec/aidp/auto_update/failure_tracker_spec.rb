# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/auto_update/failure_tracker"

RSpec.describe Aidp::AutoUpdate::FailureTracker do
  let(:project_dir) { Dir.mktmpdir }
  let(:tracker) { described_class.new(project_dir: project_dir, max_failures: 3) }

  after { FileUtils.rm_rf(project_dir) }

  describe "#initialize" do
    it "creates state file in .aidp directory" do
      expect(tracker.state_file).to include(".aidp")
      expect(tracker.state_file).to end_with("auto_update_failures.json")
    end

    it "sets max_failures" do
      expect(tracker.max_failures).to eq(3)
    end

    it "loads existing state if present" do
      # Create existing state file
      state_dir = File.join(project_dir, ".aidp")
      FileUtils.mkdir_p(state_dir)
      state_file = File.join(state_dir, "auto_update_failures.json")

      existing_state = {
        failures: [{timestamp: Time.now.utc.iso8601, version: "0.24.0"}],
        last_success: Time.now.utc.iso8601,
        last_success_version: "0.24.0"
      }
      File.write(state_file, JSON.pretty_generate(existing_state))

      new_tracker = described_class.new(project_dir: project_dir)
      expect(new_tracker.failure_count).to eq(1)
    end

    it "handles corrupted state file gracefully" do
      state_dir = File.join(project_dir, ".aidp")
      FileUtils.mkdir_p(state_dir)
      state_file = File.join(state_dir, "auto_update_failures.json")
      File.write(state_file, "invalid json {")

      new_tracker = described_class.new(project_dir: project_dir)
      expect(new_tracker.failure_count).to eq(0)
    end
  end

  describe "#record_failure" do
    it "adds failure to state" do
      expect {
        tracker.record_failure
      }.to change { tracker.failure_count }.from(0).to(1)
    end

    it "includes timestamp and version in failure" do
      tracker.record_failure
      timestamps = tracker.failure_timestamps

      expect(timestamps).not_to be_empty
      expect(timestamps.first).to be_a(Time)
    end

    it "prunes old failures older than 1 hour" do
      # Manually inject old failure
      old_failure = {
        timestamp: (Time.now - 7200).utc.iso8601, # 2 hours ago
        version: "0.24.0"
      }

      state_dir = File.join(project_dir, ".aidp")
      FileUtils.mkdir_p(state_dir)
      state_file = File.join(state_dir, "auto_update_failures.json")
      File.write(state_file, JSON.pretty_generate({failures: [old_failure], last_success: nil, last_success_version: nil}))

      new_tracker = described_class.new(project_dir: project_dir, max_failures: 3)
      new_tracker.record_failure # This should prune the old failure

      expect(new_tracker.failure_count).to eq(1) # Only the new one
    end

    it "persists state to disk" do
      tracker.record_failure

      # Create new tracker instance to verify persistence
      new_tracker = described_class.new(project_dir: project_dir)
      expect(new_tracker.failure_count).to eq(1)
    end
  end

  describe "#too_many_failures?" do
    it "returns false when below threshold" do
      tracker.record_failure
      tracker.record_failure

      expect(tracker.too_many_failures?).to be false
    end

    it "returns true when at threshold" do
      3.times { tracker.record_failure }

      expect(tracker.too_many_failures?).to be true
    end

    it "returns true when above threshold" do
      4.times { tracker.record_failure }

      expect(tracker.too_many_failures?).to be true
    end

    it "logs error when restart loop detected" do
      3.times { tracker.record_failure }

      expect(Aidp).to receive(:log_error).with("failure_tracker", "restart_loop_detected", anything)
      tracker.too_many_failures?
    end
  end

  describe "#reset_on_success" do
    it "clears all failures" do
      3.times { tracker.record_failure }

      tracker.reset_on_success

      expect(tracker.failure_count).to eq(0)
    end

    it "records last success timestamp" do
      tracker.reset_on_success

      status = tracker.status
      expect(status[:last_success]).not_to be_nil
    end

    it "records last success version" do
      tracker.reset_on_success

      status = tracker.status
      expect(status[:last_success_version]).to eq(Aidp::VERSION)
    end

    it "persists reset state to disk" do
      tracker.record_failure
      tracker.reset_on_success

      new_tracker = described_class.new(project_dir: project_dir)
      expect(new_tracker.failure_count).to eq(0)
    end
  end

  describe "#failure_count" do
    it "returns 0 when no failures" do
      expect(tracker.failure_count).to eq(0)
    end

    it "returns accurate count" do
      2.times { tracker.record_failure }
      expect(tracker.failure_count).to eq(2)
    end
  end

  describe "#time_since_last_success" do
    it "returns nil when never successful" do
      expect(tracker.time_since_last_success).to be_nil
    end

    it "returns time since last success" do
      tracker.reset_on_success
      sleep 0.1

      time_elapsed = tracker.time_since_last_success
      expect(time_elapsed).to be > 0
      expect(time_elapsed).to be < 2 # Should be less than 2 seconds
    end

    it "handles corrupt timestamp gracefully" do
      # Manually corrupt the last_success timestamp
      state_dir = File.join(project_dir, ".aidp")
      FileUtils.mkdir_p(state_dir)
      state_file = File.join(state_dir, "auto_update_failures.json")
      File.write(state_file, JSON.pretty_generate({failures: [], last_success: "invalid-timestamp", last_success_version: nil}))

      new_tracker = described_class.new(project_dir: project_dir)
      expect(new_tracker.time_since_last_success).to be_nil
    end
  end

  describe "#failure_timestamps" do
    it "returns empty array when no failures" do
      expect(tracker.failure_timestamps).to eq([])
    end

    it "returns array of Time objects" do
      2.times { tracker.record_failure }

      timestamps = tracker.failure_timestamps
      expect(timestamps.length).to eq(2)
      expect(timestamps.all? { |t| t.is_a?(Time) }).to be true
    end

    it "handles parsing errors gracefully" do
      # Manually inject invalid timestamp
      state_dir = File.join(project_dir, ".aidp")
      FileUtils.mkdir_p(state_dir)
      state_file = File.join(state_dir, "auto_update_failures.json")
      File.write(state_file, JSON.pretty_generate({
        failures: [{timestamp: "invalid", version: "0.24.0"}],
        last_success: nil,
        last_success_version: nil
      }))

      new_tracker = described_class.new(project_dir: project_dir)
      expect(new_tracker.failure_timestamps).to eq([])
    end
  end

  describe "#force_reset" do
    it "clears all failures" do
      3.times { tracker.record_failure }

      tracker.force_reset

      expect(tracker.failure_count).to eq(0)
    end

    it "logs warning about manual reset" do
      tracker.record_failure

      expect(Aidp).to receive(:log_warn).with("failure_tracker", "manual_reset_triggered", anything)
      tracker.force_reset
    end

    it "persists reset to disk" do
      tracker.record_failure
      tracker.force_reset

      new_tracker = described_class.new(project_dir: project_dir)
      expect(new_tracker.failure_count).to eq(0)
    end
  end

  describe "#status" do
    it "returns comprehensive status hash" do
      tracker.record_failure
      status = tracker.status

      expect(status).to include(
        :failure_count,
        :max_failures,
        :too_many_failures,
        :last_success,
        :last_success_version,
        :recent_failures
      )
    end

    it "includes accurate failure count" do
      2.times { tracker.record_failure }

      expect(tracker.status[:failure_count]).to eq(2)
    end

    it "includes max_failures threshold" do
      expect(tracker.status[:max_failures]).to eq(3)
    end

    it "includes too_many_failures boolean" do
      expect(tracker.status[:too_many_failures]).to be false

      3.times { tracker.record_failure }
      expect(tracker.status[:too_many_failures]).to be true
    end

    it "includes last success info after reset" do
      tracker.reset_on_success
      status = tracker.status

      expect(status[:last_success]).not_to be_nil
      expect(status[:last_success_version]).to eq(Aidp::VERSION)
    end
  end

  describe "error handling" do
    it "handles save_state failures gracefully" do
      # Make state file unwritable
      state_dir = File.join(project_dir, ".aidp")
      FileUtils.mkdir_p(state_dir)
      state_file = File.join(state_dir, "auto_update_failures.json")
      File.write(state_file, "{}")
      FileUtils.chmod(0o444, state_file) # Read-only

      expect(Aidp).to receive(:log_error).with("failure_tracker", "save_state_failed", anything)
      tracker.record_failure

      # Cleanup
      FileUtils.chmod(0o644, state_file)
    end

    it "handles record_failure errors gracefully" do
      # Stub Time.parse to raise error
      allow(Time).to receive(:parse).and_raise(ArgumentError, "invalid time")

      expect(Aidp).to receive(:log_error).with("failure_tracker", "record_failure_failed", anything)
      tracker.record_failure
    end

    it "handles reset_on_success errors gracefully" do
      # Make state file unwritable
      state_dir = File.join(project_dir, ".aidp")
      FileUtils.mkdir_p(state_dir)
      state_file = File.join(state_dir, "auto_update_failures.json")
      File.write(state_file, "{}")
      FileUtils.chmod(0o444, state_file)

      expect(Aidp).to receive(:log_error).with("failure_tracker", "reset_failed", anything)
      tracker.reset_on_success

      # Cleanup
      FileUtils.chmod(0o644, state_file)
    end
  end
end
