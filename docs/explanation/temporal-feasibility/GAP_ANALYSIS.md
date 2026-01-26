# Temporal Feasibility Study: Gap Analysis for Multi-Agent Orchestration

This document identifies gaps in Aidp's current implementation that must be addressed to achieve fully durable multi-agent orchestration where parallel agents work on atomic units that combine into feature-complete PRs.

---

## 1. Vision: The Promised Land

### 1.1 Target Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                  Feature Orchestrator                            │
│  "Implement user authentication with OAuth2"                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │ Decompose Feature │
                    │ into Atomic Units │
                    └─────────┬─────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│ Agent A       │    │ Agent B       │    │ Agent C       │
│ "OAuth config"│    │ "Login flow"  │    │ "Session mgmt"│
│               │    │               │    │               │
│ ✓ Implement   │    │ ✓ Implement   │    │ ✓ Implement   │
│ ✓ Test        │    │ ✓ Test        │    │ ✓ Test        │
│ ✓ Commit      │    │ ✓ Commit      │    │ ✓ Commit      │
└───────────────┘    └───────────────┘    └───────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │  Merge & Combine  │
                    │  All Atomic PRs   │
                    └─────────┬─────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │ Feature-Complete PR │
                    │ Ready for Review    │
                    └─────────────────────┘
```

### 1.2 Required Capabilities

| Capability | Description |
| ---------- | ----------- |
| **Durable Orchestration** | Survive crashes, resume from exact point |
| **Hierarchical Workflows** | Parent coordinates N children |
| **Parallel Execution** | Run many agents concurrently |
| **Failure Isolation** | One agent fails, others continue |
| **Partial Retry** | Retry only failed agents |
| **Progress Visibility** | See all agents in real-time |
| **Result Aggregation** | Intelligently combine agent outputs |
| **Dependency Management** | Task A before Task B |
| **Resource Coordination** | Limit concurrent heavy tasks |
| **Inter-Agent Communication** | Share artifacts between agents |

---

## 2. Current State Analysis

### 2.1 What Exists Today

| Component | Current Implementation | Limitations |
| --------- | ---------------------- | ----------- |
| **Parallel Execution** | `WorkstreamExecutor` with fork() | No crash recovery; manual aggregation |
| **Hierarchical Issues** | Parent/sub-issue in StateStore | Only 2 levels; no ordering |
| **State Sharing** | YAML files + GitHub | Polling-based; no real-time |
| **Result Aggregation** | Exit code collection | No intelligent merging |
| **Dependencies** | Implicit via labels | No explicit task graph |
| **Retry Logic** | Per-activity in Backoff | No workflow-level retry |

### 2.2 Current Orchestration Flow

```text
# Current: WorkstreamExecutor (workstream_executor.rb)
def execute_parallel(slugs, options = {})
  pool = Concurrent::FixedThreadPool.new(@max_concurrent)

  futures = slugs.map do |slug|
    Concurrent::Future.execute(executor: pool) do
      pid = fork { execute_in_worktree(slug) }
      Process.wait2(pid)
    end
  end

  results = futures.map(&:value)  # Wait for ALL
  display_execution_summary(results)
  results
end
```

**Problems:**

- If orchestrator crashes, no way to know which agents completed
- If 5 of 50 fail, must restart everything or manually track
- No visibility during execution
- No partial retry capability

---

## 3. Gap Analysis

### Gap 1: No Durable Orchestrator State

**Current State:**

- Orchestrator is a Ruby process with in-memory state
- Workstream states in separate files
- No single source of truth

**Problem:**

```text
Orchestrator starts 20 agents
     ↓
Agent 1-10 complete
     ↓
CRASH! (OOM, network, power)
     ↓
