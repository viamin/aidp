# frozen_string_literal: true

require "open3"

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
        test_commands = @config.test_commands || []
        return {success: true, output: "", failures: []} if test_commands.empty?

        results = test_commands.map { |cmd| execute_command(cmd, "test") }
        aggregate_results(results, "Tests")
      end

      # Run all configured linters
      # Returns: { success: boolean, output: string, failures: array }
      def run_linters
        lint_commands = @config.lint_commands || []
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
    end
  end
end
