# Bitter-Lesson-Oriented Architecture

This document describes the substrate added for issue `#464`.

## Primitives

- `Aidp::StrategyExecution::StrategySpec`
  Externalized strategy schema loaded from YAML. A strategy defines recursion depth, speculative fanout, agent commands, evaluator commands, merge policy, and optional constraints/timeouts.
- `Aidp::StrategyExecution::CliProtocol::Runner`
  Standard JSON-over-stdin/stdout protocol for agents and evaluators. Each invocation receives a protocol version, task payload, strategy metadata, and an artifact directory. Responses may include output, subtasks, artifacts, scores, pass/fail, and metadata. `stderr` is preserved as logs.
- `Aidp::StrategyExecution::ExperienceStore`
  Replay-oriented persistence layer backed by SQLite. It records strategies, tasks, runs, branch runs, artifacts, evaluations, and embeddings.

## Temporal Integration

- `Aidp::Temporal::Workflows::StrategyExecutionWorkflow`
  Parent workflow that executes a strategy as data. It registers the strategy, creates or reuses a replayable task, fans out speculative branch workflows, selects the winning branch via evaluator scores, and recursively executes discovered subtasks up to `max_depth`.
- `Aidp::Temporal::Workflows::StrategyBranchWorkflow`
  Child workflow for one speculative branch. It runs the configured agent CLI, runs evaluators, records artifacts/evaluations in the experience store, and returns an aggregate score to the parent.
- `Aidp::Temporal::Activities::ExecuteCliCommandActivity`
  Generic activity for invoking agent and evaluator CLIs through the protocol.
- `Aidp::Temporal::Activities::ManageExperienceStoreActivity`
  Activity for recording strategy/task/run/evaluation/artifact data and for loading replay bundles.

## Replay And Benchmarking

- `aidp temporal start strategy <strategy.yml> [task.json]`
  Starts a generic strategy workflow.
- `aidp temporal replay <run_id> <strategy.yml>`
  Replays a historical task from the experience store with a new strategy.
- `aidp temporal benchmark <strategy.yml> <run_id> [run_id...]`
  Starts multiple replay workflows for objective comparison across the same historical tasks.

## Experience Store Schema

Migration `V4_STRATEGY_EXECUTION` adds:

- `strategies`
- `experience_tasks`
- `experience_runs`
- `experience_evaluations`
- `experience_artifacts`
- `experience_embeddings`

The schema is intentionally general so future meta-optimization can search over strategies without changing the storage model.
