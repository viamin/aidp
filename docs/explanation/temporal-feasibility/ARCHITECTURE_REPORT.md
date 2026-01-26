# Temporal Feasibility Study: Architecture Report

## Executive Summary

This report evaluates whether Aidp should replace its native Ruby workflow orchestration code with Temporal.io workflows running in a self-hosted environment. The evaluation focuses specifically on Aidp's strategic direction toward **multi-agent orchestration** where multiple parallel agents work on atomic units that combine into feature-complete PRs.

## Recommendation: Strongly Recommended

Temporal adoption is essential for achieving durable multi-agent orchestration at scale. The current fork-based implementation cannot provide the durability, failure isolation, and visibility required when coordinating 10-50+ parallel agents on complex features. Temporal's hierarchical workflow model maps directly to the multi-agent pattern.

### Key Drivers for Adoption

| Requirement | Current Gap | Temporal Solution |
| ----------- | ----------- | ----------------- |
| Orchestrator crash recovery | Lost state; manual restart | Automatic resume via Event History |
| Partial failure retry | Restart all or manual track | Retry only failed child workflows |
| Progress visibility | Per-process log files | Real-time queries + Web UI |
| Agent coordination | File-based polling | Signals between workflows |
| Result aggregation | Manual exit code collection | Structured child workflow results |

---

## 1. Current Aidp Orchestration Architecture

### 1.1 Core Components

Aidp's orchestration is built on these foundational components:

| Component | Location | Responsibility |
| --------- | -------- | -------------- |
| `WorkLoopRunner` | `lib/aidp/execute/work_loop_runner.rb` | Fix-forward state machine for iterative AI execution |
| `AsyncWorkLoopRunner` | `lib/aidp/execute/async_work_loop_runner.rb` | Thread-based async execution with pause/resume/cancel |
| `BackgroundRunner` | `lib/aidp/jobs/background_runner.rb` | Daemonized process execution with PID tracking |
| `WorkstreamExecutor` | `lib/aidp/workstream_executor.rb` | Parallel execution via fork() and concurrent-ruby |
| `Watch::Runner` | `lib/aidp/watch/runner.rb` | Continuous GitHub monitoring with multiple processors |
| `Concurrency::Backoff` | `lib/aidp/concurrency/backoff.rb` | Retry logic with exponential backoff |
| `Concurrency::Wait` | `lib/aidp/concurrency/wait.rb` | Deterministic condition waiting with timeouts |

### 1.2 Workflow State Machine

The `WorkLoopRunner` implements a fix-forward state machine:

```text
READY → APPLY_PATCH → TEST → {PASS → DONE | FAIL → DIAGNOSE → NEXT_PATCH} → READY
```

Key characteristics:

- Maximum 50 iterations safety limit
- Periodic checkpoints every 5 iterations
- Style guide reminder injection every 5 iterations
- No rollback - only forward progress through fixes

### 1.3 Data Flow Architecture

```text
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
| ---------- | ------- | -------- |
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
| ----- | ------------ | ------ |
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
| ------- | ------- |
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
| -------------- | ------------------- | --------- |
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

```text
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
| -------- | ----- | ------ | ----------- |
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
| ------- | ----------- |
| **Automatic State Persistence** | Every workflow state transition persisted; no manual checkpointing |
| **Crash Recovery** | Workers restart and resume from exact point of failure |
| **Deterministic Replay** | Workflow history can be replayed for debugging |
| **Network Partition Handling** | Built-in retry policies; automatic reconnection |

### 4.2 Observability

| Feature | Value |
| ------- | ----- |
| **Event History** | Complete record of all workflow events |
| **Web UI** | Built-in dashboard for workflow monitoring |
| **Tracing** | Native OpenTelemetry integration |
| **Metrics** | Prometheus metrics out of the box |

### 4.3 Operational Benefits

| Benefit | Description |
| ------- | ----------- |
| **Horizontal Scaling** | Add Workers to handle more workflows |
| **Task Queues** | Route work to specific Worker pools |
| **Versioning** | Safely deploy workflow updates |
| **Timeouts** | Fine-grained timeout control at workflow/activity level |

---

## 5. Drawbacks and Risks

### 5.1 Complexity Costs

| Risk | Mitigation |
| ---- | ---------- |
| **Learning Curve** | Ruby SDK is new; team needs Temporal expertise |
| **Operational Overhead** | Self-hosted requires database, monitoring, maintenance |
| **Testing Complexity** | Need Temporal test framework; mock service for unit tests |
| **Debugging** | Event history interpretation requires training |

### 5.2 Migration Challenges

| Challenge | Difficulty |
| --------- | ---------- |
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

