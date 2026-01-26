# Temporal.io Feasibility Study for Aidp

This directory contains a comprehensive feasibility study evaluating whether Aidp should replace its native Ruby workflow orchestration with Temporal.io workflows running in a self-hosted environment.

## Executive Summary

**Recommendation: Strongly Recommended** ⭐

Temporal adoption is strongly recommended to enable Aidp's strategic direction toward **multi-agent orchestration** - where multiple parallel agents work on atomic units that combine into feature-complete PRs. The current native implementation cannot support this at scale due to limitations in failure isolation, partial retry, and hierarchical workflow coordination.

**Core value delivered in ~4 months** (Phases 0-2), with full migration taking ~9 months.

## Documents

| Document | Description |
| -------- | ----------- |
| [ARCHITECTURE_REPORT.md](./ARCHITECTURE_REPORT.md) | Overview of current Aidp architecture, pain points, and proposed Temporal architecture |
| [WORKFLOW_MAPPING.md](./WORKFLOW_MAPPING.md) | Detailed mapping of Aidp concepts to Temporal primitives, including multi-agent and recursive patterns |
| [GAP_ANALYSIS.md](./GAP_ANALYSIS.md) | Critical gaps in current implementation for multi-agent orchestration |
| [MIGRATION_PLAN.md](./MIGRATION_PLAN.md) | Stepwise migration plan prioritizing multi-agent orchestration |
| [INTEGRATION_API.md](./INTEGRATION_API.md) | Proposed Ruby interface for Temporal integration |
| [DEPLOYMENT_NOTES.md](./DEPLOYMENT_NOTES.md) | Self-hosted Temporal deployment instructions |
| [RFC.md](./RFC.md) | Formal proposal to adopt Temporal in Aidp |

## Key Findings

### Current Architecture Strengths

- Well-designed concurrency primitives (`Backoff`, `Wait`, `Exec`)
- Thread-safe state management with MonitorMixin
- Fix-forward work loop pattern
- Process isolation for parallel workstreams

### Current Architecture Weaknesses (Multi-Agent Gaps)

- **No failure isolation**: Fork-based parallelism; one crash affects all agents
- **2-level hierarchy limit**: Cannot support recursive agent decomposition
- **No partial retry**: Failed agent requires restarting entire operation
- File-based checkpoints with manual recovery
- No unified workflow history for debugging multi-agent failures
- PID-based process tracking unreliable for 50+ parallel agents

### Temporal Benefits

- **First-class Child Workflows**: Perfect for multi-agent orchestration
- **Failure isolation**: Per-child error handling
- **Partial retry**: Retry individual agents without restarting others
- Automatic state persistence
- Deterministic replay
- Built-in observability (Web UI, metrics)
- Worker crash recovery
- Fine-grained retry policies

### Temporal Challenges

- Ruby SDK is pre-release (January 2025)
- Infrastructure complexity (database, workers)
- Team learning curve
- Activity determinism requirements

## Quick Links

- **Current Orchestration Code**:
  - `lib/aidp/execute/work_loop_runner.rb` - Main work loop
  - `lib/aidp/execute/async_work_loop_runner.rb` - Async execution
  - `lib/aidp/workstream_executor.rb` - Parallel execution
  - `lib/aidp/watch/runner.rb` - Watch mode
  - `lib/aidp/jobs/background_runner.rb` - Background jobs

- **Temporal Resources**:
  - [Ruby SDK Documentation](https://docs.temporal.io/develop/ruby)
  - [Ruby SDK GitHub](https://github.com/temporalio/sdk-ruby)
  - [Self-Hosted Guide](https://docs.temporal.io/self-hosted-guide)
  - [Best Practices](https://docs.temporal.io/production-deployment)

## Decision Criteria

### Adopt (Strongly Recommended)

- **Multi-agent orchestration is the strategic direction**
- Need to coordinate 10-50+ parallel agents
- Failure isolation required (one agent failure shouldn't block others)
- Partial retry capability needed
- Real-time visibility into orchestration progress

### Defer Only If

- Single-agent use cases are sufficient long-term
- Team cannot invest in 4-month core implementation
- Infrastructure complexity is a blocker
- Ruby SDK maturity is unacceptable (test in Phase 0)

## Timeline Summary (Multi-Agent Priority)

| Phase | Duration | Focus | Value |
| ----- | -------- | ----- | ----- |
| Phase 0 | 2-4 weeks | Infrastructure setup | Temporal running |
| Phase 1 | 6-8 weeks | **Multi-Agent Core** | **Parallel agents work!** |
| Phase 2 | 4-6 weeks | **Merge & Aggregate** | **Feature PRs from agents** |
| Phase 3 | 4-6 weeks | Single-Agent Polish | Better individual agents |
| Phase 4 | 4-6 weeks | Watch Mode (Optional) | Automated GitHub loop |
| Phase 5 | 4-6 weeks | Full Migration (Optional) | Complete transition |
| **Core Value** | **~4 months** | Phases 0-2 | Multi-agent orchestration |
| **Full Migration** | **~9 months** | All phases | Complete transition |

## Contact

For questions about this feasibility study, please open an issue in the Aidp repository.
