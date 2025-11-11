# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Aidp
  module AutoUpdate
    # Service for tracking update failures to prevent restart loops
    class FailureTracker
      attr_reader :state_file, :max_failures

      def initialize(project_dir: Dir.pwd, max_failures: 3)
        @project_dir = project_dir
        @state_file = File.join(project_dir, ".aidp", "auto_update_failures.json")
        @max_failures = max_failures
        @state = load_state
        ensure_state_directory
      end

      # Record a failure
      def record_failure
        @state[:failures] << {
          timestamp: Time.now.utc.iso8601,
          version: Aidp::VERSION
        }

        # Keep only recent failures (last hour)
        @state[:failures].select! { |f|
          Time.parse(f[:timestamp]) > Time.now - 3600
        }

        save_state

        Aidp.log_warn("failure_tracker", "failure_recorded",
          total_failures: @state[:failures].size,
          max_failures: @max_failures)
      rescue => e
        Aidp.log_error("failure_tracker", "record_failure_failed",
          error: e.message)
      end

      # Check if too many consecutive failures have occurred
      # @return [Boolean]
      def too_many_failures?
        failure_count = @state[:failures].size
        is_looping = failure_count >= @max_failures

        if is_looping
          Aidp.log_error("failure_tracker", "restart_loop_detected",
            failure_count: failure_count,
            max_failures: @max_failures)
        end

        is_looping
      end

      # Reset failure count after successful operation
      def reset_on_success
        previous_failures = @state[:failures].size

        @state[:failures] = []
        @state[:last_success] = Time.now.utc.iso8601
        @state[:last_success_version] = Aidp::VERSION

        save_state

        Aidp.log_info("failure_tracker", "reset_on_success",
          previous_failures: previous_failures,
          version: Aidp::VERSION)
      rescue => e
        Aidp.log_error("failure_tracker", "reset_failed",
          error: e.message)
      end

      # Get current failure count
      # @return [Integer]
      def failure_count
        @state[:failures].size
      end

      # Get time since last success
      # @return [Integer, nil] Seconds since last success, or nil if never successful
      def time_since_last_success
        return nil unless @state[:last_success]

        Time.now - Time.parse(@state[:last_success])
      rescue => e
        Aidp.log_error("failure_tracker", "time_calculation_failed",
          error: e.message)
        nil
      end

      # Get all failure timestamps
      # @return [Array<Time>]
      def failure_timestamps
        @state[:failures].map { |f| Time.parse(f[:timestamp]) }
      rescue => e
        Aidp.log_error("failure_tracker", "timestamp_parsing_failed",
          error: e.message)
        []
      end

      # Manually reset failures (for CLI command or recovery)
      def force_reset
        Aidp.log_warn("failure_tracker", "manual_reset_triggered",
          previous_failures: @state[:failures].size)

        @state[:failures] = []
        save_state
      end

      # Get state summary for status display
      # @return [Hash]
      def status
        {
          failure_count: failure_count,
          max_failures: @max_failures,
          too_many_failures: too_many_failures?,
          last_success: @state[:last_success],
          last_success_version: @state[:last_success_version],
          recent_failures: @state[:failures]
        }
      end

      private

      def load_state
        return default_state unless File.exist?(@state_file)

        JSON.parse(File.read(@state_file), symbolize_names: true)
      rescue JSON::ParserError => e
        Aidp.log_warn("failure_tracker", "state_file_corrupted",
          error: e.message)
        default_state
      rescue => e
        Aidp.log_warn("failure_tracker", "load_state_failed",
          error: e.message)
        default_state
      end

      def save_state
        File.write(@state_file, JSON.pretty_generate(@state))
      rescue => e
        Aidp.log_error("failure_tracker", "save_state_failed",
          error: e.message)
      end

      def default_state
        {
          failures: [],
          last_success: nil,
          last_success_version: nil
        }
      end

      def ensure_state_directory
        FileUtils.mkdir_p(File.dirname(@state_file))
      rescue => e
        Aidp.log_error("failure_tracker", "mkdir_failed",
          dir: File.dirname(@state_file),
          error: e.message)
      end
    end
  end
end
