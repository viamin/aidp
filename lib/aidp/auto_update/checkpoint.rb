# frozen_string_literal: true

require "securerandom"
require "time"
require "socket"
require "digest"

module Aidp
  module AutoUpdate
    # Aggregate root representing a complete state snapshot for restart recovery
    class Checkpoint
      attr_reader :checkpoint_id, :created_at, :aidp_version, :mode, :watch_state,
        :metadata, :checksum

      SCHEMA_VERSION = 1

      def initialize(
        mode:, checkpoint_id: SecureRandom.uuid,
        created_at: Time.now,
        aidp_version: Aidp::VERSION,
        watch_state: nil,
        metadata: {},
        checksum: nil
      )
        @checkpoint_id = checkpoint_id
        @created_at = created_at
        @aidp_version = aidp_version
        @mode = validate_mode(mode)
        @watch_state = watch_state
        @metadata = default_metadata.merge(metadata)
        @checksum = checksum || compute_checksum
      end

      # Create checkpoint from current watch mode state
      # @param runner [Aidp::Watch::Runner] Watch mode runner
      # @return [Checkpoint]
      def self.from_watch_runner(runner)
        new(
          mode: "watch",
          watch_state: {
            repository: runner.instance_variable_get(:@repository_client).full_repo,
            interval: runner.instance_variable_get(:@interval),
            provider_name: runner.instance_variable_get(:@plan_processor).instance_variable_get(:@plan_generator).instance_variable_get(:@provider_name),
            persona: nil, # Not currently tracked in runner
            safety_config: runner.instance_variable_get(:@safety_checker).instance_variable_get(:@config),
            worktree_context: capture_worktree_context,
            state_store_snapshot: runner.instance_variable_get(:@state_store).send(:state)
          }
        )
      end

      # Create checkpoint from hash (deserialization)
      # @param hash [Hash] Serialized checkpoint data
      # @return [Checkpoint]
      def self.from_h(hash)
        new(
          checkpoint_id: hash[:checkpoint_id] || hash["checkpoint_id"],
          created_at: Time.parse(hash[:created_at] || hash["created_at"]),
          aidp_version: hash[:aidp_version] || hash["aidp_version"],
          mode: hash[:mode] || hash["mode"],
          watch_state: hash[:watch_state] || hash["watch_state"],
          metadata: hash[:metadata] || hash["metadata"] || {},
          checksum: hash[:checksum] || hash["checksum"]
        )
      end

      # Convert to hash for serialization
      # @return [Hash]
      def to_h
        {
          schema_version: SCHEMA_VERSION,
          checkpoint_id: @checkpoint_id,
          created_at: @created_at.utc.iso8601(6), # Preserve microsecond precision
          aidp_version: @aidp_version,
          mode: @mode,
          watch_state: @watch_state,
          metadata: @metadata,
          checksum: @checksum
        }
      end

      # Verify checkpoint integrity
      # @return [Boolean]
      def valid?
        @checksum == compute_checksum
      end

      # Check if checkpoint is for watch mode
      # @return [Boolean]
      def watch_mode?
        @mode == "watch"
      end

      # Check if checkpoint is compatible with current Aidp version
      # @return [Boolean]
      def compatible_version?
        # Allow restoring from same major.minor version
        checkpoint_ver = Gem::Version.new(@aidp_version)
        current_ver = Gem::Version.new(Aidp::VERSION)

        checkpoint_ver.segments[0] == current_ver.segments[0] &&
          checkpoint_ver.segments[1] == current_ver.segments[1]
      rescue ArgumentError
        false
      end

      private

      def validate_mode(mode)
        valid_modes = %w[watch execute analyze]
        unless valid_modes.include?(mode.to_s)
          raise ArgumentError, "Invalid mode: #{mode}. Must be one of: #{valid_modes.join(", ")}"
        end
        mode.to_s
      end

      def default_metadata
        {
          hostname: Socket.gethostname,
          project_dir: Dir.pwd,
          ruby_version: RUBY_VERSION
        }
      end

      def compute_checksum
        # Compute SHA256 of checkpoint data (excluding checksum field)
        # Use canonical JSON with sorted keys for deterministic hashing
        data = {
          checkpoint_id: @checkpoint_id,
          created_at: @created_at.utc.iso8601(6), # Preserve microsecond precision
          aidp_version: @aidp_version,
          mode: @mode,
          watch_state: @watch_state,
          metadata: @metadata
        }

        canonical_json = JSON.generate(sort_keys(data))
        Digest::SHA256.hexdigest(canonical_json)
      end

      def sort_keys(obj)
        case obj
        when Hash
          # Convert all keys to strings and sort for consistent ordering
          obj.transform_keys(&:to_s).sort.to_h { |k, v| [k, sort_keys(v)] }
        when Array
          obj.map { |v| sort_keys(v) }
        else
          obj
        end
      end

      class << self
        private

        def capture_worktree_context
          return {} unless system("git rev-parse --git-dir > /dev/null 2>&1")

          {
            branch: `git rev-parse --abbrev-ref HEAD`.strip,
            commit_sha: `git rev-parse HEAD`.strip,
            remote_url: `git config --get remote.origin.url`.strip
          }
        rescue => e
          Aidp.log_debug("checkpoint", "worktree_context_unavailable", error: e.message)
          {}
        end
      end
    end
  end
end
