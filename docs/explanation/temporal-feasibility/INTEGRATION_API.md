# Temporal Feasibility Study: Integration API

This document defines the proposed Ruby interface for integrating Temporal.io workflows into Aidp.

---

## 1. Architecture Overview

```text
┌─────────────────────────────────────────────────────────────────┐
│                        Aidp CLI                                  │
│  (Existing commands: execute, watch, jobs, workstreams)          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   OrchestrationRouter                            │
│  (Routes to Temporal or Native based on config)                  │
└─────────────────────────────────────────────────────────────────┘
                              │
            ┌─────────────────┴─────────────────┐
            │                                   │
            ▼                                   ▼
┌─────────────────────┐            ┌─────────────────────┐
│  Temporal Client    │            │   Native Engine     │
│  (New)              │            │   (Existing)        │
└─────────────────────┘            └─────────────────────┘
```

---

## 2. Module Structure

```text
lib/aidp/temporal/
├── client.rb                 # Main Temporal client wrapper
├── connection.rb             # Connection management
├── workflows/
│   ├── base_workflow.rb      # Base class for workflows
│   ├── work_loop_workflow.rb
│   ├── workstream_workflow.rb
│   ├── watch_mode_workflow.rb
│   └── analyze_workflow.rb
├── activities/
│   ├── base_activity.rb      # Base class for activities
│   ├── execute_agent_activity.rb
│   ├── run_tests_activity.rb
│   ├── run_linter_activity.rb
│   ├── git_operation_activity.rb
│   ├── github_api_activity.rb
│   └── create_worktree_activity.rb
├── workers/
│   ├── work_loop_worker.rb
│   ├── watch_mode_worker.rb
│   └── worker_manager.rb
└── adapters/
    ├── work_loop_adapter.rb  # Adapts existing interfaces
    ├── job_adapter.rb
    └── workstream_adapter.rb
```

---

## 3. Core Client API

### 3.1 Connection Class

```ruby
# lib/aidp/temporal/connection.rb
module Aidp
  module Temporal
    class Connection
      DEFAULT_ADDRESS = "localhost:7233"
      DEFAULT_NAMESPACE = "default"

      attr_reader :client, :namespace

      def initialize(config = {})
        @address = config[:address] || DEFAULT_ADDRESS
        @namespace = config[:namespace] || DEFAULT_NAMESPACE
        @client = nil
      end

      def connect
        @client ||= Temporalio::Client.connect(
          @address,
          namespace: @namespace
        )
      end

      def connected?
        !@client.nil?
      end

      def disconnect
        @client = nil
      end

      def health_check
        connect
        # Ping temporal service
        @client.workflow_service.get_system_info
        true
      rescue => e
        Aidp.log_error("temporal_connection", "health_check_failed", error: e.message)
        false
      end
    end
  end
end
```

### 3.2 Main Client Class

