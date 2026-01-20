# Temporal Feasibility Study: Migration Plan

This document provides a stepwise migration plan for adopting Temporal.io in Aidp, with a focus on enabling **multi-agent orchestration** where parallel agents work on atomic units that combine into feature-complete PRs.

---

## 1. Migration Philosophy

### 1.1 Key Principles

1. **Multi-Agent First**: Prioritize hierarchical orchestration over single-agent migration
2. **Parallel Operation**: Run Temporal and native modes simultaneously
3. **Feature Flags**: Toggle between implementations
4. **Value Early**: Deliver multi-agent capability as quickly as possible
5. **Rollback Capability**: Easy revert at every stage

### 1.2 Migration Phases (Multi-Agent Priority)

| Phase | Duration | Focus | Value Delivered |
|-------|----------|-------|-----------------|
| Phase 0: Foundation | 2-4 weeks | Infrastructure, SDK | Temporal running |
| Phase 1: Multi-Agent Core | 6-8 weeks | Orchestration + Child workflows | **Parallel agents work!** |
| Phase 2: Merge & Aggregate | 4-6 weeks | Result combination, PR creation | **Feature PRs from agents** |
| Phase 3: Single-Agent Polish | 4-6 weeks | WorkLoopWorkflow improvements | Better individual agents |
| Phase 4: Watch Mode (Optional) | 4-6 weeks | Watch mode migration | Automated GitHub loop |

**Key Change from Original Plan**: We front-load the multi-agent orchestration (Phases 1-2) because that's the strategic direction. Single-agent improvements (Phase 3) and Watch mode (Phase 4) become less critical.

---

## 2. Phase 0: Foundation

### 2.1 Infrastructure Setup

**Objectives**:
- Deploy self-hosted Temporal Service
- Integrate Ruby SDK into Aidp
- Establish CI/CD for Temporal components

**Tasks**:

| Task | Description | Effort |
|------|-------------|--------|
| Deploy Temporal Service | Docker Compose with PostgreSQL | 2-3 days |
| Set up Temporal Web UI | Deploy UI for workflow monitoring | 1 day |
| Configure monitoring | Prometheus + Grafana dashboards | 2-3 days |
| Add Ruby SDK dependency | Add `temporalio` gem to Gemfile | 1 day |
| Create Temporal client wrapper | `lib/aidp/temporal/client.rb` | 2-3 days |
| Set up test infrastructure | Test server for unit/integration tests | 3-4 days |
| CI pipeline updates | Add Temporal service to CI | 2 days |

**Deliverables**:
- Running Temporal Service (dev/staging)
- Ruby SDK integrated
- Test framework operational
- CI pipeline with Temporal tests

### 2.2 Feature Flag System

Create a configuration option to enable Temporal:

```ruby
# config/aidp.yml
orchestration:
  engine: native  # or "temporal"
  temporal:
    address: "localhost:7233"
    namespace: "aidp-dev"
    task_queues:
      work_loop: "aidp-work-loop"
      watch_mode: "aidp-watch-mode"
```

```ruby
# lib/aidp/orchestration_router.rb
module Aidp
  class OrchestrationRouter
    def initialize(config)
      @engine = config.dig(:orchestration, :engine) || "native"
    end

    def execute_work_loop(step_name, step_spec, context)
      if @engine == "temporal"
        Aidp::Temporal::WorkLoopClient.new.execute(step_name, step_spec, context)
      else
        Aidp::Execute::WorkLoopRunner.new(...).execute_step(step_name, step_spec, context)
      end
    end
  end
end
```

### 2.3 Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Ruby SDK instability | Medium | High | Pin SDK version; maintain native fallback |
| Infrastructure complexity | Medium | Medium | Start with Docker Compose; defer K8s |
| Team learning curve | High | Medium | Training before migration begins |

---

## 3. Phase 1: Multi-Agent Core

**This is the critical phase** - it delivers the core multi-agent orchestration capability.

### 3.1 Feature Orchestration Workflow

