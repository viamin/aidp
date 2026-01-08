# SQLite Migration Plan for .aidp Directory

## Overview

This document outlines the migration from file-based storage in `.aidp/` to a single SQLite database (`aidp.db`), while preserving specific files that should remain as files.

## Audit Results & Rationale

This section documents the deep audit of each file type in `.aidp/` to verify active usage and determine whether to migrate to SQLite, remove as dead code, or keep as files.

### Files to Migrate to SQLite (Actively Used)

| File | Status | Rationale |
| ---- | ------ | --------- |
| `checkpoint.yml` | ✅ ACTIVE | Used by work loops (every 5 iterations), CLI `aidp checkpoint` commands, background job monitoring. Records iteration-level progress. |
| `checkpoint_history.jsonl` | ✅ ACTIVE | Append-only history used by `aidp checkpoint history` command. Essential for debugging and progress tracking. |
| `tasklist.jsonl` | ✅ ACTIVE | Critical for `task_completion_requirement` enforcement in work loops. Used by WorkLoopRunner, BuildProcessor, ChangeRequestProcessor. NOT superseded by GitHub Projects (different purpose). |
| `progress/execute.yml` | ✅ ACTIVE | Step completion tracking for execute mode. Used by Runner, StateManager, ConditionDetector. Core to workflow execution. |
| `progress/analyze.yml` | ✅ ACTIVE | Step completion tracking for analyze mode. Same architecture as execute progress. |
| `harness/*_state.json` | ✅ ACTIVE | Primary state management for execution context. Tracks user feedback, provider state, rate limits, token usage. NOT redundant with progress (complementary). |
| `workstreams/*/state.json` | ✅ ACTIVE | Core to parallel work execution via git worktrees. 13 CLI subcommands, 9 REPL macros. Actively maintained feature. |
| `workstreams/*/history.jsonl` | ✅ ACTIVE | Event log for workstream lifecycle (created, iteration, paused, resumed, completed). Essential for debugging. |
| `watch/*.yml` | ✅ ACTIVE | Critical for watch mode deduplication (prevents re-processing). Tracks plans, builds, reviews, CI fixes, change requests. 30+ read/write locations. |
| `worktrees.json` | ✅ ACTIVE | Registry for standard worktrees. Used by CLI, watch mode processors, cleanup jobs. Core to workstream feature. |
| `pr_worktrees.json` | ✅ ACTIVE | Registry for PR-specific worktrees. Used by ChangeRequestProcessor, CiFixProcessor, BuildProcessor. |
| `evaluations/*.json` | ✅ ACTIVE | Feedback collection system. 3 entry points: CLI, REPL `/rate`, GitHub reactions. Well-integrated feature. |
| `provider_metrics.yml` | ✅ ACTIVE | Persists provider performance metrics. Used for dashboard, load balancing, health tracking. Written on every provider call. |
| `provider_rate_limits.yml` | ✅ ACTIVE | Persists rate limit state. Critical for automatic failover between providers. |
| `secrets_registry.json` | ✅ ACTIVE | Security feature for credential proxying. 5 CLI commands. Only stores metadata, never actual secrets. |
| `prompt_archive/*.md` | ✅ ACTIVE | Write-only audit trail. Archives created on every prompt write (10+ call sites). Useful for debugging. |
| `jobs/*` | ✅ ACTIVE | Background job tracking (metadata, logs, PID). 7+ CLI commands for job management. Production-ready feature. |
| `deprecated_models.json` | ✅ ACTIVE | Runtime deprecation detection cache. Critical for model auto-upgrade. Used by Anthropic provider and RubyLLMRegistry. |
| `checkpoints/*.json` (auto-update) | ✅ ACTIVE | State recovery for auto-update process. Used by AutoUpdate::Coordinator for resumption. |
| `providers/*_info.yml` | ✅ ACTIVE | Caches provider capabilities (24h TTL). Used by `aidp providers info` command. |

### Files to Remove (Dead Code)