```ruby
# lib/aidp/temporal/client.rb
module Aidp
  module Temporal
    class Client
      # Expose for testability
      attr_reader :connection, :config

      def initialize(config = {})
        @config = config
        @connection = Connection.new(config)
      end

      # ========== Work Loop Operations ==========

      # Start a work loop and wait for completion
      def execute_work_loop(step_name, step_spec, context = {})
        workflow_id = generate_workflow_id("work-loop", step_name)

        handle = connection.connect.start_workflow(
          Workflows::WorkLoopWorkflow,
          step_name, step_spec, context,
          id: workflow_id,
          task_queue: task_queue(:work_loop)
        )

        handle.result
      end

      # Start a work loop asynchronously (returns immediately)
      def start_work_loop_async(step_name, step_spec, context = {})
        workflow_id = generate_workflow_id("work-loop", step_name)

        connection.connect.start_workflow(
          Workflows::WorkLoopWorkflow,
          step_name, step_spec, context,
          id: workflow_id,
          task_queue: task_queue(:work_loop)
        )

        { workflow_id: workflow_id, status: "started" }
      end

      # Wait for async work loop to complete
      def wait_for_work_loop(workflow_id)
        handle = connection.connect.get_workflow_handle(workflow_id)
        handle.result
      end

      # Send control signals to work loop
      def pause_work_loop(workflow_id)
        send_signal(workflow_id, "pause")
      end

      def resume_work_loop(workflow_id)
        send_signal(workflow_id, "resume")
      end

      def cancel_work_loop(workflow_id)
        send_signal(workflow_id, "cancel")
      end

      def inject_instruction(workflow_id, instruction)
        send_signal(workflow_id, "inject_instruction", instruction)
      end

      # Query work loop status
      def work_loop_status(workflow_id)
        query_workflow(workflow_id, "status")
      end

      # ========== Workstream Operations ==========

      def execute_workstreams(slugs, options = {})
        workflow_id = generate_workflow_id("workstreams", slugs.first)

        handle = connection.connect.start_workflow(
          Workflows::WorkstreamOrchestratorWorkflow,
          slugs, options,
          id: workflow_id,
          task_queue: task_queue(:work_loop)
        )

        handle.result
      end

      def start_workstreams_async(slugs, options = {})
        workflow_id = generate_workflow_id("workstreams", slugs.first)

        connection.connect.start_workflow(
          Workflows::WorkstreamOrchestratorWorkflow,
          slugs, options,
          id: workflow_id,
          task_queue: task_queue(:work_loop)
        )

        { workflow_id: workflow_id, status: "started", workstreams: slugs }
      end

      # ========== Watch Mode Operations ==========

      def start_watch_mode(issues_url:, interval: 30, once: false)
        workflow_id = generate_workflow_id("watch-mode", extract_repo(issues_url))

        connection.connect.start_workflow(
          Workflows::WatchModeWorkflow,
          issues_url: issues_url,
          interval: interval,
          once: once,
          id: workflow_id,
          task_queue: task_queue(:watch_mode)
        )

        { workflow_id: workflow_id, status: "started" }
      end

      def stop_watch_mode(workflow_id)
        send_signal(workflow_id, "stop")
      end

      # ========== Background Job Operations ==========

      def list_jobs(filter: nil)
        query = build_list_query(filter)

        connection.connect.list_workflows(query: query).map do |info|
          format_job_info(info)
        end
      end

      def job_status(workflow_id)
        info = connection.connect.describe_workflow(workflow_id)
        format_job_info(info)
      end

      def stop_job(workflow_id)
        connection.connect.cancel_workflow(workflow_id)
        { success: true, workflow_id: workflow_id }
      rescue Temporalio::Error::WorkflowNotFound
        { success: false, error: "Job not found" }
      end

      def job_history(workflow_id, limit: 100)
        handle = connection.connect.get_workflow_handle(workflow_id)
        handle.fetch_history(limit: limit)
      end

      private

      def send_signal(workflow_id, signal_name, *args)
        handle = connection.connect.get_workflow_handle(workflow_id)
        handle.signal(signal_name, *args)
        { success: true, workflow_id: workflow_id, signal: signal_name }
      rescue Temporalio::Error::WorkflowNotFound
        { success: false, error: "Workflow not found" }
      end

      def query_workflow(workflow_id, query_name)
        handle = connection.connect.get_workflow_handle(workflow_id)
        handle.query(query_name)
      rescue Temporalio::Error::WorkflowNotFound
        { error: "Workflow not found" }
      end

      def task_queue(type)
        @config.dig(:task_queues, type) || "aidp-#{type}"
      end

      def generate_workflow_id(type, suffix)
        timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
        random = SecureRandom.hex(4)
        "aidp-#{type}-#{suffix}-#{timestamp}-#{random}"
      end

      def build_list_query(filter)
        query = 'WorkflowType STARTS_WITH "Aidp"'
        query += " AND ExecutionStatus = '#{filter}'" if filter
        query
      end

      def format_job_info(info)
        {
          job_id: info.workflow_id,
          workflow_type: info.workflow_type,
          status: info.status.to_s,
          started_at: info.start_time,
          completed_at: info.close_time,
          running: info.status == :running
        }
      end

      def extract_repo(issues_url)
        # Extract owner/repo from URL
        uri = URI.parse(issues_url)
        uri.path.split("/")[1..2].join("-")
      end
    end
  end
end
```