**Objectives**:
- Implement parent workflow that coordinates multiple agents
- Parallel child workflow dispatch with bounded concurrency
- Failure isolation (one agent fails, others continue)
- Partial retry capability (retry only failed agents)

**Tasks**:

| Task | Description | Effort |
|------|-------------|--------|
| `FeatureOrchestrationWorkflow` | Parent workflow with child dispatch | 5-7 days |
| `AtomicUnitWorkflow` | Child workflow for single agent | 3-4 days |
| `DecomposeFeatureActivity` | AI-powered feature decomposition | 3-4 days |
| `CreateWorktreeActivity` | Git worktree management | 2-3 days |
| Parallel dispatch logic | Bounded concurrency via Task Queues | 2-3 days |
| Failure isolation | Per-child try/catch, result collection | 2-3 days |
| Partial retry mechanism | Retry only failed children | 2-3 days |
| Orchestration Signals | pause, resume, cancel, adjust_concurrency | 2-3 days |
| Orchestration Queries | status, progress, agent_details | 2-3 days |
| Unit tests | Parent and child workflow tests | 4-5 days |
| Integration tests | Multi-agent end-to-end tests | 4-5 days |

**Success Criteria**:
- [ ] 10+ agents run in parallel successfully
- [ ] Orchestrator survives crash/restart
- [ ] Failed agents can be retried without restarting successful ones
- [ ] Real-time status via queries
- [ ] Pause/resume affects all child workflows

### 3.2 Multi-Agent Worker Configuration

```ruby
# lib/aidp/temporal/workers/multi_agent_worker.rb
module Aidp
  module Temporal
    module Workers
      class MultiAgentWorker
        def initialize(config)
          @client = Temporalio::Client.connect(config[:address])

          # Orchestrator worker (low concurrency, high visibility)
          @orchestrator_worker = Temporalio::Worker.new(
            client: @client,
            task_queue: "aidp-orchestrator",
            workflows: [
              FeatureOrchestrationWorkflow,
              MergeOrchestrationWorkflow
            ],
            activities: [DecomposeFeatureActivity],
            max_concurrent_workflow_tasks: 5
          )

          # Agent worker (higher concurrency)
          @agent_worker = Temporalio::Worker.new(
            client: @client,
            task_queue: "aidp-agent-standard",
            workflows: [AtomicUnitWorkflow, WorkLoopWorkflow],
            activities: [
              ExecuteAgentActivity,
              RunTestsActivity,
              RunLinterActivity,
              CreateWorktreeActivity,
              CommitAndPushActivity
            ],
            max_concurrent_activities: 10
          )
        end

        def run
          # Run both workers in parallel
          threads = [
            Thread.new { @orchestrator_worker.run },
            Thread.new { @agent_worker.run }
          ]
          threads.each(&:join)
        end
      end
    end
  end
end
```

### 3.3 Multi-Agent Testing Strategy

```ruby
# spec/temporal/workflows/feature_orchestration_workflow_spec.rb
RSpec.describe Aidp::Temporal::FeatureOrchestrationWorkflow do
  let(:env) { Temporalio::Testing::WorkflowEnvironment.new }

  it "orchestrates multiple agents in parallel" do
    feature_spec = {
      name: "user_auth",
      units: [
        { id: "oauth", name: "OAuth config" },
        { id: "login", name: "Login flow" },
        { id: "session", name: "Session management" }
      ]
    }

    result = env.run_workflow(described_class, feature_spec: feature_spec)

    expect(result[:completed_count]).to eq(3)
    expect(result[:status]).to eq("completed")
  end

  it "isolates failures and allows partial retry" do
    feature_spec = { name: "test", units: make_units(10) }

    # Make unit 5 fail
    allow_unit_to_fail(5)

    result = env.run_workflow(described_class, feature_spec: feature_spec)

    # 9 succeeded, 1 failed
    expect(result[:completed_count]).to eq(9)
    expect(result[:failed_count]).to eq(1)
    expect(result[:failed_units]).to include("unit_5")
  end

  it "survives orchestrator crash and resumes" do
    handle = env.start_workflow(described_class, feature_spec: large_feature)

    # Wait for some children to complete
    env.time_skip(60.seconds)

    # Simulate crash
    completed_before_crash = handle.query("orchestration_status")[:completed]

    env.restart_worker

    # Workflow continues without re-running completed children
    result = handle.result
    expect(result[:total_child_executions]).to be <= result[:unit_count]
  end

  it "provides real-time status via queries" do
    handle = env.start_workflow(described_class, feature_spec: feature_spec)

    status = handle.query("orchestration_status")

    expect(status).to include(
      :total_units,
      :completed,
      :in_progress,
      :failed,
      :progress_percent,
      :unit_details
    )
  end
end
```

