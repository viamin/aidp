# Temporal Feasibility Study: Workflow Mapping

This document provides a detailed mapping from Aidp's current orchestration concepts to Temporal.io primitives.

---

## 1. Concept Mapping Overview

| Aidp Concept | Temporal Primitive | Notes |
|--------------|-------------------|-------|
| Work Loop | Workflow | State machine becomes durable workflow |
| Iteration | Workflow loop iteration | Each cycle is persisted |
| Agent Execution | Activity | Non-deterministic LLM calls |
| Test/Lint Execution | Activity | Subprocess execution |
| Checkpoint | Event History | Automatic; replaces manual checkpointing |
| Async Work Loop | Workflow + Signals | Control via Signals |
| Background Job | Async Workflow Start | Start without waiting |
| Workstream | Child Workflow | Parallel execution |
| Watch Mode Cycle | Scheduled Workflow | Cron-based trigger |
| Instruction Queue | Signal | Inject via Signal handlers |
| Guard Policy | Workflow State | Managed within workflow |
| Provider Failover | Activity Retry | Automatic with custom policies |

---

## 2. Workflow Definitions

### 2.1 WorkLoopWorkflow

**Current Aidp Code** (`work_loop_runner.rb`):
```ruby
def execute_step(step_name, step_spec, context = {})
  @iteration_count = 0
  create_initial_prompt(step_spec, context)

  loop do
    @iteration_count += 1
    break if @iteration_count > MAX_ITERATIONS

    agent_result = apply_patch(provider, model)
    all_results = run_phase_based_commands(agent_result)

    if all_checks_pass && agent_marked_complete?(agent_result)
      return build_success_result(agent_result)
    end

    prepare_next_iteration(all_results, diagnostic)
  end
end
```

**Temporal Workflow**:
```ruby
class WorkLoopWorkflow < Temporal::Workflow
  MAX_ITERATIONS = 50

  def execute(step_name, step_spec, context)
    @iteration = 0
    @state = :ready
    @paused = false
    @instructions = []

    # Create initial prompt via Activity
    workflow.execute_activity(
      CreatePromptActivity,
      step_spec: step_spec,
      context: context
    )

    while @iteration < MAX_ITERATIONS
      # Check for pause signal
      workflow.wait_condition { !@paused }

      # Check for cancel signal
      break if @cancelled

      @iteration += 1
      transition_to(:apply_patch)

      # Execute agent (Activity - non-deterministic)
      agent_result = workflow.execute_activity(
        ExecuteAgentActivity,
        prompt: read_prompt,
        provider: select_provider,
        model: select_model,
        start_to_close_timeout: 600,
        retry_policy: agent_retry_policy
      )

      transition_to(:test)

      # Run tests and linters (Activities)
      test_results = workflow.execute_activity(
        RunTestsActivity,
        project_dir: @project_dir,
        config: @test_config
      )

      lint_results = workflow.execute_activity(
        RunLinterActivity,
        project_dir: @project_dir,
        config: @lint_config
      )

      all_pass = test_results[:success] && lint_results[:success]

      if all_pass && agent_result[:completed]
        transition_to(:done)
        return build_success_result(agent_result)
      end

      # Prepare next iteration
      transition_to(:diagnose) unless all_pass
      workflow.execute_activity(
        PrepareNextIterationActivity,
        results: { tests: test_results, lint: lint_results },
        agent_result: agent_result
      )

      transition_to(:ready)
    end

    build_max_iterations_result
  end

  # Signal Handlers
  workflow.signal_handler("pause") do
    @paused = true
  end

  workflow.signal_handler("resume") do
    @paused = false
  end

  workflow.signal_handler("cancel") do
    @cancelled = true
    @paused = false  # Unblock if paused
  end

  workflow.signal_handler("inject_instruction") do |instruction|
    @instructions << instruction
  end

  # Query Handlers
  workflow.query_handler("status") do
    {
      iteration: @iteration,
      state: @state,
      paused: @paused,
      pending_instructions: @instructions.size
    }
  end

  private

  def transition_to(new_state)
    @state = new_state
  end

  def agent_retry_policy
    Temporal::RetryPolicy.new(
      initial_interval: 1,
      backoff_coefficient: 2.0,
      maximum_interval: 30,
      maximum_attempts: 3,
      non_retryable_errors: ['ConfigurationError', 'SecurityViolation']
    )
  end
end
```