---

## 4. Workflow Definitions

### 4.1 Base Workflow

```ruby
# lib/aidp/temporal/workflows/base_workflow.rb
module Aidp
  module Temporal
    module Workflows
      class BaseWorkflow < Temporalio::Workflow
        # Common configuration
        DEFAULT_ACTIVITY_TIMEOUT = 600  # 10 minutes
        DEFAULT_HEARTBEAT_TIMEOUT = 60  # 1 minute

        protected

        def execute_activity(activity_class, **args)
          workflow.execute_activity(
            activity_class,
            **args,
            start_to_close_timeout: DEFAULT_ACTIVITY_TIMEOUT,
            heartbeat_timeout: DEFAULT_HEARTBEAT_TIMEOUT
          )
        end

        def execute_activity_with_retry(activity_class, retry_policy:, **args)
          workflow.execute_activity(
            activity_class,
            **args,
            start_to_close_timeout: DEFAULT_ACTIVITY_TIMEOUT,
            heartbeat_timeout: DEFAULT_HEARTBEAT_TIMEOUT,
            retry_policy: retry_policy
          )
        end

        def default_retry_policy
          Temporalio::RetryPolicy.new(
            initial_interval: 1,
            backoff_coefficient: 2.0,
            maximum_interval: 30,
            maximum_attempts: 3
          )
        end

        def non_retryable_policy
          Temporalio::RetryPolicy.new(
            maximum_attempts: 1
          )
        end
      end
    end
  end
end
```

### 4.2 WorkLoopWorkflow