### 3.4 Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Child workflow coordination complexity | High | High | Extensive testing; start with 5 agents |
| Event History growth with many children | Medium | Medium | Monitor history size; use Continue-As-New |
| Task Queue starvation | Medium | Medium | Separate queues for orchestrator vs agents |
| Deadlock between parent and child | Low | High | Avoid parent waiting synchronously for signals |

---

## 4. Phase 2: Merge & Aggregate

**This phase completes the multi-agent value proposition** - combining agent results into feature-complete PRs.

### 4.1 Merge Orchestration Workflow

**Objectives**:
- Coordinate merge operations across atomic unit branches
- Handle merge conflicts with AI-assisted resolution
- Create feature-complete PRs from combined work

**Tasks**:

| Task | Description | Effort |
|------|-------------|--------|
| `MergeOrchestrationWorkflow` | Coordinate branch merging | 4-5 days |
| `MergeBranchActivity` | Git merge operations | 2-3 days |
| `ResolveConflictsActivity` | AI-assisted conflict resolution | 3-4 days |
| `CreateFeaturePRActivity` | GitHub PR creation | 2-3 days |
| `AggregateResultsActivity` | Combine test/lint results | 2-3 days |
| Merge strategy selection | Sequential vs parallel merge | 2-3 days |
| Conflict retry logic | Retry failed merges after fixes | 2-3 days |
| Integration tests | End-to-end merge tests | 4-5 days |

**Success Criteria**:
- [ ] Atomic unit branches merge automatically
- [ ] Merge conflicts trigger AI resolution workflow
- [ ] Feature PRs created with combined changes
- [ ] Aggregated test results available in PR
- [ ] Rollback capability for failed merges

### 4.2 Merge Orchestration Implementation

```ruby
# lib/aidp/temporal/workflows/merge_orchestration_workflow.rb
class MergeOrchestrationWorkflow < Temporalio::Workflow
  def execute(feature_id:, completed_units:, target_branch:)
    # Aggregate results from all completed units
    aggregated_results = workflow.execute_activity(
      AggregateResultsActivity,
      units: completed_units
    )

    # Determine optimal merge order (dependency-aware)
    merge_order = workflow.execute_activity(
      DetermineMergeOrderActivity,
      units: completed_units
    )

    # Merge each unit sequentially (to handle conflicts)
    merged_units = []
    merge_order.each do |unit|
      merge_result = merge_with_conflict_handling(unit, target_branch)

      if merge_result[:success]
        merged_units << unit
      else
        # Store conflict for manual review or retry
        @merge_conflicts << {
          unit: unit,
          conflict: merge_result[:conflict],
          attempted_at: workflow.now
        }
      end
    end

    # Create feature PR if enough units merged successfully
    if merged_units.size >= (completed_units.size * 0.8)  # 80% threshold
      pr_result = workflow.execute_activity(
        CreateFeaturePRActivity,
        feature_id: feature_id,
        merged_units: merged_units,
        aggregated_results: aggregated_results,
        conflicts: @merge_conflicts
      )

      { status: "pr_created", pr_url: pr_result[:url], merged_count: merged_units.size }
    else
      { status: "insufficient_merges", merged_count: merged_units.size, conflicts: @merge_conflicts }
    end
  end

  private

  def merge_with_conflict_handling(unit, target_branch)
    result = workflow.execute_activity(
      MergeBranchActivity,
      source_branch: unit[:branch],
      target_branch: target_branch
    )

    return result if result[:success]

    # Attempt AI-assisted conflict resolution
    resolution = workflow.execute_activity(
      ResolveConflictsActivity,
      conflict: result[:conflict],
      unit: unit
    )

    if resolution[:resolved]
      # Retry merge after resolution
      workflow.execute_activity(
        MergeBranchActivity,
        source_branch: unit[:branch],
        target_branch: target_branch
      )
    else
      result  # Return original failure
    end
  end
end
```

