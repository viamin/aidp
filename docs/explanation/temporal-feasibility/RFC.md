# RFC: Temporal.io Adoption for Aidp Workflow Orchestration

**RFC Number**: 001
**Title**: Replace Native Ruby Orchestration with Temporal.io
**Author**: Feasibility Study Team
**Status**: Proposal
**Created**: 2026-01-20
**Updated**: 2026-01-20

---

## Abstract

This RFC proposes adopting Temporal.io as the workflow orchestration engine for Aidp, replacing the current native Ruby implementation. The change would provide improved durability, observability, and fault tolerance for Aidp's AI development workflows.

---

## 1. Motivation

### 1.1 Current Challenges

Aidp's native orchestration has served well but faces limitations:

1. **Durability Gaps**: File-based checkpoints with manual recovery
2. **Observability Limitations**: No unified workflow history or replay
3. **Recovery Complexity**: Manual intervention required after crashes
4. **Scaling Constraints**: Thread/process-based parallelism limits
5. **Operational Burden**: PID tracking, stuck detection, daemon management

### 1.2 Business Value

| Benefit | Impact |
|---------|--------|
| Reduced data loss | Higher user trust |
| Better debugging | Faster issue resolution |
| Automatic recovery | Reduced ops burden |
| Workflow visibility | Better understanding of AI execution |

---

## 2. Proposal

### 2.1 Overview

Replace Aidp's orchestration subsystem with Temporal.io:

- **WorkLoopRunner** → Temporal Workflow
- **AsyncWorkLoopRunner** → Temporal Workflow + Signals
- **BackgroundRunner** → Async Workflow Start
- **WorkstreamExecutor** → Child Workflows
- **Watch::Runner** → Scheduled Workflow

### 2.2 Key Changes

1. **Add Ruby SDK Dependency**: `temporalio` gem
2. **Introduce Workflow Definitions**: New `lib/aidp/temporal/workflows/`
3. **Implement Activities**: CLI execution, tests, Git operations
4. **Create Worker Process**: Long-running Temporal worker
5. **Add Orchestration Router**: Feature flag between native/Temporal
6. **Deploy Temporal Service**: Self-hosted with PostgreSQL

### 2.3 What Stays the Same

- CLI interface and commands
- Provider abstraction layer
- AI agent execution patterns
- Configuration system
- Watch mode behavior (from user perspective)

---

## 3. Technical Design

### 3.1 Workflow Architecture

```
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
|----------------|-------------------|
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

### 4.1 Phases

| Phase | Focus | Duration |
|-------|-------|----------|
| Phase 0 | Infrastructure setup | 2-4 weeks |
| Phase 1 | WorkLoopWorkflow PoC | 4-6 weeks |
| Phase 2 | Core workflows | 8-12 weeks |
| Phase 3 | Watch mode | 6-8 weeks |
| Phase 4 | Full migration | 4-6 weeks |

### 4.2 Incremental Adoption

1. **Feature Flag**: `orchestration.engine: native | temporal`
2. **Parallel Operation**: Both engines available
3. **Gradual Rollout**: Opt-in per project
4. **Deprecation Period**: Native remains available

### 4.3 Rollback Plan

- Revert feature flag to `native`
- Keep native code through stabilization period
- No data migration required (workflows are independent)

---

## 5. Operational Impact

### 5.1 New Dependencies

| Dependency | Purpose |
|------------|---------|
| Temporal Service | Workflow orchestration |
| PostgreSQL | Event history persistence |
| Prometheus | Metrics collection |
| Grafana | Dashboards |

### 5.2 Infrastructure Requirements

| Environment | Setup |
|-------------|-------|
| Development | Docker Compose |
| Production | Kubernetes (Helm) or Docker Compose |

### 5.3 Monitoring Changes

| Current | With Temporal |
|---------|---------------|
| Log files | Temporal Web UI |
| PID tracking | Workflow state |
| File-based checkpoints | Event history |
| Manual metrics | Prometheus/Grafana |

---

## 6. Risks and Mitigations

### 6.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Ruby SDK bugs | Medium | High | Pin versions; keep native fallback |
| Non-determinism issues | Medium | High | Strict Activity boundaries |
| Performance regression | Low | Medium | Benchmarking; optimization |

### 6.2 Operational Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Infrastructure complexity | Medium | High | Start with Docker Compose |
| Team learning curve | High | Medium | Training; documentation |
| Maintenance burden | Medium | Medium | Use managed DB in production |

### 6.3 Project Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
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
|----------|---------|
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
|-----------|-------------|
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
|-------|----------------------|
| Phase 0 | 4 |
| Phase 1 | 6 |
| Phase 2 | 12 |
| Phase 3 | 8 |
| Phase 4 | 6 |
| **Total** | **36 person-weeks** |

### 10.2 Infrastructure Cost (Self-Hosted)

| Component | Monthly Cost |
|-----------|--------------|
| Temporal Service | ~$100 |
| PostgreSQL | ~$60 |
| Workers | ~$120 |
| **Total** | **~$280/month** |

---

## 11. Decision

### 11.1 Recommendation

**Conditionally Recommended**

Temporal adoption provides significant benefits for durability, observability, and fault tolerance. However, the decision should be based on:

**Adopt If**:
- Durability is a critical requirement
- Team has capacity for 9-month investment
- Scaling beyond single-user is planned
- Observability gaps are causing issues

**Defer If**:
- Current implementation meets needs
- Team lacks Temporal expertise
- Infrastructure complexity is a concern
- Ruby SDK maturity is insufficient

### 11.2 Next Steps (If Approved)

1. Form implementation team
2. Begin Phase 0 (infrastructure setup)
3. Schedule team training
4. Establish success metrics
5. Create detailed sprint plans

---

## 12. References

### 12.1 Feasibility Study Documents

- [ARCHITECTURE_REPORT.md](./ARCHITECTURE_REPORT.md) - Architecture analysis
- [WORKFLOW_MAPPING.md](./WORKFLOW_MAPPING.md) - Concept mapping
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
|------|------------|
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
|------|------|----------|------|
| Technical Lead | | Pending | |
| Product Owner | | Pending | |
| Operations Lead | | Pending | |

---

*This RFC is part of the Temporal Feasibility Study. Please refer to the accompanying documents for detailed technical analysis.*