| File | Status | Rationale | Action |
| ---- | ------ | --------- | ------ |
| `security/audit.jsonl` | ❌ DEAD | Path defined in ConfigPaths but NEVER written or read. No implementation exists. | Remove `security_audit_log_file()` from ConfigPaths. Remove table from schema. |
| `security/mcp_risk_profile.yml` | ❌ DEAD | Planned AGD feature that was never implemented. Only exists in GitHub issue template. | Remove `mcp_risk_profile_file()` from ConfigPaths. Remove from migration scope. |
| `future_work.yml` | ❌ DEAD | FutureWorkBacklog class (412 lines) is never instantiated. Superseded by PersistentTasklist which is actively used. | Remove FutureWorkBacklog class and future_work table from schema. |
| `json/*.json` (JsonFileStorage) | ❌ DEAD | JsonFileStorage class (292 lines) is never instantiated. Complete implementation but never integrated. | Remove JsonFileStorage class. Keep FileManager which has minimal active usage. |

### Files with Minimal Usage (Consider Removal)

| File | Status | Rationale | Recommendation |
| ---- | ------ | --------- | -------------- |
| `model_cache/models.json` | ⚠️ MINIMAL | Only read in error path (ThinkingDepthManager). Never written in normal workflows. | Keep for now but consider deprecation. Low priority for migration. |

### Files to Keep as Files (No Migration)

| File | Reason | Notes |
| ---- | ------ | ----- |
| `aidp.yml` | User-editable configuration | Users may manually edit |
| `firewall-allowlist.yml` | User-editable security rules | Users may manually edit |
| `PROMPT.md` | Current prompt (user may view/edit) | Active work loop prompt |
| `docs/*.md` | Planning documents (WBS, GANTT, etc.) | Markdown for human consumption |
| `logs/*.log` | Log files (text-based, rotated) | Standard log file format |
| `grammars/*` | Binary tree-sitter grammar files | Binary data, not suitable for SQLite |
| `out/*` | Harness tool output files | Tool-specific output |
| `harness/*.lock` | Filesystem-level lock files | Required for process coordination |
| `kb/*.json` | Knowledge base (large, infrequently accessed) | Large files, tree-sitter cache |
| `work_loop/initial_units.txt` | Transient signaling file | Written by BuildProcessor, read and deleted by WorkLoopUnitScheduler. Transient coordination file. |

---

## Scope

### Files to Migrate to SQLite

| Current File | Data Type | Write Frequency | Migration Priority |
| ------------ | --------- | --------------- | ------------------ |
| `checkpoint.yml` | YAML | Frequent | High |
| `checkpoint_history.jsonl` | JSONL | Frequent | High |
| `tasklist.jsonl` | JSONL | Frequent | High |
| `worktrees.json` | JSON | On-demand | Medium |
| `pr_worktrees.json` | JSON | On-demand | Medium |
| `provider_metrics.yml` | YAML | Frequent | Medium |
| `provider_rate_limits.yml` | YAML | Frequent | Medium |
| `deprecated_models.json` | JSON | On-demand | Low |
| `progress/execute.yml` | YAML | Frequent | High |
| `progress/analyze.yml` | YAML | Frequent | High |
| `harness/*_state.json` | JSON | Frequent | High |
| `evaluations/*.json` + `index.json` | JSON | On-demand | Medium |
| `security/secrets_registry.json` | JSON | On-demand | Medium |
| ~~`security/audit.jsonl`~~ | ~~JSONL~~ | ~~On-demand~~ | ❌ REMOVE (dead code) |
| ~~`security/mcp_risk_profile.yml`~~ | ~~YAML~~ | ~~On-demand~~ | ❌ REMOVE (dead code) |
| `workstreams/*/state.json` | JSON | Frequent | High |
| `workstreams/*/history.jsonl` | JSONL | Frequent | High |
| `watch/*.yml` | YAML | Frequent | High |
| ~~`json/*.json` (analysis results)~~ | ~~JSON~~ | ~~On-demand~~ | ❌ REMOVE (dead code) |
| `providers/*_info.yml` | YAML | On-demand | Low |
| `model_cache/models.json` | JSON | On-demand | Low |
| `prompt_archive/*.md` | Markdown | On-demand | Medium |
| ~~`future_work.yml`~~ | ~~YAML~~ | ~~On-demand~~ | ❌ REMOVE (dead code) |
| `jobs/*` | Mixed | On-demand | Medium |
| `checkpoints/*.json` (auto-update) | JSON | On-demand | Medium |

