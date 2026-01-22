# frozen_string_literal: true

require_relative "base_activity"

module Aidp
  module Temporal
    module Activities
      # Activity that records a checkpoint for progress tracking
      # Persists state for recovery and observability
      class RecordCheckpointActivity < BaseActivity
        activity_type "record_checkpoint"

        def execute(input)
          with_activity_context do
            project_dir = input[:project_dir]
            step_name = input[:step_name]
            iteration = input[:iteration]
            state = input[:state]
            test_results = input[:test_results]

            log_activity("recording_checkpoint",
              project_dir: project_dir,
              step_name: step_name,
              iteration: iteration)

            # Create checkpoint recorder
            checkpoint = Aidp::Execute::Checkpoint.new(project_dir)

            # Build metrics from test results
            metrics = build_metrics(test_results)

            # Record the checkpoint
            checkpoint.record_checkpoint(
              step_name,
              iteration,
              {
                state: state,
                test_results_summary: summarize_test_results(test_results),
                metrics: metrics,
                workflow_type: "temporal"
              }
            )

            success_result(
              step_name: step_name,
              iteration: iteration,
              timestamp: Time.now.iso8601
            )
          end
        end

        private

        def build_metrics(test_results)
          return {} unless test_results

          results = test_results[:results] || {}
          passing = results.count { |_, r| r[:success] }
          total = results.count

          {
            checks_passing: passing,
            checks_total: total,
            pass_rate: (total > 0) ? (passing.to_f / total * 100).round(1) : 0
          }
        end

        def summarize_test_results(test_results)
          return {} unless test_results

          results = test_results[:results] || {}

          results.transform_values do |result|
            {
              success: result[:success],
              duration: result[:duration]
            }
          end
        end
      end
    end
  end
end