### 2.2 AsyncWorkLoopWorkflow (Replaces AsyncWorkLoopRunner)

**Current Aidp Code** (`async_work_loop_runner.rb`):
```ruby
def execute_step_async(step_name, step_spec, context = {})
  @work_thread = Thread.new { run_async_loop }
  { status: "started", state: @state.summary }
end

def pause
  @state.pause!
end

def cancel(save_checkpoint: true)
  @state.cancel!
  @work_thread&.join(@cancel_timeout)
end
```

**Temporal Approach**:
The async pattern is inherently supported by Temporal. Start the workflow without waiting:

```ruby
class AidpClient
  def start_work_loop_async(step_name, step_spec, context)
    # Start workflow without waiting for result
    run_id = @client.start_workflow(
      WorkLoopWorkflow,
      step_name, step_spec, context,
      id: generate_workflow_id(step_name),
      task_queue: 'aidp-work-loop'
    )

    { status: "started", workflow_id: run_id }
  end

  def pause_work_loop(workflow_id)
    @client.signal_workflow(workflow_id, "pause")
  end

  def resume_work_loop(workflow_id)
    @client.signal_workflow(workflow_id, "resume")
  end

  def cancel_work_loop(workflow_id)
    @client.signal_workflow(workflow_id, "cancel")
  end

  def get_status(workflow_id)
    @client.query_workflow(workflow_id, "status")
  end
end
```

### 2.3 WorkstreamWorkflow (Replaces WorkstreamExecutor)

**Current Aidp Code** (`workstream_executor.rb`):
```ruby
def execute_parallel(slugs, options = {})
  pool = Concurrent::FixedThreadPool.new(@max_concurrent)

  futures = slugs.map do |slug|
    Concurrent::Future.execute(executor: pool) do
      execute_workstream(slug, options)
    end
  end

  results = futures.map(&:value)
  pool.shutdown
  results
end
```

**Temporal Workflow with Child Workflows**:
```ruby
class WorkstreamOrchestratorWorkflow < Temporal::Workflow
  def execute(slugs, options)
    # Start all child workflows
    child_handles = slugs.map do |slug|
      workflow.execute_child_workflow(
        WorkstreamChildWorkflow,
        slug: slug,
        options: options,
        parent_close_policy: :terminate,  # Terminate children if parent fails
        id: "workstream-#{slug}-#{workflow.info.run_id}"
      )
    end

    # Wait for all to complete (fan-in)
    results = child_handles.map do |handle|
      begin
        handle.result
      rescue Temporal::ChildWorkflowFailure => e
        { slug: e.workflow_id, status: "failed", error: e.message }
      end
    end

    build_execution_summary(results)
  end
end

class WorkstreamChildWorkflow < Temporal::Workflow
  def execute(slug:, options:)
    started_at = workflow.now

    # Create worktree (Activity)
    worktree = workflow.execute_activity(
      CreateWorktreeActivity,
      slug: slug,
      project_dir: options[:project_dir]
    )

    # Execute work loop in worktree
    result = workflow.execute_child_workflow(
      WorkLoopWorkflow,
      step_name: options[:step_name],
      step_spec: options[:step_spec],
      context: options[:context].merge(worktree_path: worktree[:path])
    )

    completed_at = workflow.now

    {
      slug: slug,
      status: result[:status],
      duration: completed_at - started_at,
      result: result
    }
  end
end
```

### 2.4 WatchModeWorkflow (Replaces Watch::Runner)

