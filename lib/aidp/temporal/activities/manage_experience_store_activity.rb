# frozen_string_literal: true

require_relative "base_activity"
require_relative "../../strategy_execution/experience_store"
require_relative "../../strategy_execution/strategy_spec"

module Aidp
  module Temporal
    module Activities
      class ManageExperienceStoreActivity < BaseActivity
        def execute(input)
          with_activity_context do
            project_dir = input[:project_dir]
            operation = input[:operation]
            payload = input[:payload] || {}
            store = Aidp::StrategyExecution::ExperienceStore.new(project_dir: project_dir)

            Aidp.log_debug("manage_experience_store_activity", "dispatching",
              operation: operation,
              run_id: payload[:run_id],
              task_id: payload[:task_id],
              strategy_id: payload[:strategy_id])

            case operation
            when "register_strategy"
              strategy = Aidp::StrategyExecution::StrategySpec.from_hash(payload[:strategy])
              store.register_strategy(strategy)
            when "create_task"
              store.create_task(**payload)
            when "start_run"
              store.start_run(**payload)
            when "complete_run"
              store.complete_run(**payload)
            when "record_evaluation"
              store.record_evaluation(**payload)
              success_result
            when "record_artifact"
              store.record_artifact(**payload)
              success_result
            when "replay_bundle"
              store.replay_bundle(payload[:run_id])
            when "run_details"
              store.run_details(payload[:run_id])
            else
              Aidp.log_error("manage_experience_store_activity", "unknown_operation",
                operation: operation)
              error_result("Unknown operation: #{operation}")
            end
          end
        end
      end
    end
  end
end
