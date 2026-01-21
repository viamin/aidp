# frozen_string_literal: true

require_relative "base_activity"

module Aidp
  module Temporal
    module Activities
      # Activity that runs tests and linters
      # Wraps AIDP test runner with Temporal durability
      class RunTestsActivity < BaseActivity
        activity_type "run_tests"

        def execute(input)
          with_activity_context do
            project_dir = input[:project_dir]
            iteration = input[:iteration]
            phases = input[:phases] || [:test, :lint]

            log_activity("running_tests",
              project_dir: project_dir,
              iteration: iteration,
              phases: phases)

            # Load configuration
            config = load_config(project_dir)

            # Create test runner
            test_runner = Aidp::Harness::TestRunner.new(project_dir, config)

            # Run tests with periodic heartbeat
            results = {}
            all_passing = true
            partial_pass = false

            phases.each do |phase|
              heartbeat(phase: phase, iteration: iteration)
              check_cancellation!

              result = run_phase(test_runner, phase)
              results[phase] = result

              if result[:success]
                partial_pass = true
              else
                all_passing = false
              end

              log_activity("phase_complete",
                phase: phase,
                success: result[:success],
                duration: result[:duration])
            end

            success_result(
              all_passing: all_passing,
              partial_pass: partial_pass,
              results: results,
              iteration: iteration,
              summary: build_summary(results)
            )
          end
        end

        private

        def run_phase(test_runner, phase)
          start_time = Time.now

          result = case phase
          when :test, "test"
            test_runner.run_tests
          when :lint, "lint"
            test_runner.run_lint
          when :typecheck, "typecheck"
            test_runner.run_typecheck
          when :build, "build"
            test_runner.run_build
          else
            {success: false, output: "Unknown phase: #{phase}"}
          end

          duration = Time.now - start_time

          {
            success: result[:success],
            output: result[:output],
            exit_code: result[:exit_code],
            duration: duration.round(2)
          }
        rescue => e
          Aidp.log_error("run_tests_activity", "phase_failed",
            phase: phase,
            error: e.message)

          {
            success: false,
            output: e.message,
            exit_code: -1,
            duration: (Time.now - start_time).round(2)
          }
        end

        def build_summary(results)
          passing = results.count { |_, r| r[:success] }
          total = results.count

          {
            passing: passing,
            total: total,
            failed_phases: results.reject { |_, r| r[:success] }.keys
          }
        end
      end
    end
  end
end