**Current Aidp Code** (`watch/runner.rb`):
```ruby
def start
  loop do
    process_cycle
    break if @once
    sleep @interval
  end
end
```

**Temporal Workflow with Continue-As-New**:
```ruby
class WatchModeWorkflow < Temporal::Workflow
  # Event History limit mitigation
  MAX_CYCLES_PER_RUN = 100

  def execute(issues_url:, interval:, cycle_count: 0)
    owner, repo = parse_issues_url(issues_url)

    loop do
      # Check if we need to Continue-As-New
      if cycle_count >= MAX_CYCLES_PER_RUN
        workflow.continue_as_new(
          issues_url: issues_url,
          interval: interval,
          cycle_count: 0
        )
        return  # Won't reach here
      end

      # Process one cycle
      work_items = workflow.execute_activity(
        CollectWorkItemsActivity,
        owner: owner,
        repo: repo
      )

      # Process items via child workflows
      work_items.each do |item|
        case item[:processor_type]
        when :plan
          workflow.execute_child_workflow(PlanProcessorWorkflow, item: item)
        when :build
          workflow.execute_child_workflow(BuildProcessorWorkflow, item: item)
        when :review
          workflow.execute_child_workflow(ReviewProcessorWorkflow, item: item)
        when :ci_fix
          workflow.execute_child_workflow(CiFixProcessorWorkflow, item: item)
        end
      end

      # Maintenance tasks
      workflow.execute_activity(WorktreeCleanupActivity)
      workflow.execute_activity(WorktreeReconciliationActivity)

      cycle_count += 1

      # Sleep for interval
      workflow.sleep(interval)
    end
  end
end

# Alternative: Use Temporal Schedules for cron-based polling
class WatchModeCycleWorkflow < Temporal::Workflow
  def execute(issues_url:)
    # Execute single cycle
    owner, repo = parse_issues_url(issues_url)

    work_items = workflow.execute_activity(CollectWorkItemsActivity, owner: owner, repo: repo)

    work_items.each do |item|
      process_work_item(item)
    end

    { processed: work_items.size }
  end
end

# Schedule configuration
schedule = Temporal::Schedule.new(
  id: "aidp-watch-mode",
  spec: Temporal::ScheduleSpec.new(
    interval: [Temporal::ScheduleIntervalSpec.new(every: 30)]  # Every 30 seconds
  ),
  action: Temporal::ScheduleWorkflowAction.new(
    workflow: WatchModeCycleWorkflow,
    args: [{ issues_url: "https://github.com/owner/repo/issues" }],
    task_queue: "aidp-watch-mode"
  )
)
```

### 2.5 BackgroundJobWorkflow (Replaces BackgroundRunner)

**Current Aidp Code** (`jobs/background_runner.rb`):
```ruby
def start(mode, options = {})
  job_id = generate_job_id

  pid = fork do
    Process.daemon(true)
    runner = Aidp::Harness::Runner.new(@project_dir, mode, options)
    result = runner.run
    mark_job_completed(job_id, result)
  end

  Process.detach(pid)
  job_id
end
```

**Temporal Approach**:
No separate "background" workflow needed. All Temporal workflows run asynchronously:

```ruby
class AidpJobManager
  def start_background_job(mode, options)
    workflow_id = "aidp-job-#{SecureRandom.hex(8)}"

    @client.start_workflow(
      determine_workflow_class(mode),
      options,
      id: workflow_id,
      task_queue: determine_task_queue(mode)
    )

    workflow_id  # Return workflow ID as job ID
  end

  def list_jobs
    @client.list_workflows(
      query: 'WorkflowType LIKE "Aidp%"'
    ).map do |info|
      {
        job_id: info.workflow_id,
        status: info.status,
        started_at: info.start_time,
        mode: extract_mode(info.workflow_type)
      }
    end
  end

  def job_status(workflow_id)
    info = @client.describe_workflow(workflow_id)
    {
      job_id: workflow_id,
      status: info.status,
      running: info.status == :running,
      started_at: info.start_time,
      completed_at: info.close_time
    }
  end

  def stop_job(workflow_id)
    @client.cancel_workflow(workflow_id)
    { success: true }
  rescue Temporal::WorkflowNotFoundError
    { success: false, message: "Job not found" }
  end
end
```

