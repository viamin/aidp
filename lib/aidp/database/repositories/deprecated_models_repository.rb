# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      # Repository for deprecated models cache
      # Replaces: .aidp/deprecated_models.json
      #
      # Tracks models that have been deprecated by providers at runtime
      class DeprecatedModelsRepository < Repository
        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "deprecated_models")
        end

        # Add a deprecated model to the cache
        #
        # @param provider_name [String] Provider name (e.g., "anthropic")
        # @param model_name [String] Deprecated model ID
        # @param replacement [String, nil] Replacement model ID
        # @param reason [String, nil] Deprecation reason
        # @return [Boolean] Success status
        def add(provider_name:, model_name:, replacement: nil, reason: nil)
          Aidp.log_debug("deprecated_models_repo", "add",
            provider: provider_name, model: model_name, replacement: replacement)

          execute(<<~SQL, [project_dir, provider_name, model_name, replacement, reason, current_timestamp])
            INSERT INTO #{table_name}
              (project_dir, provider_name, model_name, replacement, reason, detected_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(project_dir, provider_name, model_name) DO UPDATE SET
              replacement = excluded.replacement,
              reason = excluded.reason,
              detected_at = excluded.detected_at
          SQL

          Aidp.log_info("deprecated_models_repo", "added_deprecated_model",
            provider: provider_name, model: model_name, replacement: replacement)
          true
        rescue => e
          Aidp.log_error("deprecated_models_repo", "add_failed",
            provider: provider_name, model: model_name, error: e.message)
          false
        end

        # Check if a model is deprecated
        #
        # @param provider_name [String] Provider name
        # @param model_name [String] Model ID to check
        # @return [Boolean]
        def deprecated?(provider_name:, model_name:)
          result = query_value(<<~SQL, [project_dir, provider_name, model_name])
            SELECT 1 FROM #{table_name}
            WHERE project_dir = ? AND provider_name = ? AND model_name = ?
          SQL

          !result.nil?
        end

        # Get replacement model for a deprecated model
        #
        # @param provider_name [String] Provider name
        # @param model_name [String] Deprecated model ID
        # @return [String, nil] Replacement model ID or nil
        def replacement_for(provider_name:, model_name:)
          query_value(<<~SQL, [project_dir, provider_name, model_name])
            SELECT replacement FROM #{table_name}
            WHERE project_dir = ? AND provider_name = ? AND model_name = ?
          SQL
        end

        # Get all deprecated models for a provider
        #
        # @param provider_name [String] Provider name
        # @return [Array<String>] List of deprecated model IDs
        def deprecated_models(provider_name:)
          rows = query(<<~SQL, [project_dir, provider_name])
            SELECT model_name FROM #{table_name}
            WHERE project_dir = ? AND provider_name = ?
            ORDER BY model_name
          SQL

          rows.map { |row| row["model_name"]}
        end

        # Get full deprecation info for a model
        #
        # @param provider_name [String] Provider name
        # @param model_name [String] Model ID
        # @return [Hash, nil] Deprecation metadata or nil
        def info(provider_name:, model_name:)
          row = query_one(<<~SQL, [project_dir, provider_name, model_name])
            SELECT replacement, reason, detected_at
            FROM #{table_name}
            WHERE project_dir = ? AND provider_name = ? AND model_name = ?
          SQL

          return nil unless row

          {
            replacement: row["replacement"],
            reason: row["reason"],
            detected_at: row["detected_at"]
         }
        end

        # Remove a model from the deprecated cache
        #
        # @param provider_name [String] Provider name
        # @param model_name [String] Model ID to remove
        def remove(provider_name:, model_name:)
          Aidp.log_debug("deprecated_models_repo", "remove",
            provider: provider_name, model: model_name)

          execute(<<~SQL, [project_dir, provider_name, model_name])
            DELETE FROM #{table_name}
            WHERE project_dir = ? AND provider_name = ? AND model_name = ?
          SQL

          Aidp.log_info("deprecated_models_repo", "removed_deprecated_model",
            provider: provider_name, model: model_name)
        end

        # Clear all deprecations for project
        def clear!
          Aidp.log_debug("deprecated_models_repo", "clear")
          delete_by_project
          Aidp.log_info("deprecated_models_repo", "cleared_all")
        end

        # Get cache statistics
        #
        # @return [Hash] Statistics
        def stats
          providers_rows = query(<<~SQL, [project_dir])
            SELECT DISTINCT provider_name FROM #{table_name}
            WHERE project_dir = ?
            ORDER BY provider_name
          SQL

          providers = providers_rows.map { |row| row["provider_name"]}

          by_provider = {}
          providers.each do |provider|
            count = query_value(<<~SQL, [project_dir, provider])
              SELECT COUNT(*) FROM #{table_name}
              WHERE project_dir = ? AND provider_name = ?
            SQL
            by_provider[provider] = count || 0
          end

          total = by_provider.values.sum

          {
            providers: providers,
            total_deprecated: total,
            by_provider: by_provider
         }
        end

        # List all deprecated models with full info
        #
        # @return [Array<Hash>] All deprecated models
        def list_all
          rows = query(<<~SQL, [project_dir])
            SELECT provider_name, model_name, replacement, reason, detected_at
            FROM #{table_name}
            WHERE project_dir = ?
            ORDER BY provider_name, model_name
          SQL

          rows.map do |row|
            {
              provider: row["provider_name"],
              model: row["model_name"],
              replacement: row["replacement"],
              reason: row["reason"],
              detected_at: row["detected_at"]
           }
          end
        end

        # Find deprecated models with replacements
        #
        # @return [Array<Hash>] Models with replacement info
        def with_replacements
          rows = query(<<~SQL, [project_dir])
            SELECT provider_name, model_name, replacement
            FROM #{table_name}
            WHERE project_dir = ? AND replacement IS NOT NULL
            ORDER BY provider_name, model_name
          SQL

          rows.map do |row|
            {
              provider: row["provider_name"],
              model: row["model_name"],
              replacement: row["replacement"]
           }
          end
        end
      end
    end
  end
end