### Files to Keep as Files

| File | Reason |
| ---- | ------ |
| `aidp.yml` | User-editable configuration |
| `firewall-allowlist.yml` | User-editable security rules |
| `PROMPT.md` | Current prompt (user may view/edit) |
| `docs/*.md` | Planning documents (WBS, GANTT, etc.) |
| `logs/*.log` | Log files (text-based, rotated) |
| `grammars/*` | Binary tree-sitter grammar files |
| `out/*` | Harness tool output files |
| `harness/*.lock` | Filesystem-level lock files |
| `kb/*.json` | Knowledge base (large, infrequently accessed) |

## Database Schema Design

### Core Tables

```sql
-- Schema version tracking for migrations
CREATE TABLE schema_migrations (
    version INTEGER PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Checkpoints (replaces checkpoint.yml)
CREATE TABLE checkpoints (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    step_name TEXT,
    step_index INTEGER,
    total_steps INTEGER,
    status TEXT,
    started_at TEXT,
    completed_at TEXT,
    run_loop_started_at TEXT,
    metadata TEXT, -- JSON blob for additional data
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_checkpoints_project ON checkpoints(project_dir);

-- Checkpoint history (replaces checkpoint_history.jsonl)
CREATE TABLE checkpoint_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    step_name TEXT,
    step_index INTEGER,
    status TEXT,
    timestamp TEXT NOT NULL,
    metadata TEXT -- JSON blob
);
CREATE INDEX idx_checkpoint_history_project ON checkpoint_history(project_dir);
CREATE INDEX idx_checkpoint_history_timestamp ON checkpoint_history(timestamp);

-- Tasks (replaces tasklist.jsonl)
CREATE TABLE tasks (
    id TEXT PRIMARY KEY, -- UUID
    project_dir TEXT NOT NULL,
    description TEXT NOT NULL,
    priority TEXT DEFAULT 'medium',
    status TEXT DEFAULT 'pending',
    tags TEXT, -- JSON array
    source TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    completed_at TEXT
);
CREATE INDEX idx_tasks_project ON tasks(project_dir);
CREATE INDEX idx_tasks_status ON tasks(status);

-- Progress tracking (replaces progress/*.yml)
CREATE TABLE progress (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    mode TEXT NOT NULL, -- 'execute' or 'analyze'
    current_step TEXT,
    current_step_index INTEGER,
    total_steps INTEGER,
    steps_completed TEXT, -- JSON array
    started_at TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    metadata TEXT -- JSON blob
);
CREATE UNIQUE INDEX idx_progress_project_mode ON progress(project_dir, mode);

-- Harness state (replaces harness/*_state.json)
CREATE TABLE harness_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    mode TEXT NOT NULL,
    state TEXT NOT NULL, -- JSON blob
    version INTEGER DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX idx_harness_state_project_mode ON harness_state(project_dir, mode);

-- Worktrees (replaces worktrees.json and pr_worktrees.json)
CREATE TABLE worktrees (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    worktree_type TEXT NOT NULL, -- 'standard' or 'pr'
    path TEXT NOT NULL,
    branch TEXT NOT NULL,
    slug TEXT,
    pr_number INTEGER,
    status TEXT DEFAULT 'active',
    metadata TEXT, -- JSON blob
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_worktrees_project ON worktrees(project_dir);
CREATE INDEX idx_worktrees_type ON worktrees(worktree_type);

-- Workstream state (replaces workstreams/*/state.json)
CREATE TABLE workstreams (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    slug TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    iteration INTEGER DEFAULT 0,
    branch TEXT,
    worktree_path TEXT,
    metadata TEXT, -- JSON blob
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX idx_workstreams_project_slug ON workstreams(project_dir, slug);

-- Workstream history (replaces workstreams/*/history.jsonl)
CREATE TABLE workstream_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    workstream_slug TEXT NOT NULL,
    event_type TEXT NOT NULL,
    event_data TEXT, -- JSON blob
    timestamp TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_workstream_events_slug ON workstream_events(project_dir, workstream_slug);

-- Watch mode state (replaces watch/*.yml)
CREATE TABLE watch_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    repository TEXT NOT NULL,
    issues TEXT, -- JSON blob of issue states
    pull_requests TEXT, -- JSON blob of PR states
    last_poll_at TEXT,
    metadata TEXT, -- JSON blob
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX idx_watch_state_repo ON watch_state(project_dir, repository);

-- Evaluations (replaces evaluations/*.json)
CREATE TABLE evaluations (
    id TEXT PRIMARY KEY, -- evaluation ID
    project_dir TEXT NOT NULL,
    evaluation_type TEXT,
    status TEXT,
    result TEXT, -- JSON blob
    started_at TEXT,
    completed_at TEXT,
    metadata TEXT, -- JSON blob
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_evaluations_project ON evaluations(project_dir);
CREATE INDEX idx_evaluations_type ON evaluations(evaluation_type);

-- Provider metrics (replaces provider_metrics.yml)
CREATE TABLE provider_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    provider_name TEXT NOT NULL,
    metric_type TEXT NOT NULL,
    value REAL,
    recorded_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_provider_metrics_provider ON provider_metrics(project_dir, provider_name);

-- Provider rate limits (replaces provider_rate_limits.yml)
CREATE TABLE provider_rate_limits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    provider_name TEXT NOT NULL,
    limit_type TEXT NOT NULL,
    limit_value INTEGER,
    remaining INTEGER,
    reset_at TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX idx_rate_limits_provider_type ON provider_rate_limits(project_dir, provider_name, limit_type);

-- Security secrets registry (replaces security/secrets_registry.json)
CREATE TABLE secrets_registry (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    secret_name TEXT NOT NULL,
    secret_type TEXT,
    source TEXT,
    registered_at TEXT NOT NULL DEFAULT (datetime('now')),
    metadata TEXT -- JSON blob (never actual secrets)
);
CREATE UNIQUE INDEX idx_secrets_project_name ON secrets_registry(project_dir, secret_name);

-- REMOVED: security_audit_log table
-- Reason: security/audit.jsonl is dead code (path defined but never used)

-- Prompt archive (replaces prompt_archive/*.md)
CREATE TABLE prompt_archive (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    step_name TEXT,
    content TEXT NOT NULL,
    archived_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_prompt_archive_project ON prompt_archive(project_dir);

-- Provider info cache (replaces providers/*_info.yml)
CREATE TABLE provider_info_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    provider_name TEXT NOT NULL,
    info TEXT NOT NULL, -- JSON blob
    cached_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT
);
CREATE UNIQUE INDEX idx_provider_info_name ON provider_info_cache(project_dir, provider_name);

-- Model cache (replaces model_cache/models.json)
CREATE TABLE model_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    provider_name TEXT NOT NULL,
    models TEXT NOT NULL, -- JSON array
    cached_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT
);
CREATE UNIQUE INDEX idx_model_cache_provider ON model_cache(project_dir, provider_name);

-- Deprecated models cache (replaces deprecated_models.json)
CREATE TABLE deprecated_models (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_dir TEXT NOT NULL,
    provider_name TEXT NOT NULL,
    model_name TEXT NOT NULL,
    deprecation_info TEXT, -- JSON blob
    detected_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_deprecated_models_provider ON deprecated_models(project_dir, provider_name);

-- REMOVED: json_storage table
-- Reason: JsonFileStorage class is dead code (292 lines, never instantiated)

-- REMOVED: future_work table
-- Reason: FutureWorkBacklog class is dead code (412 lines, superseded by PersistentTasklist)

-- Background jobs (replaces jobs/*)
CREATE TABLE background_jobs (
    id TEXT PRIMARY KEY, -- job ID
    project_dir TEXT NOT NULL,
    job_type TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    input TEXT, -- JSON blob
    output TEXT, -- JSON blob
    error TEXT,
    started_at TEXT,
    completed_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_jobs_project ON background_jobs(project_dir);
CREATE INDEX idx_jobs_status ON background_jobs(status);

-- Auto-update checkpoints (replaces checkpoints/*.json)
CREATE TABLE auto_update_checkpoints (
    id TEXT PRIMARY KEY, -- checkpoint ID
    project_dir TEXT NOT NULL,
    checkpoint_type TEXT,
    data TEXT NOT NULL, -- JSON blob
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_auto_checkpoints_project ON auto_update_checkpoints(project_dir);
```

