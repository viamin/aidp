# frozen_string_literal: true

require "json"
require "time"
require "securerandom"
require "fileutils"

module Aidp
  module Execute
    # Task struct for persistent tasklist entries
    Task = Struct.new(
      :id,
      :description,
      :status,
      :priority,
      :created_at,
      :updated_at,
      :session,
      :discovered_during,
      :started_at,
      :completed_at,
      :abandoned_at,
      :abandoned_reason,
      :tags,
      keyword_init: true
    ) do
      def to_h
        super.compact
      end
    end

    # Persistent tasklist for tracking tasks across sessions
    # Uses append-only JSONL format for git-friendly storage
    class PersistentTasklist
      attr_reader :project_dir, :file_path

      class TaskNotFoundError < StandardError; end
      class InvalidTaskError < StandardError; end

      def initialize(project_dir)
        @project_dir = project_dir
        @file_path = File.join(project_dir, ".aidp", "tasklist.jsonl")
        ensure_file_exists
      end

      # Create a new task
      def create(description, priority: :medium, session: nil, discovered_during: nil, tags: [])
        validate_description!(description)
        validate_priority!(priority)

        task = Task.new(
          id: generate_id,
          description: description.strip,
          status: :pending,
          priority: priority,
          created_at: Time.now,
          updated_at: Time.now,
          session: session,
          discovered_during: discovered_during,
          tags: Array(tags)
        )

        append_task(task)
        Aidp.log_debug("tasklist", "Created task", task_id: task.id, description: task.description)
        task
      end

      # Update task status
      def update_status(task_id, new_status, reason: nil)
        validate_status!(new_status)
        task = find(task_id)
        raise TaskNotFoundError, "Task not found: #{task_id}" unless task

        task.status = new_status
        task.updated_at = Time.now

        case new_status
        when :in_progress
          task.started_at ||= Time.now
        when :done
          task.completed_at = Time.now
        when :abandoned
          task.abandoned_at = Time.now
          task.abandoned_reason = reason
        end

        append_task(task)
        Aidp.log_debug("tasklist", "Updated task status", task_id: task.id, status: new_status)
        task
      end

      # Query tasks with optional filters
      def all(status: nil, priority: nil, since: nil, tags: nil)
        tasks = load_latest_tasks

        tasks = tasks.select { |t| t.status == status } if status
        tasks = tasks.select { |t| t.priority == priority } if priority
        tasks = tasks.select { |t| t.created_at >= since } if since
        tasks = tasks.select { |t| (Array(t.tags) & Array(tags)).any? } if tags && !tags.empty?

        tasks.sort_by(&:created_at).reverse
      end

      # Find single task by ID
      def find(task_id)
        all.find { |t| t.id == task_id }
      end

      # Query pending tasks (common operation)
      def pending
        all(status: :pending)
      end

      # Query in-progress tasks
      def in_progress
        all(status: :in_progress)
      end

      # Count tasks by status
      def counts
        tasks = load_latest_tasks
        {
          total: tasks.size,
          pending: tasks.count { |t| t.status == :pending },
          in_progress: tasks.count { |t| t.status == :in_progress },
          done: tasks.count { |t| t.status == :done },
          abandoned: tasks.count { |t| t.status == :abandoned }
        }
      end

      private

      VALID_STATUSES = [:pending, :in_progress, :done, :abandoned].freeze
      VALID_PRIORITIES = [:high, :medium, :low].freeze

      def append_task(task)
        File.open(@file_path, "a") do |f|
          f.puts serialize_task(task)
        end
      end

      def load_latest_tasks
        return [] unless File.exist?(@file_path)

        tasks_by_id = {}

        File.readlines(@file_path).each_with_index do |line, index|
          next if line.strip.empty?

          begin
            data = JSON.parse(line.strip, symbolize_names: true)
            task = deserialize_task(data)
            tasks_by_id[task.id] = task
          rescue JSON::ParserError => e
            Aidp.log_warn("tasklist", "Skipping malformed JSONL line", line_number: index + 1, error: e.message)
            next
          rescue => e
            Aidp.log_warn("tasklist", "Error loading task", line_number: index + 1, error: e.message)
            next
          end
        end

        tasks_by_id.values
      end

      def serialize_task(task)
        hash = task.to_h
        # Convert Time objects to ISO8601 strings
        hash[:created_at] = hash[:created_at].iso8601 if hash[:created_at]
        hash[:updated_at] = hash[:updated_at].iso8601 if hash[:updated_at]
        hash[:started_at] = hash[:started_at].iso8601 if hash[:started_at]
        hash[:completed_at] = hash[:completed_at].iso8601 if hash[:completed_at]
        hash[:abandoned_at] = hash[:abandoned_at].iso8601 if hash[:abandoned_at]
        JSON.generate(hash)
      end

      def deserialize_task(data)
        Task.new(**data.merge(
          status: data[:status]&.to_sym,
          priority: data[:priority]&.to_sym,
          created_at: parse_time(data[:created_at]),
          updated_at: parse_time(data[:updated_at]),
          started_at: parse_time(data[:started_at]),
          completed_at: parse_time(data[:completed_at]),
          abandoned_at: parse_time(data[:abandoned_at]),
          tags: Array(data[:tags])
        ))
      end

      def parse_time(time_string)
        return nil if time_string.nil?
        Time.parse(time_string)
      rescue ArgumentError
        nil
      end

      def generate_id
        "task_#{Time.now.to_i}_#{SecureRandom.hex(4)}"
      end

      def ensure_file_exists
        FileUtils.mkdir_p(File.dirname(@file_path))
        FileUtils.touch(@file_path) unless File.exist?(@file_path)
      end

      def validate_description!(description)
        raise InvalidTaskError, "Description cannot be empty" if description.nil? || description.strip.empty?
        raise InvalidTaskError, "Description too long (max 200 chars)" if description.length > 200
      end

      def validate_priority!(priority)
        raise InvalidTaskError, "Invalid priority: #{priority}" unless VALID_PRIORITIES.include?(priority)
      end

      def validate_status!(status)
        raise InvalidTaskError, "Invalid status: #{status}" unless VALID_STATUSES.include?(status)
      end
    end
  end
end
