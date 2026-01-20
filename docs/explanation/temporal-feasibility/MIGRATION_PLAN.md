# Temporal Feasibility Study: Migration Plan

This document provides a stepwise migration plan for adopting Temporal.io in Aidp, including risks, mitigations, and rollout strategy.

---

## 1. Migration Philosophy

### 1.1 Key Principles

1. **Incremental Adoption**: Migrate one workflow at a time
2. **Parallel Operation**: Run Temporal and native modes simultaneously
3. **Feature Flags**: Toggle between implementations
4. **Zero Breaking Changes**: Existing CLI interface unchanged
5. **Rollback Capability**: Easy revert at every stage

### 1.2 Migration Phases

| Phase | Duration | Focus |
|-------|----------|-------|
| Phase 0: Foundation | 2-4 weeks | Infrastructure setup, SDK integration |
| Phase 1: Proof of Concept | 4-6 weeks | Single WorkLoopWorkflow migration |
| Phase 2: Core Workflows | 8-12 weeks | All work loop variants |
| Phase 3: Watch Mode | 6-8 weeks | Watch mode and processors |
| Phase 4: Full Migration | 4-6 weeks | Deprecate native orchestration |

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

## 3. Phase 1: Proof of Concept

### 3.1 WorkLoopWorkflow Migration

**Objectives**:
- Migrate `WorkLoopRunner` to Temporal Workflow
- Validate durability and recovery
- Benchmark performance

**Tasks**:

| Task | Description | Effort |
|------|-------------|--------|
| Define WorkLoopWorkflow | Port state machine to Temporal | 3-5 days |
| Implement ExecuteAgentActivity | CLI execution activity | 2-3 days |
| Implement RunTestsActivity | Test runner activity | 1-2 days |
| Implement RunLinterActivity | Linter activity | 1-2 days |
| Add Signal handlers | pause, resume, cancel | 1-2 days |
| Add Query handlers | status, metrics | 1 day |
| Unit tests | Workflow and Activity tests | 3-4 days |
| Integration tests | End-to-end workflow tests | 3-4 days |
| Benchmarking | Compare with native implementation | 2-3 days |

**Success Criteria**:
- [ ] Work loop completes successfully
- [ ] Worker restart resumes execution
- [ ] Signals correctly pause/resume workflow
- [ ] Queries return accurate status
- [ ] No performance regression (< 10% overhead)

### 3.2 Worker Implementation

```ruby
# lib/aidp/temporal/worker.rb
module Aidp
  module Temporal
    class Worker
      def initialize(config)
        @client = Temporalio::Client.connect(config[:address])
        @worker = Temporalio::Worker.new(
          client: @client,
          task_queue: config[:task_queue],
          workflows: [WorkLoopWorkflow],
          activities: [
            ExecuteAgentActivity,
            RunTestsActivity,
            RunLinterActivity,
            PrepareNextIterationActivity
          ]
        )
      end

      def run
        @worker.run
      end
    end
  end
end
```

### 3.3 Testing Strategy

```ruby
# spec/temporal/workflows/work_loop_workflow_spec.rb
RSpec.describe Aidp::Temporal::WorkLoopWorkflow do
  let(:env) { Temporalio::Testing::WorkflowEnvironment.new }

  it "completes after successful iteration" do
    result = env.run_workflow(
      described_class,
      "test_step",
      { name: "test" },
      {}
    )

    expect(result[:status]).to eq("completed")
  end

  it "handles pause signal" do
    handle = env.start_workflow(described_class, ...)
    handle.signal("pause")

    status = handle.query("status")
    expect(status[:paused]).to be true
  end

  it "recovers from worker restart" do
    # Start workflow
    handle = env.start_workflow(described_class, ...)

    # Wait for first iteration
    env.time_skip(10.seconds)

    # Simulate worker restart
    env.restart_worker

    # Workflow should continue
    result = handle.result
    expect(result[:status]).to eq("completed")
  end
end
```

