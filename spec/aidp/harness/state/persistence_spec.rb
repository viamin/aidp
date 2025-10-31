# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/state/persistence"
require "tmpdir"

RSpec.describe Aidp::Harness::State::Persistence do
  let(:project_dir) { Dir.mktmpdir }
  let(:mode) { "work_loop" }
  let(:persistence) { described_class.new(project_dir, mode, skip_persistence: true) }
  let(:state_dir) { File.join(project_dir, ".aidp", "harness") }
  let(:state_file) { File.join(state_dir, "#{mode}_state.json") }
  let(:lock_file) { File.join(state_dir, "#{mode}_state.lock") }

  after do
    FileUtils.rm_rf(project_dir) if project_dir && Dir.exist?(project_dir)
  end

  describe "#initialize" do
    it "creates state directory" do
      persistence
      expect(Dir.exist?(state_dir)).to be true
    end

    it "sets up state file path" do
      expect(persistence.instance_variable_get(:@state_file)).to eq(state_file)
    end

    it "sets up lock file path" do
      lock_file = File.join(state_dir, "#{mode}_state.lock")
      expect(persistence.instance_variable_get(:@lock_file)).to eq(lock_file)
    end
  end

  describe "#has_state?" do
    context "when skip_persistence is true" do
      it "returns false" do
        expect(persistence.has_state?).to be false
      end
    end

    # Note: Other test scenarios require skip_persistence: false
  end

  context "with real persistence (skip_persistence: false)" do
    let(:real_persistence) { described_class.new(project_dir, mode, skip_persistence: false) }

    it "returns false before save and true after save" do
      expect(real_persistence.has_state?).to be false
      real_persistence.save_state({foo: "bar"})
      expect(real_persistence.has_state?).to be true
    end

    it "persists and loads state including metadata" do
      real_persistence.save_state({alpha: 1})
      loaded = real_persistence.load_state
      expect(loaded[:alpha]).to eq(1)
      expect(loaded[:mode]).to eq(mode)
      expect(loaded[:project_dir]).to eq(project_dir)
      expect(loaded[:saved_at]).to be_a(String)
    end

    it "clears state file" do
      real_persistence.save_state({x: 2})
      expect(File.exist?(state_file)).to be true
      real_persistence.clear_state
      expect(File.exist?(state_file)).to be false
    end
  end

  describe "#load_state" do
    context "when skip_persistence is true" do
      it "returns empty hash" do
        expect(persistence.load_state).to eq({})
      end
    end

    # Note: File I/O scenarios require skip_persistence: false
  end

  describe "JSON parse error handling" do
    it "returns empty hash and warns when file is corrupt" do
      real = described_class.new(project_dir, mode, skip_persistence: false)
      FileUtils.mkdir_p(state_dir)
      File.write(state_file, "{invalid-json")
      expect(real.load_state).to eq({})
    end
  end

  describe "#save_state" do
    let(:state_data) { {step: "current_step", status: "running"} }

    context "when skip_persistence is true" do
      it "does not write to file" do
        persistence.save_state(state_data)
        expect(File.exist?(state_file)).to be false
      end
    end

    # Note: File write scenarios require skip_persistence: false
  end

  describe "locking behavior" do
    it "does not leave lock file after successful save" do
      real = described_class.new(project_dir, mode, skip_persistence: false)
      real.save_state({ok: true})
      expect(File.exist?(lock_file)).to be false
    end

    it "raises timeout error when lock cannot be acquired" do
      real = described_class.new(project_dir, mode, skip_persistence: false)
      FileUtils.mkdir_p(state_dir)
      File.write(lock_file, "held")
      # Force try_acquire_lock to never succeed
      allow(real).to receive(:try_acquire_lock).and_return([false, nil])
      original_timeout = ENV["AIDP_STATE_LOCK_TIMEOUT"]
      original_sleep = ENV["AIDP_STATE_LOCK_SLEEP"]
      begin
        ENV["AIDP_STATE_LOCK_TIMEOUT"] = "0.2"
        ENV["AIDP_STATE_LOCK_SLEEP"] = "0.01"
        expect { real.save_state({z: 9}) }.to raise_error(/Could not acquire state lock/)
      ensure
        ENV["AIDP_STATE_LOCK_TIMEOUT"] = original_timeout
        ENV["AIDP_STATE_LOCK_SLEEP"] = original_sleep
      end
    end
  end

  describe "#clear_state" do
    context "when skip_persistence is true" do
      it "does not perform file operations" do
        persistence.clear_state
        # With skip_persistence: true, this is a no-op
        expect(File.exist?(state_file)).to be false
      end
    end

    # Note: File deletion scenarios require skip_persistence: false
  end

  describe "private methods" do
    describe "#add_metadata" do
      let(:state_data) { {key: "value"} }

      it "adds metadata to state" do
        result = persistence.send(:add_metadata, state_data)

        expect(result[:key]).to eq("value")
        expect(result[:mode]).to eq(mode)
        expect(result[:project_dir]).to eq(project_dir)
        expect(result[:saved_at]).to be_a(String)
      end

      it "does not modify original state data" do
        original = state_data.dup
        persistence.send(:add_metadata, state_data)
        expect(state_data).to eq(original)
      end
    end
  end
end