### 4.3 Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Merge conflicts between units | High | High | AI-assisted resolution; clear merge order |
| Failed merges blocking feature | Medium | High | 80% threshold; manual override option |
| Git state corruption | Low | High | Activity-level rollback; worktree isolation |
| Large history from many merges | Medium | Medium | Squash merges for atomic units |

---

## 5. Phase 3: Single-Agent Polish

**This phase improves individual agent execution** - refinements to the single-agent work loop.

### 5.1 WorkLoop Workflow Improvements

**Objectives**:
- Migrate existing `WorkLoopRunner` to Temporal
- Add durability to individual agent execution
- Enable better recovery and debugging

**Tasks**:

| Task | Description | Effort |
|------|-------------|--------|
| `WorkLoopWorkflow` | Single-agent work loop | 3-4 days |
| Iteration state management | Track fix-forward progress | 2-3 days |
| Provider-agnostic execution | Support all AI providers | 3-4 days |
| Checkpoint migration | Replace file-based checkpoints | 2-3 days |
| Signal handlers | pause, resume, cancel, inject | 2-3 days |
| Query handlers | status, iteration_count, history | 2-3 days |
| Unit tests | WorkLoop workflow tests | 3-4 days |

### 5.2 AsyncWorkLoop & BackgroundRunner

**Objective**: Migrate async execution patterns

```ruby
# lib/aidp/temporal/async_client.rb
class AsyncWorkLoopClient
  def execute_async(step_name, step_spec, context)
    workflow_id = generate_workflow_id

    @client.start_workflow(
      WorkLoopWorkflow,
      step_name, step_spec, context,
      id: workflow_id,
      task_queue: "aidp-work-loop"
    )

    { status: "started", workflow_id: workflow_id }
  end

  def wait(workflow_id)
    @client.get_workflow_handle(workflow_id).result
  end
end

# lib/aidp/temporal/job_manager.rb
class JobManager
  def start(mode, options)
    workflow_class = case mode
      when :execute then WorkLoopWorkflow
      when :multi_agent then FeatureOrchestrationWorkflow
      when :watch then WatchModeWorkflow
    end

    workflow_id = "aidp-#{mode}-#{SecureRandom.hex(4)}"

    @client.start_workflow(
      workflow_class,
      options,
      id: workflow_id,
      task_queue: determine_queue(mode)
    )

    workflow_id
  end
end
```

### 5.3 Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Activity timeout issues | Medium | Medium | Tune timeouts; add heartbeats |
| Non-determinism bugs | Medium | High | Strict Activity boundaries; testing |
| CLI output capture | Low | Medium | Test with all providers |

---

## 6. Phase 4: Watch Mode (Optional)

**This phase enables automated GitHub monitoring** - can be deferred if multi-agent is primary focus.

### 6.1 Watch Mode Migration

**Objective**: Replace continuous polling with Temporal Schedule

**Option A: Scheduled Workflow**
```ruby
# Execute single cycle, scheduled externally
schedule = client.create_schedule(
  "aidp-watch",
  spec: ScheduleSpec.new(interval: [IntervalSpec.new(every: 30)]),
  action: ScheduleWorkflowAction.new(
    workflow: WatchCycleWorkflow,
    task_queue: "aidp-watch-mode"
  )
)
```