## Implementation Plan

### Phase 0: Dead Code Cleanup (Priority: Immediate)

Before starting the SQLite migration, remove dead code identified in the audit:

#### 0.1 Remove Dead Security Code

- [ ] Remove `security_audit_log_file()` method from `lib/aidp/config_paths.rb:32`
- [ ] Remove `mcp_risk_profile_file()` method from `lib/aidp/config_paths.rb:33`
- [ ] Verify no references exist to these methods

#### 0.2 Remove FutureWorkBacklog (Superseded by PersistentTasklist)

- [ ] Remove `lib/aidp/execute/future_work_backlog.rb` (412 lines)
- [ ] Remove `spec/aidp/execute/future_work_backlog_spec.rb`
- [ ] Remove any documentation references to future_work.yml
- [ ] Verify PersistentTasklist handles all use cases

#### 0.3 Remove JsonFileStorage (Never Integrated)

- [ ] Remove `lib/aidp/analyze/json_file_storage.rb` (292 lines)
- [ ] Remove `spec/aidp/analyze/json_file_storage_spec.rb`
- [ ] Keep `lib/aidp/storage/json_storage.rb` (used by FileManager)
- [ ] Verify no broken imports

#### 0.4 Update Documentation

- [ ] Remove references to dead code from docs
- [ ] Update this migration plan to reflect cleanup

