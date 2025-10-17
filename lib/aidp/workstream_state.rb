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

      # Per-worktree state files (mirrored for local inspection)
      def worktree_state_file(slug, project_dir)
        worktree_path = File.join(project_dir, ".worktrees", slug)
        return nil unless Dir.exist?(worktree_path)
        File.join(worktree_path, ".aidp", "workstreams", slug, "state.json")
      end

      def worktree_history_file(slug, project_dir)
        worktree_path = File.join(project_dir, ".worktrees", slug)
        return nil unless Dir.exist?(worktree_path)
        File.join(worktree_path, ".aidp", "workstreams", slug, "history.jsonl")
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
        # Mirror to worktree if it exists
        mirror_to_worktree(slug, project_dir, state)
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
        # Mirror to worktree if it exists
        mirror_to_worktree(slug, project_dir, state)
        state
      end

      # Increment iteration counter and record event
      def increment_iteration(slug:, project_dir:)
        state = read(slug: slug, project_dir: project_dir) || init(slug: slug, project_dir: project_dir)
        state[:iterations] = (state[:iterations] || 0) + 1
        state[:updated_at] = Time.now.utc.iso8601
        # Update status to active if paused (auto-resume on iteration)
        state[:status] = "active" if state[:status] == "paused"
        write_json(state_file(slug, project_dir), state)
        # Mirror to worktree if it exists
        mirror_to_worktree(slug, project_dir, state)
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
        # Mirror to worktree if it exists
        wt_file = worktree_history_file(slug, project_dir)
        if wt_file
          FileUtils.mkdir_p(File.dirname(wt_file))
          File.open(wt_file, "a") { |f| f.puts(JSON.generate(event)) }
        end
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

      # Check if workstream appears stalled (no activity for threshold seconds)
      def stalled?(slug:, project_dir:, threshold_seconds: 3600)
        state = read(slug: slug, project_dir: project_dir)
        return false unless state && state[:updated_at]
        return false if state[:status] != "active" # Only check active workstreams
        (Time.now.utc - Time.parse(state[:updated_at])).to_i > threshold_seconds
      end

      # Auto-complete stalled workstreams
      def auto_complete_stalled(slug:, project_dir:, threshold_seconds: 3600)
        return unless stalled?(slug: slug, project_dir: project_dir, threshold_seconds: threshold_seconds)
        complete(slug: slug, project_dir: project_dir)
        append_event(slug: slug, project_dir: project_dir, type: "auto_completed", data: {reason: "stalled"})
      end

      def mark_removed(slug:, project_dir:)
        state = read(slug: slug, project_dir: project_dir)
        # Auto-complete if active when removing
        if state && state[:status] == "active"
          complete(slug: slug, project_dir: project_dir)
        end
        update(slug: slug, project_dir: project_dir, status: "removed")
        append_event(slug: slug, project_dir: project_dir, type: "removed", data: {})
      end

      # Pause workstream (stop iteration without completion)
      def pause(slug:, project_dir:)
        state = read(slug: slug, project_dir: project_dir)
        return {error: "Workstream not found"} unless state
        return {error: "Already paused"} if state[:status] == "paused"

        now = Time.now.utc.iso8601
        update(slug: slug, project_dir: project_dir, status: "paused", paused_at: now)
        append_event(slug: slug, project_dir: project_dir, type: "paused", data: {})
        {status: "paused"}
      end

      # Resume workstream (return to active status)
      def resume(slug:, project_dir:)
        state = read(slug: slug, project_dir: project_dir)
        return {error: "Workstream not found"} unless state
        return {error: "Not paused"} unless state[:status] == "paused"

        now = Time.now.utc.iso8601
        update(slug: slug, project_dir: project_dir, status: "active", resumed_at: now)
        append_event(slug: slug, project_dir: project_dir, type: "resumed", data: {})
        {status: "active"}
      end

      # Mark workstream as completed
      def complete(slug:, project_dir:)
        state = read(slug: slug, project_dir: project_dir)
        return {error: "Workstream not found"} unless state
        return {error: "Already completed"} if state[:status] == "completed"

        now = Time.now.utc.iso8601
        update(slug: slug, project_dir: project_dir, status: "completed", completed_at: now)
        append_event(slug: slug, project_dir: project_dir, type: "completed", data: {iterations: state[:iterations]})
        {status: "completed"}
      end

      private

      def write_json(path, obj)
        File.write(path, JSON.pretty_generate(obj))
      end

      # Mirror state to worktree's .aidp directory for local visibility
      def mirror_to_worktree(slug, project_dir, state)
        wt_file = worktree_state_file(slug, project_dir)
        return unless wt_file
        FileUtils.mkdir_p(File.dirname(wt_file))
        write_json(wt_file, state)
      rescue
        # Silently ignore mirroring errors to not disrupt main operation
        nil
      end
    end
  end
end
