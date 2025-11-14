# frozen_string_literal: true

require "open3"
require_relative "../tooling_detector"
require_relative "output_filter"

module Aidp
  module Harness
    # Executes test, lint, formatter, build, and documentation commands configured in aidp.yml
    # Returns results with exit status and output
    class TestRunner
      def initialize(project_dir, config)
        @project_dir = project_dir
        @config = config
        @iteration_count = 0
      end

      # Run all configured tests
      # Returns: { success: boolean, output: string, failures: array, required_failures: array }
      def run_tests
        @iteration_count += 1
        mode = determine_test_output_mode
        run_command_category(:test, "Tests", mode: mode)
      end

      # Run all configured linters
      # Returns: { success: boolean, output: string, failures: array, required_failures: array }
      def run_linters
        @iteration_count += 1
        mode = determine_lint_output_mode
        run_command_category(:lint, "Linters", mode: mode)
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

      private

      # Run commands for a specific category (test, lint, formatter, build, documentation)
      def run_command_category(category, display_name, mode: :full)
        commands = resolved_commands(category)

        return {
          success: true,
          output: "#{display_name}: No commands configured",
          failures: [],
          required_failures: [],
          optional_failures: []
        } if commands.empty?

        results = commands.map do |cmd_config|
          result = execute_command(cmd_config[:command], category.to_s)
          result.merge(required: cmd_config[:required])
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
        all_failures = results.reject { |r| r[:success] }
        required_failures = all_failures.select { |r| r[:required] }
        optional_failures = all_failures.reject { |r| r[:required] }

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

          filtered_stdout = filter_output(failure[:stdout], mode, detect_framework_from_command(failure[:command]))
          filtered_stderr = filter_output(failure[:stderr], mode, :unknown)

          output << filtered_stdout unless filtered_stdout.strip.empty?
          output << filtered_stderr unless filtered_stderr.strip.empty?
          output << ""
        end

        output.join("\n")
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

        detected = detected_tooling.test_commands.map { |cmd| {command: cmd, required: true} }
        log_fallback(:tests, detected.map { |c| c[:command] }) unless detected.empty?
        detected
      end

      def resolved_lint_commands
        explicit = @config.lint_commands
        return explicit unless explicit.empty?

        detected = detected_tooling.lint_commands.map { |cmd| {command: cmd, required: true} }
        log_fallback(:linters, detected.map { |c| c[:command] }) unless detected.empty?
        detected
      end

      def filter_output(raw_output, mode, framework)
        return raw_output if mode == :full || raw_output.nil? || raw_output.empty?

        filter_config = {
          mode: mode,
          include_context: true,
          context_lines: 3,
          max_lines: 500
        }

        filter = OutputFilter.new(filter_config)
        filter.filter(raw_output, framework: framework)
      rescue NameError
        raw_output
      rescue => e
        Aidp.log_warn("test_runner", "filter_failed",
          error: e.message,
          framework: framework)
        raw_output
      end

      def detect_framework_from_command(command)
        case command
        when /rspec/
          :rspec
        when /minitest/
          :minitest
        when /jest/
          :jest
        when /pytest/
          :pytest
        else
          :unknown
        end
      end

      def determine_test_output_mode
        if @config.respond_to?(:test_output_mode)
          @config.test_output_mode
        elsif @iteration_count > 1
          :failures_only
        else
          :full
        end
      end

      def determine_lint_output_mode
        if @config.respond_to?(:lint_output_mode)
          @config.lint_output_mode
        elsif @iteration_count > 1
          :failures_only
        else
          :full
        end
      end

      def detected_tooling
        @detected_tooling ||= Aidp::ToolingDetector.detect(@project_dir)
      rescue => e
        Aidp.log_warn("test_runner", "tooling_detection_failed", error: e.message)
        Aidp::ToolingDetector::Result.new(test_commands: [], lint_commands: [])
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