---

## 3. Activity Definitions

### 3.1 ExecuteAgentActivity

Encapsulates non-deterministic LLM/agent CLI execution:

```ruby
class ExecuteAgentActivity < Temporal::Activity
  def execute(prompt:, provider:, model:, options: {})
    activity.heartbeat("Starting agent execution")

    # Build command based on provider
    command = build_agent_command(provider, model, prompt, options)

    # Execute with output capture
    output = ""
    status = nil

    Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
      stdin.close

      # Heartbeat while reading output
      threads = []
      threads << Thread.new do
        stdout.each_line do |line|
          output << line
          activity.heartbeat("Processing output...")
        end
      end
      threads << Thread.new do
        stderr.each_line { |line| output << line }
      end

      threads.each(&:join)
      status = wait_thr.value
    end

    {
      status: status.success? ? "completed" : "failed",
      output: output,
      exit_code: status.exitstatus,
      completed: detect_completion_signal(output)
    }
  rescue => e
    raise Temporal::ActivityFailure.new(e.message)
  end

  private

  def build_agent_command(provider, model, prompt, options)
    case provider
    when "anthropic"
      "claude --model #{model} --prompt-file #{prompt}"
    when "cursor"
      "cursor --ai-prompt #{prompt}"
    when "aider"
      "aider --message-file #{prompt}"
    else
      raise "Unknown provider: #{provider}"
    end
  end
end
```

### 3.2 RunTestsActivity

```ruby
class RunTestsActivity < Temporal::Activity
  def execute(project_dir:, config:)
    activity.heartbeat("Running tests")

    Dir.chdir(project_dir) do
      output = `#{config[:test_command]} 2>&1`
      success = $?.success?

      {
        success: success,
        output: output,
        exit_code: $?.exitstatus
      }
    end
  end
end
```

### 3.3 RunLinterActivity

```ruby
class RunLinterActivity < Temporal::Activity
  def execute(project_dir:, config:)
    activity.heartbeat("Running linter")

    Dir.chdir(project_dir) do
      output = `#{config[:lint_command]} 2>&1`
      success = $?.success?

      {
        success: success,
        output: output,
        exit_code: $?.exitstatus
      }
    end
  end
end
```

### 3.4 GitHubApiActivity

```ruby
class GitHubApiActivity < Temporal::Activity
  def execute(method:, path:, params: {})
    client = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])

    result = case method
    when :get
      client.get(path, params)
    when :post
      client.post(path, params)
    when :patch
      client.patch(path, params)
    end

    { success: true, data: result }
  rescue Octokit::Error => e
    { success: false, error: e.message, status: e.response_status }
  end
end
```

### 3.5 CreateWorktreeActivity

```ruby
class CreateWorktreeActivity < Temporal::Activity
  def execute(slug:, project_dir:, branch: nil)
    worktree_path = File.join(project_dir, ".aidp", "workstreams", slug)
    branch ||= "workstream/#{slug}"

    # Create worktree
    system("git", "-C", project_dir, "worktree", "add", "-b", branch, worktree_path)

    {
      path: worktree_path,
      branch: branch,
      slug: slug
    }
  end
