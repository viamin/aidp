# RFC: Temporal.io Adoption for Aidp Workflow Orchestration

**RFC Number**: 001
**Title**: Replace Native Ruby Orchestration with Temporal.io
**Author**: Feasibility Study Team
**Status**: Proposal
**Created**: 2026-01-20
**Updated**: 2026-01-20

---

## Abstract

This RFC proposes adopting Temporal.io as the workflow orchestration engine for Aidp, replacing the current native Ruby implementation. The change is **strongly recommended** to enable Aidp's strategic direction toward **multi-agent orchestration** - where multiple parallel agents work on atomic units that combine into feature-complete PRs.

---

## 1. Motivation

### 1.1 Strategic Direction: Multi-Agent Orchestration

Aidp is evolving toward a model where complex features are decomposed into atomic units, with multiple AI agents working in parallel. This multi-agent approach requires:

1. **Hierarchical Workflow Coordination**: Parent orchestrator managing 10-50+ child agents
2. **Failure Isolation**: One agent failure shouldn't crash the entire operation
3. **Partial Retry**: Retry only failed agents without re-running successful ones
4. **Visibility**: Real-time status across all parallel agents
5. **Durability**: Orchestrator state survives crashes and restarts
6. **Merge Coordination**: Combining atomic unit branches into feature PRs

### 1.2 Current Architecture Limitations

Aidp's native orchestration cannot support multi-agent orchestration at scale:

| Gap | Impact |
| --- | ------ |
| Fork-based parallelism | No failure isolation; one crash affects all |
| 2-level hierarchy limit | Can't support recursive agent decomposition |
| No partial retry | Failed agent requires restarting entire operation |
| File-based checkpoints | Manual recovery; no automatic resume |
| No unified history | Debugging multi-agent failures is difficult |
| PID-based tracking | Unreliable for 50+ parallel agents |

### 1.3 Business Value

| Benefit | Impact |
| ------- | ------ |
| **Multi-agent orchestration** | Enable parallel agent development at scale |
| Failure isolation | Individual agent failures don't block others |
| Automatic recovery | Orchestrator survives crashes |
| Real-time visibility | Track 50+ agents simultaneously |
| Reduced data loss | Higher user trust |
| Better debugging | Faster issue resolution |

### 1.4 Research Alignment

Temporal's hierarchical workflow model aligns with emerging AI research:

- **Recursive Agents**: Child Workflows support self-referencing decomposition
- **Prompt Decomposition**: Sequential, parallel, and hierarchical patterns
- **Multi-Agent Coordination**: First-class support for agent-to-agent communication

---

## 2. Proposal

### 2.1 Overview

Replace Aidp's orchestration subsystem with Temporal.io, prioritizing multi-agent orchestration:

**Multi-Agent Orchestration (Primary)**:

- **FeatureOrchestrationWorkflow** → Coordinate 10-50+ parallel agents
- **AtomicUnitWorkflow** → Individual agent executing atomic work
- **MergeOrchestrationWorkflow** → Combine agent results into feature PRs

**Single-Agent Improvements (Secondary)**:

- **WorkLoopRunner** → Temporal Workflow with durability
- **AsyncWorkLoopRunner** → Temporal Workflow + Signals
- **BackgroundRunner** → Async Workflow Start

**Optional**:

- **Watch::Runner** → Scheduled Workflow (can defer)

### 2.2 Key Changes

1. **Add Ruby SDK Dependency**: `temporalio` gem
2. **Introduce Workflow Definitions**: New `lib/aidp/temporal/workflows/`
3. **Implement Multi-Agent Orchestration**: Parent-child workflow hierarchy
4. **Implement Activities**: Agent execution, tests, Git operations, merges
5. **Create Worker Process**: Separate orchestrator and agent workers
6. **Add Orchestration Router**: Feature flag between native/Temporal
7. **Deploy Temporal Service**: Self-hosted with PostgreSQL

### 2.3 What Stays the Same

- CLI interface and commands
- Provider abstraction layer
- AI agent execution patterns (individual agents unchanged)
- Configuration system
- Watch mode behavior (from user perspective)

---

## 3. Technical Design

### 3.1 Workflow Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                        Aidp CLI                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   OrchestrationRouter                            │
│  (Feature flag: native vs temporal)                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Temporal Service                              │
│  (Self-hosted: PostgreSQL backend)                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Aidp Workers                                 │
│  (Workflows: WorkLoop, Workstream, WatchMode)                    │
│  (Activities: Agent, Tests, Lint, Git, GitHub)                   │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Workflow Mapping

| Aidp Component | Temporal Primitive |
| -------------- | ------------------ |
| Work Loop state machine | Workflow with loop |
| Agent execution | Activity |
| Test/lint execution | Activity |
| Pause/resume | Signals |
| Status queries | Queries |
| Parallel workstreams | Child Workflows |
| Watch mode polling | Scheduled Workflow |

### 3.3 Activity Boundaries

Activities encapsulate non-deterministic operations:

