# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      # Repository for harness_state table
      # Replaces harness/*_state.json files
      class HarnessStateRepository < Repository
        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "harness_state")
        end

        # Check if state exists for mode
        #
        # @param mode [String, Symbol] Mode (execute, analyze, etc.)
        # @return [Boolean]
        def has_state?(mode)
          mode_str = mode.to_s
          count = query_value(
            "SELECT COUNT(*) FROM harness_state WHERE project_dir = ? AND mode = ?",
            [project_dir, mode_str]
          )
          count.positive?
        end

        # Load state for mode
        #
        # @param mode [String, Symbol] Mode
        # @return [Hash] State data (empty hash if no state)
        def load_state(mode)
          mode_str = mode.to_s
          row = query_one(
            "SELECT * FROM harness_state WHERE project_dir = ? AND mode = ?",
            [project_dir, mode_str]
          )

          return {} unless row

          state = deserialize_json(row["state"]) || {}
          Aidp.log_debug("harness_state_repository", "loaded",
            mode: mode_str, keys: state.keys.size)
          state
        end

        # Save state for mode
        #
        # @param mode [String, Symbol] Mode
        # @param state_data [Hash] State to save
        def save_state(mode, state_data)
          mode_str = mode.to_s
          now = current_timestamp

          # Add metadata
          state_with_metadata = state_data.merge(
            mode: mode_str,
            project_dir: project_dir,
            saved_at: now
          )

          existing = query_one(
            "SELECT id, version FROM harness_state WHERE project_dir = ? AND mode = ?",
            [project_dir, mode_str]
          )

          if existing
            new_version = (existing["version"] || 1) + 1
            execute(
              <<~SQL,
                UPDATE harness_state SET
                  state = ?,
                  version = ?,
                  updated_at = ?
                WHERE project_dir = ? AND mode = ?
              SQL
              [
                serialize_json(state_with_metadata),
                new_version,
                now,
                project_dir,
                mode_str
              ]
            )
            Aidp.log_debug("harness_state_repository", "updated",
              mode: mode_str, version: new_version)
          else
            execute(
              insert_sql([:project_dir, :mode, :state, :version, :created_at, :updated_at]),
              [
                project_dir,
                mode_str,
                serialize_json(state_with_metadata),
                1,
                now,
                now
              ]
            )
            Aidp.log_debug("harness_state_repository", "created", mode: mode_str)
          end
        end

        # Clear state for mode
        #
        # @param mode [String, Symbol] Mode
        def clear_state(mode)
          mode_str = mode.to_s
          execute(
            "DELETE FROM harness_state WHERE project_dir = ? AND mode = ?",
            [project_dir, mode_str]
          )
          Aidp.log_debug("harness_state_repository", "cleared", mode: mode_str)
        end

        # Get all modes with state
        #
        # @return [Array<String>] Mode names
        def modes_with_state
          rows = query(
            "SELECT DISTINCT mode FROM harness_state WHERE project_dir = ?",
            [project_dir]
          )
          rows.map { |r| r["mode"]}
        end

        # Get state version for mode
        #
        # @param mode [String, Symbol] Mode
        # @return [Integer] Version number (0 if no state)
        def version(mode)
          mode_str = mode.to_s
          query_value(
            "SELECT version FROM harness_state WHERE project_dir = ? AND mode = ?",
            [project_dir, mode_str]
          ) || 0
        end
      end
    end
  end
end
