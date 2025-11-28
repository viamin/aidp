# frozen_string_literal: true

module Aidp
  module AutoUpdate
    # Facade for orchestrating the complete auto-update workflow
    class Coordinator
      attr_reader :policy, :version_detector, :checkpoint_store, :update_logger, :failure_tracker

      def initialize(
        policy:,
        version_detector: nil,
        checkpoint_store: nil,
        update_logger: nil,
        failure_tracker: nil,
        project_dir: Dir.pwd
      )
        @policy = policy
        @project_dir = project_dir

        # Use provided instances or create defaults
        @version_detector = version_detector || VersionDetector.new(policy: policy)
        @checkpoint_store = checkpoint_store || CheckpointStore.new(project_dir: project_dir)
        @update_logger = update_logger || UpdateLogger.new(project_dir: project_dir)
        @failure_tracker = failure_tracker || FailureTracker.new(
          project_dir: project_dir,
          max_failures: policy.max_consecutive_failures
        )
      end

      # Create coordinator from configuration
      # @param config [Hash] Auto-update configuration from aidp.yml
      # @param project_dir [String] Project root directory
      # @return [Coordinator]
      def self.from_config(config, project_dir: Dir.pwd)
        policy = UpdatePolicy.from_config(config)
        new(policy: policy, project_dir: project_dir)
      end

      # Check if update is available and allowed
      # @return [UpdateCheck] Update check result
      def check_for_update
        return UpdateCheck.unavailable unless @policy.enabled

        update_check = @version_detector.check_for_update
        @update_logger.log_check(update_check)
        update_check
      rescue => e
        Aidp.log_error("auto_update_coordinator", "check_failed",
          error: e.message)
        UpdateCheck.failed(e.message)
      end

      # Initiate update process (checkpoint + exit with code 75)
      # @param current_state [Hash] Current application state (from Watch::Runner)
      # @return [void] (exits process with code 75)
      # @raise [UpdateError] If updates are disabled or preconditions not met
      # @raise [UpdateLoopError] If too many consecutive failures
      def initiate_update(current_state)
        raise UpdateError, "Updates disabled by configuration" unless @policy.enabled

        # Check for restart loops
        if @failure_tracker.too_many_failures?
          @update_logger.log_restart_loop(@failure_tracker.failure_count)
          raise UpdateLoopError, "Too many consecutive update failures (#{@failure_tracker.failure_count}/#{@policy.max_consecutive_failures})"
        end

        # Verify supervisor is configured
        unless @policy.supervised?
          raise UpdateError, "No supervisor configured. Set auto_update.supervisor in aidp.yml"
        end

        # Get latest version to record in checkpoint
        update_check = check_for_update

        unless update_check.should_update?
          Aidp.log_info("auto_update_coordinator", "no_update_needed",
            reason: update_check.policy_reason)
          return
        end

        # Create checkpoint from current state
        checkpoint = build_checkpoint(current_state, update_check.available_version)

        # Save checkpoint
        unless @checkpoint_store.save_checkpoint(checkpoint)
          raise UpdateError, "Failed to save checkpoint"
        end

        # Log update initiation
        @update_logger.log_update_initiated(checkpoint, target_version: update_check.available_version)

        Aidp.log_info("auto_update_coordinator", "exiting_for_update",
          from_version: update_check.current_version,
          to_version: update_check.available_version,
          checkpoint_id: checkpoint.checkpoint_id)

        # Exit with special code 75 to signal supervisor to update
        exit(75)
      rescue UpdateError, UpdateLoopError
        # Re-raise domain errors
        raise
      rescue => e
        @failure_tracker.record_failure
        @update_logger.log_failure(e.message)
        Aidp.log_error("auto_update_coordinator", "initiate_failed",
          error: e.message)
        raise UpdateError, "Update initiation failed: #{e.message}"
      end

      # Restore from checkpoint after update
      # @return [Checkpoint, nil] Restored checkpoint or nil
      def restore_from_checkpoint
        checkpoint = @checkpoint_store.latest_checkpoint
        return nil unless checkpoint

        Aidp.log_info("auto_update_coordinator", "restoring_checkpoint",
          id: checkpoint.checkpoint_id,
          created_at: checkpoint.created_at.iso8601)

        # Validate checkpoint
        unless checkpoint.valid?
          Aidp.log_error("auto_update_coordinator", "invalid_checkpoint",
            id: checkpoint.checkpoint_id,
            reason: "Checksum validation failed")
          @failure_tracker.record_failure
          @update_logger.log_failure("Invalid checkpoint checksum", checkpoint_id: checkpoint.checkpoint_id)
          return nil
        end

        # Check version compatibility
        unless checkpoint.compatible_version?
          Aidp.log_warn("auto_update_coordinator", "incompatible_version",
            checkpoint_version: checkpoint.aidp_version,
            current_version: Aidp::VERSION)
          @failure_tracker.record_failure
          @update_logger.log_failure(
            "Incompatible version: checkpoint from #{checkpoint.aidp_version}, current #{Aidp::VERSION}",
            checkpoint_id: checkpoint.checkpoint_id
          )
          return nil
        end

        # Log successful restoration
        @update_logger.log_restore(checkpoint)
        @update_logger.log_success(
          from_version: checkpoint.aidp_version,
          to_version: Aidp::VERSION
        )

        # Reset failure tracker on success
        @failure_tracker.reset_on_success

        # Delete checkpoint after successful restore
        @checkpoint_store.delete_checkpoint(checkpoint.checkpoint_id)

        checkpoint
      rescue => e
        @failure_tracker.record_failure
        @update_logger.log_failure("Checkpoint restore failed: #{e.message}")
        Aidp.log_error("auto_update_coordinator", "restore_failed",
          error: e.message)
        nil
      end

      # Get status summary for CLI display
      # @return [Hash] Status information
      def status
        update_check = check_for_update

        {
          enabled: @policy.enabled,
          policy: @policy.policy,
          supervisor: @policy.supervisor,
          current_version: Aidp::VERSION,
          available_version: update_check.available_version,
          update_available: update_check.update_available,
          update_allowed: update_check.update_allowed,
          policy_reason: update_check.policy_reason,
          failure_tracker: @failure_tracker.status,
          recent_updates: @update_logger.recent_entries(limit: 5)
        }
      end

      # Perform hot code reload without restarting the process
      #
      # This method performs a git pull and then uses Zeitwerk to reload
      # all Ruby classes. Unlike initiate_update (which exits with code 75),
      # this method keeps the process running.
      #
      # @param update_check [UpdateCheck] Update check result
      # @return [Boolean] Whether reload was successful
      # @raise [UpdateError] If updates are disabled or reload fails
      def hot_reload_update(update_check = nil)
        raise UpdateError, "Updates disabled by configuration" unless @policy.enabled

        # Verify Zeitwerk loader is set up for reloading
        unless Aidp::Loader.setup? && Aidp::Loader.reloading?
          Aidp.log_warn("auto_update_coordinator", "hot_reload_not_available",
            reason: "Zeitwerk loader not configured for reloading")
          raise UpdateError, "Hot reloading not available. Loader must be configured with enable_reloading: true"
        end

        update_check ||= check_for_update
        return false unless update_check.should_update?

        from_version = update_check.current_version
        to_version = update_check.available_version

        Aidp.log_info("auto_update_coordinator", "hot_reload_starting",
          from_version: from_version,
          to_version: to_version)

        # Perform git pull
        unless perform_git_pull
          raise UpdateError, "Git pull failed"
        end

        # Reload all classes using Zeitwerk
        unless Aidp::Loader.reload!
          @failure_tracker.record_failure
          @update_logger.log_failure("Zeitwerk reload failed")
          raise UpdateError, "Zeitwerk reload failed"
        end

        # Log success
        @update_logger.log_success(
          from_version: from_version,
          to_version: to_version
        )
        @failure_tracker.reset_on_success

        Aidp.log_info("auto_update_coordinator", "hot_reload_complete",
          from_version: from_version,
          to_version: to_version)

        true
      rescue UpdateError
        raise
      rescue => e
        @failure_tracker.record_failure
        @update_logger.log_failure("Hot reload failed: #{e.message}")
        Aidp.log_error("auto_update_coordinator", "hot_reload_failed",
          error: e.message)
        raise UpdateError, "Hot reload failed: #{e.message}"
      end

      # Check if hot reloading is available
      # @return [Boolean]
      def hot_reload_available?
        Aidp::Loader.setup? && Aidp::Loader.reloading?
      end

      private

      # Perform git pull to fetch latest code
      # @return [Boolean] Whether pull was successful
      def perform_git_pull
        require "open3"

        Aidp.log_debug("auto_update_coordinator", "git_pull_starting",
          project_dir: @project_dir)

        Dir.chdir(@project_dir) do
          stdout, stderr, status = Open3.capture3("git", "pull", "--ff-only")

          if status.success?
            Aidp.log_info("auto_update_coordinator", "git_pull_success",
              output: stdout.strip)
            true
          else
            Aidp.log_error("auto_update_coordinator", "git_pull_failed",
              stderr: stderr.strip,
              exit_code: status.exitstatus)
            false
          end
        end
      rescue => e
        Aidp.log_error("auto_update_coordinator", "git_pull_error",
          error: e.message)
        false
      end

      def build_checkpoint(current_state, target_version)
        Checkpoint.new(
          mode: current_state[:mode] || "watch",
          watch_state: current_state[:watch_state]
        ).tap do |cp|
          # Store target version in metadata for logging
          cp.instance_variable_set(:@target_version, target_version)
        end
      end
    end
  end
end