**Estimated Cleanup**: ~700 lines of dead code removal

---

### Phase 1: Foundation (Priority: Critical)

#### 1.1 Create Database Infrastructure

- [ ] Add `sqlite3` gem to `aidp.gemspec`
- [ ] Create `lib/aidp/database.rb` - Database connection manager
- [ ] Create `lib/aidp/database/schema.rb` - Schema definitions
- [ ] Create `lib/aidp/database/migrations.rb` - Migration runner
- [ ] Update `ConfigPaths` to include `database_file` method

**Files to create:**

```plaintext
lib/aidp/database.rb
lib/aidp/database/schema.rb
lib/aidp/database/migrations.rb
lib/aidp/database/connection.rb
```

**Key classes:**

```ruby
# lib/aidp/database.rb
module Aidp
  module Database
    def self.connection(project_dir = Dir.pwd)
      # Returns SQLite3::Database instance
      # Uses connection pooling for thread safety
    end

    def self.migrate!(project_dir = Dir.pwd)
      # Runs pending migrations
    end
  end
end
```

#### 1.2 Create Repository Pattern Base

- [ ] Create `lib/aidp/database/repository.rb` - Base repository class
- [ ] Implement common CRUD operations
- [ ] Add JSON serialization helpers
- [ ] Add timestamp management

**Base repository:**

```ruby
# lib/aidp/database/repository.rb
module Aidp
  module Database
    class Repository
      def initialize(project_dir: Dir.pwd)
        @project_dir = project_dir
        @db = Database.connection(project_dir)
      end

      protected

      def serialize_json(data)
        data.nil? ? nil : JSON.generate(data)
      end

      def deserialize_json(json_string)
        json_string.nil? ? nil : JSON.parse(json_string, symbolize_names: true)
      end
    end
  end
end
```

### Phase 2: High-Priority Migrations

#### 2.1 Checkpoint Migration

- [ ] Create `lib/aidp/database/repositories/checkpoint_repository.rb`
- [ ] Update `lib/aidp/execute/checkpoint.rb` to use repository
- [ ] Create migration script for existing `checkpoint.yml` and `checkpoint_history.jsonl`
- [ ] Add tests

**Current file:** `lib/aidp/execute/checkpoint.rb`
**Methods to update:**

- `save_checkpoint` (line 300)
- `load_checkpoint` (line 48)
- `append_to_history` (line 304)
- `load_history` (line 56)

#### 2.2 Task List Migration