??? Which agents completed ???
??? How do we resume ???
```

**Required:**

- Orchestrator state survives crashes
- Know exactly which children completed
- Resume from exact point of failure

**Temporal Solution:**

```ruby
# Workflow state is automatically persisted
class FeatureOrchestrationWorkflow < Temporal::Workflow
  def execute(units)
    @completed = []

    units.each do |unit|
      result = workflow.execute_child_workflow(AtomicUnitWorkflow, unit)
      @completed << unit.id  # Persisted automatically
    end
  end
end
# After crash: workflow resumes with @completed intact
```

---

### Gap 2: No Task Graph / DAG Support

**Current State:**

- Linear state machine per work loop
- Hierarchical issues are flat (parent → children)
- No way to express complex dependencies

**Problem:**

```text
Cannot express:
  Task A ──┐
           ├──→ Task C ──→ Task E
  Task B ──┘              ↗
                         /
  Task D ───────────────┘
```

**Required:**

- Explicit dependency declaration
- Parallel execution of independent tasks
- Sequential execution of dependent tasks
- Dynamic task graph modification

**Temporal Solution:**

```ruby
class FeatureWorkflow < Temporal::Workflow
  def execute(feature)
    # Phase 1: Parallel independent tasks
    results_ab = workflow.execute_child_workflows_parallel([
      [TaskAWorkflow, { task: "oauth_config" }],
      [TaskBWorkflow, { task: "login_flow" }]
    ])

    # Phase 2: C depends on A and B
    result_c = workflow.execute_child_workflow(TaskCWorkflow, {
      task: "session_mgmt",
      inputs: results_ab  # Pass results from A and B
    })

    # Phase 3: D runs independently
    result_d = workflow.execute_child_workflow(TaskDWorkflow, { task: "tests" })

    # Phase 4: E depends on C and D
    workflow.execute_child_workflow(TaskEWorkflow, {
      task: "integration",
      inputs: [result_c, result_d]
    })
  end
end
```

---

### Gap 3: No Failure Isolation with Partial Retry

**Current State:**

- One agent fails → entire WorkstreamExecutor continues
- No way to retry just the failed agent
- Manual intervention required

**Problem:**

```text
Run 50 agents
     ↓
Agent 23 fails (API rate limit)
Agent 47 fails (network timeout)
     ↓
Options:
  A) Restart all 50 (wasteful)
  B) Manually track and retry 2 (tedious)
  C) Ignore failures (incomplete feature)
```

**Required:**

- Automatic retry of failed agents
- Configurable retry policies per agent type
- Continue-on-failure with aggregated error report
- Manual retry trigger for specific agents

**Temporal Solution:**

```ruby
class FeatureOrchestrationWorkflow < Temporal::Workflow
  def execute(units)
    # Start all children
    handles = units.map do |unit|
      workflow.start_child_workflow(
        AtomicUnitWorkflow,
        unit,
        retry_policy: unit_retry_policy(unit)
      )
    end

    # Collect results with failure isolation
    results = handles.map do |handle|
      begin
        { status: :completed, result: handle.result }
      rescue Temporal::ChildWorkflowFailure => e
        { status: :failed, error: e.message, workflow_id: handle.workflow_id }
      end
    end

    # Retry failed ones
    failed = results.select { |r| r[:status] == :failed }
    if failed.any? && @retry_count < 3
      @retry_count += 1
      retry_results = retry_failed(failed)
      results = merge_results(results, retry_results)
    end

    results
  end
end
```

---

### Gap 4: No Real-Time Progress Visibility

**Current State:**

- Per-workstream log files
- File-based state updated periodically
- No unified view of all agents

**Problem:**

```text
$ aidp workstreams status
# Shows: slug, status (active/completed/failed)
# Missing: progress %, current step, ETA, errors
```

**Required:**

- Real-time status of all agents
- Progress percentage per agent
- Current step/iteration
- Estimated completion time
- Error details without digging through logs

**Temporal Solution:**

```ruby
# Query handler in orchestrator workflow
workflow.query_handler("orchestration_status") do
  {
    total_units: @units.size,
    completed: @completed.size,
    in_progress: @in_progress.size,
    failed: @failed.size,
    progress_percent: (@completed.size.to_f / @units.size * 100).round,
    unit_details: @units.map do |unit|
      {
        id: unit.id,
        status: unit_status(unit),
        progress: unit_progress(unit),
        current_step: unit_current_step(unit),
        started_at: unit.started_at,
        estimated_completion: estimate_completion(unit)
      }
    end,
    estimated_total_completion: estimate_total_completion
  }
