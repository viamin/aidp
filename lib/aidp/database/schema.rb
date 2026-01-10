# frozen_string_literal: true

module Aidp
  module Database
    # Schema definitions for AIDP SQLite database
    # Each constant represents a migration version with its SQL statements
    module Schema
      # Version 1: Initial schema with all core tables
      V1_INITIAL = <<~SQL
        -- Schema version tracking for migrations
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        -- Checkpoints (replaces checkpoint.yml)
        CREATE TABLE IF NOT EXISTS checkpoints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            step_name TEXT,
            step_index INTEGER,
            total_steps INTEGER,
            status TEXT,
            started_at TEXT,
            completed_at TEXT,
            run_loop_started_at TEXT,
            metadata TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_checkpoints_project ON checkpoints(project_dir);

        -- Checkpoint history (replaces checkpoint_history.jsonl)
        CREATE TABLE IF NOT EXISTS checkpoint_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            step_name TEXT,
            step_index INTEGER,
            status TEXT,
            timestamp TEXT NOT NULL,
            metadata TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_checkpoint_history_project ON checkpoint_history(project_dir);
        CREATE INDEX IF NOT EXISTS idx_checkpoint_history_timestamp ON checkpoint_history(timestamp);

        -- Tasks (replaces tasklist.jsonl)
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            project_dir TEXT NOT NULL,
            description TEXT NOT NULL,
            priority TEXT DEFAULT 'medium',
            status TEXT DEFAULT 'pending',
            tags TEXT,
            source TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            started_at TEXT,
            completed_at TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks(project_dir);
        CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);

        -- Progress tracking (replaces progress/*.yml)
        CREATE TABLE IF NOT EXISTS progress (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            mode TEXT NOT NULL,
            current_step TEXT,
            current_step_index INTEGER,
            total_steps INTEGER,
            steps_completed TEXT,
            started_at TEXT,
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            metadata TEXT
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_progress_project_mode ON progress(project_dir, mode);

        -- Harness state (replaces harness/*_state.json)
        CREATE TABLE IF NOT EXISTS harness_state (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            mode TEXT NOT NULL,
            state TEXT NOT NULL,
            version INTEGER DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_harness_state_project_mode ON harness_state(project_dir, mode);

        -- Worktrees (replaces worktrees.json and pr_worktrees.json)
        CREATE TABLE IF NOT EXISTS worktrees (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            worktree_type TEXT NOT NULL,
            path TEXT NOT NULL,
            branch TEXT NOT NULL,
            slug TEXT,
            pr_number INTEGER,
            status TEXT DEFAULT 'active',
            metadata TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_worktrees_project ON worktrees(project_dir);
        CREATE INDEX IF NOT EXISTS idx_worktrees_type ON worktrees(worktree_type);

        -- Workstream state (replaces workstreams/*/state.json)
        CREATE TABLE IF NOT EXISTS workstreams (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            slug TEXT NOT NULL,
            status TEXT DEFAULT 'pending',
            iteration INTEGER DEFAULT 0,
            branch TEXT,
            worktree_path TEXT,
            task TEXT,
            metadata TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_workstreams_project_slug ON workstreams(project_dir, slug);

        -- Workstream history (replaces workstreams/*/history.jsonl)
        CREATE TABLE IF NOT EXISTS workstream_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            workstream_slug TEXT NOT NULL,
            event_type TEXT NOT NULL,
            event_data TEXT,
            timestamp TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_workstream_events_slug ON workstream_events(project_dir, workstream_slug);

        -- Watch mode state (replaces watch/*.yml)
        CREATE TABLE IF NOT EXISTS watch_state (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            repository TEXT NOT NULL,
            plans TEXT,
            builds TEXT,
            reviews TEXT,
            ci_fixes TEXT,
            change_requests TEXT,
            detection_comments TEXT,
            feedback_comments TEXT,
            processed_reactions TEXT,
            auto_prs TEXT,
            projects TEXT,
            hierarchies TEXT,
            worktree_cleanup TEXT,
            last_poll_at TEXT,
            metadata TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_watch_state_repo ON watch_state(project_dir, repository);

        -- Evaluations (replaces evaluations/*.json)
        CREATE TABLE IF NOT EXISTS evaluations (
            id TEXT PRIMARY KEY,
            project_dir TEXT NOT NULL,
            rating TEXT NOT NULL,
            comment TEXT,
            target_type TEXT,
            target_id TEXT,
            context TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_evaluations_project ON evaluations(project_dir);
        CREATE INDEX IF NOT EXISTS idx_evaluations_rating ON evaluations(rating);

        -- Provider metrics (replaces provider_metrics.yml)
        CREATE TABLE IF NOT EXISTS provider_metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            provider_name TEXT NOT NULL,
            model_name TEXT,
            metrics TEXT NOT NULL,
            recorded_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_provider_metrics_provider ON provider_metrics(project_dir, provider_name);

        -- Provider rate limits (replaces provider_rate_limits.yml)
        CREATE TABLE IF NOT EXISTS provider_rate_limits (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            provider_name TEXT NOT NULL,
            model_name TEXT,
            rate_limit_info TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_rate_limits_provider ON provider_rate_limits(project_dir, provider_name, model_name);

        -- Security secrets registry (replaces security/secrets_registry.json)
        CREATE TABLE IF NOT EXISTS secrets_registry (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            secret_id TEXT NOT NULL,
            secret_name TEXT NOT NULL,
            env_var TEXT,
            description TEXT,
            scopes TEXT,
            registered_at TEXT NOT NULL DEFAULT (datetime('now')),
            metadata TEXT
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_secrets_project_name ON secrets_registry(project_dir, secret_name);

        -- Prompt archive (replaces prompt_archive/*.md)
        CREATE TABLE IF NOT EXISTS prompt_archive (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            step_name TEXT,
            content TEXT NOT NULL,
            archived_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_prompt_archive_project ON prompt_archive(project_dir);

        -- Provider info cache (replaces providers/*_info.yml)
        CREATE TABLE IF NOT EXISTS provider_info_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            provider_name TEXT NOT NULL,
            info TEXT NOT NULL,
            cached_at TEXT NOT NULL DEFAULT (datetime('now')),
            expires_at TEXT
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_provider_info_name ON provider_info_cache(project_dir, provider_name);

        -- Model cache (replaces model_cache/models.json)
        CREATE TABLE IF NOT EXISTS model_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            provider_name TEXT NOT NULL,
            models TEXT NOT NULL,
            cached_at TEXT NOT NULL DEFAULT (datetime('now')),
            expires_at TEXT
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_model_cache_provider ON model_cache(project_dir, provider_name);

        -- Deprecated models cache (replaces deprecated_models.json)
        CREATE TABLE IF NOT EXISTS deprecated_models (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            provider_name TEXT NOT NULL,
            model_name TEXT NOT NULL,
            replacement TEXT,
            reason TEXT,
            detected_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_deprecated_models_provider ON deprecated_models(project_dir, provider_name);
        CREATE UNIQUE INDEX IF NOT EXISTS idx_deprecated_models_unique ON deprecated_models(project_dir, provider_name, model_name);

        -- Background jobs (replaces jobs/*)
        CREATE TABLE IF NOT EXISTS background_jobs (
            id TEXT PRIMARY KEY,
            project_dir TEXT NOT NULL,
            job_type TEXT NOT NULL,
            status TEXT DEFAULT 'pending',
            pid INTEGER,
            options TEXT,
            result TEXT,
            error TEXT,
            started_at TEXT,
            completed_at TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_jobs_project ON background_jobs(project_dir);
        CREATE INDEX IF NOT EXISTS idx_jobs_status ON background_jobs(status);

        -- Auto-update checkpoints (replaces checkpoints/*.json)
        CREATE TABLE IF NOT EXISTS auto_update_checkpoints (
            id TEXT PRIMARY KEY,
            project_dir TEXT NOT NULL,
            checkpoint_type TEXT,
            data TEXT NOT NULL,
            checksum TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_auto_checkpoints_project ON auto_update_checkpoints(project_dir);
      SQL

      # Version 2: Add prompt feedback table for AGD pattern
      V2_PROMPT_FEEDBACK = <<~SQL
        -- Prompt feedback (tracks prompt template effectiveness for AGD evolution)
        CREATE TABLE IF NOT EXISTS prompt_feedback (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            template_id TEXT NOT NULL,
            outcome TEXT NOT NULL,
            iterations INTEGER,
            user_reaction TEXT,
            suggestions TEXT,
            context TEXT,
            aidp_version TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_prompt_feedback_project ON prompt_feedback(project_dir);
        CREATE INDEX IF NOT EXISTS idx_prompt_feedback_template ON prompt_feedback(template_id);
        CREATE INDEX IF NOT EXISTS idx_prompt_feedback_outcome ON prompt_feedback(outcome);
      SQL

      # All migrations in order
      MIGRATIONS = {
        1 => V1_INITIAL,
        2 => V2_PROMPT_FEEDBACK
      }.freeze

      # Get SQL for a specific version
      def self.migration_sql(version)
        MIGRATIONS[version]
      end

      # Get all migration versions
      def self.versions
        MIGRATIONS.keys.sort
      end

      # Get latest version
      def self.latest_version
        versions.last || 0
      end
    end
  end
end