```ruby
# lib/aidp/temporal/workflows/work_loop_workflow.rb
module Aidp
  module Temporal
    module Workflows
      class WorkLoopWorkflow < BaseWorkflow
        MAX_ITERATIONS = 50
        CHECKPOINT_INTERVAL = 5

        def execute(step_name, step_spec, context)
          @step_name = step_name
          @iteration = 0
          @state = :ready
          @paused = false
          @cancelled = false
          @instructions = []
          @metrics = {}

          # Initial prompt creation
          execute_activity(
            Activities::CreatePromptActivity,
            step_spec: step_spec,
            context: context,
            project_dir: context[:project_dir]
          )

          run_work_loop(step_spec, context)
        end

        # Signal Handlers
        workflow.signal_handler("pause") { @paused = true }
        workflow.signal_handler("resume") { @paused = false }
        workflow.signal_handler("cancel") { @cancelled = true; @paused = false }
        workflow.signal_handler("inject_instruction") { |inst| @instructions << inst }
        workflow.signal_handler("update_guard") { |key, val| @guard_updates[key] = val }

        # Query Handlers
        workflow.query_handler("status") do
          {
            step_name: @step_name,
            iteration: @iteration,
            state: @state,
            paused: @paused,
            cancelled: @cancelled,
            pending_instructions: @instructions.size,
            metrics: @metrics
          }
        end

        workflow.query_handler("metrics") { @metrics }

        private

        def run_work_loop(step_spec, context)
          while @iteration < MAX_ITERATIONS
            # Wait if paused
            workflow.wait_condition { !@paused }

            # Check for cancellation
            if @cancelled
              return build_result(:cancelled, "Cancelled by user")
            end

            @iteration += 1
            transition(:apply_patch)

            # Execute agent
            agent_result = execute_agent(context)

            # Handle agent errors
            if agent_result[:status] == "error"
              if should_retry_agent?(agent_result)
                transition(:diagnose)
                append_error_to_prompt(agent_result[:error])
                next
              else
                return build_result(:error, agent_result[:error])
              end
            end

            transition(:test)

            # Run validation
            validation_results = run_validation(context)

            # Record checkpoint periodically
            record_checkpoint(validation_results) if (@iteration % CHECKPOINT_INTERVAL).zero?

            # Check completion
            all_pass = validation_results.values.all? { |r| r[:success] }

            if all_pass && agent_result[:completed]
              transition(:done)
              return build_result(:completed, agent_result[:output])
            elsif !all_pass
              transition(:diagnose)
              prepare_next_iteration(validation_results)
            end

            transition(:ready)
          end

          build_result(:max_iterations, "Max iterations (#{MAX_ITERATIONS}) reached")
        end

        def execute_agent(context)
          provider, model = select_provider_and_model

          execute_activity_with_retry(
            Activities::ExecuteAgentActivity,
            provider: provider,
            model: model,
            prompt_path: prompt_path(context[:project_dir]),
            options: context[:agent_options] || {},
            retry_policy: agent_retry_policy
          )
        rescue Temporalio::Error::ActivityFailure => e
          { status: "error", error: e.message }
        end

        def run_validation(context)
          # Run tests and linter in parallel using async activities
          test_future = workflow.execute_activity_async(
            Activities::RunTestsActivity,
            project_dir: context[:project_dir],
            config: context[:test_config] || {}
          )

          lint_future = workflow.execute_activity_async(
            Activities::RunLinterActivity,
            project_dir: context[:project_dir],
            config: context[:lint_config] || {}
          )

          {
            tests: test_future.result,
            lint: lint_future.result
          }
        end

        def prepare_next_iteration(results)
          execute_activity(
            Activities::PrepareNextIterationActivity,
            results: results,
            instructions: drain_instructions,
            project_dir: @context[:project_dir]
          )
        end

        def drain_instructions
          instructions = @instructions.dup
          @instructions.clear
          instructions
        end

        def transition(new_state)
          @state = new_state
        end

        def agent_retry_policy
          Temporalio::RetryPolicy.new(
            initial_interval: 2,
            backoff_coefficient: 2.0,
            maximum_interval: 60,
            maximum_attempts: 3,
            non_retryable_errors: [
              'Aidp::Errors::ConfigurationError',
              'Aidp::Security::PolicyViolation'
            ]
          )
        end

        def should_retry_agent?(result)
          !result[:non_retryable]
        end

        def build_result(status, message)
          {
            status: status.to_s,
            message: message,
            iterations: @iteration,
            step_name: @step_name,
            metrics: @metrics
          }
        end
      end
    end
  end
end
```

---

## 5. Activity Definitions

### 5.1 Base Activity

```ruby
# lib/aidp/temporal/activities/base_activity.rb
module Aidp
  module Temporal
    module Activities
      class BaseActivity < Temporalio::Activity
        protected

        def heartbeat(message)
          activity.heartbeat(message)
        end

        def log_activity(action, **data)
          Aidp.log_debug("temporal_activity", action, **data)
        end
      end
    end
  end
end
```

### 5.2 ExecuteAgentActivity

