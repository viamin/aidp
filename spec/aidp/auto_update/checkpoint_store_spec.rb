# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/auto_update"

RSpec.describe Aidp::AutoUpdate::CheckpointStore do
  let(:project_dir) { Dir.mktmpdir }
  let(:store) { described_class.new(project_dir: project_dir) }

  after { FileUtils.rm_rf(project_dir) }

  describe "#save_checkpoint" do
    it "saves checkpoint to .aidp/checkpoints/" do
      checkpoint = Aidp::AutoUpdate::Checkpoint.new(
        mode: "watch",
        watch_state: {
          repository: "viamin/aidp",
          interval: 30
        }
      )

      result = store.save_checkpoint(checkpoint)

      expect(result).to be true
      checkpoint_path = File.join(project_dir, ".aidp", "checkpoints", "#{checkpoint.checkpoint_id}.json")
      expect(File.exist?(checkpoint_path)).to be true

      # Verify content
      saved = JSON.parse(File.read(checkpoint_path), symbolize_names: true)
      expect(saved[:mode]).to eq("watch")
      expect(saved[:watch_state][:repository]).to eq("viamin/aidp")
    end
  end

  describe "#latest_checkpoint" do
    context "when no checkpoints exist" do
      it "returns nil" do
        expect(store.latest_checkpoint).to be_nil
      end
    end

    context "when multiple checkpoints exist" do
      it "returns the most recent one" do
        old_checkpoint = Aidp::AutoUpdate::Checkpoint.new(mode: "watch")
        store.save_checkpoint(old_checkpoint)

        sleep 0.1 # Ensure different timestamps

        new_checkpoint = Aidp::AutoUpdate::Checkpoint.new(mode: "watch")
        store.save_checkpoint(new_checkpoint)

        latest = store.latest_checkpoint

        expect(latest.checkpoint_id).to eq(new_checkpoint.checkpoint_id)
      end
    end
  end

  describe "#delete_checkpoint" do
    it "deletes checkpoint file" do
      checkpoint = Aidp::AutoUpdate::Checkpoint.new(mode: "watch")
      store.save_checkpoint(checkpoint)

      checkpoint_path = File.join(project_dir, ".aidp", "checkpoints", "#{checkpoint.checkpoint_id}.json")
      expect(File.exist?(checkpoint_path)).to be true

      store.delete_checkpoint(checkpoint.checkpoint_id)

      expect(File.exist?(checkpoint_path)).to be false
    end
  end

  describe "#cleanup_old_checkpoints" do
    it "removes checkpoints older than max_age_days" do
      # Create old checkpoint with timestamp 8 days ago
      old_checkpoint = Aidp::AutoUpdate::Checkpoint.new(
        mode: "watch",
        created_at: Time.now - (8 * 24 * 3600)
      )
      store.save_checkpoint(old_checkpoint)

      new_checkpoint = Aidp::AutoUpdate::Checkpoint.new(mode: "watch")
      store.save_checkpoint(new_checkpoint)

      count = store.cleanup_old_checkpoints(max_age_days: 7)

      expect(count).to eq(1)
      expect(store.latest_checkpoint.checkpoint_id).to eq(new_checkpoint.checkpoint_id)
    end
  end
end
