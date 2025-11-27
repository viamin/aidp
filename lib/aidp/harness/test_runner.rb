# frozen_string_literal: true

require "open3"
require_relative "../tooling_detector"
require_relative "output_filter"
require_relative "output_filter_config"

module Aidp
  module Harness
    # Executes test and linter commands configured in aidp.yml
    # Returns results with exit status and output
    # Applies intelligent output filtering to reduce token consumption
    class TestRunner
      def initialize(project_dir, config)
        @project_dir = project_dir
        @config = config
        @iteration_count = 0
        @filter_stats = { total_input_bytes: 0, total_output_bytes: 0 }
      end

      # Run all configured tests
      # Returns: { success: boolean, output: string, failures: array, required_failures: array }
      def run_tests
        @iteration_count += 1
        run_command_category(:test, "Tests")
      end

      # Run all configured linters
      # Returns: { success: boolean, output: string, failures: array, required_failures: array }
      def run_linters
        @iteration_count += 1
        run_command_category(:lint, "Linters")
      end

      # Run all configured formatters
      # Returns: { success: boolean, output: string, failures: array, required_failures: array }
      def run_formatters
        run_command_category(:formatter, "Formatters")
      end

      # Run all configured build commands
      # Returns: { success: boolean, output: string, failures: array, required_failures: array }
      def run_builds
        run_command_category(:build, "Build")
      end

      # Run all configured documentation commands
      # Returns: { success: boolean, output: string, failures: array, required_failures: array }
      def run_documentation
        run_command_category(:documentation, "Documentation")
      end

      # Preview the commands that will run for each category so callers can log intent
      # Returns a hash of category => array of normalized command entries
      def planned_commands
        {
          tests: resolved_commands(:test),
          lints: resolved_commands(:lint),
          formatters: resolved_commands(:formatter),
          builds: resolved_commands(:build),
          docs: resolved_commands(:documentation)
        }
      end

      # Get current iteration count
      attr_reader :iteration_count

      # Get filtering statistics
      attr_reader :filter_stats

      # Reset iteration counter (useful for testing)
      def reset_iteration_count
        @iteration_count = 0
      end

      private

      # Run commands for a specific category (test, lint, formatter, build, documentation)
      def run_command_category(category, display_name)
        commands = resolved_commands(category)

        # If no commands configured, return success (empty check passes)
        return {success: true, output: "", failures: [], required_failures: []} if commands.empty?

        # Determine output mode based on category
        mode = determine_output_mode(category)

        Aidp.log_debug("test_runner", "running_category",
          category: category,
          command_count: commands.length,
          iteration: @iteration_count,
          output_mode: mode)

        # Execute all commands
        results = commands.map do |cmd_config|
          # Handle both string commands (legacy) and hash format (new)
          if cmd_config.is_a?(String)
            result = execute_command(cmd_config, category.to_s)
            result.merge(required: true)
          else
            result = execute_command(cmd_config[:command], category.to_s)
            result.merge(required: cmd_config[:required])
          end
        end

        aggregate_results(results, display_name, mode: mode)
      rescue NameError
        # Logging not available
        commands = resolved_commands(category)
        return {success: true, output: "", failures: [], required_failures: []} if commands.empty?

        mode = determine_output_mode(category)
        results = commands.map do |cmd_config|
          if cmd_config.is_a?(String)
            result = execute_command(cmd_config, category.to_s)
            result.merge(required: true)
          else
            result = execute_command(cmd_config[:command], category.to_s)
            result.merge(required: cmd_config[:required])
          end
        end

        aggregate_results(results, display_name, mode: mode)
      end

      def execute_command(command, type)
        stdout, stderr, status = Open3.capture3(command, chdir: @project_dir)

        {
          command: command,
          type: type,
          success: status.success?,
          exit_code: status.exitstatus,
          stdout: stdout,
          stderr: stderr
        }
      end

      def aggregate_results(results, category, mode: :full)
        # Separate required and optional command failures
        all_failures = results.reject { |r| r[:success] }
        required_failures = all_failures.select { |r| r[:required] }
        optional_failures = all_failures.reject { |r| r[:required] }

        # Success only if all REQUIRED commands pass
        # Optional command failures don't block completion
        success = required_failures.empty?

        output = if all_failures.empty?
          "#{category}: All passed (#{results.length} commands)"
        elsif required_failures.empty?
          "#{category}: Required checks passed (#{optional_failures.length} optional warnings)\n" +
            format_failures(optional_failures, "#{category} - Optional", mode: mode)
        else
          format_failures(required_failures, "#{category} - Required", mode: mode) +
            (optional_failures.any? ? "\n" + format_failures(optional_failures, "#{category} - Optional", mode: mode) : "")
        end

        # Add filtering summary if filtering was applied
        if mode != :full && all_failures.any?
          output += "\n[Output filtered: mode=#{mode}]"
        end

        {
          success: success,
          output: output,
          failures: all_failures,
          required_failures: required_failures,
          optional_failures: optional_failures
        }
      end

      def format_failures(failures, category, mode: :full)
        output = ["#{category} Failures:", ""]

        failures.each do |failure|
          output << "Command: #{failure[:command]}"
          output << "Exit Code: #{failure[:exit_code]}"
          output << "--- Output ---"

          # Detect framework for filtering
          framework = detect_framework_from_command(failure[:command])

          # Apply filtering based on mode and framework
          filtered_stdout = filter_output(failure[:stdout], mode, framework, :test)
          filtered_stderr = filter_output(failure[:stderr], mode, :unknown, :lint)

          output << filtered_stdout unless filtered_stdout.strip.empty?
          output << filtered_stderr unless filtered_stderr.strip.empty?
          output << ""
        end

        output.join("\n")
      end

      def filter_output(raw_output, mode, framework, category)
        return raw_output if mode == :full || raw_output.nil? || raw_output.empty?

        # Build filter config from configuration or defaults
        filter_config = build_filter_config(mode, category)

        # Track input size for stats
        @filter_stats[:total_input_bytes] += raw_output.bytesize

        filter = OutputFilter.new(filter_config)
        filtered = filter.filter(raw_output, framework: framework)

        # Track output size for stats
        @filter_stats[:total_output_bytes] += filtered.bytesize

        Aidp.log_debug("test_runner", "output_filtered",
          framework: framework,
          mode: mode,
          input_size: raw_output.bytesize,
          output_size: filtered.bytesize)

        filtered
      rescue NameError
        # Logging infrastructure not available
        raw_output
      rescue => e
        begin
          Aidp.log_warn("test_runner", "filter_failed",
            error: e.message,
            framework: framework)
        rescue NameError
          # Logging not available
        end
        raw_output  # Fallback to unfiltered on error
      end

      def build_filter_config(mode, category)
        config_hash = {
          mode: mode,
          include_context: output_filtering_include_context,
          context_lines: output_filtering_context_lines,
          max_lines: max_output_lines_for_category(category)
        }

        OutputFilterConfig.from_hash(config_hash)
      end

      def detect_framework_from_command(command)
        # Use ToolingDetector's enhanced framework detection
        Aidp::ToolingDetector.framework_from_command(command)
      end

      def determine_output_mode(category)
        # Check config for category-specific mode
        case category
        when :test
          configured_mode = test_output_mode_from_config
          return configured_mode if configured_mode

          # Default: full on first iteration, failures_only after
          @iteration_count > 1 ? :failures_only : :full
        when :lint
          configured_mode = lint_output_mode_from_config
          return configured_mode if configured_mode

          # Default: full on first iteration, failures_only after
          @iteration_count > 1 ? :failures_only : :full
        else
          :full
        end
      end

      def test_output_mode_from_config
        return nil unless @config.respond_to?(:test_output_mode)
        mode = @config.test_output_mode
        return nil if mode.nil?
        mode.to_sym
      rescue
        nil
      end

      def lint_output_mode_from_config
        return nil unless @config.respond_to?(:lint_output_mode)
        mode = @config.lint_output_mode
        return nil if mode.nil?
        mode.to_sym
      rescue
        nil
      end

      def max_output_lines_for_category(category)
        case category
        when :test
          return @config.test_max_output_lines if @config.respond_to?(:test_max_output_lines) && @config.test_max_output_lines
          OutputFilterConfig::DEFAULT_MAX_LINES
        when :lint
          return @config.lint_max_output_lines if @config.respond_to?(:lint_max_output_lines) && @config.lint_max_output_lines
          300  # Default smaller for lint output
        else
          OutputFilterConfig::DEFAULT_MAX_LINES
        end
      end

      def output_filtering_include_context
        return @config.output_filtering_include_context if @config.respond_to?(:output_filtering_include_context)
        OutputFilterConfig::DEFAULT_INCLUDE_CONTEXT
      end

      def output_filtering_context_lines
        return @config.output_filtering_context_lines if @config.respond_to?(:output_filtering_context_lines)
        OutputFilterConfig::DEFAULT_CONTEXT_LINES
      end

      # Resolve commands for a specific category
      # Returns normalized command configs (array of {command:, required:} hashes)
      def resolved_commands(category)
        case category
        when :test
          resolved_test_commands
        when :lint
          resolved_lint_commands
        when :formatter
          @config.formatter_commands
        when :build
          @config.build_commands
        when :documentation
          @config.documentation_commands
        else
          []
        end
      end

      def resolved_test_commands
        explicit = @config.test_commands
        return explicit unless explicit.empty?

        # Auto-detect test commands if none explicitly configured
        detected = detected_tooling.test_commands.map { |cmd| {command: cmd, required: true} }
        log_fallback(:tests, detected.map { |c| c[:command] }) unless detected.empty?
        detected
      end

      def resolved_lint_commands
        explicit = @config.lint_commands
        return explicit unless explicit.empty?

        # Auto-detect lint commands if none explicitly configured
        detected = detected_tooling.lint_commands.map { |cmd| {command: cmd, required: true} }
        log_fallback(:linters, detected.map { |c| c[:command] }) unless detected.empty?
        detected
      end

      def detected_tooling
        @detected_tooling ||= Aidp::ToolingDetector.detect(@project_dir)
      rescue => e
        begin
          Aidp.log_warn("test_runner", "tooling_detection_failed", error: e.message)
        rescue NameError
          # Logging not available
        end
        Aidp::ToolingDetector::Result.new(
          test_commands: [],
          lint_commands: [],
          formatter_commands: [],
          frameworks: {}
        )
      end

      def log_fallback(type, commands)
        Aidp.log_info(
          "test_runner",
          "auto_detected_commands",
          category: type,
          commands: commands
        )
      rescue NameError
        # Logging infrastructure not available in some tests
      end
    end
  end
end