- [ ] Create `lib/aidp/database/repositories/task_repository.rb`
- [ ] Update `lib/aidp/execute/persistent_tasklist.rb` to use repository
- [ ] Create migration script for existing `tasklist.jsonl`
- [ ] Add tests

**Current file:** `lib/aidp/execute/persistent_tasklist.rb`
**Methods to update:**

- `append_task` (line 137)
- `load_tasks` (line 147)
- `all_tasks` (line 162)

#### 2.3 Progress Migration

- [ ] Create `lib/aidp/database/repositories/progress_repository.rb`
- [ ] Update `lib/aidp/execute/progress.rb` to use repository
- [ ] Update `lib/aidp/analyze/progress.rb` to use repository
- [ ] Create migration script for existing `progress/*.yml`
- [ ] Add tests

**Current files:**

- `lib/aidp/execute/progress.rb`
- `lib/aidp/analyze/progress.rb`

#### 2.4 Harness State Migration

- [ ] Create `lib/aidp/database/repositories/harness_state_repository.rb`
- [ ] Update `lib/aidp/harness/state/persistence.rb` to use repository
- [ ] Create migration script for existing `harness/*_state.json`
- [ ] Add tests

**Current file:** `lib/aidp/harness/state/persistence.rb`

#### 2.5 Workstream Migration

- [ ] Create `lib/aidp/database/repositories/workstream_repository.rb`
- [ ] Update `lib/aidp/workstream_state.rb` to use repository
- [ ] Create migration script for existing `workstreams/*/state.json` and `history.jsonl`
- [ ] Add tests

**Current file:** `lib/aidp/workstream_state.rb`

#### 2.6 Watch State Migration

- [ ] Create `lib/aidp/database/repositories/watch_state_repository.rb`
- [ ] Update `lib/aidp/watch/state_store.rb` to use repository
- [ ] Create migration script for existing `watch/*.yml`
- [ ] Add tests

**Current file:** `lib/aidp/watch/state_store.rb`

### Phase 3: Medium-Priority Migrations

#### 3.1 Worktree Registry Migration

- [ ] Create `lib/aidp/database/repositories/worktree_repository.rb`
- [ ] Update `lib/aidp/worktree.rb` to use repository
- [ ] Update `lib/aidp/worktree_branch_manager.rb` to use repository
- [ ] Update `lib/aidp/pr_worktree_manager.rb` to use repository
- [ ] Create migration script

#### 3.2 Evaluations Migration

- [ ] Create `lib/aidp/database/repositories/evaluation_repository.rb`
- [ ] Update `lib/aidp/evaluations/evaluation_storage.rb` to use repository
- [ ] Create migration script

#### 3.3 Provider Metrics Migration

- [ ] Create `lib/aidp/database/repositories/provider_metrics_repository.rb`
- [ ] Update `lib/aidp/harness/provider_metrics.rb` to use repository
- [ ] Create migration script

#### 3.4 Security Migration

- [ ] Create `lib/aidp/database/repositories/security_repository.rb`
- [ ] Update `lib/aidp/security/secrets_registry.rb` to use repository
- [ ] Create migration script for `secrets_registry.json` only
- **Note**: `audit.jsonl` removed in Phase 0 (dead code - never implemented)

#### 3.5 Prompt Archive Migration

- [ ] Create `lib/aidp/database/repositories/prompt_archive_repository.rb`
- [ ] Update `lib/aidp/execute/prompt_manager.rb` to use repository
- [ ] Create migration script

#### ~~3.6 Future Work Migration~~ (REMOVED - Dead Code)

- ~~Create `lib/aidp/database/repositories/future_work_repository.rb`~~
- ~~Update `lib/aidp/execute/future_work_backlog.rb` to use repository~~
- **Action**: Remove FutureWorkBacklog class in Phase 0 (superseded by PersistentTasklist)

#### 3.7 Background Jobs Migration

- [ ] Create `lib/aidp/database/repositories/job_repository.rb`
- [ ] Update `lib/aidp/jobs/background_runner.rb` to use repository
- [ ] Create migration script

### Phase 4: Low-Priority Migrations

#### 4.1 Cache Migrations

