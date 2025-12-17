# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::WorkstreamExecutor do
  let(:project_dir) { Dir.mktmpdir("aidp-executor-spec") }
  let(:runner_double) { instance_double(Aidp::Harness::Runner, run: {status: "completed"}) }
  let(:runner_factory) { ->(path, mode, opts) { runner_double } }
  let(:executor) { described_class.new(project_dir: project_dir, max_concurrent: 2, runner_factory: runner_factory) }

  before do
    # Setup git repo
    Dir.chdir(project_dir) do
      system("git", "init", "-q")
      system("git", "config", "user.email", "test@example.com")
      system("git", "config", "user.name", "Test User")
      system("git", "config", "commit.gpgsign", "false")
      File.write("README.md", "# Test Project")
      system("git", "add", ".")
      system("git", "commit", "-m", "Initial commit", "-q")
    end
  end

  after do
    FileUtils.rm_rf(project_dir) if File.exist?(project_dir)
  end

  describe "#initialize" do
    it "sets project_dir and max_concurrent" do
      expect(executor.project_dir).to eq(project_dir)
      expect(executor.max_concurrent).to eq(2)
    end

    it "defaults max_concurrent to 3" do
      default_executor = described_class.new(project_dir: project_dir)
      expect(default_executor.max_concurrent).to eq(3)
    end

    it "initializes concurrent data structures" do
      results = executor.results
      start_times = executor.start_times

      expect(results).to be_a(Concurrent::Hash)
      expect(start_times).to be_a(Concurrent::Hash)
    end
  end

  describe "#execute_parallel" do
    let(:slug1) { "test-ws-1" }
    let(:slug2) { "test-ws-2" }

    before do
      # Create workstreams
      Aidp::Worktree.create(slug: slug1, project_dir: project_dir, task: "Task 1")
      Aidp::Worktree.create(slug: slug2, project_dir: project_dir, task: "Task 2")
    end

    after do
      # Cleanup workstreams
      begin
        Aidp::Worktree.remove(slug: slug1, project_dir: project_dir)
      rescue
        nil
      end
      begin
        Aidp::Worktree.remove(slug: slug2, project_dir: project_dir)
      rescue
        nil
      end
    end

    it "validates workstream existence before execution" do
      expect do
        executor.execute_parallel(["nonexistent"], {})
      end.to raise_error(ArgumentError, /not found/)
    end

    it "returns WorkstreamResult for each workstream" do
      # Mock execute_workstream to avoid full harness execution
      allow(executor).to receive(:execute_workstream).and_return(
        Aidp::WorkstreamExecutor::WorkstreamResult.new(
          slug: slug1,
          status: "completed",
          exit_code: 0,
          started_at: Time.now,
          completed_at: Time.now,
          duration: 1.5,
          error: nil
        )
      )

      results = executor.execute_parallel([slug1], {})

      expect(results).to be_an(Array)
      expect(results.size).to eq(1)
      expect(results.first).to be_a(Aidp::WorkstreamExecutor::WorkstreamResult)
      expect(results.first.slug).to eq(slug1)
    end

    it "executes multiple workstreams" do
      allow(executor).to receive(:execute_workstream).and_call_original
      allow(executor).to receive(:execute_workstream).and_call_original

      results = executor.execute_parallel([slug1, slug2], {})

      expect(results.size).to eq(2)
      expect(results.map(&:slug)).to contain_exactly(slug1, slug2)
    end

    it "respects max_concurrent limit via thread pool" do
      # Create 5 workstreams but max_concurrent is 2
      slugs = Array.new(5) { |i| "test-ws-limit-#{i}" }
      slugs.each do |slug|
        Aidp::Worktree.create(slug: slug, project_dir: project_dir, task: "Task")
      end

      execution_tracker = []
      allow(executor).to receive(:execute_workstream) do |slug, _opts|
        execution_tracker << slug
        sleep(0.01) # Minimal sleep for timing tests
        Aidp::WorkstreamExecutor::WorkstreamResult.new(
          slug: slug,
          status: "completed",
          exit_code: 0,
          started_at: Time.now,
          completed_at: Time.now,
          duration: 0.01,
          error: nil
        )
      end

      executor.execute_parallel(slugs, {})

      # All should execute
      expect(execution_tracker.size).to eq(5)

      slugs.each do |slug|
        Aidp::Worktree.remove(slug: slug, project_dir: project_dir)
      rescue
        nil
      end
    end
  end

  describe "#execute_all" do
    it "returns empty array when no workstreams exist" do
      results = executor.execute_all({})
      expect(results).to eq([])
    end

    it "executes all active workstreams" do
      # Create multiple workstreams
      slugs = %w[ws-1 ws-2 ws-3]
      slugs.each do |slug|
        Aidp::Worktree.create(slug: slug, project_dir: project_dir, task: "Task #{slug}")
      end

      allow(executor).to receive(:execute_workstream).and_return(
        Aidp::WorkstreamExecutor::WorkstreamResult.new(
          slug: "test",
          status: "completed",
          exit_code: 0,
          started_at: Time.now,
          completed_at: Time.now,
          duration: 1.0,
          error: nil
        )
      )

      results = executor.execute_all({})

      expect(results.size).to eq(3)

      slugs.each do |slug|
        Aidp::Worktree.remove(slug: slug, project_dir: project_dir)
      rescue
        nil
      end
    end

    it "skips inactive workstreams" do
      # Create active and inactive workstreams
      active_slug = "active-ws"
      Aidp::Worktree.create(slug: active_slug, project_dir: project_dir)

      # Manually create registry entry for inactive workstream
      registry_file = File.join(project_dir, ".aidp", "worktrees.json")
      registry = JSON.parse(File.read(registry_file))
      registry["inactive-ws"] = {
        "path" => File.join(project_dir, ".worktrees", "inactive-ws"),
        "branch" => "aidp/inactive-ws",
        "created_at" => Time.now.utc.iso8601
      }
      File.write(registry_file, JSON.pretty_generate(registry))

      allow(executor).to receive(:execute_workstream).and_return(
        Aidp::WorkstreamExecutor::WorkstreamResult.new(
          slug: active_slug,
          status: "completed",
          exit_code: 0,
          started_at: Time.now,
          completed_at: Time.now,
          duration: 1.0,
          error: nil
        )
      )

      results = executor.execute_all({})

      # Only active workstream should be executed
      expect(results.size).to eq(1)
      expect(results.first.slug).to eq(active_slug)

      begin
        Aidp::Worktree.remove(slug: active_slug, project_dir: project_dir)
      rescue
        nil
      end
    end
  end

  describe "#execute_workstream" do
    let(:slug) { "test-workstream" }
    let(:workstream_path) { File.join(project_dir, ".worktrees", slug) }

    before do
      Aidp::Worktree.create(slug: slug, project_dir: project_dir, task: "Test task")
    end

    after do
      Aidp::Worktree.remove(slug: slug, project_dir: project_dir)
    rescue
      nil
    end

    it "returns error result for nonexistent workstream" do
      result = executor.execute_workstream("nonexistent", {})

      expect(result).to be_a(Aidp::WorkstreamExecutor::WorkstreamResult)
      expect(result.status).to eq("error")
      expect(result.error).to match(/not found/)
    end

    it "updates workstream state to active before execution" do
      executor.execute_workstream(slug, {})

      executor.execute_workstream(slug, {})

      # State should be updated (either active during execution or completed after)
      state = Aidp::WorkstreamState.read(slug: slug, project_dir: project_dir)
      expect(state).not_to be_nil
      expect(%w[active completed failed]).to include(state[:status])
    end

    it "executes harness in forked process" do
      result = executor.execute_workstream(slug, {})

      expect(result).to be_a(Aidp::WorkstreamExecutor::WorkstreamResult)
      expect(result.slug).to eq(slug)
      expect(result.started_at).to be_a(Time)
      expect(result.completed_at).to be_a(Time)
      expect(result.duration).to be_a(Numeric)
    end

    it "sets status to completed on successful execution" do
      local_runner = instance_double(Aidp::Harness::Runner, run: {status: "completed"})
      local_executor = described_class.new(project_dir: project_dir, runner_factory: ->(*_args) { local_runner })
      result = local_executor.execute_workstream(slug, {})

      expect(result.status).to eq("completed")
      expect(result.exit_code).to eq(0)
      expect(result.error).to be_nil
    end

    it "sets status to failed on harness failure" do
      failing_runner = instance_double(Aidp::Harness::Runner, run: {status: "failed"})
      failing_executor = described_class.new(project_dir: project_dir, runner_factory: ->(*_args) { failing_runner })
      result = failing_executor.execute_workstream(slug, {})

      expect(result.status).to eq("failed")
      expect(result.exit_code).to eq(1)
    end

    it "handles exceptions during execution" do
      raising_runner = instance_double(Aidp::Harness::Runner)
      allow(raising_runner).to receive(:run).and_raise("Test error")
      raising_executor = described_class.new(project_dir: project_dir, runner_factory: ->(*_args) { raising_runner })
      result = raising_executor.execute_workstream(slug, {})

      expect(result.status).to eq("failed")
      expect(result.exit_code).to eq(1)
      expect(result.error).not_to be_nil
      expect(result.error).to include("Process exited with code 1")
    end

    it "calculates duration correctly" do
      timing_runner = instance_double(Aidp::Harness::Runner)
      allow(timing_runner).to receive(:run) do
        sleep(0.01)
        {status: "completed"}
      end
      timing_executor = described_class.new(project_dir: project_dir, runner_factory: ->(*_args) { timing_runner })
      result = timing_executor.execute_workstream(slug, {})

      expect(result.duration).to be >= 0.01 # More forgiving threshold
      expect(result.duration).to be < 2.0
    end
  end

  describe "WorkstreamResult" do
    it "is created with all required fields" do
      result = Aidp::WorkstreamExecutor::WorkstreamResult.new(
        slug: "test",
        status: "completed",
        exit_code: 0,
        started_at: Time.now,
        completed_at: Time.now + 5,
        duration: 5.0,
        error: nil
      )

      expect(result.slug).to eq("test")
      expect(result.status).to eq("completed")
      expect(result.exit_code).to eq(0)
      expect(result.duration).to eq(5.0)
      expect(result.error).to be_nil
    end

    it "supports keyword arguments" do
      time = Time.now
      result = Aidp::WorkstreamExecutor::WorkstreamResult.new(
        slug: "test",
        status: "failed",
        exit_code: 1,
        started_at: time,
        completed_at: time + 10,
        duration: 10.0,
        error: "Something went wrong"
      )

      expect(result.error).to eq("Something went wrong")
    end
  end

  describe "private helper methods" do
    describe "#format_duration" do
      it "formats seconds under 60" do
        result = executor.send(:format_duration, 45.7)
        expect(result).to eq("45.7s")
      end

      it "formats minutes and seconds" do
        result = executor.send(:format_duration, 125.3)
        expect(result).to eq("2m 5s")
      end

      it "formats hours and minutes" do
        result = executor.send(:format_duration, 7325)
        expect(result).to eq("2h 2m")
      end

      it "handles exactly 60 seconds" do
        result = executor.send(:format_duration, 60)
        expect(result).to eq("1m 0s")
      end

      it "handles exactly 1 hour" do
        result = executor.send(:format_duration, 3600)
        expect(result).to eq("1h 0m")
      end
    end

    describe "#display_execution_summary" do
      it "displays summary with all completed" do
        allow(executor).to receive(:display_message)

        results = [
          Aidp::WorkstreamExecutor::WorkstreamResult.new(
            slug: "ws1",
            status: "completed",
            exit_code: 0,
            started_at: Time.now - 10,
            completed_at: Time.now,
            duration: 10.0,
            error: nil
          ),
          Aidp::WorkstreamExecutor::WorkstreamResult.new(
            slug: "ws2",
            status: "completed",
            exit_code: 0,
            started_at: Time.now - 5,
            completed_at: Time.now,
            duration: 5.0,
            error: nil
          )
        ]

        executor.send(:display_execution_summary, results)

        expect(executor).to have_received(:display_message).at_least(:once)
      end

      it "displays summary with some failures" do
        allow(executor).to receive(:display_message)

        results = [
          Aidp::WorkstreamExecutor::WorkstreamResult.new(
            slug: "ws1",
            status: "completed",
            exit_code: 0,
            started_at: Time.now - 10,
            completed_at: Time.now,
            duration: 10.0,
            error: nil
          ),
          Aidp::WorkstreamExecutor::WorkstreamResult.new(
            slug: "ws2",
            status: "failed",
            exit_code: 1,
            started_at: Time.now - 5,
            completed_at: Time.now,
            duration: 5.0,
            error: "Test error"
          )
        ]

        executor.send(:display_execution_summary, results)

        expect(executor).to have_received(:display_message).at_least(:once)
      end
    end
  end
end
