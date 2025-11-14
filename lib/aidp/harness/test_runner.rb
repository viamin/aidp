# frozen_string_literal: true

require "open3"
require_relative "../tooling_detector"
require_relative "output_filter"

module Aidp
  module Harness
    # Executes test and linter commands configured in aidp.yml
    # Returns results with exit status and output
    class TestRunner
      def initialize(project_dir, config)
        @project_dir = project_dir
        @config = config
        @iteration_count = 0
      end

      # Run all configured tests
      # Returns: { success: boolean, output: string, failures: array }
      def run_tests
        @iteration_count += 1
        test_commands = resolved_test_commands
        return {success: true, output: "", failures: []} if test_commands.empty?

        mode = determine_test_output_mode
        results = test_commands.map { |cmd| execute_command(cmd, "test") }
        aggregate_results(results, "Tests", mode: mode)
      end

      # Run all configured linters
      # Returns: { success: boolean, output: string, failures: array }
      def run_linters
        @iteration_count += 1
        lint_commands = resolved_lint_commands
        return {success: true, output: "", failures: []} if lint_commands.empty?

        mode = determine_lint_output_mode
        results = lint_commands.map { |cmd| execute_command(cmd, "linter") }
        aggregate_results(results, "Linters", mode: mode)
      end

      private

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
        failures = results.reject { |r| r[:success] }
        success = failures.empty?

        output = if success
          "#{category}: All passed"
        else
          format_failures(failures, category, mode: mode)
        end

        {
          success: success,
          output: output,
          failures: failures
        }
      end

      def format_failures(failures, category, mode: :full)
        output = ["#{category} Failures:", ""]

        failures.each do |failure|
          output << "Command: #{failure[:command]}"
          output << "Exit Code: #{failure[:exit_code]}"
          output << "--- Output ---"

          # Apply filtering based on mode and framework
          filtered_stdout = filter_output(failure[:stdout], mode, detect_framework_from_command(failure[:command]))
          filtered_stderr = filter_output(failure[:stderr], mode, :unknown)

          output << filtered_stdout unless filtered_stdout.strip.empty?
          output << filtered_stderr unless filtered_stderr.strip.empty?
          output << ""
        end

        output.join("\n")
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
        # Logging infrastructure not available
        raw_output
      rescue => e
        Aidp.log_warn("test_runner", "filter_failed",
          error: e.message,
          framework: framework)
        raw_output  # Fallback to unfiltered on error
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
        # Check if config has test_output_mode method
        if @config.respond_to?(:test_output_mode)
          @config.test_output_mode
        elsif @iteration_count > 1
          :failures_only
        else
          :full
        end
      end

      def determine_lint_output_mode
        # Check if config has lint_output_mode method
        if @config.respond_to?(:lint_output_mode)
          @config.lint_output_mode
        elsif @iteration_count > 1
          :failures_only
        else
          :full
        end
      end

      def resolved_test_commands
        explicit = Array(@config.test_commands).compact.map(&:strip).reject(&:empty?)
        return explicit unless explicit.empty?

        detected = detected_tooling.test_commands
        log_fallback(:tests, detected) unless detected.empty?
        detected
      end

      def resolved_lint_commands
        explicit = Array(@config.lint_commands).compact.map(&:strip).reject(&:empty?)
        return explicit unless explicit.empty?

        detected = detected_tooling.lint_commands
        log_fallback(:linters, detected) unless detected.empty?
        detected
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