end

# Web UI shows this in real-time
```

---

### Gap 5: No Result Aggregation Framework

**Current State:**

- WorkstreamExecutor collects exit codes
- HierarchicalPrStrategy checks all sub-PRs merged
- No composable aggregation logic

**Problem:**

```text
Agent A produces: PR with OAuth config changes
Agent B produces: PR with login flow changes
Agent C produces: PR with session management changes

How to combine into single feature PR?
- Merge commits? Rebase? Squash?
- Resolve conflicts?
- Combine PR descriptions?
- Aggregate test results?
```

**Required:**

- Configurable merge strategies
- Conflict detection and resolution
- Combined PR description generation
- Aggregated test/lint results
- Dependency-aware merge ordering

**Temporal Solution:**

```ruby
class MergeAtomicUnitsWorkflow < Temporal::Workflow
  def execute(unit_results, target_branch:)
    # Sort by dependency order
    ordered = topological_sort(unit_results)

    # Sequential merge to handle conflicts
    ordered.each do |unit|
      workflow.execute_activity(
        MergeBranchActivity,
        source: unit.branch,
        target: target_branch,
        strategy: determine_merge_strategy(unit)
      )
    end

    # Generate combined PR
    workflow.execute_activity(
      CreateFeaturePrActivity,
      branch: target_branch,
      description: aggregate_descriptions(unit_results),
      test_results: aggregate_test_results(unit_results)
    )
  end
end
```

---

### Gap 6: No Inter-Agent Communication

**Current State:**

- Agents work in isolation
- Share data only via GitHub (comments, branches)
- No artifact passing between agents

**Problem:**

```text
Agent A: Generates API schema
Agent B: Needs schema to implement client
Agent C: Needs schema to implement server

Currently: B and C must regenerate or hard-code schema
Required: A produces artifact, B and C consume it
```

**Required:**

- Artifact storage during orchestration
- Input/output declarations per agent
- Artifact dependency resolution
- Caching for repeated access

**Temporal Solution:**

```ruby
class FeatureWorkflow < Temporal::Workflow
  def execute(feature)
    # Agent A produces artifact
    schema_result = workflow.execute_child_workflow(
      SchemaGeneratorWorkflow,
      feature: feature
    )

    # Agent B and C consume artifact in parallel
    workflow.execute_child_workflows_parallel([
      [ClientImplementationWorkflow, {
        feature: feature,
        schema: schema_result[:schema]  # Pass artifact
      }],
      [ServerImplementationWorkflow, {
        feature: feature,
        schema: schema_result[:schema]  # Same artifact
      }]
    ])
  end
end
```

---

### Gap 7: No Workflow Definition Language

**Current State:**

- Workflows hardcoded in Ruby
- Changing orchestration requires code changes
- No declarative specification

**Problem:**

```text
User wants: "Run 3 agents in parallel, then merge"
Currently: Must modify workstream_executor.rb
Required: Declarative config that users can customize
```

**Required:**

```yaml
# Declarative workflow spec
workflow:
  name: "Feature Implementation"

  stages:
    - name: decompose
      type: single
      processor: plan_decomposer
      outputs: [atomic_units]

    - name: implement
      type: parallel
      foreach: atomic_units
      processor: work_loop
      max_concurrent: 5
      retry_policy:
        max_attempts: 3
        backoff: exponential
      outputs: [unit_results]

    - name: merge
      type: single
      processor: pr_merger
      depends_on: [implement]
      inputs: [unit_results]
      merge_strategy: sequential_rebase

    - name: finalize
      type: single
      processor: feature_pr_creator
      depends_on: [merge]