### 3.4 Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Activity timeout issues | Medium | Medium | Tune timeouts; add heartbeats |
| Non-determinism bugs | Medium | High | Strict Activity boundaries; testing |
| CLI output capture | Low | Medium | Test with all providers |

---

## 4. Phase 2: Core Workflows

### 4.1 AsyncWorkLoop Migration

**Objective**: Migrate `AsyncWorkLoopRunner` functionality

Since Temporal workflows are inherently asynchronous, this is mostly a client-side change:

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
```

### 4.2 BackgroundRunner Migration

**Objective**: Replace daemonized processes with Temporal workflows

| Current Feature | Temporal Equivalent |
|-----------------|---------------------|
| `start(mode, options)` | `client.start_workflow(...)` |
| `list_jobs` | `client.list_workflows(...)` |
| `job_status(id)` | `client.describe_workflow(id)` |
| `stop_job(id)` | `client.cancel_workflow(id)` |
| `job_logs(id)` | Activity heartbeat messages + UI |

```ruby
# lib/aidp/temporal/job_manager.rb
class JobManager
  def start(mode, options)
    workflow_class = case mode
      when :execute then WorkLoopWorkflow
      when :analyze then AnalyzeWorkflow
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

  def list_jobs
    @client.list_workflows(
      query: 'WorkflowType STARTS_WITH "Aidp"'
    ).map { |info| format_job_info(info) }
  end
