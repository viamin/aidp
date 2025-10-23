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

  describe "#load_state" do
    context "when skip_persistence is true" do
      it "returns empty hash" do
        expect(persistence.load_state).to eq({})
      end
    end

    # Note: File I/O scenarios require skip_persistence: false
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
