# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      # Repository for progress table
      # Replaces progress/execute.yml and progress/analyze.yml
      class ProgressRepository < Repository
        VALID_MODES = %w[execute analyze].freeze

        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "progress")
        end

        # Get progress for a mode
        #
        # @param mode [String, Symbol] Mode (execute or analyze)
        # @return [Hash] Progress data
        def get(mode)
          mode_str = mode.to_s
          row = query_one(
            "SELECT * FROM progress WHERE project_dir = ? AND mode = ?",
            [project_dir, mode_str]
          )

          return empty_progress(mode_str) unless row

          deserialize_progress(row)
        end

        # Get completed steps
        #
        # @param mode [String, Symbol] Mode
        # @return [Array<String>] Completed step names
        def completed_steps(mode)
          progress = get(mode)
          progress[:steps_completed] || []
        end

        # Get current step
        #
        # @param mode [String, Symbol] Mode
        # @return [String, nil] Current step name
        def current_step(mode)
          progress = get(mode)
          progress[:current_step]
        end

        # Check if step is completed
        #
        # @param mode [String, Symbol] Mode
        # @param step_name [String] Step name
        # @return [Boolean]
        def step_completed?(mode, step_name)
          completed_steps(mode).include?(step_name)
        end

        # Mark step as completed
        #
        # @param mode [String, Symbol] Mode
        # @param step_name [String] Step name
        def mark_step_completed(mode, step_name)
          mode_str = mode.to_s
          progress = get(mode)

          steps = progress[:steps_completed] || []
          steps << step_name unless steps.include?(step_name)

          now = current_timestamp
          started_at = progress[:started_at] || now

          upsert_progress(
            mode: mode_str,
            current_step: nil,
            steps_completed: steps,
            started_at: started_at,
            updated_at: now
          )

          Aidp.log_debug("progress_repository", "step_completed",
            mode: mode_str, step: step_name)
        end

        # Mark step as in progress
        #
        # @param mode [String, Symbol] Mode
        # @param step_name [String] Step name
        def mark_step_in_progress(mode, step_name)
          mode_str = mode.to_s
          progress = get(mode)

          now = current_timestamp
          started_at = progress[:started_at] || now

          upsert_progress(
            mode: mode_str,
            current_step: step_name,
            steps_completed: progress[:steps_completed] || [],
            started_at: started_at,
            updated_at: now
          )

          Aidp.log_debug("progress_repository", "step_in_progress",
            mode: mode_str, step: step_name)
        end

        # Reset progress for a mode
        #
        # @param mode [String, Symbol] Mode
        def reset(mode)
          mode_str = mode.to_s
          execute(
            "DELETE FROM progress WHERE project_dir = ? AND mode = ?",
            [project_dir, mode_str]
          )

          Aidp.log_debug("progress_repository", "reset", mode: mode_str)
        end

        # Get started_at timestamp
        #
        # @param mode [String, Symbol] Mode
        # @return [Time, nil] Started at time
        def started_at(mode)
          progress = get(mode)
          return nil unless progress[:started_at]

          Time.parse(progress[:started_at])
        rescue ArgumentError
          nil
        end

        private

        def empty_progress(mode)
          {
            mode: mode,
            current_step: nil,
            steps_completed: [],
            started_at: nil,
            updated_at: nil
          }
        end

        def upsert_progress(mode:, current_step:, steps_completed:, started_at:, updated_at:)
          existing = query_one(
            "SELECT id FROM progress WHERE project_dir = ? AND mode = ?",
            [project_dir, mode]
          )

          if existing
            execute(
              <<~SQL,
                UPDATE progress SET
                  current_step = ?,
                  steps_completed = ?,
                  started_at = ?,
                  updated_at = ?
                WHERE project_dir = ? AND mode = ?
              SQL
              [
                current_step,
                serialize_json(steps_completed),
                started_at,
                updated_at,
                project_dir,
                mode
              ]
            )
          else
            execute(
              insert_sql([
                :project_dir, :mode, :current_step, :steps_completed,
                :started_at, :updated_at
              ]),
              [
                project_dir,
                mode,
                current_step,
                serialize_json(steps_completed),
                started_at,
                updated_at
              ]
            )
          end
        end

        def deserialize_progress(row)
          {
            id: row["id"],
            mode: row["mode"],
            current_step: row["current_step"],
            steps_completed: deserialize_json(row["steps_completed"]) || [],
            started_at: row["started_at"],
            updated_at: row["updated_at"]
          }
        end
      end
    end
  end
end