```text
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
| ---------- | ------- | --------- |
| `aidp-work-loop` | 2-4 | WorkLoopWorkflow, WorkstreamWorkflow |
| `aidp-watch-mode` | 1-2 | WatchModeWorkflow, ProcessorWorkflows |
| `aidp-analysis` | 1-2 | AnalyzeWorkflow, FeatureAnalysis |
| `aidp-activities` | 4-8 | All Activities (shared) |

### 6.3 Signal/Query Design

| Signal | Purpose |
| ------ | ------- |
| `pause_work_loop` | Pause iteration at next safe point |
| `resume_work_loop` | Resume paused workflow |
| `cancel_work_loop` | Request graceful cancellation |
| `inject_instruction` | Add user instruction to queue |
| `update_guard_policy` | Modify guard configuration |

| Query | Returns |
| ----- | ------- |
| `get_status` | Current state, iteration, progress |
| `get_pending_instructions` | Queued instruction count |
| `get_metrics` | Checkpoint metrics |

---

## 7. Multi-Agent Orchestration Architecture

The strategic direction toward multi-agent orchestration fundamentally changes the architectural requirements.

### 7.1 Multi-Agent Vision

```text
┌─────────────────────────────────────────────────────────────────┐
│                  Feature Orchestrator Workflow                   │
│  "Implement user authentication with OAuth2"                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │ FeatureDecomposer │
                    │    Activity       │
                    └─────────┬─────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│ AtomicUnit    │    │ AtomicUnit    │    │ AtomicUnit    │
│ Child Workflow│    │ Child Workflow│    │ Child Workflow│
│               │    │               │    │               │
│ "OAuth config"│    │ "Login flow"  │    │ "Session mgmt"│
│               │    │               │    │               │
│ ✓ WorkLoop    │    │ ✓ WorkLoop    │    │ ✓ WorkLoop    │
│ ✓ Tests       │    │ ✓ Tests       │    │ ✓ Tests       │
│ ✓ Commit      │    │ ✓ Commit      │    │ ✓ Commit      │
└───────────────┘    └───────────────┘    └───────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │  MergeOrchestrator│
                    │  Child Workflow   │
                    └─────────┬─────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │ Feature-Complete PR │
                    └─────────────────────┘
```

### 7.2 Why Temporal is Essential for Multi-Agent

| Multi-Agent Requirement | Current Limitation | Temporal Capability |
| ----------------------- | ------------------ | ------------------- |
| **Durable Orchestrator** | In-memory; crash = lost state | Event History survives crashes |
| **50+ Parallel Agents** | fork() doesn't scale | Child Workflows with isolation |
| **Partial Failure Retry** | All-or-nothing restart | Retry only failed children |
| **Progress Visibility** | Log files per process | Query handlers + Web UI |
| **Agent Coordination** | File-based polling | Signals between workflows |
| **Result Aggregation** | Manual exit code check | Structured child results |
| **Dependency Graphs** | Only 2-level hierarchy | Arbitrary workflow nesting |

### 7.3 Multi-Agent Task Queues

| Task Queue | Workers | Purpose |
| ---------- | ------- | ------- |
| `aidp-orchestrator` | 2 | Feature orchestration (parent workflows) |
| `aidp-agent-light` | 10 | Lightweight agents (schema gen, config) |
| `aidp-agent-standard` | 5 | Standard agents (implementation) |
| `aidp-agent-heavy` | 2 | Heavy agents (integration tests) |
| `aidp-merge` | 2 | PR merging and aggregation |

### 7.4 Multi-Agent Signals and Queries

**Orchestrator Signals:**

| Signal | Purpose |
| ------ | ------- |
| `pause_orchestration` | Pause at next safe point |
| `resume_orchestration` | Resume paused orchestration |
| `cancel_orchestration` | Cancel all agents gracefully |
| `retry_failed_agents` | Retry only failed child workflows |
| `adjust_concurrency` | Change parallel agent count |

**Orchestrator Queries:**

| Query | Returns |
| ----- | ------- |
| `orchestration_status` | Overall progress, per-agent status |
| `agent_details` | Detailed status for specific agent |
| `estimated_completion` | ETA based on current progress |
| `failure_summary` | List of failed agents with errors |

---

## 8. Recommendation

### 8.1 Decision: Strongly Recommended

For the multi-agent orchestration direction, Temporal adoption is **strongly recommended**.

**Critical Drivers:**

1. **Durability at Scale**: Orchestrating 50+ agents requires crash-resilient state
2. **Failure Isolation**: One bad agent shouldn't kill the entire feature
3. **Operational Visibility**: Must see what all agents are doing
4. **Partial Retry**: Retry failed agents without restarting successful ones
5. **Hierarchical Coordination**: Parent-child workflow model fits perfectly

**The Alternative is Worse:**
Building these capabilities natively would require:

- Custom event sourcing system
- Workflow replay mechanism
- Distributed state management
- Custom monitoring/dashboards
- Essentially rebuilding Temporal

### 8.2 Recommended Approach (Multi-Agent Priority)

1. **Phase 1: Multi-Agent Foundation**
   - Implement `FeatureOrchestrationWorkflow` (parent)
   - Implement `AtomicUnitWorkflow` (child)
   - Parallel execution with failure isolation

2. **Phase 2: Aggregation & Merge**
   - Implement `MergeOrchestrationWorkflow`
   - Result aggregation from children
   - Feature PR creation

3. **Phase 3: Single-Agent Migration**
   - Migrate `WorkLoopRunner` to Temporal
   - This becomes the child workflow execution

4. **Defer: Watch Mode**
   - Watch mode is less critical for multi-agent
   - Migrate after core multi-agent works

### 8.3 Success Criteria

| Metric | Target |
| ------ | ------ |
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