end
```

### 4.3 WorkstreamExecutor Migration

**Objective**: Replace fork-based parallelism with Child Workflows

This is the most complex migration as it involves:
1. Parent workflow orchestrating children
2. Parallel execution management
3. Result aggregation

**Tasks**:

| Task | Description | Effort |
|------|-------------|--------|
| WorkstreamOrchestratorWorkflow | Parent workflow | 2-3 days |
| WorkstreamChildWorkflow | Child workflow | 2-3 days |
| CreateWorktreeActivity | Git worktree management | 1-2 days |
| Result aggregation | Fan-in logic | 1-2 days |
| Integration tests | Multi-workflow tests | 3-4 days |

### 4.4 Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Child workflow coordination | Medium | High | Test Continue-As-New scenarios |
| Git worktree state | Medium | Medium | Activity-based worktree ops |
| Resource exhaustion | Low | High | Limit concurrent children |

---

## 5. Phase 3: Watch Mode

### 5.1 Watch Mode Migration

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
class WatchModeWorkflow
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

### 5.2 Processor Migration

Each processor becomes a Child Workflow:

| Processor | Child Workflow |
|-----------|---------------|
| PlanProcessor | PlanProcessorWorkflow |
| BuildProcessor | BuildProcessorWorkflow |
| ReviewProcessor | ReviewProcessorWorkflow |
| CiFixProcessor | CiFixProcessorWorkflow |
| ChangeRequestProcessor | ChangeRequestProcessorWorkflow |

### 5.3 Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Event History growth | High | Medium | Continue-As-New at 100 cycles |
| GitHub API rate limits | Medium | Medium | Activity-level rate limiting |
| Long-running stability | Medium | High | Extensive testing; monitoring |

---

## 6. Phase 4: Full Migration

### 6.1 Deprecation Strategy

1. **Announcement**: Document migration in CHANGELOG
2. **Warning Period**: Log deprecation warnings for native mode
3. **Default Switch**: Change default from `native` to `temporal`
4. **Removal**: Remove native orchestration code

### 6.2 Cleanup Tasks

| Task | Description |
|------|-------------|
| Remove `AsyncWorkLoopRunner` | Replaced by Temporal |
| Remove `BackgroundRunner` | Replaced by Temporal |
| Remove `WorkstreamExecutor` | Replaced by Child Workflows |
| Update documentation | New orchestration docs |
| Archive legacy tests | Remove native-only tests |

### 6.3 Rollback Plan

If issues arise post-migration:

1. **Feature Flag Revert**: Change `orchestration.engine` to `native`
2. **Keep Native Code**: Don't delete until confident (Phase 4+)
3. **Data Migration**: Export workflow history if needed
4. **Worker Shutdown**: Gracefully drain Temporal workers

---

## 7. Risk Registry

### 7.1 Technical Risks

| ID | Risk | Likelihood | Impact | Mitigation | Owner |
|----|------|------------|--------|------------|-------|
| T1 | Ruby SDK bugs | Medium | High | Pin version; fallback | Dev Team |
| T2 | Non-determinism | Medium | High | Strict Activity boundaries | Dev Team |
| T3 | Performance regression | Low | Medium | Benchmarking | Dev Team |
| T4 | Activity timeouts | Medium | Medium | Heartbeats; tuning | Dev Team |
| T5 | State migration | High | Medium | Don't migrate; start fresh | Dev Team |

### 7.2 Operational Risks

| ID | Risk | Likelihood | Impact | Mitigation | Owner |
|----|------|------------|--------|------------|-------|
| O1 | Infrastructure complexity | Medium | High | Docker Compose first | Ops Team |
| O2 | Database management | Medium | Medium | Managed PostgreSQL | Ops Team |
| O3 | Monitoring gaps | Medium | Medium | Prometheus/Grafana | Ops Team |
| O4 | Team expertise | High | Medium | Training program | Team Lead |

### 7.3 Project Risks

| ID | Risk | Likelihood | Impact | Mitigation | Owner |
|----|------|------------|--------|------------|-------|
| P1 | Scope creep | Medium | Medium | Strict phase gates | PM |
| P2 | Timeline slip | Medium | Medium | Buffer in estimates | PM |
| P3 | Parallel workload | Medium | High | Dedicated resources | PM |

---

## 8. Success Metrics

### 8.1 Phase 0 Success

- [ ] Temporal Service running in dev/staging
- [ ] Ruby SDK integrated and tested
- [ ] CI pipeline passing
- [ ] Team trained on Temporal basics

### 8.2 Phase 1 Success

- [ ] WorkLoopWorkflow passes all tests
- [ ] Worker restart recovers execution < 5s
- [ ] Performance within 10% of native
- [ ] Signals work correctly

### 8.3 Phase 2 Success

- [ ] All work loop variants migrated
- [ ] Background jobs work via Temporal
- [ ] Workstream parallelism functional
- [ ] No regressions in existing functionality

### 8.4 Phase 3 Success

- [ ] Watch mode runs 24+ hours without issues
- [ ] Event history stays within limits
- [ ] All processors work as Child Workflows
- [ ] Monitoring shows healthy metrics

### 8.5 Phase 4 Success

- [ ] Native code removed
- [ ] Documentation updated
- [ ] No user-reported issues after 2 weeks
- [ ] Performance baseline established

---

## 9. Timeline Summary

| Phase | Start | End | Milestone |
|-------|-------|-----|-----------|
| Phase 0 | Week 1 | Week 4 | Infrastructure ready |
| Phase 1 | Week 5 | Week 10 | WorkLoopWorkflow in production |
| Phase 2 | Week 11 | Week 22 | All core workflows migrated |
| Phase 3 | Week 23 | Week 30 | Watch mode migrated |
| Phase 4 | Week 31 | Week 36 | Migration complete |

**Total Duration**: ~9 months (with buffer)

---

## 10. Decision Points

### 10.1 Go/No-Go Criteria

**Phase 0 → Phase 1**:
- Infrastructure stable for 1 week
- All team members trained
- Test framework operational

**Phase 1 → Phase 2**:
- WorkLoopWorkflow in production 2+ weeks
- No critical bugs
- Performance acceptable

**Phase 2 → Phase 3**:
- All core workflows stable
- No rollbacks required
- Team confident

**Phase 3 → Phase 4**:
- Watch mode stable 4+ weeks
- All functionality validated
- Stakeholder approval

### 10.2 Abort Criteria

Consider aborting migration if:
- Ruby SDK has critical unfixable bugs
- Performance regression > 25%
- Operational overhead unmanageable
- Team unable to maintain both systems
