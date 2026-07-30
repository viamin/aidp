# frozen_string_literal: true

require "json"
require_relative "../database"
require_relative "../database/repositories/strategy_repository"
require_relative "../database/repositories/experience_task_repository"
require_relative "../database/repositories/experience_run_repository"
require_relative "../database/repositories/experience_evaluation_repository"
require_relative "../database/repositories/experience_artifact_repository"

module Aidp
  module StrategyExecution
    class ExperienceStore
      def initialize(project_dir: Dir.pwd)
        @project_dir = project_dir
        Aidp::Database.migrate!(@project_dir)
      end

      def register_strategy(strategy_spec)
        record = strategy_repository.register(
          name: strategy_spec.name,
          spec: JSON.generate(strategy_spec.to_h)
        )
        Aidp.log_debug("experience_store", "strategy_registered",
          strategy_id: record[:id], name: strategy_spec.name)
        record
      end

      def create_task(description:, title: nil, input_payload: {}, context: {}, source_run_id: nil)
        task = task_repository.create(
          description: description,
          title: title,
          input_payload: input_payload,
          context: context,
          source_run_id: source_run_id
        )
        Aidp.log_debug("experience_store", "task_created",
          task_id: task[:id], source_run_id: source_run_id)
        task
      end

      def start_run(task_id:, strategy_id:, workflow_id:, depth:, input_payload:, parent_run_id: nil, branch_key: nil, metadata: {})
        run = run_repository.start(
          task_id: task_id,
          strategy_id: strategy_id,
          workflow_id: workflow_id,
          depth: depth,
          input_payload: input_payload,
          parent_run_id: parent_run_id,
          branch_key: branch_key,
          metadata: metadata
        )
        Aidp.log_debug("experience_store", "run_started",
          run_id: run[:id],
          task_id: task_id,
          strategy_id: strategy_id,
          branch_key: branch_key,
          depth: depth)
        run
      end

      def complete_run(run_id:, status:, output_payload:, metadata: {})
        run = run_repository.complete(
          run_id: run_id,
          status: status,
          output_payload: output_payload,
          metadata: metadata
        )
        Aidp.log_debug("experience_store", "run_completed",
          run_id: run_id, status: status)
        run
      end

      def record_evaluation(run_id:, evaluator_name:, score:, passed:, summary: nil, metadata: {})
        evaluation_repository.record(
          run_id: run_id,
          evaluator_name: evaluator_name,
          score: score,
          passed: passed,
          summary: summary,
          metadata: metadata
        )
        Aidp.log_debug("experience_store", "evaluation_recorded",
          run_id: run_id,
          evaluator_name: evaluator_name,
          score: score,
          passed: passed)
      end

      def record_artifact(run_id:, role:, path:, metadata: {})
        artifact_repository.record(
          run_id: run_id,
          role: role,
          path: path,
          metadata: metadata
        )
        Aidp.log_debug("experience_store", "artifact_recorded",
          run_id: run_id, role: role, path: path)
      end

      def replay_bundle(run_id)
        bundle = run_repository.bundle_for_replay(run_id)
        Aidp.log_debug("experience_store", "replay_bundle_loaded",
          run_id: run_id, found: !bundle.nil?)
        bundle
      end

      def run_details(run_id)
        run = run_repository.load(run_id)
        return nil unless run

        details = run.merge(
          evaluations: evaluation_repository.list_for_run(run_id),
          artifacts: artifact_repository.list_for_run(run_id),
          children: run_repository.children(run_id)
        )
        Aidp.log_debug("experience_store", "run_details_loaded",
          run_id: run_id,
          evaluation_count: details[:evaluations].length,
          artifact_count: details[:artifacts].length,
          child_count: details[:children].length)
        details
      end

      private

      def strategy_repository
        @strategy_repository ||= Aidp::Database::Repositories::StrategyRepository.new(project_dir: @project_dir)
      end

      def task_repository
        @task_repository ||= Aidp::Database::Repositories::ExperienceTaskRepository.new(project_dir: @project_dir)
      end

      def run_repository
        @run_repository ||= Aidp::Database::Repositories::ExperienceRunRepository.new(project_dir: @project_dir)
      end

      def evaluation_repository
        @evaluation_repository ||= Aidp::Database::Repositories::ExperienceEvaluationRepository.new(project_dir: @project_dir)
      end

      def artifact_repository
        @artifact_repository ||= Aidp::Database::Repositories::ExperienceArtifactRepository.new(project_dir: @project_dir)
      end
    end
  end
end
