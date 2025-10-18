# frozen_string_literal: true

require "json"
require "fileutils"

module Aidp
  module Harness
    module State
      # Handles file I/O and persistence for state management
      class Persistence
        def initialize(project_dir, mode)
          @project_dir = project_dir
          @mode = mode
          @state_dir = File.join(project_dir, ".aidp", "harness")
          @state_file = File.join(@state_dir, "#{mode}_state.json")
          @lock_file = File.join(@state_dir, "#{mode}_state.lock")
          ensure_state_directory
        end

        def has_state?
          return false if test_mode?
          File.exist?(@state_file)
        end

        def load_state
          return {} if test_mode? || !has_state?

          with_lock do
            content = File.read(@state_file)
            JSON.parse(content, symbolize_names: true)
          rescue JSON::ParserError => e
            warn "Failed to parse state file: #{e.message}"
            {}
          end
        end

        def save_state(state_data)
          return if test_mode?

          with_lock do
            state_with_metadata = add_metadata(state_data)
            write_atomically(state_with_metadata)
          end
        end

        def clear_state
          return if test_mode?

          with_lock do
            File.delete(@state_file) if File.exist?(@state_file)
          end
        end

        private

        def test_mode?
          ENV["RACK_ENV"] == "test" || defined?(RSpec)
        end

        def add_metadata(state_data)
          state_data.merge(
            mode: @mode,
            project_dir: @project_dir,
            saved_at: Time.now.iso8601
          )
        end

        def write_atomically(state_with_metadata)
          temp_file = "#{@state_file}.tmp"
          File.write(temp_file, JSON.pretty_generate(state_with_metadata))
          File.rename(temp_file, @state_file)
        end

        def ensure_state_directory
          FileUtils.mkdir_p(@state_dir) unless Dir.exist?(@state_dir)
        end

        def with_lock(&block)
          return yield if test_mode?

          acquire_lock_with_timeout(&block)
        ensure
          cleanup_lock_file
        end

        def acquire_lock_with_timeout(&block)
          lock_acquired = false
          timeout = 30
          start_time = Time.now

          while (Time.now - start_time) < timeout
            lock_acquired = try_acquire_lock(&block)
            break if lock_acquired
            sleep_briefly
          end

          raise_lock_timeout_error unless lock_acquired
        end

        def try_acquire_lock(&block)
          File.open(@lock_file, File::CREAT | File::EXCL | File::WRONLY) do |_lock|
            yield
            true
          end
        rescue Errno::EEXIST
          false
        end

        def sleep_briefly
          # Brief sleep for lock retry - using simple sleep is fine here
          sleep(0.1)
        end

        def raise_lock_timeout_error
          raise "Could not acquire state lock within 30 seconds"
        end

        def cleanup_lock_file
          File.delete(@lock_file) if File.exist?(@lock_file)
        end
      end
    end
  end
end
