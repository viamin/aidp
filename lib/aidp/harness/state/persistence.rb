# frozen_string_literal: true

require "json"
require "fileutils"

module Aidp
  module Harness
    module State
      # Handles file I/O and persistence for state management
      class Persistence
        def initialize(project_dir, mode, skip_persistence: false)
          @project_dir = project_dir
          @mode = mode
          @state_dir = File.join(project_dir, ".aidp", "harness")
          @state_file = File.join(@state_dir, "#{mode}_state.json")
          @lock_file = File.join(@state_dir, "#{mode}_state.lock")
          # Use explicit skip_persistence flag for dependency injection
          # Callers should set skip_persistence: true for test/dry-run scenarios
          @skip_persistence = skip_persistence
          ensure_state_directory
          Aidp.log_debug("state_persistence", "initialized", mode: @mode, skip: @skip_persistence, dir: @state_dir)
        end

        def has_state?
          return false if @skip_persistence
          exists = File.exist?(@state_file)
          Aidp.log_debug("state_persistence", "has_state?", exists: exists, file: @state_file) if exists
          exists
        end

        def load_state
          return {} if @skip_persistence || !has_state?

          with_lock do
            Aidp.log_debug("state_persistence", "load_state.start", file: @state_file)
            content = File.read(@state_file)
            parsed = JSON.parse(content, symbolize_names: true)
            Aidp.log_debug("state_persistence", "load_state.success", keys: parsed.keys.size, file: @state_file)
            parsed
          rescue JSON::ParserError => e
            Aidp.log_warn("state_persistence", "parse_error", error: e.message, file: @state_file)
            {}
          end
        end

        def save_state(state_data)
          return if @skip_persistence

          with_lock do
            Aidp.log_debug("state_persistence", "save_state.start", keys: state_data.keys.size)
            state_with_metadata = add_metadata(state_data)
            write_atomically(state_with_metadata)
            Aidp.log_debug("state_persistence", "save_state.written", file: @state_file, size: state_with_metadata.keys.size)
          end
        end

        def clear_state
          return if @skip_persistence

          with_lock do
            Aidp.log_debug("state_persistence", "clear_state.start", file: @state_file)
            File.delete(@state_file) if File.exist?(@state_file)
            Aidp.log_debug("state_persistence", "clear_state.done", file: @state_file)
          end
        end

        private

        def add_metadata(state_data)
          state_data.merge(
            mode: @mode,
            project_dir: @project_dir,
            saved_at: Time.now.iso8601
          )
        end

        def write_atomically(state_with_metadata)
          temp_file = "#{@state_file}.tmp"
          Aidp.log_debug("state_persistence", "write_atomically.start", temp: temp_file)
          File.write(temp_file, JSON.pretty_generate(state_with_metadata))
          File.rename(temp_file, @state_file)
          Aidp.log_debug("state_persistence", "write_atomically.rename", file: @state_file)
        end

        def ensure_state_directory
          FileUtils.mkdir_p(@state_dir) unless Dir.exist?(@state_dir)
        end

        def with_lock(&block)
          return yield if @skip_persistence
          result = acquire_lock_with_timeout(&block)
          result
        ensure
          cleanup_lock_file
        end

        def acquire_lock_with_timeout(&block)
          timeout = ENV["AIDP_STATE_LOCK_TIMEOUT"]&.to_f || ((ENV["RSPEC_RUNNING"] == "true") ? 1.0 : 30.0)
          start_time = Time.now
          attempt_result = nil
          while (Time.now - start_time) < timeout
            acquired, attempt_result = try_acquire_lock(&block)
            return attempt_result if acquired
            sleep_briefly
          end
          raise_lock_timeout_error(timeout)
        end

        def try_acquire_lock(&block)
          File.open(@lock_file, File::CREAT | File::EXCL | File::WRONLY) do |_lock|
            Aidp.log_debug("state_persistence", "lock.acquired", file: @lock_file)
            [true, yield]
          end
        rescue Errno::EEXIST
          Aidp.log_debug("state_persistence", "lock.busy", file: @lock_file)
          [false, nil]
        end

        def sleep_briefly
          sleep(ENV["AIDP_STATE_LOCK_SLEEP"]&.to_f || 0.05)
        end

        def raise_lock_timeout_error(timeout)
          # Prefer explicit error class; fall back if not defined yet
          error_class = defined?(Aidp::Errors::StateError) ? Aidp::Errors::StateError : RuntimeError
          Aidp.log_error("state_persistence", "lock.timeout", file: @lock_file, waited: timeout)
          raise error_class, "Could not acquire state lock within #{timeout} seconds"
        end

        def cleanup_lock_file
          if File.exist?(@lock_file)
            File.delete(@lock_file)
            Aidp.log_debug("state_persistence", "lock.cleaned", file: @lock_file)
          end
        end
      end
    end
  end
end