```ruby
# lib/aidp/temporal/activities/execute_agent_activity.rb
require "open3"

module Aidp
  module Temporal
    module Activities
      class ExecuteAgentActivity < BaseActivity
        COMPLETION_SIGNALS = [
          "## Task Complete",
          "[DONE]",
          "All tasks completed"
        ].freeze

        def execute(provider:, model:, prompt_path:, options: {})
          log_activity("execute_agent.start", provider: provider, model: model)
          heartbeat("Starting agent execution")

          command = build_command(provider, model, prompt_path, options)
          output = execute_command(command)

          {
            status: "completed",
            output: output,
            completed: detect_completion(output),
            provider: provider,
            model: model
          }
        rescue => e
          log_activity("execute_agent.error", error: e.message)
          raise Temporalio::Error::ApplicationError.new(
            e.message,
            type: classify_error(e),
            non_retryable: non_retryable_error?(e)
          )
        end

        private

        def build_command(provider, model, prompt_path, options)
          case provider
          when "anthropic", "claude"
            build_claude_command(model, prompt_path, options)
          when "cursor"
            build_cursor_command(prompt_path, options)
          when "aider"
            build_aider_command(model, prompt_path, options)
          when "copilot"
            build_copilot_command(prompt_path, options)
          else
            raise "Unknown provider: #{provider}"
          end
        end

        def execute_command(command)
          output = ""

          Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
            stdin.close

            # Read output with periodic heartbeats
            threads = []

            threads << Thread.new do
              stdout.each_line do |line|
                output << line
                heartbeat("Processing: #{line[0..50]}...")
              end
            end

            threads << Thread.new do
              stderr.each_line { |line| output << "[stderr] #{line}" }
            end

            threads.each(&:join)

            unless wait_thr.value.success?
              raise "Agent command failed with exit code #{wait_thr.value.exitstatus}"
            end
          end

          output
        end

        def detect_completion(output)
          COMPLETION_SIGNALS.any? { |signal| output.include?(signal) }
        end

        def classify_error(error)
          case error.message
          when /authentication|auth|token/i
            "AuthenticationError"
          when /rate limit|429/i
            "RateLimitError"
          when /configuration|config/i
            "ConfigurationError"
          else
            "AgentExecutionError"
          end
        end

        def non_retryable_error?(error)
          error.message =~ /configuration|security|policy/i
        end
      end
    end
  end
end
```

### 5.3 RunTestsActivity

```ruby
# lib/aidp/temporal/activities/run_tests_activity.rb
module Aidp
  module Temporal
    module Activities
      class RunTestsActivity < BaseActivity
        def execute(project_dir:, config: {})
          log_activity("run_tests.start", project_dir: project_dir)
          heartbeat("Running tests")

          command = config[:command] || detect_test_command(project_dir)
          return skip_result("No test command found") unless command

          Dir.chdir(project_dir) do
            output = `#{command} 2>&1`
            success = $?.success?

            {
              success: success,
              output: output,
              exit_code: $?.exitstatus,
              command: command
            }
          end
        end

        private

        def detect_test_command(project_dir)
          if File.exist?(File.join(project_dir, "Gemfile"))
            "bundle exec rspec"
          elsif File.exist?(File.join(project_dir, "package.json"))
            "npm test"
          elsif File.exist?(File.join(project_dir, "pytest.ini"))
            "pytest"
          end
        end

        def skip_result(reason)
          { success: true, output: reason, skipped: true }
        end
      end
    end
  end
