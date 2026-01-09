# frozen_string_literal: true

require "yaml"
require "json"
require "fileutils"
require_relative "../config_paths"
require_relative "../database"

module Aidp
  module Database
    # Migrates file-based storage to SQLite database
    #
    # Handles migration of all .aidp directory files to the new SQLite storage.
    # Supports dry-run mode, backup creation, and rollback.
    #
    # Usage:
    #   migrator = StorageMigrator.new(project_dir: Dir.pwd)
    #   migrator.migrate!
    #
    class StorageMigrator
      class MigrationError < StandardError; end

      attr_reader :project_dir, :stats, :errors

      def initialize(project_dir: Dir.pwd, dry_run: false)
        @project_dir = project_dir
        @dry_run = dry_run
        @stats = Hash.new(0)
        @errors = []
      end

      # Check if migration is needed
      #
      # @return [Boolean] True if file-based storage exists
      def migration_needed?
        file_storage_exists?
      end

      # Check if database already has data
      #
      # @return [Boolean] True if database has migrated data
      def already_migrated?
        return false unless File.exist?(ConfigPaths.database_file(project_dir))

        Database::Migrations.run!(project_dir)
        # Check if any tables have data
        db = Database.connection(project_dir)
        tables = %w[checkpoints tasks progress harness_state workstreams watch_state]
        tables.any? do |table|
          count = db.get_first_value("SELECT COUNT(*) FROM #{table}")
          count.to_i > 0
        end
      rescue
        false
      end

      # Run the migration
      #
      # @param backup [Boolean] Create backup before migration
      # @return [Hash] Migration results
      def migrate!(backup: true)
        Aidp.log_info("storage_migrator", "starting_migration",
          project_dir: project_dir, dry_run: @dry_run)

        unless migration_needed?
          Aidp.log_info("storage_migrator", "no_migration_needed")
          return {status: :skipped, reason: "No file-based storage found"}
        end

        create_backup if backup && !@dry_run
        Database::Migrations.run!(project_dir) unless @dry_run

        migrate_checkpoints
        migrate_tasks
        migrate_progress
        migrate_harness_state
        migrate_workstreams
        migrate_watch_state
        migrate_worktrees
        migrate_evaluations
        migrate_provider_info
        migrate_model_cache
        migrate_deprecated_models
        migrate_secrets
        migrate_prompt_archive
        migrate_jobs
        migrate_provider_metrics

        result = {
          status: @errors.empty? ? :success : :partial,
          stats: @stats.dup,
          errors: @errors.dup,
          dry_run: @dry_run
        }

        Aidp.log_info("storage_migrator", "migration_complete",
          status: result[:status], stats: @stats)

        result
      end

      # Create backup of .aidp directory
      #
      # @return [String] Backup directory path
      def create_backup
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        backup_dir = File.join(project_dir, ".aidp_backup_#{timestamp}")

        Aidp.log_info("storage_migrator", "creating_backup", backup_dir: backup_dir)

        FileUtils.cp_r(ConfigPaths.aidp_dir(project_dir), backup_dir)
        @stats[:backup_created] = 1
        backup_dir
      end

      # Clean up old file-based storage after successful migration
      #
      # @param keep_config [Boolean] Keep aidp.yml config file
      def cleanup_old_storage!(keep_config: true)
        return if @dry_run

        Aidp.log_info("storage_migrator", "cleaning_up_old_storage")

        files_to_remove = migrated_files
        files_to_remove.each do |file|
          next unless File.exist?(file)
          next if keep_config && file == ConfigPaths.config_file(project_dir)

          FileUtils.rm_rf(file)
          @stats[:files_removed] += 1
        end

        # Remove empty directories
        cleanup_empty_directories
      end

      private

      def file_storage_exists?
        files = [
          ConfigPaths.checkpoint_file(project_dir),
          ConfigPaths.checkpoint_history_file(project_dir),
          File.join(ConfigPaths.aidp_dir(project_dir), "tasks.json"),
          ConfigPaths.execute_progress_file(project_dir),
          ConfigPaths.analyze_progress_file(project_dir)
        ]

        dirs = [
          ConfigPaths.harness_state_dir(project_dir),
          ConfigPaths.providers_dir(project_dir),
          ConfigPaths.evaluations_dir(project_dir),
          ConfigPaths.jobs_dir(project_dir)
        ]

        files.any? { |f| File.exist?(f) } || dirs.any? { |d| Dir.exist?(d) && !Dir.empty?(d) }
      end

      def migrated_files
        [
          ConfigPaths.checkpoint_file(project_dir),
          ConfigPaths.checkpoint_history_file(project_dir),
          File.join(ConfigPaths.aidp_dir(project_dir), "tasks.json"),
          ConfigPaths.execute_progress_file(project_dir),
          ConfigPaths.analyze_progress_file(project_dir),
          File.join(ConfigPaths.aidp_dir(project_dir), "worktrees.json"),
          File.join(ConfigPaths.aidp_dir(project_dir), "pr_worktrees.json"),
          File.join(ConfigPaths.aidp_dir(project_dir), "workstreams.json"),
          File.join(ConfigPaths.aidp_dir(project_dir), "watch_state.yml"),
          File.join(ConfigPaths.aidp_dir(project_dir), "watch_results.yml"),
          File.join(ConfigPaths.aidp_dir(project_dir), "deprecated_models.json"),
          File.join(ConfigPaths.aidp_dir(project_dir), "provider_metrics.yml"),
          File.join(ConfigPaths.aidp_dir(project_dir), "provider_rate_limits.yml"),
          ConfigPaths.secrets_registry_file(project_dir),
          ConfigPaths.harness_state_dir(project_dir),
          ConfigPaths.providers_dir(project_dir),
          ConfigPaths.evaluations_dir(project_dir),
          ConfigPaths.jobs_dir(project_dir),
          ConfigPaths.model_cache_dir(project_dir),
          File.join(ConfigPaths.aidp_dir(project_dir), "prompt_archive")
        ]
      end

      def cleanup_empty_directories
        dirs = [
          ConfigPaths.progress_dir(project_dir),
          ConfigPaths.harness_state_dir(project_dir),
          ConfigPaths.providers_dir(project_dir),
          ConfigPaths.evaluations_dir(project_dir),
          ConfigPaths.jobs_dir(project_dir),
          ConfigPaths.model_cache_dir(project_dir),
          ConfigPaths.security_dir(project_dir),
          File.join(ConfigPaths.aidp_dir(project_dir), "prompt_archive")
        ]

        dirs.each do |dir|
          next unless Dir.exist?(dir)
          FileUtils.rm_rf(dir) if Dir.empty?(dir)
        end
      end

      # Migration methods for each data type

      def migrate_checkpoints
        checkpoint_file = ConfigPaths.checkpoint_file(project_dir)
        history_file = ConfigPaths.checkpoint_history_file(project_dir)

        return unless File.exist?(checkpoint_file) || File.exist?(history_file)

        Aidp.log_debug("storage_migrator", "migrating_checkpoints")

        require_relative "repositories/checkpoint_repository"
        repo = Repositories::CheckpointRepository.new(project_dir: project_dir)

        # Migrate current checkpoint
        if File.exist?(checkpoint_file)
          data = YAML.safe_load_file(checkpoint_file, permitted_classes: [Time, Symbol])
          if data && !@dry_run
            repo.save_checkpoint(
              step_name: data["step"] || data[:step],
              iteration: data["iteration"] || data[:iteration] || data["step_index"] || data[:step_index] || 0,
              status: data["status"] || data[:status] || "unknown",
              run_loop_started_at: data["run_loop_started_at"] || data[:run_loop_started_at],
              metrics: data
            )
          end
          @stats[:checkpoints_migrated] += 1
        end

        # Migrate checkpoint history
        if File.exist?(history_file)
          File.foreach(history_file) do |line|
            next if line.strip.empty?
            entry = JSON.parse(line, symbolize_names: true)
            unless @dry_run
              repo.append_history(
                step_name: entry[:step],
                iteration: entry[:iteration] || entry[:step_index] || 0,
                status: entry[:status] || "completed",
                metrics: entry
              )
            end
            @stats[:checkpoint_history_migrated] += 1
          rescue JSON::ParserError => e
            @errors << {type: :checkpoint_history, error: e.message}
          end
        end
      rescue => e
        @errors << {type: :checkpoints, error: e.message}
        Aidp.log_error("storage_migrator", "checkpoint_migration_failed", error: e.message)
      end

      def migrate_tasks
        tasks_file = File.join(ConfigPaths.aidp_dir(project_dir), "tasks.json")
        return unless File.exist?(tasks_file)

        Aidp.log_debug("storage_migrator", "migrating_tasks")

        require_relative "repositories/task_repository"
        repo = Repositories::TaskRepository.new(project_dir: project_dir)

        data = JSON.parse(File.read(tasks_file), symbolize_names: true)
        tasks = data[:tasks] || data["tasks"] || []

        tasks.each do |task|
          unless @dry_run
            repo.create(
              description: task[:title] || task["title"] || task[:description] || task["description"],
              priority: task[:priority] || task["priority"] || "medium",
              tags: task[:tags] || task["tags"] || []
            )
          end
          @stats[:tasks_migrated] += 1
        end
      rescue => e
        @errors << {type: :tasks, error: e.message}
        Aidp.log_error("storage_migrator", "tasks_migration_failed", error: e.message)
      end

      def migrate_progress
        %w[execute analyze].each do |mode|
          progress_file = File.join(ConfigPaths.progress_dir(project_dir), "#{mode}.yml")
          next unless File.exist?(progress_file)

          Aidp.log_debug("storage_migrator", "migrating_progress", mode: mode)

          require_relative "repositories/progress_repository"
          repo = Repositories::ProgressRepository.new(project_dir: project_dir)

          data = YAML.safe_load_file(progress_file, permitted_classes: [Time, Symbol])
          next unless data

          now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
          unless @dry_run
            repo.upsert_progress(
              mode: mode,
              current_step: data["current_step"] || data[:current_step],
              steps_completed: data["steps_completed"] || data[:steps_completed] || [],
              started_at: data["started_at"] || data[:started_at] || now,
              updated_at: now
            )
          end
          @stats[:progress_migrated] += 1
        end
      rescue => e
        @errors << {type: :progress, error: e.message}
        Aidp.log_error("storage_migrator", "progress_migration_failed", error: e.message)
      end

      def migrate_harness_state
        state_dir = ConfigPaths.harness_state_dir(project_dir)
        return unless Dir.exist?(state_dir)

        Aidp.log_debug("storage_migrator", "migrating_harness_state")

        require_relative "repositories/harness_state_repository"
        repo = Repositories::HarnessStateRepository.new(project_dir: project_dir)

        Dir.glob(File.join(state_dir, "*_state.json")).each do |state_file|
          mode = File.basename(state_file, "_state.json")
          data = JSON.parse(File.read(state_file), symbolize_names: true)

          unless @dry_run
            repo.save_state(mode, data)
          end
          @stats[:harness_states_migrated] += 1
        rescue => e
          @errors << {type: :harness_state, file: state_file, error: e.message}
        end
      rescue => e
        @errors << {type: :harness_state, error: e.message}
        Aidp.log_error("storage_migrator", "harness_state_migration_failed", error: e.message)
      end

      def migrate_workstreams
        workstreams_file = File.join(ConfigPaths.aidp_dir(project_dir), "workstreams.json")
        return unless File.exist?(workstreams_file)

        Aidp.log_debug("storage_migrator", "migrating_workstreams")

        require_relative "repositories/workstream_repository"
        repo = Repositories::WorkstreamRepository.new(project_dir: project_dir)

        data = JSON.parse(File.read(workstreams_file), symbolize_names: true)
        workstreams = data[:workstreams] || data["workstreams"] || data

        workstreams = [workstreams] if workstreams.is_a?(Hash)

        workstreams.each do |ws|
          slug = ws[:slug] || ws["slug"] || ws[:name] || ws["name"]
          next unless slug

          unless @dry_run
            repo.init(
              slug: slug,
              task: ws[:task] || ws["task"] || ws[:name] || ws["name"]
            )
            # Update additional attributes if present
            branch = ws[:branch] || ws["branch"]
            if branch
              repo.update(slug: slug, branch: branch)
            end
          end
          @stats[:workstreams_migrated] += 1
        end
      rescue => e
        @errors << {type: :workstreams, error: e.message}
        Aidp.log_error("storage_migrator", "workstreams_migration_failed", error: e.message)
      end

      def migrate_watch_state
        watch_state_file = File.join(ConfigPaths.aidp_dir(project_dir), "watch_state.yml")
        watch_results_file = File.join(ConfigPaths.aidp_dir(project_dir), "watch_results.yml")

        return unless File.exist?(watch_state_file) || File.exist?(watch_results_file)

        # Watch state has a complex format that requires issue-specific records.
        # Skip automatic migration - the data will be regenerated when watch mode runs.
        Aidp.log_debug("storage_migrator", "skipping_watch_state_migration",
          reason: "Watch state will be regenerated on next watch mode run")

        @stats[:watch_state_skipped] = 1 if File.exist?(watch_state_file)
        @stats[:watch_results_skipped] = 1 if File.exist?(watch_results_file)
      end

      def migrate_worktrees
        worktrees_file = File.join(ConfigPaths.aidp_dir(project_dir), "worktrees.json")
        pr_worktrees_file = File.join(ConfigPaths.aidp_dir(project_dir), "pr_worktrees.json")

        return unless File.exist?(worktrees_file) || File.exist?(pr_worktrees_file)

        Aidp.log_debug("storage_migrator", "migrating_worktrees")

        require_relative "repositories/worktree_repository"
        repo = Repositories::WorktreeRepository.new(project_dir: project_dir)

        # Standard worktrees
        if File.exist?(worktrees_file)
          data = JSON.parse(File.read(worktrees_file), symbolize_names: true)
          worktrees = data[:worktrees] || data["worktrees"] || data

          worktrees.each do |slug, wt|
            wt = wt.merge(slug: slug) if wt.is_a?(Hash)
            slug_str = (wt[:slug] || slug).to_s
            path = wt[:path] || wt["path"]
            branch = wt[:branch] || wt["branch"]
            next unless slug_str && path && branch

            unless @dry_run
              repo.register(slug: slug_str, path: path, branch: branch)
            end
            @stats[:worktrees_migrated] += 1
          end
        end

        # PR worktrees
        if File.exist?(pr_worktrees_file)
          data = JSON.parse(File.read(pr_worktrees_file), symbolize_names: true)
          pr_worktrees = data[:pr_worktrees] || data["pr_worktrees"] || data

          pr_worktrees.each do |pr_num, wt|
            path = wt[:path] || wt["path"]
            branch = wt[:branch] || wt["branch"] || "main"
            next unless path

            unless @dry_run
              repo.register_pr(
                pr_number: pr_num.to_s.to_i,
                path: path,
                base_branch: wt[:base_branch] || wt["base_branch"] || "main",
                head_branch: wt[:head_branch] || wt["head_branch"] || branch
              )
            end
            @stats[:pr_worktrees_migrated] += 1
          end
        end
      rescue => e
        @errors << {type: :worktrees, error: e.message}
        Aidp.log_error("storage_migrator", "worktrees_migration_failed", error: e.message)
      end

      def migrate_evaluations
        eval_dir = ConfigPaths.evaluations_dir(project_dir)
        return unless Dir.exist?(eval_dir)

        Aidp.log_debug("storage_migrator", "migrating_evaluations")

        require_relative "repositories/evaluation_repository"
        repo = Repositories::EvaluationRepository.new(project_dir: project_dir)

        Dir.glob(File.join(eval_dir, "*.json")).each do |eval_file|
          next if File.basename(eval_file) == "index.json"

          data = JSON.parse(File.read(eval_file), symbolize_names: true)
          unless @dry_run
            repo.store(
              id: data[:id] || File.basename(eval_file, ".json"),
              rating: data[:rating] || data["rating"] || data[:status] || data["status"] || "neutral",
              target_type: data[:type] || data["type"] || data[:target_type] || data["target_type"],
              target_id: data[:target_id] || data["target_id"],
              feedback: data[:comment] || data["comment"] || data[:feedback] || data["feedback"],
              context: data[:context] || data["context"] || data
            )
          end
          @stats[:evaluations_migrated] += 1
        rescue => e
          @errors << {type: :evaluation, file: eval_file, error: e.message}
        end
      rescue => e
        @errors << {type: :evaluations, error: e.message}
        Aidp.log_error("storage_migrator", "evaluations_migration_failed", error: e.message)
      end

      def migrate_provider_info
        providers_dir = ConfigPaths.providers_dir(project_dir)
        return unless Dir.exist?(providers_dir)

        Aidp.log_debug("storage_migrator", "migrating_provider_info")

        require_relative "repositories/provider_info_cache_repository"
        repo = Repositories::ProviderInfoCacheRepository.new(project_dir: project_dir)

        Dir.glob(File.join(providers_dir, "*_info.yml")).each do |info_file|
          provider_name = File.basename(info_file, "_info.yml")
          data = YAML.safe_load_file(info_file, permitted_classes: [Time, Symbol])

          unless @dry_run
            repo.cache(provider_name, data)
          end
          @stats[:provider_info_migrated] += 1
        rescue => e
          @errors << {type: :provider_info, file: info_file, error: e.message}
        end
      rescue => e
        @errors << {type: :provider_info, error: e.message}
        Aidp.log_error("storage_migrator", "provider_info_migration_failed", error: e.message)
      end

      def migrate_model_cache
        cache_file = File.join(ConfigPaths.model_cache_dir(project_dir), "models.json")
        return unless File.exist?(cache_file)

        Aidp.log_debug("storage_migrator", "migrating_model_cache")

        require_relative "repositories/model_cache_repository"
        repo = Repositories::ModelCacheRepository.new(project_dir: project_dir)

        data = JSON.parse(File.read(cache_file), symbolize_names: true)

        data.each do |provider, cache_entry|
          provider = provider.to_s
          models = cache_entry[:models] || cache_entry["models"] || []
          ttl = cache_entry[:ttl] || cache_entry["ttl"] || 86400

          unless @dry_run
            repo.cache_models(provider, models, ttl: ttl)
          end
          @stats[:model_cache_migrated] += 1
        end
      rescue => e
        @errors << {type: :model_cache, error: e.message}
        Aidp.log_error("storage_migrator", "model_cache_migration_failed", error: e.message)
      end

      def migrate_deprecated_models
        deprecated_file = File.join(ConfigPaths.aidp_dir(project_dir), "deprecated_models.json")
        return unless File.exist?(deprecated_file)

        Aidp.log_debug("storage_migrator", "migrating_deprecated_models")

        require_relative "repositories/deprecated_models_repository"
        repo = Repositories::DeprecatedModelsRepository.new(project_dir: project_dir)

        data = JSON.parse(File.read(deprecated_file), symbolize_names: true)
        providers = data[:providers] || data["providers"] || {}

        providers.each do |provider, models|
          provider = provider.to_s
          models.each do |model_name, info|
            unless @dry_run
              repo.add(
                provider_name: provider,
                model_name: model_name.to_s,
                replacement: info[:replacement] || info["replacement"],
                reason: info[:reason] || info["reason"]
              )
            end
            @stats[:deprecated_models_migrated] += 1
          end
        end
      rescue => e
        @errors << {type: :deprecated_models, error: e.message}
        Aidp.log_error("storage_migrator", "deprecated_models_migration_failed", error: e.message)
      end

      def migrate_secrets
        secrets_file = ConfigPaths.secrets_registry_file(project_dir)
        return unless File.exist?(secrets_file)

        Aidp.log_debug("storage_migrator", "migrating_secrets")

        require_relative "repositories/secrets_repository"
        repo = Repositories::SecretsRepository.new(project_dir: project_dir)

        data = JSON.parse(File.read(secrets_file), symbolize_names: true)
        secrets = data[:secrets] || data["secrets"] || data

        secrets.each do |secret|
          name = secret[:name] || secret["name"]
          env_var = secret[:env_var] || secret["env_var"]
          next unless name && env_var

          unless @dry_run
            repo.register(
              name: name,
              env_var: env_var,
              description: secret[:description] || secret["description"],
              scopes: secret[:scopes] || secret["scopes"] || []
            )
          end
          @stats[:secrets_migrated] += 1
        end
      rescue => e
        @errors << {type: :secrets, error: e.message}
        Aidp.log_error("storage_migrator", "secrets_migration_failed", error: e.message)
      end

      def migrate_prompt_archive
        archive_dir = File.join(ConfigPaths.aidp_dir(project_dir), "prompt_archive")
        return unless Dir.exist?(archive_dir)

        Aidp.log_debug("storage_migrator", "migrating_prompt_archive")

        require_relative "repositories/prompt_archive_repository"
        repo = Repositories::PromptArchiveRepository.new(project_dir: project_dir)

        Dir.glob(File.join(archive_dir, "*.md")).each do |prompt_file|
          content = File.read(prompt_file)
          filename = File.basename(prompt_file, ".md")

          # Parse filename for step name (format: timestamp_step_provider.md)
          parts = filename.split("_")
          step = parts[1..-2]&.join("_") || "unknown"

          unless @dry_run
            repo.archive(step_name: step, content: content)
          end
          @stats[:prompts_migrated] += 1
        rescue => e
          @errors << {type: :prompt_archive, file: prompt_file, error: e.message}
        end
      rescue => e
        @errors << {type: :prompt_archive, error: e.message}
        Aidp.log_error("storage_migrator", "prompt_archive_migration_failed", error: e.message)
      end

      def migrate_jobs
        jobs_dir = ConfigPaths.jobs_dir(project_dir)
        return unless Dir.exist?(jobs_dir)

        Aidp.log_debug("storage_migrator", "migrating_jobs")

        require_relative "repositories/job_repository"
        repo = Repositories::JobRepository.new(project_dir: project_dir)

        Dir.glob(File.join(jobs_dir, "*.json")).each do |job_file|
          data = JSON.parse(File.read(job_file), symbolize_names: true)

          unless @dry_run
            # Note: create() generates its own job_id, so old IDs are not preserved
            new_job_id = repo.create(
              job_type: data[:type] || data["type"] || "background",
              input: data[:options] || data["options"] || data[:input] || data["input"] || {}
            )

            # Update status based on stored state
            status = data[:status] || data["status"]
            case status
            when "running"
              repo.start(new_job_id, pid: data[:pid] || data["pid"])
            when "completed"
              output = data[:result] || data["result"] || data[:output] || data["output"] || {}
              repo.complete(new_job_id, output: output)
            when "failed"
              repo.fail(new_job_id, error: data[:error] || data["error"] || "Unknown error")
            end
          end
          @stats[:jobs_migrated] += 1
        rescue => e
          @errors << {type: :job, file: job_file, error: e.message}
        end
      rescue => e
        @errors << {type: :jobs, error: e.message}
        Aidp.log_error("storage_migrator", "jobs_migration_failed", error: e.message)
      end

      def migrate_provider_metrics
        metrics_file = File.join(ConfigPaths.aidp_dir(project_dir), "provider_metrics.yml")
        rate_limits_file = File.join(ConfigPaths.aidp_dir(project_dir), "provider_rate_limits.yml")

        return unless File.exist?(metrics_file) || File.exist?(rate_limits_file)

        Aidp.log_debug("storage_migrator", "migrating_provider_metrics")

        require_relative "repositories/provider_metrics_repository"
        repo = Repositories::ProviderMetricsRepository.new(project_dir: project_dir)

        if File.exist?(metrics_file)
          data = YAML.safe_load_file(metrics_file, permitted_classes: [Time, Symbol])
          data&.each do |provider, metrics|
            unless @dry_run
              repo.save_metrics(provider.to_s, metrics)
            end
            @stats[:provider_metrics_migrated] += 1
          end
        end

        if File.exist?(rate_limits_file)
          data = YAML.safe_load_file(rate_limits_file, permitted_classes: [Time, Symbol])
          data&.each do |provider, limits|
            unless @dry_run
              repo.save_rate_limits(provider.to_s, limits)
            end
            @stats[:rate_limits_migrated] += 1
          end
        end
      rescue => e
        @errors << {type: :provider_metrics, error: e.message}
        Aidp.log_error("storage_migrator", "provider_metrics_migration_failed", error: e.message)
      end
    end
  end
end
