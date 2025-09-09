# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../execute/progress"
require_relative "../analyze/progress"
require_relative "../execute/steps"
require_relative "../analyze/steps"

module Aidp
  module Harness
    # Manages harness-specific state and persistence, extending existing progress tracking
    class StateManager
      def initialize(project_dir, mode)
        @project_dir = project_dir
        @mode = mode
        @state_dir = File.join(project_dir, ".aidp", "harness")
        @state_file = File.join(@state_dir, "#{mode}_state.json")
        @lock_file = File.join(@state_dir, "#{mode}_state.lock")

        # Initialize the appropriate progress tracker
        case mode
        when :analyze
          @progress_tracker = Aidp::Analyze::Progress.new(project_dir)
        when :execute
          @progress_tracker = Aidp::Execute::Progress.new(project_dir)
        else
          raise ArgumentError, "Unsupported mode: #{mode}"
        end

        ensure_state_directory
      end

      # Check if state exists
      def has_state?
        File.exist?(@state_file)
      end

      # Load existing state
      def load_state
        return {} unless has_state?

        with_lock do
          begin
            content = File.read(@state_file)
            JSON.parse(content, symbolize_names: true)
          rescue JSON::ParserError => e
            warn "Failed to parse state file: #{e.message}"
            {}
          end
        end
      end

      # Save current state
      def save_state(state_data)
        with_lock do
          # Add metadata
          state_with_metadata = state_data.merge(
            mode: @mode,
            project_dir: @project_dir,
            saved_at: Time.now.iso8601
          )

          # Write to temporary file first, then rename (atomic operation)
          temp_file = "#{@state_file}.tmp"
          File.write(temp_file, JSON.pretty_generate(state_with_metadata))
          File.rename(temp_file, @state_file)
        end
      end

      # Clear state (for fresh start)
      def clear_state
        with_lock do
          File.delete(@state_file) if File.exist?(@state_file)
        end
      end

      # Get state metadata
      def state_metadata
        return {} unless has_state?

        state = load_state
        {
          mode: state[:mode],
          saved_at: state[:saved_at],
          current_step: state[:current_step],
          state: state[:state],
          last_updated: state[:last_updated]
        }
      end

      # Update specific state fields
      def update_state(updates)
        current_state = load_state
        updated_state = current_state.merge(updates)
        save_state(updated_state)
      end

      # Get current step from state (legacy method - use progress tracker integration instead)
      def current_step_from_state
        state = load_state
        state[:current_step]
      end

      # Set current step
      def set_current_step(step_name)
        update_state(current_step: step_name, last_updated: Time.now)
      end

      # Get user input from state
      def user_input
        state = load_state
        state[:user_input] || {}
      end

      # Add user input
      def add_user_input(key, value)
        current_input = user_input
        current_input[key] = value
        update_state(user_input: current_input, last_updated: Time.now)
      end

      # Get execution log
      def execution_log
        state = load_state
        state[:execution_log] || []
      end

      # Add to execution log
      def add_execution_log(entry)
        current_log = execution_log
        current_log << entry
        update_state(execution_log: current_log, last_updated: Time.now)
      end

      # Get provider state
      def provider_state
        state = load_state
        state[:provider_state] || {}
      end

      # Update provider state
      def update_provider_state(provider_name, provider_data)
        current_provider_state = provider_state
        current_provider_state[provider_name] = provider_data
        update_state(provider_state: current_provider_state, last_updated: Time.now)
      end

      # Get rate limit information
      def rate_limit_info
        state = load_state
        state[:rate_limit_info] || {}
      end

      # Update rate limit information
      def update_rate_limit_info(provider_name, reset_time, error_count = 0)
        current_info = rate_limit_info
        current_info[provider_name] = {
          reset_time: reset_time&.iso8601,
          error_count: error_count,
          last_updated: Time.now.iso8601
        }
        update_state(rate_limit_info: current_info, last_updated: Time.now)
      end

      # Check if provider is rate limited
      def provider_rate_limited?(provider_name)
        info = rate_limit_info[provider_name]
        return false unless info

        reset_time = Time.parse(info[:reset_time]) if info[:reset_time]
        reset_time && Time.now < reset_time
      end

      # Get next available provider reset time
      def next_provider_reset_time
        rate_limit_info.map do |_provider, info|
          Time.parse(info[:reset_time]) if info[:reset_time]
        end.compact.min
      end

      # Clean up old state (older than specified days)
      def cleanup_old_state(days_old = 7)
        return unless has_state?

        state = load_state
        saved_at = Time.parse(state[:saved_at]) if state[:saved_at]

        if saved_at && (Time.now - saved_at) > (days_old * 24 * 60 * 60)
          clear_state
          true
        else
          false
        end
      end

      # Export state for debugging
      def export_state
        {
          state_file: @state_file,
          has_state: has_state?,
          metadata: state_metadata,
          state: load_state
        }
      end

      # Progress tracking integration methods

      # Get the underlying progress tracker
      def progress_tracker
        @progress_tracker
      end

      # Get completed steps from progress tracker
      def completed_steps
        @progress_tracker.completed_steps
      end

      # Get current step from progress tracker
      def current_step
        @progress_tracker.current_step
      end

      # Check if step is completed
      def step_completed?(step_name)
        @progress_tracker.step_completed?(step_name)
      end

      # Mark step as completed
      def mark_step_completed(step_name)
        @progress_tracker.mark_step_completed(step_name)
        # Also update harness state
        update_state(current_step: nil, last_step_completed: step_name)
      end

      # Mark step as in progress
      def mark_step_in_progress(step_name)
        @progress_tracker.mark_step_in_progress(step_name)
        # Also update harness state
        update_state(current_step: step_name)
      end

      # Get next step to execute
      def next_step
        @progress_tracker.next_step
      end

      # Get total steps count
      def total_steps
        case @mode
        when :analyze
          Aidp::Analyze::Steps::SPEC.keys.size
        when :execute
          Aidp::Execute::Steps::SPEC.keys.size
        else
          0
        end
      end

      # Check if all steps are completed
      def all_steps_completed?
        completed_steps.size == total_steps
      end

      # Reset both progress and harness state
      def reset_all
        @progress_tracker.reset
        clear_state
      end

      # Get progress summary
      def progress_summary
        {
          mode: @mode,
          completed_steps: completed_steps.size,
          total_steps: total_steps,
          current_step: current_step,
          next_step: next_step,
          all_completed: all_steps_completed?,
          started_at: @progress_tracker.started_at,
          harness_state: has_state? ? load_state : {}
        }
      end

      private

      def ensure_state_directory
        FileUtils.mkdir_p(@state_dir) unless Dir.exist?(@state_dir)
      end

      def with_lock(&_block)
        # Simple file-based locking
        lock_acquired = false
        timeout = 30 # 30 seconds timeout

        begin
          # Try to acquire lock
          File.open(@lock_file, File::CREAT | File::EXCL | File::WRONLY) do |_lock|
            lock_acquired = true
            yield
          end
        rescue Errno::EEXIST
          # Lock file exists, wait for it to be released
          start_time = Time.now
          while File.exist?(@lock_file) && (Time.now - start_time) < timeout
            sleep(0.1)
          end

          if File.exist?(@lock_file)
            raise "Could not acquire state lock within #{timeout} seconds"
          else
            # Retry once more
            retry
          end
        ensure
          # Clean up lock file
          File.delete(@lock_file) if lock_acquired && File.exist?(@lock_file)
        end
      end
    end
  end
end
