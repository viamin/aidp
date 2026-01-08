# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      # Repository for workstreams and workstream_events tables
      # Replaces workstreams/*/state.json and history.jsonl
      class WorkstreamRepository < Repository
        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "workstreams")
        end

        # Initialize a new workstream
        #
        # @param slug [String] Workstream slug
        # @param task [String, nil] Task description
        # @return [Hash] Created workstream state
        def init(slug:, task: nil)
          now = current_timestamp

          execute(
            insert_sql([
              :project_dir, :slug, :status, :iteration, :metadata,
              :created_at, :updated_at
            ]),
            [
              project_dir,
              slug,
              "active",
              0,
              serialize_json({task: task, started_at: now}),
              now,
              now
            ]
          )

          append_event(slug: slug, type: "created", data: {task: task})

          Aidp.log_debug("workstream_repository", "initialized", slug: slug)

          read(slug: slug)
        end

        # Read workstream state
        #
        # @param slug [String] Workstream slug
        # @return [Hash, nil] Workstream state or nil
        def read(slug:)
          row = query_one(
            "SELECT * FROM workstreams WHERE project_dir = ? AND slug = ?",
            [project_dir, slug]
          )
          return nil unless row

          deserialize_workstream(row)
        end

        # Update workstream attributes
        #
        # @param slug [String] Workstream slug
        # @param attrs [Hash] Attributes to update
        # @return [Hash] Updated workstream state
        def update(slug:, **attrs)
          existing = read(slug: slug)
          existing ||= init(slug: slug)

          now = current_timestamp
          metadata = existing[:metadata] || {}
          metadata = metadata.merge(attrs.except(:status, :iteration, :branch, :worktree_path))

          execute(
            <<~SQL,
              UPDATE workstreams SET
                status = ?,
                iteration = ?,
                branch = ?,
                worktree_path = ?,
                metadata = ?,
                updated_at = ?
              WHERE project_dir = ? AND slug = ?
            SQL
            [
              attrs[:status] || existing[:status],
              attrs[:iteration] || existing[:iteration],
              attrs[:branch] || existing[:branch],
              attrs[:worktree_path] || existing[:worktree_path],
              serialize_json(metadata),
              now,
              project_dir,
              slug
            ]
          )

          Aidp.log_debug("workstream_repository", "updated", slug: slug)

          read(slug: slug)
        end

        # Increment iteration counter
        #
        # @param slug [String] Workstream slug
        # @return [Hash] Updated workstream state
        def increment_iteration(slug:)
          existing = read(slug: slug)
          existing ||= init(slug: slug)

          new_iteration = (existing[:iteration] || 0) + 1
          new_status = (existing[:status] == "paused") ? "active" : existing[:status]

          state = update(slug: slug, iteration: new_iteration, status: new_status)

          append_event(slug: slug, type: "iteration", data: {count: new_iteration})

          state
        end

        # Append event to workstream history
        #
        # @param slug [String] Workstream slug
        # @param type [String] Event type
        # @param data [Hash] Event data
        def append_event(slug:, type:, data: {})
          now = current_timestamp

          execute(
            <<~SQL,
              INSERT INTO workstream_events
                (project_dir, workstream_slug, event_type, event_data, timestamp)
              VALUES (?, ?, ?, ?, ?)
            SQL
            [project_dir, slug, type, serialize_json(data), now]
          )

          Aidp.log_debug("workstream_repository", "event_appended",
            slug: slug, type: type)
        end

        # Get recent events for workstream
        #
        # @param slug [String] Workstream slug
        # @param limit [Integer] Maximum events to return
        # @return [Array<Hash>] Recent events
        def recent_events(slug:, limit: 5)
          rows = query(
            <<~SQL,
              SELECT * FROM workstream_events
              WHERE project_dir = ? AND workstream_slug = ?
              ORDER BY timestamp DESC
              LIMIT ?
            SQL
            [project_dir, slug, limit]
          )

          rows.map { |row| deserialize_event(row) }.reverse
        end

        # Pause workstream
        #
        # @param slug [String] Workstream slug
        # @return [Hash] Result with status or error
        def pause(slug:)
          state = read(slug: slug)
          return {error: "Workstream not found" } unless state
          return {error: "Already paused" } if state[:status] == "paused"

          now = current_timestamp
          update(slug: slug, status: "paused", paused_at: now)
          append_event(slug: slug, type: "paused", data: {})

          {status: "paused"}
        end

        # Resume workstream
        #
        # @param slug [String] Workstream slug
        # @return [Hash] Result with status or error
        def resume(slug:)
          state = read(slug: slug)
          return {error: "Workstream not found" } unless state
          return {error: "Not paused" } unless state[:status] == "paused"

          now = current_timestamp
          update(slug: slug, status: "active", resumed_at: now)
          append_event(slug: slug, type: "resumed", data: {})

          {status: "active"}
        end

        # Complete workstream
        #
        # @param slug [String] Workstream slug
        # @return [Hash] Result with status or error
        def complete(slug:)
          state = read(slug: slug)
          return {error: "Workstream not found" } unless state
          return {error: "Already completed" } if state[:status] == "completed"

          now = current_timestamp
          update(slug: slug, status: "completed", completed_at: now)
          append_event(slug: slug, type: "completed", data: {iterations: state[:iteration]})

          {status: "completed"}
        end

        # Mark workstream as removed
        #
        # @param slug [String] Workstream slug
        def mark_removed(slug:)
          state = read(slug: slug)

          # Auto-complete if active
          complete(slug: slug) if state && state[:status] == "active"

          update(slug: slug, status: "removed")
          append_event(slug: slug, type: "removed", data: {})

          Aidp.log_debug("workstream_repository", "removed", slug: slug)
        end

        # Check if workstream is stalled
        #
        # @param slug [String] Workstream slug
        # @param threshold_seconds [Integer] Stall threshold in seconds
        # @return [Boolean]
        def stalled?(slug:, threshold_seconds: 3600)
          state = read(slug: slug)
          return false unless state && state[:updated_at]
          return false if state[:status] != "active"

          updated = Time.parse(state[:updated_at])
          (Time.now.utc - updated).to_i > threshold_seconds
        rescue ArgumentError
          false
        end

        # Get elapsed time for workstream
        #
        # @param slug [String] Workstream slug
        # @return [Integer] Elapsed seconds
        def elapsed_seconds(slug:)
          state = read(slug: slug)
          return 0 unless state

          metadata = state[:metadata] || {}
          return 0 unless metadata[:started_at]

          started = Time.parse(metadata[:started_at])
          (Time.now.utc - started).to_i
        rescue ArgumentError
          0
        end

        # List all workstreams for project
        #
        # @param status [String, nil] Filter by status
        # @return [Array<Hash>] Workstreams
        def list(status: nil)
          rows = if status
            query(
              "SELECT * FROM workstreams WHERE project_dir = ? AND status = ? ORDER BY updated_at DESC",
              [project_dir, status]
            )
          else
            query(
              "SELECT * FROM workstreams WHERE project_dir = ? ORDER BY updated_at DESC",
              [project_dir]
            )
          end

          rows.map { |row| deserialize_workstream(row)}
        end

        private

        def deserialize_workstream(row)
          metadata = deserialize_json(row["metadata"]) || {}

          {
            id: row["id"],
            slug: row["slug"],
            status: row["status"],
            iteration: row["iteration"] || 0,
            branch: row["branch"],
            worktree_path: row["worktree_path"],
            metadata: metadata,
            task: metadata[:task],
            started_at: metadata[:started_at],
            paused_at: metadata[:paused_at],
            resumed_at: metadata[:resumed_at],
            completed_at: metadata[:completed_at],
            created_at: row["created_at"],
            updated_at: row["updated_at"]
         }
        end

        def deserialize_event(row)
          {
            id: row["id"],
            workstream_slug: row["workstream_slug"],
            type: row["event_type"],
            data: deserialize_json(row["event_data"]) || {},
            timestamp: row["timestamp"]
         }
        end
      end
    end
  end
end
