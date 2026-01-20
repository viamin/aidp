# Temporal Feasibility Study: Architecture Report

## Executive Summary

This report evaluates whether Aidp should replace its native Ruby workflow orchestration code with Temporal.io workflows running in a self-hosted environment. After comprehensive analysis of Aidp's current architecture and Temporal's capabilities, we provide findings, recommendations, and a proposed new architecture.

**Recommendation: Conditionally Recommended**

Temporal adoption would provide significant benefits for durability, observability, and failure recovery, but the migration complexity and operational overhead must be weighed against Aidp's current scale and use cases.

---

## 1. Current Aidp Orchestration Architecture

### 1.1 Core Components

Aidp's orchestration is built on these foundational components:

| Component | Location | Responsibility |
|-----------|----------|----------------|
| `WorkLoopRunner` | `lib/aidp/execute/work_loop_runner.rb` | Fix-forward state machine for iterative AI execution |
| `AsyncWorkLoopRunner` | `lib/aidp/execute/async_work_loop_runner.rb` | Thread-based async execution with pause/resume/cancel |
| `BackgroundRunner` | `lib/aidp/jobs/background_runner.rb` | Daemonized process execution with PID tracking |
| `WorkstreamExecutor` | `lib/aidp/workstream_executor.rb` | Parallel execution via fork() and concurrent-ruby |
| `Watch::Runner` | `lib/aidp/watch/runner.rb` | Continuous GitHub monitoring with multiple processors |
| `Concurrency::Backoff` | `lib/aidp/concurrency/backoff.rb` | Retry logic with exponential backoff |
| `Concurrency::Wait` | `lib/aidp/concurrency/wait.rb` | Deterministic condition waiting with timeouts |

### 1.2 Workflow State Machine

The `WorkLoopRunner` implements a fix-forward state machine:

```
READY → APPLY_PATCH → TEST → {PASS → DONE | FAIL → DIAGNOSE → NEXT_PATCH} → READY
```

Key characteristics:
- Maximum 50 iterations safety limit
- Periodic checkpoints every 5 iterations
- Style guide reminder injection every 5 iterations
- No rollback - only forward progress through fixes

### 1.3 Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        User / CLI                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Harness::Runner                              │
│  (Central orchestration dispatcher for execution modes)          │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│ WorkLoopRunner│    │Watch::Runner  │    │BackgroundRunner│
│ (Sync/Async)  │    │(GitHub Auto)  │    │(Daemonized)   │
└───────────────┘    └───────────────┘    └───────────────┘
        │                     │                     │
        ▼                     ▼                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Provider Manager                             │
