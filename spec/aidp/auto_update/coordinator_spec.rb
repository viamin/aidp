# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"
require_relative "../../../lib/aidp/auto_update"

RSpec.describe Aidp::AutoUpdate::Coordinator do
  let(:project_dir) { Dir.mktmpdir }
  let(:policy) do
    Aidp::AutoUpdate::UpdatePolicy.new(
      enabled: true,
      policy: "minor",
      allow_prerelease: false,
      check_interval_seconds: 3600,
      supervisor: "supervisord",
      max_consecutive_failures: 3
    )
  end

  after { FileUtils.rm_rf(project_dir) }

  describe "#check_for_update" do
    context "when auto-update is disabled" do
      it "returns unavailable check" do
        disabled_policy = Aidp::AutoUpdate::UpdatePolicy.new(enabled: false, policy: "off")
        coordinator = described_class.new(policy: disabled_policy, project_dir: project_dir)

        check = coordinator.check_for_update

        expect(check).to be_a(Aidp::AutoUpdate::UpdateCheck)
        expect(check.update_available).to be false
      end
    end

    context "when auto-update is enabled" do
      it "performs version check and logs result" do
        mock_detector = instance_double(Aidp::AutoUpdate::VersionDetector)
        mock_logger = instance_double(Aidp::AutoUpdate::UpdateLogger)

        update_check = Aidp::AutoUpdate::UpdateCheck.new(
          current_version: "0.24.0",
          available_version: "0.25.0",
          update_available: true,
          update_allowed: true,
          policy_reason: "minor update allowed",
          checked_at: Time.now
        )

        allow(mock_detector).to receive(:check_for_update).and_return(update_check)
        allow(mock_logger).to receive(:log_check)

        coordinator = described_class.new(
          policy: policy,
          version_detector: mock_detector,
          update_logger: mock_logger,
          project_dir: project_dir
        )

        result = coordinator.check_for_update

        expect(result).to eq(update_check)
        expect(mock_logger).to have_received(:log_check).with(update_check)
      end

      it "returns failed check when version detection fails" do
        mock_detector = instance_double(Aidp::AutoUpdate::VersionDetector)
        mock_logger = instance_double(Aidp::AutoUpdate::UpdateLogger)

        allow(mock_detector).to receive(:check_for_update).and_raise(StandardError, "network error")
        allow(mock_logger).to receive(:log_check)

        coordinator = described_class.new(
          policy: policy,
          version_detector: mock_detector,
          update_logger: mock_logger,
          project_dir: project_dir
        )

        result = coordinator.check_for_update

        expect(result).to be_a(Aidp::AutoUpdate::UpdateCheck)
        expect(result.update_available).to be false
      end
    end
  end

  describe "#initiate_update" do
    context "when updates are disabled" do
      it "raises UpdateError" do
        disabled_policy = Aidp::AutoUpdate::UpdatePolicy.new(enabled: false, policy: "off")
        coordinator = described_class.new(policy: disabled_policy, project_dir: project_dir)

        expect {
          coordinator.initiate_update({mode: "watch"})
        }.to raise_error(Aidp::AutoUpdate::UpdateError, /disabled/)
      end
    end

    context "when too many failures" do
      it "raises UpdateLoopError" do
        mock_tracker = instance_double(Aidp::AutoUpdate::FailureTracker)
        mock_logger = instance_double(Aidp::AutoUpdate::UpdateLogger)
        allow(mock_tracker).to receive(:too_many_failures?).and_return(true)
        allow(mock_tracker).to receive(:failure_count).and_return(3)
        allow(mock_logger).to receive(:log_restart_loop)

        coordinator = described_class.new(
          policy: policy,
          failure_tracker: mock_tracker,
          update_logger: mock_logger,
          project_dir: project_dir
        )

        expect {
          coordinator.initiate_update({mode: "watch"})
        }.to raise_error(Aidp::AutoUpdate::UpdateLoopError, /Too many consecutive/)

        expect(mock_logger).to have_received(:log_restart_loop).with(3)
      end
    end

    context "when no supervisor configured" do
      it "raises UpdateError" do
        no_supervisor_policy = Aidp::AutoUpdate::UpdatePolicy.new(
          enabled: true,
          policy: "minor",
          supervisor: "none"
        )
        coordinator = described_class.new(policy: no_supervisor_policy, project_dir: project_dir)

        expect {
          coordinator.initiate_update({mode: "watch"})
        }.to raise_error(Aidp::AutoUpdate::UpdateError, /No supervisor/)
      end
    end

    context "when no update available" do
      it "returns without exiting" do
        mock_detector = instance_double(Aidp::AutoUpdate::VersionDetector)
        mock_logger = instance_double(Aidp::AutoUpdate::UpdateLogger)
        mock_tracker = instance_double(Aidp::AutoUpdate::FailureTracker)

        update_check = Aidp::AutoUpdate::UpdateCheck.new(
          current_version: "0.24.0",
          available_version: "0.24.0",
          update_available: false,
          update_allowed: false,
          policy_reason: "no update available",
          checked_at: Time.now
        )

        allow(mock_tracker).to receive(:too_many_failures?).and_return(false)
        allow(mock_detector).to receive(:check_for_update).and_return(update_check)
        allow(mock_logger).to receive(:log_check)

        coordinator = described_class.new(
          policy: policy,
          version_detector: mock_detector,
          update_logger: mock_logger,
          failure_tracker: mock_tracker,
          project_dir: project_dir
        )

        # Should not exit, just return
        expect {
          coordinator.initiate_update({mode: "watch"})
        }.not_to raise_error
      end
    end

    context "when checkpoint save fails" do
      it "raises UpdateError without recording failure" do
        mock_detector = instance_double(Aidp::AutoUpdate::VersionDetector)
        mock_logger = instance_double(Aidp::AutoUpdate::UpdateLogger)
        mock_tracker = instance_double(Aidp::AutoUpdate::FailureTracker)
        mock_checkpoint_store = instance_double(Aidp::AutoUpdate::CheckpointStore)

        update_check = Aidp::AutoUpdate::UpdateCheck.new(
          current_version: "0.24.0",
          available_version: "0.25.0",
          update_available: true,
          update_allowed: true,
          policy_reason: "minor update allowed",
          checked_at: Time.now
        )

        allow(mock_tracker).to receive(:too_many_failures?).and_return(false)
        allow(mock_detector).to receive(:check_for_update).and_return(update_check)
        allow(mock_logger).to receive(:log_check)
        allow(mock_checkpoint_store).to receive(:save_checkpoint).and_return(false)

        coordinator = described_class.new(
          policy: policy,
          version_detector: mock_detector,
          update_logger: mock_logger,
          failure_tracker: mock_tracker,
          checkpoint_store: mock_checkpoint_store,
          project_dir: project_dir
        )

        expect {
          coordinator.initiate_update({mode: "watch"})
        }.to raise_error(Aidp::AutoUpdate::UpdateError, /Failed to save checkpoint/)
      end
    end
  end

  describe "#restore_from_checkpoint" do
    context "when no checkpoint exists" do
      it "returns nil" do
        coordinator = described_class.new(policy: policy, project_dir: project_dir)
        result = coordinator.restore_from_checkpoint

        expect(result).to be_nil
      end
    end

    context "when checkpoint exists and is valid" do
      it "restores checkpoint and resets failure tracker" do
        # Create a valid checkpoint
        checkpoint_dir = File.join(project_dir, ".aidp", "checkpoints")
        FileUtils.mkdir_p(checkpoint_dir)

        checkpoint = Aidp::AutoUpdate::Checkpoint.new(
          mode: "watch",
          watch_state: {
            repository: "viamin/aidp",
            interval: 30
          }
        )

        checkpoint_path = File.join(checkpoint_dir, "#{checkpoint.checkpoint_id}.json")
        File.write(checkpoint_path, JSON.pretty_generate(checkpoint.to_h))

        coordinator = described_class.new(policy: policy, project_dir: project_dir)
        result = coordinator.restore_from_checkpoint

        expect(result).to be_a(Aidp::AutoUpdate::Checkpoint)
        expect(result.mode).to eq("watch")
        expect(File.exist?(checkpoint_path)).to be false # Should be deleted after restore
      end
    end

    context "when checkpoint has invalid checksum" do
      it "returns nil and records failure" do
        mock_checkpoint_store = instance_double(Aidp::AutoUpdate::CheckpointStore)
        mock_tracker = instance_double(Aidp::AutoUpdate::FailureTracker)
        mock_logger = instance_double(Aidp::AutoUpdate::UpdateLogger)

        # Create invalid checkpoint (valid? returns false)
        invalid_checkpoint = instance_double(Aidp::AutoUpdate::Checkpoint,
          valid?: false,
          checkpoint_id: "test-id",
          created_at: Time.now)

        allow(mock_checkpoint_store).to receive(:latest_checkpoint).and_return(invalid_checkpoint)
        allow(mock_tracker).to receive(:record_failure)
        allow(mock_logger).to receive(:log_failure)

        coordinator = described_class.new(
          policy: policy,
          checkpoint_store: mock_checkpoint_store,
          failure_tracker: mock_tracker,
          update_logger: mock_logger,
          project_dir: project_dir
        )

        result = coordinator.restore_from_checkpoint

        expect(result).to be_nil
        expect(mock_tracker).to have_received(:record_failure)
        expect(mock_logger).to have_received(:log_failure)
      end
    end

    context "when checkpoint version is incompatible" do
      it "returns nil and records failure" do
        mock_checkpoint_store = instance_double(Aidp::AutoUpdate::CheckpointStore)
        mock_tracker = instance_double(Aidp::AutoUpdate::FailureTracker)
        mock_logger = instance_double(Aidp::AutoUpdate::UpdateLogger)

        # Create checkpoint with incompatible version
        incompatible_checkpoint = instance_double(Aidp::AutoUpdate::Checkpoint,
          valid?: true,
          compatible_version?: false,
          checkpoint_id: "test-id",
          aidp_version: "0.1.0",
          created_at: Time.now)

        allow(mock_checkpoint_store).to receive(:latest_checkpoint).and_return(incompatible_checkpoint)
        allow(mock_tracker).to receive(:record_failure)
        allow(mock_logger).to receive(:log_failure)

        coordinator = described_class.new(
          policy: policy,
          checkpoint_store: mock_checkpoint_store,
          failure_tracker: mock_tracker,
          update_logger: mock_logger,
          project_dir: project_dir
        )

        result = coordinator.restore_from_checkpoint

        expect(result).to be_nil
        expect(mock_tracker).to have_received(:record_failure)
        expect(mock_logger).to have_received(:log_failure)
      end
    end

    context "when restore fails with exception" do
      it "returns nil and records failure" do
        mock_checkpoint_store = instance_double(Aidp::AutoUpdate::CheckpointStore)
        mock_tracker = instance_double(Aidp::AutoUpdate::FailureTracker)
        mock_logger = instance_double(Aidp::AutoUpdate::UpdateLogger)

        allow(mock_checkpoint_store).to receive(:latest_checkpoint).and_raise(StandardError, "disk error")
        allow(mock_tracker).to receive(:record_failure)
        allow(mock_logger).to receive(:log_failure)

        coordinator = described_class.new(
          policy: policy,
          checkpoint_store: mock_checkpoint_store,
          failure_tracker: mock_tracker,
          update_logger: mock_logger,
          project_dir: project_dir
        )

        result = coordinator.restore_from_checkpoint

        expect(result).to be_nil
        expect(mock_tracker).to have_received(:record_failure)
        expect(mock_logger).to have_received(:log_failure).with("Checkpoint restore failed: disk error")
      end
    end
  end

  describe "#status" do
    it "returns comprehensive status information" do
      # Stub RubyGems API to avoid real network call
      stub_request(:get, "https://rubygems.org/api/v1/gems/aidp.json")
        .with(
          headers: {
            "Accept" => "*/*",
            "Accept-Encoding" => "gzip;q=1.0,deflate;q=0.6,identity;q=0.3",
            "Host" => "rubygems.org",
            "User-Agent" => "Aidp/#{Aidp::VERSION}"
          }
        )
        .to_return(
          status: 200,
          body: {version: Aidp::VERSION}.to_json,
          headers: {"Content-Type" => "application/json"}
        )

      coordinator = described_class.new(policy: policy, project_dir: project_dir)
      status = coordinator.status

      expect(status).to include(
        :enabled,
        :policy,
        :supervisor,
        :current_version,
        :available_version,
        :update_available,
        :update_allowed,
        :policy_reason,
        :failure_tracker,
        :recent_updates
      )

      expect(status[:enabled]).to be true
      expect(status[:policy]).to eq("minor")
      expect(status[:supervisor]).to eq("supervisord")
    end
  end

  describe ".from_config" do
    it "creates coordinator from configuration" do
      config = {
        "enabled" => true,
        "policy" => "minor",
        "supervisor" => "supervisord"
      }

      coordinator = described_class.from_config(config, project_dir: project_dir)

      expect(coordinator).to be_a(described_class)
    end

    it "handles nil config by using defaults" do
      coordinator = described_class.from_config(nil, project_dir: project_dir)

      expect(coordinator).to be_a(described_class)
    end

    it "handles empty config by using defaults" do
      coordinator = described_class.from_config({}, project_dir: project_dir)

      expect(coordinator).to be_a(described_class)
    end
  end

  describe "#hot_reload_available?" do
    it "returns true when Zeitwerk loader is set up for reloading" do
      allow(Aidp::Loader).to receive(:setup?).and_return(true)
      allow(Aidp::Loader).to receive(:reloading?).and_return(true)

      coordinator = described_class.new(policy: policy, project_dir: project_dir)

      expect(coordinator.hot_reload_available?).to be true
    end

    it "returns false when Zeitwerk loader is not set up" do
      allow(Aidp::Loader).to receive(:setup?).and_return(false)
      allow(Aidp::Loader).to receive(:reloading?).and_return(false)

      coordinator = described_class.new(policy: policy, project_dir: project_dir)

      expect(coordinator.hot_reload_available?).to be false
    end

    it "returns false when reloading is disabled" do
      allow(Aidp::Loader).to receive(:setup?).and_return(true)
      allow(Aidp::Loader).to receive(:reloading?).and_return(false)

      coordinator = described_class.new(policy: policy, project_dir: project_dir)

      expect(coordinator.hot_reload_available?).to be false
    end
  end

  describe "#hot_reload_update" do
    context "when updates are disabled" do
      it "raises UpdateError" do
        disabled_policy = Aidp::AutoUpdate::UpdatePolicy.new(enabled: false, policy: "off")
        coordinator = described_class.new(policy: disabled_policy, project_dir: project_dir)

        expect {
          coordinator.hot_reload_update
        }.to raise_error(Aidp::AutoUpdate::UpdateError, /disabled/)
      end
    end

    context "when reloading is not available" do
      it "raises UpdateError" do
        allow(Aidp::Loader).to receive(:setup?).and_return(false)
        allow(Aidp::Loader).to receive(:reloading?).and_return(false)

        coordinator = described_class.new(policy: policy, project_dir: project_dir)

        expect {
          coordinator.hot_reload_update
        }.to raise_error(Aidp::AutoUpdate::UpdateError, /not available/)
      end
    end

    context "when no update is available" do
      it "returns false without reloading" do
        allow(Aidp::Loader).to receive(:setup?).and_return(true)
        allow(Aidp::Loader).to receive(:reloading?).and_return(true)

        mock_detector = instance_double(Aidp::AutoUpdate::VersionDetector)
        mock_logger = instance_double(Aidp::AutoUpdate::UpdateLogger)

        no_update_check = Aidp::AutoUpdate::UpdateCheck.new(
          current_version: "0.24.0",
          available_version: "0.24.0",
          update_available: false,
          update_allowed: false,
          policy_reason: "no update available",
          checked_at: Time.now
        )

        allow(mock_detector).to receive(:check_for_update).and_return(no_update_check)
        allow(mock_logger).to receive(:log_check)

        coordinator = described_class.new(
          policy: policy,
          version_detector: mock_detector,
          update_logger: mock_logger,
          project_dir: project_dir
        )

        result = coordinator.hot_reload_update

        expect(result).to be false
      end
    end

    context "when update is available and reload succeeds" do
      it "performs git pull and reloads classes" do
        allow(Aidp::Loader).to receive(:setup?).and_return(true)
        allow(Aidp::Loader).to receive(:reloading?).and_return(true)
        allow(Aidp::Loader).to receive(:reload!).and_return(true)

        mock_detector = instance_double(Aidp::AutoUpdate::VersionDetector)
        mock_logger = instance_double(Aidp::AutoUpdate::UpdateLogger)
        mock_tracker = instance_double(Aidp::AutoUpdate::FailureTracker)

        update_check = Aidp::AutoUpdate::UpdateCheck.new(
          current_version: "0.24.0",
          available_version: "0.25.0",
          update_available: true,
          update_allowed: true,
          policy_reason: "minor update allowed",
          checked_at: Time.now
        )

        allow(mock_detector).to receive(:check_for_update).and_return(update_check)
        allow(mock_logger).to receive(:log_check)
        allow(mock_logger).to receive(:log_success)
        allow(mock_tracker).to receive(:reset_on_success)

        coordinator = described_class.new(
          policy: policy,
          version_detector: mock_detector,
          update_logger: mock_logger,
          failure_tracker: mock_tracker,
          project_dir: project_dir
        )

        # Mock git pull to succeed
        allow(coordinator).to receive(:perform_git_pull).and_return(true)

        result = coordinator.hot_reload_update(update_check)

        expect(result).to be true
        expect(Aidp::Loader).to have_received(:reload!)
        expect(mock_logger).to have_received(:log_success)
        expect(mock_tracker).to have_received(:reset_on_success)
      end
    end

    context "when git pull fails" do
      it "raises UpdateError" do
        allow(Aidp::Loader).to receive(:setup?).and_return(true)
        allow(Aidp::Loader).to receive(:reloading?).and_return(true)

        mock_detector = instance_double(Aidp::AutoUpdate::VersionDetector)
        mock_logger = instance_double(Aidp::AutoUpdate::UpdateLogger)

        update_check = Aidp::AutoUpdate::UpdateCheck.new(
          current_version: "0.24.0",
          available_version: "0.25.0",
          update_available: true,
          update_allowed: true,
          policy_reason: "minor update allowed",
          checked_at: Time.now
        )

        allow(mock_detector).to receive(:check_for_update).and_return(update_check)
        allow(mock_logger).to receive(:log_check)

        coordinator = described_class.new(
          policy: policy,
          version_detector: mock_detector,
          update_logger: mock_logger,
          project_dir: project_dir
        )

        # Mock git pull to fail
        allow(coordinator).to receive(:perform_git_pull).and_return(false)

        expect {
          coordinator.hot_reload_update(update_check)
        }.to raise_error(Aidp::AutoUpdate::UpdateError, /Git pull failed/)
      end
    end

    context "when Zeitwerk reload fails" do
      it "raises UpdateError and records failure" do
        allow(Aidp::Loader).to receive(:setup?).and_return(true)
        allow(Aidp::Loader).to receive(:reloading?).and_return(true)
        allow(Aidp::Loader).to receive(:reload!).and_return(false)

        mock_detector = instance_double(Aidp::AutoUpdate::VersionDetector)
        mock_logger = instance_double(Aidp::AutoUpdate::UpdateLogger)
        mock_tracker = instance_double(Aidp::AutoUpdate::FailureTracker)

        update_check = Aidp::AutoUpdate::UpdateCheck.new(
          current_version: "0.24.0",
          available_version: "0.25.0",
          update_available: true,
          update_allowed: true,
          policy_reason: "minor update allowed",
          checked_at: Time.now
        )

        allow(mock_detector).to receive(:check_for_update).and_return(update_check)
        allow(mock_logger).to receive(:log_check)
        allow(mock_logger).to receive(:log_failure)
        allow(mock_tracker).to receive(:record_failure)

        coordinator = described_class.new(
          policy: policy,
          version_detector: mock_detector,
          update_logger: mock_logger,
          failure_tracker: mock_tracker,
          project_dir: project_dir
        )

        # Mock git pull to succeed
        allow(coordinator).to receive(:perform_git_pull).and_return(true)

        expect {
          coordinator.hot_reload_update(update_check)
        }.to raise_error(Aidp::AutoUpdate::UpdateError, /Zeitwerk reload failed/)

        expect(mock_tracker).to have_received(:record_failure)
        expect(mock_logger).to have_received(:log_failure)
      end
    end
  end
end
