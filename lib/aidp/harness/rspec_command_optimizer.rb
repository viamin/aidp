# frozen_string_literal: true

module Aidp
  module Harness
    # Optimizes RSpec command execution by using --only-failures on subsequent runs.
    # This dramatically reduces both execution time and output volume when fixing
    # failing tests during work loops.
    #
    # Requirements:
    # - RSpec must be configured with example_status_persistence_file_path in spec_helper.rb
    # - A .rspec_status file (or configured path) must exist from a previous run
    #
    # @example
    #   optimizer = RSpecCommandOptimizer.new("/path/to/project")
    #   result = optimizer.optimize_command("bundle exec rspec", iteration: 2, had_failures: true)
    #   # => "bundle exec rspec --only-failures"
    #
    class RSpecCommandOptimizer
      # Default paths where RSpec stores example status
      DEFAULT_STATUS_PATHS = [
        ".rspec_status",
        "tmp/.rspec_status",
        "spec/.rspec_status"
      ].freeze

      # Common spec_helper paths to check for persistence configuration
      SPEC_HELPER_PATHS = [
        "spec/spec_helper.rb",
        "spec/rails_helper.rb"
      ].freeze

      attr_reader :project_dir

      def initialize(project_dir)
        @project_dir = project_dir
        @status_file_cache = nil
        @persistence_configured_cache = nil
      end

      # Optimize an RSpec command based on iteration context
      #
      # @param command [String] The original RSpec command
      # @param iteration [Integer] Current iteration number (1-indexed)
      # @param had_failures [Boolean] Whether the previous iteration had test failures
      # @return [Hash] { command: String, optimized: Boolean, reason: String }
      def optimize_command(command, iteration:, had_failures:)
        return skip_optimization(command, "not an RSpec command") unless rspec_command?(command)
        return skip_optimization(command, "first iteration") if iteration <= 1
        return skip_optimization(command, "no previous failures") unless had_failures
        return skip_optimization(command, "already has --only-failures") if command.include?("--only-failures")

        status_file = find_status_file
        unless status_file
          Aidp.log_debug("rspec_optimizer", "no_status_file",
            project_dir: @project_dir,
            checked_paths: DEFAULT_STATUS_PATHS)

          return skip_optimization(command, "no .rspec_status file found - see setup instructions")
        end

        optimized_command = add_only_failures_flag(command)

        Aidp.log_info("rspec_optimizer", "command_optimized",
          original: command,
          optimized: optimized_command,
          iteration: iteration,
          status_file: status_file)

        {
          command: optimized_command,
          optimized: true,
          reason: "using --only-failures (iteration #{iteration})",
          status_file: status_file
        }
      end

      # Check if RSpec persistence is properly configured in this project
      #
      # @return [Hash] { configured: Boolean, file_path: String, message: String }
      def check_persistence_configuration
        return @persistence_configured_cache if @persistence_configured_cache

        @persistence_configured_cache = begin
          # Check if any spec_helper configures persistence
          configured_in_spec_helper = SPEC_HELPER_PATHS.any? do |path|
            full_path = File.join(@project_dir, path)
            next false unless File.exist?(full_path)

            content = File.read(full_path, encoding: "UTF-8")
            content.include?("example_status_persistence_file_path")
          end

          if configured_in_spec_helper
            status_file = find_status_file
            {
              configured: true,
              file_path: status_file,
              message: "RSpec persistence configured" + (status_file ? " (#{status_file} exists)" : " (waiting for first run)")
            }
          else
            {
              configured: false,
              file_path: nil,
              message: "RSpec persistence not configured. Add to spec_helper.rb:\n" \
                       "  config.example_status_persistence_file_path = '.rspec_status'"
            }
          end
        end
      end

      # Find the RSpec status file if it exists
      #
      # @return [String, nil] Path to status file or nil if not found
      def find_status_file
        return @status_file_cache if @status_file_cache

        @status_file_cache = DEFAULT_STATUS_PATHS.find do |path|
          full_path = File.join(@project_dir, path)
          File.exist?(full_path)
        end
      end

      # Check if command is an RSpec command
      #
      # @param command [String] Command to check
      # @return [Boolean]
      def rspec_command?(command)
        return false unless command.is_a?(String)
        command.downcase.include?("rspec")
      end

      # Reset caches (useful after test runs that may create status file)
      def reset_caches!
        @status_file_cache = nil
        @persistence_configured_cache = nil
      end

      private

      def skip_optimization(command, reason)
        {
          command: command,
          optimized: false,
          reason: reason
        }
      end

      def add_only_failures_flag(command)
        # Insert --only-failures before any file arguments
        # "bundle exec rspec" -> "bundle exec rspec --only-failures"
        # "bundle exec rspec spec/foo_spec.rb" -> "bundle exec rspec --only-failures spec/foo_spec.rb"
        parts = command.split(/\s+/)
        rspec_index = parts.index { |p| p.downcase == "rspec" }

        if rspec_index
          # Insert after "rspec" but before any file arguments
          parts.insert(rspec_index + 1, "--only-failures")
          parts.join(" ")
        else
          # Fallback: append to end
          "#{command} --only-failures"
        end
      end
    end
  end
end
