# frozen_string_literal: true

require "concurrent-ruby"
require "time"
require_relative "worktree"
require_relative "workstream_state"
require_relative "harness/runner"
require_relative "message_display"

module Aidp
  # Executes multiple workstreams in parallel using concurrent-ruby.
  # Provides true parallel execution with process isolation and status tracking.
  class WorkstreamExecutor
    include Aidp::MessageDisplay

    # Result from executing a workstream
    WorkstreamResult = Struct.new(
      :slug,
      :status,
      :exit_code,
      :started_at,
      :completed_at,
      :duration,
      :error,
      keyword_init: true
    )

    # @param project_dir [String] root directory of the project
    # @param max_concurrent [Integer] maximum number of concurrent workstreams (thread pool size)
    # @param runner_factory [Proc] factory that builds a harness runner. Signature: (path, mode, options) => object responding to #run
    def initialize(project_dir: Dir.pwd, max_concurrent: 3, runner_factory: nil)
      @project_dir = project_dir
      @max_concurrent = max_concurrent
      @results = Concurrent::Hash.new
      @start_times = Concurrent::Hash.new
      @runner_factory = runner_factory || lambda do |path, mode, options|
        Aidp::Harness::Runner.new(path, mode, options)
      end
    end

    # Execute multiple workstreams in parallel
    #
    # @param slugs [Array<String>] Workstream slugs to execute
    # @param options [Hash] Execution options
    # @option options [Array<String>] :selected_steps Steps to execute
    # @option options [Symbol] :workflow_type Workflow type (:execute, :analyze, etc.)
    # @option options [Hash] :user_input User input for harness
    # @return [Array<WorkstreamResult>] Results for each workstream
    def execute_parallel(slugs, options = {})
      validate_workstreams!(slugs)

      display_message("🚀 Starting parallel execution of #{slugs.size} workstreams (max #{@max_concurrent} concurrent)", type: :info)

      # Create thread pool with max concurrent limit
      pool = Concurrent::FixedThreadPool.new(@max_concurrent)

      # Create futures for each workstream
      futures = slugs.map do |slug|
        Concurrent::Future.execute(executor: pool) do
          execute_workstream(slug, options)
        end
      end

      # Wait for all futures to complete
      results = futures.map(&:value)

      # Shutdown pool gracefully
      pool.shutdown
      pool.wait_for_termination(30)

      display_execution_summary(results)
      results
    end

    # Execute all active workstreams in parallel
    #
    # @param options [Hash] Execution options (same as execute_parallel)
    # @return [Array<WorkstreamResult>] Results for each workstream
    def execute_all(options = {})
      workstreams = Aidp::Worktree.list(project_dir: @project_dir)
      active_slugs = workstreams.select { |ws| ws[:active] }.map { |ws| ws[:slug] }

      if active_slugs.empty?
        display_message("⚠️  No active workstreams found", type: :warn)
        return []
      end

      execute_parallel(active_slugs, options)
    end

    # Execute a single workstream (used by futures in parallel execution)
    #
    # @param slug [String] Workstream slug
    # @param options [Hash] Execution options
    # @return [WorkstreamResult] Execution result
    def execute_workstream(slug, options = {})
      started_at = Time.now
      @start_times[slug] = started_at

      workstream = Aidp::Worktree.info(slug: slug, project_dir: @project_dir)
      unless workstream
        return WorkstreamResult.new(
          slug: slug,
          status: "error",
          exit_code: 1,
          started_at: started_at,
          completed_at: Time.now,
          duration: 0,
          error: "Workstream not found"
        )
      end

      display_message("▶️  [#{slug}] Starting execution in #{workstream[:path]}", type: :info)

      # Update workstream state to active
      Aidp::WorkstreamState.update(
        slug: slug,
        project_dir: @project_dir,
        status: "active",
        started_at: started_at.utc.iso8601
      )

      # Execute in forked process for true isolation
      pid = fork do
        # Change to workstream directory
        Dir.chdir(workstream[:path])

        # Execute harness
        runner = @runner_factory.call(
          workstream[:path],
          options[:mode] || :execute,
          options
        )

        result = runner.run

        # Update state on completion
        exit_code = (result[:status] == "completed") ? 0 : 1
        final_status = (result[:status] == "completed") ? "completed" : "failed"

        Aidp::WorkstreamState.update(
          slug: slug,
          project_dir: @project_dir,
          status: final_status,
          completed_at: Time.now.utc.iso8601
        )

        exit(exit_code)
      rescue => e
        # Update state on error
        Aidp::WorkstreamState.update(
          slug: slug,
          project_dir: @project_dir,
          status: "failed",
          completed_at: Time.now.utc.iso8601
        )

        # Log error and exit
        warn("Error in workstream #{slug}: #{e.message}")
        warn(e.backtrace.first(5).join("\n"))
        exit(1)
      end

      # Wait for child process
      _pid, status = Process.wait2(pid)
      completed_at = Time.now
      duration = completed_at - started_at

      # Build result
      result_status = status.success? ? "completed" : "failed"
      result = WorkstreamResult.new(
        slug: slug,
        status: result_status,
        exit_code: status.exitstatus,
        started_at: started_at,
        completed_at: completed_at,
        duration: duration,
        error: status.success? ? nil : "Process exited with code #{status.exitstatus}"
      )

      @results[slug] = result

      display_message("#{status.success? ? "✅" : "❌"} [#{slug}] #{result_status.capitalize} in #{format_duration(duration)}", type: status.success? ? :success : :error)

      result
    rescue => e
      completed_at = Time.now
      duration = completed_at - started_at

      WorkstreamResult.new(
        slug: slug,
        status: "error",
        exit_code: 1,
        started_at: started_at,
        completed_at: completed_at,
        duration: duration,
        error: e.message
      )
    end

    private

    # Validate that all workstreams exist
    def validate_workstreams!(slugs)
      invalid = slugs.reject do |slug|
        Aidp::Worktree.exists?(slug: slug, project_dir: @project_dir)
      end

      unless invalid.empty?
        raise ArgumentError, "Workstreams not found: #{invalid.join(", ")}"
      end
    end

    # Display execution summary
    def display_execution_summary(results)
      completed = results.count { |r| r.status == "completed" }
      failed = results.count { |r| r.status == "failed" || r.status == "error" }
      total_duration = results.sum(&:duration)

      display_message("\n" + "=" * 60, type: :muted)
      display_message("📊 Execution Summary", type: :info)
      display_message("Total: #{results.size} | Completed: #{completed} | Failed: #{failed}", type: :info)
      display_message("Total Duration: #{format_duration(total_duration)}", type: :info)

      if failed > 0
        display_message("\n❌ Failed Workstreams:", type: :error)
        results.select { |r| r.status != "completed" }.each do |result|
          display_message("  - #{result.slug}: #{result.error}", type: :error)
        end
      end

      display_message("=" * 60, type: :muted)
    end

    # Format duration in human-readable format
    def format_duration(seconds)
      if seconds < 60
        "#{seconds.round(1)}s"
      elsif seconds < 3600
        minutes = (seconds / 60).floor
        secs = (seconds % 60).round
        "#{minutes}m #{secs}s"
      else
        hours = (seconds / 3600).floor
        minutes = ((seconds % 3600) / 60).floor
        "#{hours}h #{minutes}m"
      end
    end
  end
end