```ruby
# Example: Agent execution as Activity
class ExecuteAgentActivity < Temporalio::Activity
  def execute(prompt:, provider:, model:)
    # CLI execution - non-deterministic
    output = execute_agent_cli(provider, model, prompt)
    { status: "completed", output: output }
  end
end
```

### 3.4 Signal Handlers

```ruby
# Example: Pause/resume via Signals
workflow.signal_handler("pause") { @paused = true }
workflow.signal_handler("resume") { @paused = false }
workflow.signal_handler("cancel") { @cancelled = true }
workflow.signal_handler("inject_instruction") { |i| @queue << i }
```

---

## 4. Migration Strategy

### 4.1 Phases (Multi-Agent Priority)

| Phase | Focus | Duration | Value |
| ----- | ----- | -------- | ----- |
| Phase 0 | Infrastructure setup | 2-4 weeks | Temporal running |
| Phase 1 | **Multi-Agent Core** | 6-8 weeks | **Parallel agents work!** |
| Phase 2 | **Merge & Aggregate** | 4-6 weeks | **Feature PRs from agents** |
| Phase 3 | Single-Agent Polish | 4-6 weeks | Improved individual agents |
| Phase 4 | Watch Mode (Optional) | 4-6 weeks | Automated GitHub loop |
| Phase 5 | Full Migration (Optional) | 4-6 weeks | Complete transition |

**Core Value Delivery (Phases 0-2)**: ~16 weeks (~4 months)

**Full Migration (All Phases)**: ~9 months (with buffer)

### 4.2 Incremental Adoption

1. **Feature Flag**: `orchestration.engine: native | temporal`
2. **Multi-Agent First**: New capability, not migration
3. **Parallel Operation**: Both engines available
4. **Gradual Rollout**: Opt-in per project
5. **Deprecation Period**: Native remains available

### 4.3 Rollback Plan

- Revert feature flag to `native`
- Keep native code through stabilization period
- No data migration required (workflows are independent)
- Multi-agent features gracefully degrade to sequential execution

---

## 5. Operational Impact

### 5.1 New Dependencies

| Dependency | Purpose |
| ---------- | ------- |
| Temporal Service | Workflow orchestration |
| PostgreSQL | Event history persistence |
| Prometheus | Metrics collection |
| Grafana | Dashboards |

### 5.2 Infrastructure Requirements

| Environment | Setup |
| ----------- | ----- |
| Development | Docker Compose |
| Production | Kubernetes (Helm) or Docker Compose |

### 5.3 Monitoring Changes

| Current | With Temporal |
| ------- | ------------- |
| Log files | Temporal Web UI |
| PID tracking | Workflow state |
| File-based checkpoints | Event history |
| Manual metrics | Prometheus/Grafana |

---

## 6. Risks and Mitigations

### 6.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| Ruby SDK bugs | Medium | High | Pin versions; keep native fallback |
| Non-determinism issues | Medium | High | Strict Activity boundaries |
| Performance regression | Low | Medium | Benchmarking; optimization |

### 6.2 Operational Risks

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| Infrastructure complexity | Medium | High | Start with Docker Compose |
| Team learning curve | High | Medium | Training; documentation |
| Maintenance burden | Medium | Medium | Use managed DB in production |

### 6.3 Project Risks

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| Scope creep | Medium | Medium | Strict phase gates |
| Timeline slip | Medium | Medium | Buffer in estimates |

---

## 7. Alternatives Considered

### 7.1 Enhance Native Orchestration

**Pros**:

- No new dependencies
- Team familiarity
- Lower complexity

**Cons**:

- Significant effort to achieve durability
- Custom observability needed
- Limited replay capabilities

**Decision**: Native enhancement would require rebuilding many Temporal features from scratch.

### 7.2 Temporal Cloud (Managed)

**Pros**:

- No infrastructure management
- SLA guarantees
- Multi-region support

**Cons**:

- Higher cost
- Data locality concerns
- Less control

**Decision**: Self-hosted provides more control; can migrate to Cloud later.

### 7.3 Other Orchestration Platforms

| Platform | Why Not |
| -------- | ------- |
| Apache Airflow | DAG-based; less suited for dynamic workflows |
| Prefect | Python-focused; limited Ruby support |
| Argo Workflows | Kubernetes-native; higher complexity |

**Decision**: Temporal's Ruby SDK and workflow model best fit Aidp's needs.

---

## 8. Success Criteria

### 8.1 Functional Requirements

- [ ] Work loops complete successfully via Temporal
- [ ] Signals correctly pause/resume/cancel workflows
- [ ] Queries return accurate status
- [ ] Worker restart recovers execution
- [ ] Workstreams execute in parallel

### 8.2 Non-Functional Requirements

- [ ] Latency within 10% of native implementation
- [ ] Recovery time < 5 seconds after worker restart
- [ ] Event history visible in Web UI
- [ ] Metrics exported to Prometheus

### 8.3 Acceptance Criteria

- [ ] All existing tests pass with Temporal
- [ ] No user-reported regressions after 2 weeks
- [ ] Documentation complete
- [ ] Team trained on operations

---

## 9. Timeline