```

**Temporal Solution:**
Temporal provides the runtime; we build the DSL:

```ruby
class WorkflowDslInterpreter
  def execute(workflow_spec)
    stages = workflow_spec[:stages]
    context = {}

    stages.each do |stage|
      case stage[:type]
      when "single"
        context[stage[:name]] = execute_single(stage, context)
      when "parallel"
        context[stage[:name]] = execute_parallel(stage, context)
      end
    end

    context
  end

  def execute_parallel(stage, context)
    items = context[stage[:foreach]]

    handles = items.map do |item|
      workflow.start_child_workflow(
        processor_to_workflow(stage[:processor]),
        item: item,
        inputs: resolve_inputs(stage[:inputs], context)
      )
    end

    handles.map(&:result)
  end
end
```

---

### Gap 8: No Resource Coordination

**Current State:**

- Fixed `max_concurrent` in WorkstreamExecutor
- No per-task resource limits
- No priority-based scheduling

**Problem:**

```text
Have: 50 atomic units to process
  - 10 are lightweight (schema generation)
  - 30 are medium (code implementation)
  - 10 are heavyweight (integration tests)

Currently: All get same concurrency slot
Required: Lightweight runs 10 concurrent, heavyweight runs 2
```

**Required:**

- Task weight/resource classification
- Multiple worker pools
- Priority queues
- Dynamic concurrency adjustment

**Temporal Solution:**

```ruby
# Different task queues for different resource needs
TASK_QUEUES = {
  lightweight: "aidp-lightweight",    # 10 workers
  standard: "aidp-standard",          # 5 workers
  heavyweight: "aidp-heavyweight"     # 2 workers
}

class AtomicUnitWorkflow < Temporal::Workflow
  def execute(unit)
    task_queue = classify_task_queue(unit)

    workflow.execute_activity(
      ExecuteAgentActivity,
      unit: unit,
      task_queue: task_queue  # Route to appropriate pool
    )
  end
end
```

---

### Gap 9: No Workflow-Level Checkpointing

**Current State:**

- Per-work-loop checkpoints (every 5 iterations)
- Workstream state separate
- No full workflow snapshot

**Problem:**

```text
Workflow running for 6 hours
  - 40 of 50 agents complete
  - User needs to stop for maintenance

Currently: Stop → lose orchestrator state → manual recovery
Required: Checkpoint entire workflow → resume later
```

**Required:**

- Save complete workflow state
- Resume from checkpoint
- List checkpoints
- Rollback to previous checkpoint

**Temporal Solution:**

```ruby
# Temporal handles this automatically via Event History
# Every state change is recorded
# Resume is automatic after crash

# For manual pause/resume:
workflow.signal_handler("pause") do
  @paused = true
  # State is automatically checkpointed
end

workflow.signal_handler("resume") do
  @paused = false
end

# In workflow loop:
workflow.wait_condition { !@paused }
```

---

### Gap 10: No Conflict Resolution Strategy

**Current State:**

- Workstreams modify files independently
- Git handles conflicts at merge time
- No preventive measures

**Problem:**

```text
Agent A: Modifies src/auth.rb
Agent B: Also modifies src/auth.rb
Agent C: Modifies src/session.rb (independent)

Currently: A and B will have merge conflict
Required: Orchestrator knows A and B conflict, runs sequentially
```

**Required:**

- File-level conflict detection before execution
- Automatic grouping of conflicting tasks
- Sequential execution for conflicts
- Parallel execution for independent tasks

**Temporal Solution:**

```ruby
class ConflictAwareOrchestrationWorkflow < Temporal::Workflow
  def execute(units)
    # Analyze potential conflicts
    conflict_groups = workflow.execute_activity(
      AnalyzeConflictsActivity,
      units: units
    )

    # Execute conflict groups sequentially
    # Execute independent groups in parallel
    conflict_groups.each do |group|
      if group[:independent]
        # Parallel execution
        workflow.execute_child_workflows_parallel(
          group[:units].map { |u| [AtomicUnitWorkflow, u] }
        )
      else
        # Sequential execution
        group[:units].each do |unit|
          workflow.execute_child_workflow(AtomicUnitWorkflow, unit)
        end
      end
    end
  end