│  (Multi-provider AI orchestration: Claude, Copilot, etc.)       │
└─────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────┐
│                        External CLIs                             │
│  (claude, cursor, aider, gh copilot, etc.)                      │
└─────────────────────────────────────────────────────────────────┘
```

### 1.4 Concurrency Patterns

Aidp uses `concurrent-ruby` for all concurrency needs:

1. **Thread Pools**: Named executors (`:io_pool`, `:cpu_pool`, `:background`)
2. **Process Isolation**: `fork()` for true parallelism in workstreams
3. **Future Coordination**: `Concurrent::Promises` with `zip()` for fan-in
4. **Condition Polling**: `Wait.until` with monotonic clock timeouts
5. **Retry Logic**: `Backoff.retry` with exponential/linear/constant strategies

### 1.5 State Persistence

| State Type | Storage | Location |
|------------|---------|----------|
| Checkpoint | YAML | `.aidp/checkpoint.yml` |
| Checkpoint History | JSONL | `.aidp/checkpoint_history.jsonl` |
| Job Metadata | YAML | `.aidp/jobs/{job_id}/metadata.yml` |
| Workstream State | JSON | `.aidp/workstreams/{slug}/state.json` |
| Watch State | JSON | `.aidp/watch/state.json` |
| Worktree Registry | JSON | `.aidp/worktrees.json` |

---

## 2. Identified Pain Points

### 2.1 Durability Gaps

| Issue | Current State | Impact |
|-------|--------------|--------|
| **Process Crash Recovery** | Checkpoints saved every 5 iterations; manual restart required | Lost work if crash between checkpoints |
| **State Consistency** | File-based with atomic writes; no transactions | Potential corruption on partial writes |
| **Network Partition** | No built-in handling | Silent failures on GitHub API outages |
| **Worker Restart** | No automatic resumption | Manual intervention required |

### 2.2 Observability Limitations

- **No Unified History**: Event history scattered across multiple files
- **Limited Replay**: Cannot replay workflow execution for debugging
- **Manual Metrics**: No built-in dashboards or tracing
- **Log Correlation**: Difficult to trace execution across components

### 2.3 Orchestration Brittleness

| Problem | Details |
|---------|---------|
| **Thread Safety** | MonitorMixin used but complex multi-threaded state management |
| **Process Management** | PID-based tracking; stuck detection via checkpoint age |
| **Fan-out Complexity** | Manual result aggregation with `Concurrent::Hash` |
| **Cancellation** | Graceful shutdown with timeouts; potential for orphaned processes |

### 2.4 Long-Running Workflow Challenges

- **Watch Mode**: Runs indefinitely with `sleep @interval` between cycles
- **Background Jobs**: Daemon processes with manual stuck detection (>10 min without checkpoint)
- **Work Loops**: Up to 50 iterations with no guaranteed upper time bound

---

## 3. Temporal Architecture Mapping

### 3.1 Proposed Component Mapping

| Aidp Component | Temporal Equivalent | Rationale |
|----------------|-------------------|-----------|
| `WorkLoopRunner` | **Workflow** | State machine becomes durable workflow with automatic replay |
| `execute_step()` loop | **Workflow loop with Activities** | Each iteration calls Activities for agent execution |
| `apply_patch()` | **Activity** | Non-deterministic LLM call becomes Activity |
| `run_phase_based_commands()` | **Activity** | Test/lint execution as Activities |
| `AsyncWorkLoopRunner` | **Workflow + Signals** | Pause/resume via Signals; async status via Queries |
| `BackgroundRunner` | **Async Workflow Start** | Start workflow without waiting; track via Workflow ID |
| `WorkstreamExecutor` | **Child Workflows** | Each workstream as Child Workflow with parallel execution |
| `Watch::Runner` | **Scheduled Workflow** | Cron-based polling workflow |
| Checkpoint | **Workflow Event History** | Automatic persistence; no manual checkpointing |
| `InstructionQueue` | **Signals** | Queue user input via Signal handlers |

### 3.2 Proposed Workflow Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                    AidpOrchestratorWorkflow                      │
│                    (Top-level entry point)                       │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│WorkLoopWorkflow│    │WatchModeWorkflow│   │AnalyzeWorkflow│
│(Single Step)  │    │(Continuous)    │    │(One-shot)     │
└───────────────┘    └───────────────┘    └───────────────┘
        │                     │
        ▼                     ▼
┌───────────────┐    ┌───────────────┐
│WorkstreamChild│    │ProcessorChild │
│(Parallel exec)│    │(Plan/Build/   │
└───────────────┘    │ Review/CI)    │
                     └───────────────┘
```

### 3.3 Activity Boundaries

Activities should encapsulate all non-deterministic operations:

| Activity | Input | Output | Idempotency |
|----------|-------|--------|-------------|
| `ExecuteAgentActivity` | Prompt, config | Agent output | Non-idempotent (LLM calls) |
| `RunTestsActivity` | Test config | Test results | Idempotent |
| `RunLinterActivity` | Linter config | Linter output | Idempotent |
| `GitOperationActivity` | Git command | Git result | Non-idempotent (commits) |
| `GitHubApiActivity` | API call params | API response | Idempotent for reads |
| `CreateWorktreeActivity` | Worktree config | Worktree path | Idempotent |
| `CollectMetricsActivity` | Project dir | Metrics data | Idempotent |

---

## 4. Benefits of Temporal Adoption

### 4.1 Durability & Recovery

| Benefit | Description |
|---------|-------------|
| **Automatic State Persistence** | Every workflow state transition persisted; no manual checkpointing |
| **Crash Recovery** | Workers restart and resume from exact point of failure |
| **Deterministic Replay** | Workflow history can be replayed for debugging |
| **Network Partition Handling** | Built-in retry policies; automatic reconnection |

### 4.2 Observability

| Feature | Value |
|---------|-------|
| **Event History** | Complete record of all workflow events |
| **Web UI** | Built-in dashboard for workflow monitoring |
| **Tracing** | Native OpenTelemetry integration |
| **Metrics** | Prometheus metrics out of the box |

### 4.3 Operational Benefits

| Benefit | Description |
|---------|-------------|
| **Horizontal Scaling** | Add Workers to handle more workflows |
| **Task Queues** | Route work to specific Worker pools |
| **Versioning** | Safely deploy workflow updates |
| **Timeouts** | Fine-grained timeout control at workflow/activity level |

---

## 5. Drawbacks and Risks

### 5.1 Complexity Costs

| Risk | Mitigation |
|------|------------|
| **Learning Curve** | Ruby SDK is new; team needs Temporal expertise |
| **Operational Overhead** | Self-hosted requires database, monitoring, maintenance |
| **Testing Complexity** | Need Temporal test framework; mock service for unit tests |
| **Debugging** | Event history interpretation requires training |