- [ ] Create `lib/aidp/database/repositories/cache_repository.rb`
- [ ] Update `lib/aidp/harness/provider_info.rb`
- [ ] Update `lib/aidp/harness/model_cache.rb`
- [ ] Update `lib/aidp/harness/deprecation_cache.rb`
- [ ] Create migration scripts

#### ~~4.2 Generic JSON Storage Migration~~ (REMOVED - Dead Code)

- ~~Create `lib/aidp/database/repositories/json_storage_repository.rb`~~
- ~~Update `lib/aidp/analyze/json_file_storage.rb`~~
- **Action**: Remove JsonFileStorage class in Phase 0 (never integrated)
- **Note**: Keep `lib/aidp/storage/json_storage.rb` (minimal usage by FileManager)

### Phase 5: Migration Script & Cleanup

#### 5.1 Migration Script

- [ ] Create `lib/aidp/database/migrator.rb` - Data migration from files to SQLite
- [ ] Add CLI command `aidp migrate-storage`
- [ ] Implement rollback capability
- [ ] Add progress reporting

**Migration script features:**

```ruby
module Aidp
  module Database
    class Migrator
      def migrate!
        migrate_checkpoints
        migrate_tasks
        migrate_progress
        migrate_harness_state
        migrate_workstreams
        migrate_watch_state
        migrate_worktrees
        migrate_evaluations
        migrate_provider_metrics
        migrate_security
        migrate_prompt_archive
        # REMOVED: migrate_future_work (dead code)
        migrate_jobs
        migrate_caches
        # REMOVED: migrate_json_storage (dead code)
      end

      def rollback!
        # Export SQLite data back to files
      end
    end
  end
end
```

#### 5.2 Cleanup

- [ ] Remove old file-based storage code (after migration is stable)
- [ ] Update `.gitignore` to include `aidp.db`
- [ ] Update documentation
- [ ] Remove unused `ensure_*_dir` methods from `ConfigPaths`

## File Changes Summary

### New Files to Create

```plaintext
lib/aidp/database.rb
lib/aidp/database/connection.rb
lib/aidp/database/schema.rb
lib/aidp/database/migrations.rb
lib/aidp/database/repository.rb
lib/aidp/database/migrator.rb
lib/aidp/database/repositories/
  checkpoint_repository.rb
  task_repository.rb
  progress_repository.rb
  harness_state_repository.rb
  workstream_repository.rb
  watch_state_repository.rb
  worktree_repository.rb
  evaluation_repository.rb
  provider_metrics_repository.rb
  security_repository.rb
  prompt_archive_repository.rb
  job_repository.rb
  cache_repository.rb
  # REMOVED: future_work_repository.rb (dead code)
  # REMOVED: json_storage_repository.rb (dead code)
spec/aidp/database/
  (corresponding test files)
```

### Files to Modify

```plaintext
aidp.gemspec                              # Add sqlite3 gem
lib/aidp/config_paths.rb                  # Add database_file method
lib/aidp/execute/checkpoint.rb            # Use CheckpointRepository
lib/aidp/execute/persistent_tasklist.rb   # Use TaskRepository
lib/aidp/execute/progress.rb              # Use ProgressRepository
lib/aidp/analyze/progress.rb              # Use ProgressRepository
lib/aidp/harness/state/persistence.rb     # Use HarnessStateRepository
lib/aidp/workstream_state.rb              # Use WorkstreamRepository
lib/aidp/watch/state_store.rb             # Use WatchStateRepository
lib/aidp/worktree.rb                      # Use WorktreeRepository
lib/aidp/worktree_branch_manager.rb       # Use WorktreeRepository
lib/aidp/pr_worktree_manager.rb           # Use WorktreeRepository
lib/aidp/evaluations/evaluation_storage.rb # Use EvaluationRepository
lib/aidp/harness/provider_metrics.rb      # Use ProviderMetricsRepository
lib/aidp/security/secrets_registry.rb     # Use SecurityRepository
lib/aidp/execute/prompt_manager.rb        # Use PromptArchiveRepository
# REMOVED: lib/aidp/execute/future_work_backlog.rb (delete in Phase 0)
lib/aidp/jobs/background_runner.rb        # Use JobRepository
lib/aidp/harness/provider_info.rb         # Use CacheRepository
lib/aidp/harness/model_cache.rb           # Use CacheRepository
lib/aidp/harness/deprecation_cache.rb     # Use CacheRepository
# REMOVED: lib/aidp/analyze/json_file_storage.rb (delete in Phase 0)
# NOTE: lib/aidp/storage/json_storage.rb kept (minimal usage by FileManager)
lib/aidp/cli.rb                           # Add migrate-storage command
```

