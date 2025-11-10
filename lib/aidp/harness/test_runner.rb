# frozen_string_literal: true

require "open3"
require_relative "../tooling_detector"

module Aidp
  module Harness
    # Executes test and linter commands configured in aidp.yml
    # Returns results with exit status and output
    class TestRunner
      def initialize(project_dir, config)
        @project_dir = project_dir
        @config = config
      end

      # Run all configured tests
      # Returns: { success: boolean, output: string, failures: array }
      def run_tests
        test_commands = resolved_test_commands
        return {success: true, output: "", failures: []} if test_commands.empty?

        results = test_commands.map { |cmd| execute_command(cmd, "test") }
        aggregate_results(results, "Tests")
      end

      # Run all configured linters
      # Returns: { success: boolean, output: string, failures: array }
      def run_linters
        lint_commands = resolved_lint_commands
        return {success: true, output: "", failures: []} if lint_commands.empty?

        results = lint_commands.map { |cmd| execute_command(cmd, "linter") }
        aggregate_results(results, "Linters")
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

      def aggregate_results(results, category)
        failures = results.reject { |r| r[:success] }
        success = failures.empty?

        output = if success
          "#{category}: All passed"
        else
          format_failures(failures, category)
        end

        {
          success: success,
          output: output,
          failures: failures
        }
      end

      def format_failures(failures, category)
        output = ["#{category} Failures:", ""]

        failures.each do |failure|
          output << "Command: #{failure[:command]}"
          output << "Exit Code: #{failure[:exit_code]}"
          output << "--- Output ---"
          output << failure[:stdout] unless failure[:stdout].strip.empty?
          output << failure[:stderr] unless failure[:stderr].strip.empty?
          output << ""
        end

        output.join("\n")
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