end
```

---

## 4. Gap Severity Assessment

| Gap | Severity | Impact on Multi-Agent | Temporal Addresses? |
| --- | -------- | --------------------- | ------------------- |
| No Durable Orchestrator | **Critical** | Cannot scale beyond ~10 agents | Yes - Event History |
| No Task Graph/DAG | **High** | Cannot express complex dependencies | Yes - Child Workflows |
| No Failure Isolation | **High** | Single failure wastes all work | Yes - Per-child retry |
| No Progress Visibility | **Medium** | Poor UX at scale | Yes - Queries + Web UI |
| No Result Aggregation | **High** | Manual merge coordination | Partial - needs custom logic |
| No Inter-Agent Communication | **Medium** | Duplicate work | Yes - Workflow data passing |
| No Workflow DSL | **Low** | Requires code changes | Partial - we build DSL |
| No Resource Coordination | **Medium** | Inefficient at scale | Yes - Task Queues |
| No Workflow Checkpointing | **High** | Cannot pause/resume | Yes - Automatic |
| No Conflict Resolution | **Medium** | Merge conflicts | Partial - needs custom logic |

---

## 5. Implementation Roadmap

### Phase 1: Foundation (Addresses Critical Gaps)

1. **Durable Orchestrator State** via Temporal Workflows
2. **Child Workflow Pattern** for agent execution
3. **Basic Progress Queries** for visibility

### Phase 2: Parallelism (Addresses High Gaps)

1. **Parallel Child Execution** with configurable concurrency
2. **Failure Isolation** with per-child retry policies
3. **Result Collection** with aggregation helpers

### Phase 3: Intelligence (Addresses Medium Gaps)

1. **Conflict Analysis Activity** for smart scheduling
2. **Inter-Agent Artifact Passing** via workflow inputs/outputs
3. **Resource-Based Task Queues** for load balancing

### Phase 4: Polish (Addresses Low Gaps)

1. **Workflow DSL** for declarative specifications
2. **Advanced Merge Strategies** for PR combination
3. **Comprehensive Dashboard** for orchestration status

---

## 6. What We Must Build (Beyond Temporal)

Temporal provides the durable execution foundation, but we still need:

| Component | Description | Effort |
| --------- | ----------- | ------ |
| `FeatureDecomposer` | AI-powered feature → atomic units | Medium |
| `ConflictAnalyzer` | Detect file-level conflicts between units | Medium |
| `MergeOrchestrator` | Dependency-aware sequential merge | High |
| `ArtifactStore` | Storage for inter-agent artifacts | Low |
| `ProgressAggregator` | Combine child workflow statuses | Low |
| `WorkflowDSL` | Declarative workflow specification | High |
| `DashboardUI` | Visual orchestration status | Medium |

---

## 7. Conclusion

Aidp's current implementation has significant gaps for multi-agent orchestration:

- **Critical**: No durable orchestrator state
- **High**: No task graph, failure isolation, checkpointing
- **Medium**: No progress visibility, inter-agent communication, conflict resolution

**Temporal.io directly addresses the critical and most high-severity gaps**, providing:

- Durable workflow state via Event History
- Hierarchical execution via Child Workflows
- Failure isolation via per-workflow retry
- Progress visibility via Queries and Web UI
- Automatic checkpointing via deterministic replay

**Custom work required** for:

- Intelligent feature decomposition
- Merge conflict analysis
- Result aggregation strategies
- Workflow DSL
- Dashboard UI

**Recommendation**: Temporal migration is **strongly recommended** for the multi-agent direction. The alternative (building these capabilities natively) would require rebuilding most of what Temporal provides.
