# frozen_string_literal: true

require "json"
require "fileutils"

module Aidp
  # Manages per-workstream state (task, iterations, timestamps, event log)
  # Stored under: .aidp/workstreams/<slug>/state.json and history.jsonl
  module WorkstreamState
    class Error < StandardError; end

    class << self
      def root_dir(project_dir)
        File.join(project_dir, ".aidp", "workstreams")
      end

      def workstream_dir(slug, project_dir)
        File.join(root_dir(project_dir), slug)
      end

      def state_file(slug, project_dir)
        File.join(workstream_dir(slug, project_dir), "state.json")
      end

      def history_file(slug, project_dir)
        File.join(workstream_dir(slug, project_dir), "history.jsonl")
      end

      # Initialize state for a new workstream
      def init(slug:, project_dir:, task: nil)
        dir = workstream_dir(slug, project_dir)
        FileUtils.mkdir_p(dir)
        now = Time.now.utc
        state = {
          slug: slug,
          status: "active",
          task: task,
          started_at: now.iso8601,
          updated_at: now.iso8601,
          iterations: 0
        }
        write_json(state_file(slug, project_dir), state)
        append_event(slug: slug, project_dir: project_dir, type: "created", data: {task: task})
        state
      end

      # Read current state (returns hash or nil)
      def read(slug:, project_dir:)
        file = state_file(slug, project_dir)
        return nil unless File.exist?(file)
        JSON.parse(File.read(file), symbolize_names: true)
      rescue JSON::ParserError
        nil
      end

      # Update selected attributes; updates updated_at automatically
      def update(slug:, project_dir:, **attrs)
        state = read(slug: slug, project_dir: project_dir) || init(slug: slug, project_dir: project_dir)
        state.merge!(attrs.transform_keys(&:to_sym))
        state[:updated_at] = Time.now.utc.iso8601
        write_json(state_file(slug, project_dir), state)
        state
      end

      # Increment iteration counter and record event
      def increment_iteration(slug:, project_dir:)
        state = read(slug: slug, project_dir: project_dir) || init(slug: slug, project_dir: project_dir)
        state[:iterations] = (state[:iterations] || 0) + 1
        state[:updated_at] = Time.now.utc.iso8601
        write_json(state_file(slug, project_dir), state)
        append_event(slug: slug, project_dir: project_dir, type: "iteration", data: {count: state[:iterations]})
        state
      end

      # Append event to history.jsonl
      def append_event(slug:, project_dir:, type:, data: {})
        file = history_file(slug, project_dir)
        FileUtils.mkdir_p(File.dirname(file))
        event = {
          timestamp: Time.now.utc.iso8601,
          type: type,
          data: data
        }
        File.open(file, "a") { |f| f.puts(JSON.generate(event)) }
        event
      end

      # Read recent N events
      def recent_events(slug:, project_dir:, limit: 5)
        file = history_file(slug, project_dir)
        return [] unless File.exist?(file)
        lines = File.readlines(file, chomp: true)
        lines.last(limit).map do |line|
          JSON.parse(line, symbolize_names: true)
        rescue JSON::ParserError
          nil
        end.compact
      end

      def elapsed_seconds(slug:, project_dir:)
        state = read(slug: slug, project_dir: project_dir)
        return 0 unless state && state[:started_at]
        (Time.now.utc - Time.parse(state[:started_at])).to_i
      end

      def mark_removed(slug:, project_dir:)
        update(slug: slug, project_dir: project_dir, status: "removed")
        append_event(slug: slug, project_dir: project_dir, type: "removed", data: {})
      end

      private

      def write_json(path, obj)
        File.write(path, JSON.pretty_generate(obj))
      end
    end
  end
end