### 5.2 Migration Challenges

| Challenge | Difficulty |
|-----------|-----------|
| **CLI Subprocess Handling** | Medium - Activities can launch CLIs, but output capture needs design |
| **State Migration** | High - Existing checkpoints incompatible with Temporal history |
| **Watch Mode Conversion** | Medium - Long-running workflow with Continue-As-New |
| **Error Handling Parity** | Medium - Map current error taxonomy to Temporal exceptions |

### 5.3 Ruby SDK Maturity

The Ruby SDK reached pre-release status in January 2025:
- Supports Ruby 3.2, 3.3, 3.4
- macOS and Linux only (no Windows)
- Async/fiber support requires Ruby 3.3+
- Fewer community examples than Go/Python SDKs

---

## 6. Proposed New Architecture

### 6.1 System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                        Aidp CLI                                  │
│  (User interface - starts workflows, sends signals)              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Temporal Ruby Client                           │
│  (Workflow/Signal/Query client)                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Temporal Service                              │
│  (Self-hosted: Frontend, History, Matching, Worker services)     │
│  (Database: PostgreSQL)                                          │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│ Worker Pool A │    │ Worker Pool B │    │ Worker Pool C │
│ (Work Loops)  │    │ (Watch Mode)  │    │ (Analysis)    │
└───────────────┘    └───────────────┘    └───────────────┘
        │                     │                     │
        ▼                     ▼                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Activity Implementations                     │
│  ExecuteAgent | RunTests | GitOps | GitHubApi | CollectMetrics  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Task Queue Design

| Task Queue | Workers | Workflows |
|------------|---------|-----------|
| `aidp-work-loop` | 2-4 | WorkLoopWorkflow, WorkstreamWorkflow |
| `aidp-watch-mode` | 1-2 | WatchModeWorkflow, ProcessorWorkflows |
| `aidp-analysis` | 1-2 | AnalyzeWorkflow, FeatureAnalysis |
| `aidp-activities` | 4-8 | All Activities (shared) |

### 6.3 Signal/Query Design

| Signal | Purpose |
|--------|---------|
| `pause_work_loop` | Pause iteration at next safe point |
| `resume_work_loop` | Resume paused workflow |
| `cancel_work_loop` | Request graceful cancellation |
| `inject_instruction` | Add user instruction to queue |
| `update_guard_policy` | Modify guard configuration |

| Query | Returns |
|-------|---------|
| `get_status` | Current state, iteration, progress |
| `get_pending_instructions` | Queued instruction count |
| `get_metrics` | Checkpoint metrics |

---

## 7. Recommendation

### 7.1 Decision: Conditionally Recommended

Temporal adoption is **conditionally recommended** based on:

**Adopt If:**
- Aidp needs to scale to multiple concurrent users/projects
- Durability requirements increase (enterprise deployments)
- Observability/debugging is becoming a bottleneck
- Team has capacity for infrastructure investment

**Defer If:**
- Current scale is adequate for use cases
- Operational complexity is a concern
- Ruby SDK maturity is insufficient
- Team lacks Temporal expertise

### 7.2 Recommended Approach

If proceeding, we recommend:

1. **Start with Work Loop Only**: Migrate `WorkLoopRunner` first as proof-of-concept
2. **Preserve Existing CLI**: Keep current CLI; add Temporal client layer
3. **Incremental Migration**: Run Temporal and native modes in parallel
4. **Self-Hosted PostgreSQL**: Use PostgreSQL backend for familiarity
5. **Docker Compose First**: Start with Docker Compose before Kubernetes

### 7.3 Success Criteria

| Metric | Target |
|--------|--------|
| Work Loop Recovery | Resume within 5s of worker restart |
| Observability | Full event history visible in Web UI |
| Performance | No regression in iteration latency |
| Testing | 90%+ workflow coverage with test framework |

---

## 8. Next Steps

1. **Prototype**: Build proof-of-concept WorkLoopWorkflow
2. **Benchmark**: Compare performance against current implementation
3. **Team Training**: Ruby SDK training for development team
4. **Infrastructure**: Set up self-hosted Temporal environment
5. **Migration Planning**: Develop detailed migration runbook

---

## References

- [Temporal Ruby SDK Documentation](https://docs.temporal.io/develop/ruby)
- [Temporal Ruby SDK GitHub](https://github.com/temporalio/sdk-ruby)
- [Temporal Self-Hosted Guide](https://docs.temporal.io/self-hosted-guide)
- [Temporal Architecture Overview](https://temporal.io/how-it-works)
- [Managing Long-Running Workflows](https://temporal.io/blog/very-long-running-workflows)