**Option B: Long-Running Workflow with Continue-As-New**
```ruby
class WatchModeWorkflow < Temporalio::Workflow
  MAX_CYCLES = 100  # Prevent history overflow

  def execute(config:, cycle: 0)
    if cycle >= MAX_CYCLES
      workflow.continue_as_new(config: config, cycle: 0)
      return
    end

    process_cycle(config)
    cycle += 1
    workflow.sleep(config[:interval])
  end
end
```

### 6.2 Processor Migration

Each processor becomes a Child Workflow:

| Processor | Child Workflow |
|-----------|---------------|
| PlanProcessor | PlanProcessorWorkflow |
| BuildProcessor | BuildProcessorWorkflow |
| ReviewProcessor | ReviewProcessorWorkflow |
| CiFixProcessor | CiFixProcessorWorkflow |
| ChangeRequestProcessor | ChangeRequestProcessorWorkflow |

### 6.3 Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Event History growth | High | Medium | Continue-As-New at 100 cycles |
| GitHub API rate limits | Medium | Medium | Activity-level rate limiting |
| Long-running stability | Medium | High | Extensive testing; monitoring |

---

## 7. Phase 5: Full Migration (Optional)

### 7.1 Deprecation Strategy

1. **Announcement**: Document migration in CHANGELOG
2. **Warning Period**: Log deprecation warnings for native mode
3. **Default Switch**: Change default from `native` to `temporal`
4. **Removal**: Remove native orchestration code

### 7.2 Cleanup Tasks

| Task | Description |
|------|-------------|
| Remove `AsyncWorkLoopRunner` | Replaced by Temporal |
| Remove `BackgroundRunner` | Replaced by Temporal |
| Remove `WorkstreamExecutor` | Replaced by Child Workflows |
| Update documentation | New orchestration docs |
| Archive legacy tests | Remove native-only tests |

### 7.3 Rollback Plan

If issues arise post-migration:

1. **Feature Flag Revert**: Change `orchestration.engine` to `native`
2. **Keep Native Code**: Don't delete until confident (Phase 5+)
3. **Data Migration**: Export workflow history if needed
4. **Worker Shutdown**: Gracefully drain Temporal workers

---

## 8. Risk Registry

### 8.1 Technical Risks

| ID | Risk | Likelihood | Impact | Mitigation | Owner |
|----|------|------------|--------|------------|-------|
| T1 | Ruby SDK bugs | Medium | High | Pin version; fallback | Dev Team |
| T2 | Non-determinism | Medium | High | Strict Activity boundaries | Dev Team |
| T3 | Performance regression | Low | Medium | Benchmarking | Dev Team |
| T4 | Activity timeouts | Medium | Medium | Heartbeats; tuning | Dev Team |
| T5 | State migration | High | Medium | Don't migrate; start fresh | Dev Team |
| T6 | Child workflow coordination | High | High | Extensive testing; start small | Dev Team |
| T7 | Merge conflict handling | High | High | AI-assisted resolution; manual fallback | Dev Team |

### 8.2 Operational Risks

| ID | Risk | Likelihood | Impact | Mitigation | Owner |
|----|------|------------|--------|------------|-------|
| O1 | Infrastructure complexity | Medium | High | Docker Compose first | Ops Team |
| O2 | Database management | Medium | Medium | Managed PostgreSQL | Ops Team |
| O3 | Monitoring gaps | Medium | Medium | Prometheus/Grafana | Ops Team |
| O4 | Team expertise | High | Medium | Training program | Team Lead |

### 8.3 Project Risks

| ID | Risk | Likelihood | Impact | Mitigation | Owner |
|----|------|------------|--------|------------|-------|
| P1 | Scope creep | Medium | Medium | Strict phase gates | PM |
| P2 | Timeline slip | Medium | Medium | Buffer in estimates | PM |
| P3 | Parallel workload | Medium | High | Dedicated resources | PM |

---

## 9. Success Metrics

### 9.1 Phase 0 Success (Foundation)