end
```

---

## 6. Adapter Layer

### 6.1 Orchestration Router

```ruby
# lib/aidp/orchestration_router.rb
module Aidp
  class OrchestrationRouter
    attr_reader :engine

    def initialize(config)
      @config = config
      @engine = config.dig(:orchestration, :engine) || "native"
      @temporal_client = nil
    end

    def temporal?
      @engine == "temporal"
    end

    # Work Loop operations
    def execute_work_loop(step_name, step_spec, context = {})
      if temporal?
        temporal_client.execute_work_loop(step_name, step_spec, context)
      else
        native_work_loop_runner(context).execute_step(step_name, step_spec, context)
      end
    end

    def start_work_loop_async(step_name, step_spec, context = {})
      if temporal?
        temporal_client.start_work_loop_async(step_name, step_spec, context)
      else
        native_async_runner(context).execute_step_async(step_name, step_spec, context)
      end
    end

    def pause_work_loop(workflow_id_or_runner)
      if temporal?
        temporal_client.pause_work_loop(workflow_id_or_runner)
      else
        workflow_id_or_runner.pause
      end
    end

    def resume_work_loop(workflow_id_or_runner)
      if temporal?
        temporal_client.resume_work_loop(workflow_id_or_runner)
      else
        workflow_id_or_runner.resume
      end
    end

    def cancel_work_loop(workflow_id_or_runner, save_checkpoint: true)
      if temporal?
        temporal_client.cancel_work_loop(workflow_id_or_runner)
      else
        workflow_id_or_runner.cancel(save_checkpoint: save_checkpoint)
      end
    end

    # Workstream operations
    def execute_workstreams(slugs, options = {})
      if temporal?
        temporal_client.execute_workstreams(slugs, options)
      else
        native_workstream_executor(options).execute_parallel(slugs, options)
      end
    end

    # Watch mode operations
    def start_watch_mode(issues_url:, interval: 30, **options)
      if temporal?
        temporal_client.start_watch_mode(issues_url: issues_url, interval: interval, **options)
      else
        native_watch_runner(issues_url, interval, options).start
      end
    end

    # Background job operations
    def start_background_job(mode, options = {})
      if temporal?
        temporal_client.start_work_loop_async(mode.to_s, {}, options)
      else
        native_background_runner.start(mode, options)
      end
    end

    def list_jobs
      if temporal?
        temporal_client.list_jobs
      else
        native_background_runner.list_jobs
      end
    end

    def job_status(job_id)
      if temporal?
        temporal_client.job_status(job_id)
      else
        native_background_runner.job_status(job_id)
      end
    end

    def stop_job(job_id)
      if temporal?
        temporal_client.stop_job(job_id)
      else
        native_background_runner.stop_job(job_id)
      end
    end

    private

    def temporal_client
      @temporal_client ||= Aidp::Temporal::Client.new(@config[:orchestration][:temporal])
    end

    def native_work_loop_runner(context)
      Aidp::Execute::WorkLoopRunner.new(
        context[:project_dir] || Dir.pwd,
        context[:provider_manager],
        context[:config],
        context[:options] || {}
      )
    end

    def native_async_runner(context)
      Aidp::Execute::AsyncWorkLoopRunner.new(
        context[:project_dir] || Dir.pwd,
        context[:provider_manager],
        context[:config],
        context[:options] || {}
      )
    end

    def native_workstream_executor(options)
      Aidp::WorkstreamExecutor.new(
        project_dir: options[:project_dir] || Dir.pwd,
        max_concurrent: options[:max_concurrent] || 3
      )
    end

    def native_watch_runner(issues_url, interval, options)
      Aidp::Watch::Runner.new(
        issues_url: issues_url,
        interval: interval,
        **options
      )
    end

    def native_background_runner
      @native_background_runner ||= Aidp::Jobs::BackgroundRunner.new(Dir.pwd)
    end
  end
end
```

---

## 7. Worker Management

### 7.1 Worker Manager

```ruby
# lib/aidp/temporal/workers/worker_manager.rb
module Aidp
  module Temporal
    module Workers
      class WorkerManager
        def initialize(config)
          @config = config
          @workers = {}
        end

        def start_all
          start_work_loop_worker
          start_watch_mode_worker
        end

        def start_work_loop_worker
          @workers[:work_loop] = create_worker(
            task_queue: "aidp-work-loop",
            workflows: [
              Workflows::WorkLoopWorkflow,
              Workflows::WorkstreamOrchestratorWorkflow,
              Workflows::WorkstreamChildWorkflow
            ],
            activities: [
              Activities::ExecuteAgentActivity,
              Activities::RunTestsActivity,
              Activities::RunLinterActivity,
              Activities::CreatePromptActivity,
              Activities::PrepareNextIterationActivity,
              Activities::CreateWorktreeActivity
            ]
          )
          @workers[:work_loop].run_async
        end

        def start_watch_mode_worker
          @workers[:watch_mode] = create_worker(
            task_queue: "aidp-watch-mode",
            workflows: [
              Workflows::WatchModeWorkflow,
              Workflows::PlanProcessorWorkflow,
              Workflows::BuildProcessorWorkflow,
              Workflows::ReviewProcessorWorkflow,
              Workflows::CiFixProcessorWorkflow
            ],
            activities: [
              Activities::CollectWorkItemsActivity,
              Activities::GitHubApiActivity,
              Activities::WorktreeCleanupActivity,
              Activities::ExecuteAgentActivity,
              Activities::RunTestsActivity
            ]
          )
          @workers[:watch_mode].run_async
        end

        def stop_all
          @workers.each_value(&:shutdown)
        end

        def status
          @workers.transform_values do |worker|
            {
              running: worker.running?,
              task_queue: worker.task_queue
            }
          end
        end

        private

        def create_worker(task_queue:, workflows:, activities:)
          connection = Connection.new(@config)

          Temporalio::Worker.new(
            client: connection.connect,
            task_queue: task_queue,
            workflows: workflows,
            activities: activities
          )
        end
      end
    end
  end