### Files to Remove Immediately (Phase 0 - Dead Code)

```plaintext
# Dead code to delete before SQLite migration:
lib/aidp/execute/future_work_backlog.rb        # 412 lines, superseded by PersistentTasklist
spec/aidp/execute/future_work_backlog_spec.rb  # Corresponding tests
lib/aidp/analyze/json_file_storage.rb          # 292 lines, never integrated
spec/aidp/analyze/json_file_storage_spec.rb    # Corresponding tests

# ConfigPaths methods to remove:
lib/aidp/config_paths.rb:32                    # security_audit_log_file() - never used
lib/aidp/config_paths.rb:33                    # mcp_risk_profile_file() - never used
```

### Files to Eventually Remove (after migration is stable)

```plaintext
# These directories will become empty after migration:
.aidp/progress/
.aidp/harness/*_state.json (keep .lock files)
.aidp/evaluations/
.aidp/security/secrets_registry.json
# REMOVED: .aidp/security/audit.jsonl (never created - dead code)
.aidp/workstreams/
.aidp/watch/
.aidp/providers/
.aidp/model_cache/
.aidp/prompt_archive/
.aidp/json/
.aidp/jobs/
.aidp/checkpoints/
.aidp/checkpoint.yml
.aidp/checkpoint_history.jsonl
.aidp/tasklist.jsonl
.aidp/worktrees.json
.aidp/pr_worktrees.json
.aidp/provider_metrics.yml
.aidp/provider_rate_limits.yml
.aidp/deprecated_models.json
# REMOVED: .aidp/future_work.yml (never created - dead code)
# REMOVED: .aidp/json/ (never created - dead code)
```

## Testing Strategy

1. **Unit tests** for each repository class
2. **Integration tests** for database operations
3. **Migration tests** - verify data integrity after migration
4. **Rollback tests** - verify rollback works correctly
5. **Performance tests** - ensure SQLite is not slower than file I/O

## Rollout Strategy

1. **Phase 1**: Ship database infrastructure with feature flag
2. **Phase 2**: Enable for new projects only
3. **Phase 3**: Add migration command for existing projects
4. **Phase 4**: Make SQLite the default
5. **Phase 5**: Remove file-based code (after sufficient stability period)

## Open Questions

1. **Thread safety**: Should we use a connection pool or single connection with mutex?
   - Recommendation: Use connection pool via `ConnectionPool` gem or simple mutex for single-threaded CLI

2. **Database location**: Should `aidp.db` be at `.aidp/aidp.db` or `.aidp/db/aidp.db`?
   - Recommendation: `.aidp/aidp.db` (simpler)

3. **Backup strategy**: Should we auto-backup the database periodically?
   - Recommendation: Not initially, but document manual backup procedure

4. **WAL mode**: Should we enable SQLite WAL mode for better concurrency?
   - Recommendation: Yes, enable WAL mode for better write performance

## Dependencies

- `sqlite3` gem (add to gemspec)
- No ORM - use raw SQL with prepared statements for simplicity and performance

## Risks and Mitigations

| Risk | Mitigation |
| ---- | ---------- |
| Data loss during migration | Create backup before migration, implement rollback |
| Performance regression | Benchmark critical paths, use indexes appropriately |
| Concurrent access issues | Use WAL mode, implement proper locking |
| Large database size | Implement periodic cleanup of old data |
| Corruption | Use atomic transactions, implement integrity checks |

## Success Metrics

1. All existing tests pass after migration
2. No data loss during migration
3. Performance is equal or better than file-based storage
4. Reduced disk I/O (single file vs many files)
5. Simpler codebase (unified storage layer)