- [ ] Temporal Service running in dev/staging
- [ ] Ruby SDK integrated and tested
- [ ] CI pipeline passing
- [ ] Team trained on Temporal basics

### 9.2 Phase 1 Success (Multi-Agent Core) ⭐

**This is the critical milestone - multi-agent orchestration working!**

- [ ] 10+ agents run in parallel successfully
- [ ] Orchestrator survives crash/restart
- [ ] Failed agents can be retried without restarting successful ones
- [ ] Real-time status via queries
- [ ] Pause/resume affects all child workflows
- [ ] Worker restart recovers execution < 5s

### 9.3 Phase 2 Success (Merge & Aggregate)

- [ ] Atomic unit branches merge automatically
- [ ] Merge conflicts trigger AI resolution workflow
- [ ] Feature PRs created with combined changes
- [ ] Aggregated test results available in PR
- [ ] 80%+ of units merge successfully

### 9.4 Phase 3 Success (Single-Agent Polish)

- [ ] WorkLoopWorkflow passes all tests
- [ ] Signals work correctly (pause, resume, cancel)
- [ ] Performance within 10% of native
- [ ] File-based checkpoints replaced

### 9.5 Phase 4 Success (Watch Mode - Optional)

- [ ] Watch mode runs 24+ hours without issues
- [ ] Event history stays within limits
- [ ] All processors work as Child Workflows
- [ ] Monitoring shows healthy metrics

### 9.6 Phase 5 Success (Full Migration - Optional)

- [ ] Native code removed
- [ ] Documentation updated
- [ ] No user-reported issues after 2 weeks
- [ ] Performance baseline established

---

## 10. Timeline Summary (Multi-Agent Priority)

| Phase | Focus | Duration | Milestone |
|-------|-------|----------|-----------|
| Phase 0 | Foundation | 2-4 weeks | Infrastructure ready |
| Phase 1 | **Multi-Agent Core** | 6-8 weeks | **Parallel agents working!** |
| Phase 2 | Merge & Aggregate | 4-6 weeks | **Feature PRs from agents** |
| Phase 3 | Single-Agent Polish | 4-6 weeks | Improved individual agents |
| Phase 4 | Watch Mode (Optional) | 4-6 weeks | Automated GitHub loop |
| Phase 5 | Full Migration (Optional) | 4-6 weeks | Complete transition |

**Core Value Delivery (Phases 0-2)**: ~16 weeks (~4 months)

**Full Migration (All Phases)**: ~9 months (with buffer)

**Key Insight**: By front-loading multi-agent orchestration (Phases 1-2), we deliver the strategic value within 4 months. Phases 3-5 are refinements that can be deferred or parallelized.

---

## 11. Decision Points

### 11.1 Go/No-Go Criteria

**Phase 0 → Phase 1**:
- Infrastructure stable for 1 week
- All team members trained
- Test framework operational

**Phase 1 → Phase 2**:
- Multi-agent orchestration working with 5+ agents
- Orchestrator survives restart
- No critical bugs in child workflow coordination

**Phase 2 → Phase 3**:
- Feature PRs successfully created from agent work
- Merge workflow stable
- Team confident in multi-agent value

**Phase 3 → Phase 4** (Optional):
- Single-agent workflow stable
- Resources available
- Watch mode improvement needed

**Phase 4 → Phase 5** (Optional):
- Watch mode stable 4+ weeks
- All functionality validated
- Stakeholder approval for cleanup

### 11.2 Abort Criteria

Consider aborting migration if:
- Ruby SDK has critical unfixable bugs
- Performance regression > 25%
- Child workflow coordination unreliable after 4 weeks
- Operational overhead unmanageable
- Team unable to maintain both systems

### 11.3 Early Win Criteria

**Migration is successful at Phase 2 if**:
- Multi-agent orchestration handles 10+ parallel agents
- Feature PRs created automatically from agent work
- Failure isolation works (failed agents don't block others)
- Real-time visibility into orchestration progress

At this point, even without completing Phases 3-5, the strategic value of Temporal has been realized.