| Milestone | Target Date |
| --------- | ----------- |
| RFC Approval | Week 0 |
| Phase 0 Complete | Week 4 |
| Phase 1 Complete | Week 10 |
| Phase 2 Complete | Week 22 |
| Phase 3 Complete | Week 30 |
| Migration Complete | Week 36 |

**Total Duration**: ~9 months

---

## 10. Cost Estimate

### 10.1 Development Cost

| Phase | Effort (person-weeks) |
| ----- | --------------------- |
| Phase 0 | 4 |
| Phase 1 | 6 |
| Phase 2 | 12 |
| Phase 3 | 8 |
| Phase 4 | 6 |
| **Total** | **36 person-weeks** |

### 10.2 Infrastructure Cost (Self-Hosted)

| Component | Monthly Cost |
| --------- | ------------ |
| Temporal Service | ~$100 |
| PostgreSQL | ~$60 |
| Workers | ~$120 |
| **Total** | **~$280/month** |

---

## 11. Decision

### 11.1 Recommendation

**Strongly Recommended** ⭐

Temporal adoption is strongly recommended because Aidp's strategic direction toward **multi-agent orchestration** requires capabilities that cannot be reasonably achieved with the current native implementation:

| Requirement | Native Capability | Temporal Capability |
| ----------- | ----------------- | ------------------- |
| 10-50+ parallel agents | Fork-based, fragile | First-class Child Workflows |
| Failure isolation | Not available | Per-child error handling |
| Partial retry | Not available | Retry individual workflows |
| Orchestrator durability | File checkpoints | Automatic event sourcing |
| Real-time visibility | PID tracking | Web UI + Queries |
| Recursive decomposition | 2-level limit | Arbitrary depth |

### 11.2 Key Arguments for Adoption

1. **Multi-Agent is the Direction**: Temporal's Child Workflow pattern is purpose-built for this use case
2. **Cannot Build Equivalent**: Adding these features to native would essentially rebuild Temporal
3. **Value Delivered Early**: Multi-agent capability in ~4 months (Phases 0-2)
4. **Research Alignment**: Supports recursive agents and prompt decomposition patterns
5. **Future-Proof**: Investment in proven infrastructure vs. custom code

### 11.3 Risks Acknowledged

- Ruby SDK is pre-release (January 2025)
- Infrastructure complexity
- Team learning curve

These risks are mitigated by:

- Pinning SDK version with native fallback
- Starting with Docker Compose
- Training before Phase 1

### 11.4 Next Steps (If Approved)

1. Form implementation team (2-3 engineers)
2. Begin Phase 0 (infrastructure setup)
3. Schedule team training on Temporal concepts
4. Establish success metrics for Phase 1 (multi-agent core)
5. Create detailed sprint plans for Phases 0-2

---

## 12. References

### 12.1 Feasibility Study Documents

- [ARCHITECTURE_REPORT.md](./ARCHITECTURE_REPORT.md) - Architecture analysis
- [WORKFLOW_MAPPING.md](./WORKFLOW_MAPPING.md) - Concept mapping
- [GAP_ANALYSIS.md](./GAP_ANALYSIS.md) - Multi-agent implementation gaps
- [MIGRATION_PLAN.md](./MIGRATION_PLAN.md) - Migration strategy
- [INTEGRATION_API.md](./INTEGRATION_API.md) - API design
- [DEPLOYMENT_NOTES.md](./DEPLOYMENT_NOTES.md) - Deployment guide

### 12.2 External Resources

- [Temporal Ruby SDK](https://docs.temporal.io/develop/ruby)
- [Temporal Self-Hosted Guide](https://docs.temporal.io/self-hosted-guide)
- [Temporal Best Practices](https://docs.temporal.io/production-deployment)

---

## 13. Appendix

### 13.1 Glossary

| Term | Definition |
| ---- | ---------- |
| Workflow | Durable function that orchestrates Activities |
| Activity | Non-deterministic operation (I/O, CLI, API) |
| Signal | Asynchronous message to running Workflow |
| Query | Read-only request to Workflow state |
| Worker | Process that executes Workflows and Activities |
| Task Queue | Queue that routes work to Workers |

### 13.2 Q&A

**Q: Why Temporal over building our own durability layer?**
A: Temporal provides battle-tested durability, replay, and observability that would take significant effort to build and maintain.

**Q: What happens to existing checkpoints?**
A: Existing checkpoints are not migrated. Temporal maintains its own event history. In-progress work would need to restart.

**Q: Can we run both engines simultaneously?**
A: Yes, the OrchestrationRouter allows per-project engine selection.

**Q: What's the minimum Temporal deployment?**
A: Single-node Docker Compose with PostgreSQL for development/small production.

**Q: How do we handle Ruby SDK issues?**
A: Pin SDK version, maintain native fallback, report issues upstream.

---

## Approval

| Role | Name | Decision | Date |
| ---- | ---- | -------- | ---- |
| Technical Lead | | Pending | |
| Product Owner | | Pending | |
| Operations Lead | | Pending | |

---

*This RFC is part of the Temporal Feasibility Study. Please refer to the accompanying documents for detailed technical analysis.*
