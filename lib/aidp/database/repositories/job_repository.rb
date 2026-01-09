# frozen_string_literal: true

require_relative "../repository"
require "securerandom"

module Aidp
  module Database
    module Repositories
      # Repository for background_jobs table
      # Replaces jobs/* directory (metadata, logs, PID tracking)
      class JobRepository < Repository
        VALID_STATUSES = %w[pending running completed failed stopped].freeze

        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "background_jobs")
        end

        # Create a new job
        #
        # @param job_type [String] Type of job (e.g., "execute", "analyze")
        # @param input [Hash] Job input/options
        # @return [String] Job ID
        def create(job_type:, input: {})
          job_id = generate_job_id
          now = current_timestamp

          execute(
            insert_sql([
              :id, :project_dir, :job_type, :status, :options, :created_at
            ]),
            [
              job_id,
              project_dir,
              job_type,
              "pending",
              serialize_json(input),
              now
            ]
          )

          Aidp.log_debug("job_repository", "created",
            job_id: job_id, type: job_type)

          job_id
        end

        # Start a job
        #
        # @param job_id [String] Job ID
        # @param pid [Integer, nil] Process ID
        def start(job_id, pid: nil)
          now = current_timestamp

          execute(
            <<~SQL,
              UPDATE background_jobs SET
                status = 'running',
                pid = ?,
                started_at = ?
              WHERE id = ? AND project_dir = ?
            SQL
            [pid, now, job_id, project_dir]
          )

          Aidp.log_debug("job_repository", "started", job_id: job_id, pid: pid)
        end

        # Complete a job
        #
        # @param job_id [String] Job ID
        # @param output [Hash] Job output/result
        def complete(job_id, output: {})
          now = current_timestamp

          execute(
            <<~SQL,
              UPDATE background_jobs SET
                status = 'completed',
                result = ?,
                completed_at = ?
              WHERE id = ? AND project_dir = ?
            SQL
            [serialize_json(output), now, job_id, project_dir]
          )

          Aidp.log_debug("job_repository", "completed", job_id: job_id)
        end

        # Fail a job
        #
        # @param job_id [String] Job ID
        # @param error [String] Error message
        def fail(job_id, error:)
          now = current_timestamp

          execute(
            <<~SQL,
              UPDATE background_jobs SET
                status = 'failed',
                error = ?,
                completed_at = ?
              WHERE id = ? AND project_dir = ?
            SQL
            [error, now, job_id, project_dir]
          )

          Aidp.log_debug("job_repository", "failed", job_id: job_id, error: error)
        end

        # Stop a job
        #
        # @param job_id [String] Job ID
        def stop(job_id)
          now = current_timestamp

          execute(
            <<~SQL,
              UPDATE background_jobs SET
                status = 'stopped',
                completed_at = ?
              WHERE id = ? AND project_dir = ?
            SQL
            [now, job_id, project_dir]
          )

          Aidp.log_debug("job_repository", "stopped", job_id: job_id)
        end

        # Find job by ID
        #
        # @param job_id [String] Job ID
        # @return [Hash, nil] Job or nil
        def find(job_id)
          row = query_one(
            "SELECT * FROM background_jobs WHERE id = ? AND project_dir = ?",
            [job_id, project_dir]
          )
          deserialize_job(row)
        end

        # List all jobs
        #
        # @param status [String, nil] Filter by status
        # @param limit [Integer] Maximum jobs
        # @return [Array<Hash>] Jobs
        def list(status: nil, limit: 50)
          rows = if status
            query(
              <<~SQL,
                SELECT * FROM background_jobs
                WHERE project_dir = ? AND status = ?
                ORDER BY created_at DESC
                LIMIT ?
              SQL
              [project_dir, status, limit]
            )
          else
            query(
              <<~SQL,
                SELECT * FROM background_jobs
                WHERE project_dir = ?
                ORDER BY created_at DESC
                LIMIT ?
              SQL
              [project_dir, limit]
            )
          end

          rows.map { |row| deserialize_job(row) }
        end

        # List running jobs
        #
        # @return [Array<Hash>]
        def running
          list(status: "running")
        end

        # Get job status
        #
        # @param job_id [String] Job ID
        # @return [Hash, nil] Status info or nil
        def status(job_id)
          job = find(job_id)
          return nil unless job

          pid = job[:pid]

          {
            job_id: job_id,
            mode: job[:job_type],
            status: job[:status],
            pid: pid,
            running: pid && process_running?(pid),
            started_at: job[:started_at],
            completed_at: job[:completed_at],
            error: job[:error]
          }
        end

        # Delete a job
        #
        # @param job_id [String] Job ID
        def delete(job_id)
          execute(
            "DELETE FROM background_jobs WHERE id = ? AND project_dir = ?",
            [job_id, project_dir]
          )
          Aidp.log_debug("job_repository", "deleted", job_id: job_id)
        end

        # Cleanup old completed jobs
        #
        # @param days_to_keep [Integer] Days to retain
        # @return [Integer] Deleted count
        def cleanup(days_to_keep: 7)
          threshold = (Time.now - (days_to_keep * 24 * 60 * 60)).strftime("%Y-%m-%d %H:%M:%S")

          count = query_value(
            <<~SQL,
              SELECT COUNT(*) FROM background_jobs
              WHERE project_dir = ? AND status IN ('completed', 'failed', 'stopped')
              AND completed_at < ?
            SQL
            [project_dir, threshold]
          ) || 0

          execute(
            <<~SQL,
              DELETE FROM background_jobs
              WHERE project_dir = ? AND status IN ('completed', 'failed', 'stopped')
              AND completed_at < ?
            SQL
            [project_dir, threshold]
          )

          Aidp.log_debug("job_repository", "cleanup",
            deleted: count, threshold: threshold)

          count
        end

        private

        def generate_job_id
          timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
          "job_#{timestamp}_#{SecureRandom.hex(4)}"
        end

        def process_running?(pid)
          return false unless pid

          Process.kill(0, pid)
          true
        rescue Errno::ESRCH, Errno::EPERM
          false
        end

        def deserialize_job(row)
          return nil unless row

          {
            id: row["id"],
            job_type: row["job_type"],
            status: row["status"],
            options: deserialize_json(row["options"]) || {},
            result: deserialize_json(row["result"]) || {},
            pid: row["pid"],
            error: row["error"],
            started_at: row["started_at"],
            completed_at: row["completed_at"],
            created_at: row["created_at"]
          }
        end
      end
    end
  end
end
