# frozen_string_literal: true

require_relative "../repository"
require "securerandom"

module Aidp
  module Database
    module Repositories
      # Repository for tasks table
      # Replaces tasklist.jsonl
      class TaskRepository < Repository
        VALID_STATUSES = %w[pending in_progress done abandoned].freeze
        VALID_PRIORITIES = %w[high medium low].freeze

        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "tasks")
        end

        # Create a new task
        #
        # @param description [String] Task description
        # @param priority [String, Symbol] Task priority (high, medium, low)
        # @param session [String, nil] Session identifier
        # @param discovered_during [String, nil] When task was discovered
        # @param tags [Array<String>] Task tags
        # @return [Hash] Created task
        def create(description:, priority: "medium", session: nil, discovered_during: nil, tags: [])
          now = current_timestamp
          id = generate_id

          execute(
            insert_sql([
              :id, :project_dir, :description, :priority, :status,
              :tags, :source, :created_at, :updated_at
            ]),
            [
              id,
              project_dir,
              description.strip,
              priority.to_s,
              "pending",
              serialize_json(Array(tags)),
              serialize_json({session: session, discovered_during: discovered_during}),
              now,
              now
            ]
          )

          Aidp.log_debug("task_repository", "created", id: id, description: description)

          {
            id: id,
            description: description.strip,
            status: :pending,
            priority: priority.to_sym,
            tags: Array(tags),
            session: session,
            discovered_during: discovered_during,
            created_at: now,
            updated_at: now
         }
        end

        # Update task status
        #
        # @param task_id [String] Task ID
        # @param new_status [String, Symbol] New status
        # @param reason [String, nil] Reason for status change (for abandoned)
        # @return [Hash, nil] Updated task or nil if not found
        def update_status(task_id, new_status, reason: nil)
          task = find(task_id)
          return nil unless task

          now = current_timestamp
          status_str = new_status.to_s

          updates = {status: status_str, updated_at: now}

          case status_str
          when "in_progress"
            updates[:started_at] = now unless task[:started_at]
          when "done"
            updates[:completed_at] = now
          when "abandoned"
            # Store reason in source JSON
            source = task[:source] || {}
            source[:abandoned_reason] = reason
            updates[:source] = serialize_json(source)
          end

          set_clauses = updates.keys.map { |k| "#{k} = ?" }.join(", ")
          values = updates.values + [task_id, project_dir]

          execute(
            "UPDATE tasks SET #{set_clauses} WHERE id = ? AND project_dir = ?",
            values
          )

          Aidp.log_debug("task_repository", "status_updated", id: task_id, status: status_str)

          find(task_id)
        end

        # Find task by ID
        #
        # @param task_id [String] Task ID
        # @return [Hash, nil] Task or nil
        def find(task_id)
          row = query_one(
            "SELECT * FROM tasks WHERE id = ? AND project_dir = ?",
            [task_id, project_dir]
          )
          return nil unless row

          deserialize_task(row)
        end

        # Get all tasks with optional filters
        #
        # @param status [Symbol, String, nil] Filter by status
        # @param priority [Symbol, String, nil] Filter by priority
        # @param since [Time, nil] Filter by created_at
        # @param tags [Array<String>, nil] Filter by tags (any match)
        # @return [Array<Hash>] Matching tasks
        def all(status: nil, priority: nil, since: nil, tags: nil)
          conditions = ["project_dir = ?"]
          params = [project_dir]

          if status
            conditions << "status = ?"
            params << status.to_s
          end

          if priority
            conditions << "priority = ?"
            params << priority.to_s
          end

          if since
            conditions << "created_at >= ?"
            params << since.strftime("%Y-%m-%d %H:%M:%S")
          end

          sql = <<~SQL
            SELECT * FROM tasks
            WHERE #{conditions.join(" AND ")}
            ORDER BY created_at DESC
          SQL

          rows = query(sql, params)
          tasks = rows.map { |row| deserialize_task(row)}

          # Filter by tags in Ruby (JSON array matching is complex in SQLite)
          if tags && !tags.empty?
            tag_set = tags.map(&:to_s)
            tasks = tasks.select do |task|
              (Array(task[:tags]) & tag_set).any?
            end
          end

          tasks
        end

        # Get pending tasks
        #
        # @return [Array<Hash>] Pending tasks
        def pending
          all(status: :pending)
        end

        # Get in-progress tasks
        #
        # @return [Array<Hash>] In-progress tasks
        def in_progress
          all(status: :in_progress)
        end

        # Get task counts by status
        #
        # @return [Hash] Counts by status
        def counts
          sql = <<~SQL
            SELECT status, COUNT(*) as count
            FROM tasks
            WHERE project_dir = ?
            GROUP BY status
          SQL

          rows = query(sql, [project_dir])
          counts_by_status = rows.each_with_object({}) do |row, h|
            h[row["status"].to_sym] = row["count"]
          end

          {
            total: counts_by_status.values.sum,
            pending: counts_by_status[:pending] || 0,
            in_progress: counts_by_status[:in_progress] || 0,
            done: counts_by_status[:done] || 0,
            abandoned: counts_by_status[:abandoned] || 0
         }
        end

        private

        def generate_id
          "task_#{Time.now.to_i}_#{SecureRandom.hex(4)}"
        end

        def deserialize_task(row)
          source = deserialize_json(row["source"]) || {}

          {
            id: row["id"],
            description: row["description"],
            status: row["status"]&.to_sym,
            priority: row["priority"]&.to_sym,
            tags: deserialize_json(row["tags"]) || [],
            session: source[:session],
            discovered_during: source[:discovered_during],
            abandoned_reason: source[:abandoned_reason],
            created_at: row["created_at"],
            updated_at: row["updated_at"],
            started_at: row["started_at"],
            completed_at: row["completed_at"],
            source: source
         }
        end
      end
    end
  end
end