end
```

---

## 8. CLI Integration

### 8.1 Updated Execute Command

```ruby
# In lib/aidp/cli.rb (modified)
class CLI < Thor
  desc "execute", "Execute work loop"
  option :temporal, type: :boolean, default: false, desc: "Use Temporal orchestration"
  def execute
    router = Aidp::OrchestrationRouter.new(load_config)

    # Override engine if --temporal flag provided
    router.engine = "temporal" if options[:temporal]

    result = router.execute_work_loop(
      step_name,
      step_spec,
      context
    )

    display_result(result)
  end

  desc "jobs", "Manage background jobs"
  def jobs(subcommand = "list")
    router = Aidp::OrchestrationRouter.new(load_config)

    case subcommand
    when "list"
      jobs = router.list_jobs
      display_jobs(jobs)
    when "status"
      status = router.job_status(options[:job_id])
      display_job_status(status)
    when "stop"
      result = router.stop_job(options[:job_id])
      display_result(result)
    end
  end

  desc "worker", "Manage Temporal workers"
  def worker(subcommand = "start")
    require_temporal!

    manager = Aidp::Temporal::Workers::WorkerManager.new(load_config)

    case subcommand
    when "start"
      manager.start_all
      prompt.say("Workers started. Press Ctrl+C to stop.")
      sleep
    when "status"
      display_worker_status(manager.status)
    end
  rescue Interrupt
    manager.stop_all
    prompt.say("Workers stopped.")
  end

  private

  def require_temporal!
    unless router.temporal?
      raise "Temporal not enabled. Set orchestration.engine to 'temporal' in config."
    end
  end
end
```

---

## 9. Configuration Schema

```yaml
# aidp.yml
orchestration:
  engine: native  # or "temporal"

  temporal:
    address: "localhost:7233"
    namespace: "aidp"

    task_queues:
      work_loop: "aidp-work-loop"
      watch_mode: "aidp-watch-mode"
      analysis: "aidp-analysis"

    timeouts:
      activity_start_to_close: 600      # 10 minutes
      activity_heartbeat: 60            # 1 minute
      workflow_execution: 86400         # 24 hours

    retry:
      agent:
        initial_interval: 2
        backoff_coefficient: 2.0
        maximum_interval: 60
        maximum_attempts: 3
      default:
        initial_interval: 1
        backoff_coefficient: 2.0
        maximum_interval: 30
        maximum_attempts: 3

    worker:
      max_concurrent_activities: 10
      max_concurrent_workflows: 5
```

---

## 10. Testing Support

```ruby
# spec/support/temporal_helpers.rb
module TemporalHelpers
  def with_temporal_test_env
    env = Temporalio::Testing::WorkflowEnvironment.new
    yield env
  ensure
    env.shutdown
  end

  def start_test_workflow(env, workflow_class, *args)
    env.run_workflow(workflow_class, *args)
  end

  def mock_activity(activity_class, return_value)
    allow_any_instance_of(activity_class)
      .to receive(:execute)
      .and_return(return_value)
  end
end

RSpec.configure do |config|
  config.include TemporalHelpers, temporal: true
end
```