end
```

---

## 4. Signal Mapping

| Aidp Pattern | Temporal Signal | Handler |
|--------------|----------------|---------|
| `@state.pause!` | `pause` signal | Set `@paused = true` |
| `@state.resume!` | `resume` signal | Set `@paused = false` |
| `@state.cancel!` | `cancel` signal | Set `@cancelled = true` |
| `enqueue_instruction` | `inject_instruction` signal | Append to `@instructions` |
| `request_guard_update` | `update_guard` signal | Modify `@guard_config` |
| `request_config_reload` | `reload_config` signal | Set reload flag |

---

## 5. Query Mapping

| Aidp Pattern | Temporal Query | Returns |
|--------------|---------------|---------|
| `@state.summary` | `status` query | State, iteration, progress |
| `@instruction_queue.summary` | `pending_instructions` query | Queued count |
| `checkpoint.latest_checkpoint` | `checkpoint` query | Current metrics |
| `job_status` | `job_status` query | Running, completed, etc. |

---

## 6. Retry Policy Mapping

**Current Aidp Backoff** (`concurrency/backoff.rb`):
```ruby
Backoff.retry(
  max_attempts: 5,
  base: 0.5,
  max_delay: 30.0,
  jitter: 0.2,
  strategy: :exponential,
  on: [Net::ReadTimeout]
)
```

**Temporal Retry Policy**:
```ruby
retry_policy = Temporal::RetryPolicy.new(
  initial_interval: 0.5,              # base delay
  backoff_coefficient: 2.0,           # exponential factor
  maximum_interval: 30,               # max_delay
  maximum_attempts: 5,                # max_attempts
  non_retryable_errors: [             # Inverse of `on:`
    'ConfigurationError',
    'AuthenticationError'
  ]
)

workflow.execute_activity(
  SomeActivity,
  args,
  retry_policy: retry_policy
)
```

---

## 7. Timeout Mapping

| Aidp Timeout | Temporal Timeout | Usage |
|--------------|-----------------|-------|
| `Wait.until(timeout: 30)` | `start_to_close_timeout` | Activity execution time |
| `@cancel_timeout` (5s) | `heartbeat_timeout` | Activity liveness check |
| MAX_ITERATIONS * avg_time | `workflow_execution_timeout` | Total workflow time |
| Thread.join(timeout) | `schedule_to_close_timeout` | Queue wait + execution |

---

## 8. Error Handling Mapping

**Current Aidp Error Handler** (`harness/error_handler.rb`):
```ruby
case error_type
when :rate_limited
  { action: :switch_provider }
when :auth_expired
  { action: :switch_provider, crash_if_no_fallback: true }
when :transient
  { action: :switch_model }
when :permanent
  { action: :escalate }
end
```

**Temporal Error Handling**:
```ruby
class WorkLoopWorkflow < Temporal::Workflow
  def execute(...)
    begin
      agent_result = workflow.execute_activity(
        ExecuteAgentActivity,
        retry_policy: Temporal::RetryPolicy.new(
          maximum_attempts: 3,
          non_retryable_errors: ['AuthenticationError', 'ConfigurationError']
        )
      )
    rescue Temporal::ActivityFailure => e
      case classify_error(e)
      when :rate_limited
        # Switch provider and retry
        @provider = next_provider
        retry
      when :auth_expired
        raise Temporal::ApplicationError.new(
          "All providers failed authentication",
          type: "ConfigurationError",
          non_retryable: true
        )
      when :transient
        # Let Temporal's retry policy handle it
        raise
      when :permanent
        # Escalate - workflow fails
        raise Temporal::ApplicationError.new(
          e.message,
          type: "PermanentError",
          non_retryable: true
        )
      end
    end
  end
end
```

---

## 9. Summary Table

| Current Aidp | Temporal Primitive | Migration Complexity |
|--------------|-------------------|---------------------|
| `WorkLoopRunner` | Workflow | Medium |
| `AsyncWorkLoopRunner` | Workflow + Signals | Low |
| `WorkstreamExecutor` | Child Workflows | Medium |
| `Watch::Runner` | Scheduled Workflow | Medium |
| `BackgroundRunner` | Async Start + Queries | Low |
| `Concurrency::Backoff` | Retry Policy | Low |
| `Concurrency::Wait` | Activity w/ Heartbeat | Low |
| `Checkpoint` | Event History | Automatic |
| `ErrorHandler` | Retry Policy + Exceptions | Medium |
| `WorkLoopState` | Workflow State | Automatic |
| `InstructionQueue` | Signals | Low |
