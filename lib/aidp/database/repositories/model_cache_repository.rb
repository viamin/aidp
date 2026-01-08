# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      # Repository for model cache
      # Replaces: ~/.aidp/cache/models.json
      #
      # Caches discovered models from AI providers with TTL support
      class ModelCacheRepository < Repository
        DEFAULT_TTL = 86400 # 24 hours in seconds

        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "model_cache")
        end

        # Cache models for a provider
        #
        # @param provider_name [String] Provider name
        # @param models [Array<Hash>] Models array
        # @param ttl [Integer] Time to live in seconds
        # @return [Boolean] Success status
        def cache_models(provider_name, models, ttl: DEFAULT_TTL)
          Aidp.log_debug("model_cache_repo", "cache_models",
            provider: provider_name, count: models.size, ttl: ttl)

          expires_at = Time.now.utc + ttl

          execute(<<~SQL, [project_dir, provider_name, serialize_json(models), current_timestamp, expires_at.strftime("%Y-%m-%d %H:%M:%S")])
            INSERT INTO #{table_name} (project_dir, provider_name, models, cached_at, expires_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(project_dir, provider_name) DO UPDATE SET
              models = excluded.models,
              cached_at = excluded.cached_at,
              expires_at = excluded.expires_at
          SQL

          Aidp.log_info("model_cache_repo", "cached_models",
            provider: provider_name, count: models.size)
          true
        rescue => e
          Aidp.log_error("model_cache_repo", "cache_models_failed",
            provider: provider_name, error: e.message)
          false
        end

        # Get cached models for a provider if not expired
        #
        # @param provider_name [String] Provider name
        # @return [Array<Hash>, nil] Cached models or nil if expired/not found
        def get_cached_models(provider_name)
          Aidp.log_debug("model_cache_repo", "get_cached_models",
            provider: provider_name)

          row = query_one(<<~SQL, [project_dir, provider_name])
            SELECT models, cached_at, expires_at
            FROM #{table_name}
            WHERE project_dir = ? AND provider_name = ?
          SQL

          return nil unless row

          # Check expiration
          if row["expires_at"]
            expires_at = Time.parse(row["expires_at"])
            if Time.now.utc > expires_at
              Aidp.log_debug("model_cache_repo", "cache_expired",
                provider: provider_name, expires_at: expires_at)
              return nil
            end
          end

          models = deserialize_json(row["models"])
          Aidp.log_debug("model_cache_repo", "cache_hit",
            provider: provider_name, count: models&.size || 0)
          models
        end

        # Invalidate cache for a specific provider
        #
        # @param provider_name [String] Provider name
        # @return [Boolean] Success status
        def invalidate(provider_name)
          Aidp.log_debug("model_cache_repo", "invalidate",
            provider: provider_name)

          execute(<<~SQL, [project_dir, provider_name])
            DELETE FROM #{table_name}
            WHERE project_dir = ? AND provider_name = ?
          SQL

          Aidp.log_info("model_cache_repo", "invalidated",
            provider: provider_name)
          true
        rescue => e
          Aidp.log_error("model_cache_repo", "invalidate_failed",
            provider: provider_name, error: e.message)
          false
        end

        # Invalidate all cached models
        #
        # @return [Boolean] Success status
        def invalidate_all
          Aidp.log_debug("model_cache_repo", "invalidate_all")
          delete_by_project
          Aidp.log_info("model_cache_repo", "invalidated_all")
          true
        rescue => e
          Aidp.log_error("model_cache_repo", "invalidate_all_failed",
            error: e.message)
          false
        end

        # Get list of providers with valid cached models
        #
        # @return [Array<String>] Provider names with valid caches
        def cached_providers
          rows = query(<<~SQL, [project_dir])
            SELECT provider_name, expires_at
            FROM #{table_name}
            WHERE project_dir = ?
          SQL

          providers = []
          rows.each do |row|
            next unless row["expires_at"]

            expires_at = Time.parse(row["expires_at"])
            providers << row["provider_name"] if Time.now.utc <= expires_at
          end

          providers
        end

        # Get cache statistics
        #
        # @return [Hash] Statistics
        def stats
          total = query_value(<<~SQL, [project_dir])
            SELECT COUNT(*) FROM #{table_name} WHERE project_dir = ?
          SQL

          valid_providers = cached_providers

          {
            total_providers: total || 0,
            cached_providers: valid_providers,
            valid_count: valid_providers.size
          }
        end

        # Clean up expired entries
        #
        # @return [Integer] Number of entries deleted
        def cleanup_expired
          result = query_value(<<~SQL, [project_dir])
            SELECT COUNT(*) FROM #{table_name}
            WHERE project_dir = ?
              AND expires_at IS NOT NULL
              AND datetime(expires_at) <= datetime('now')
          SQL

          execute(<<~SQL, [project_dir])
            DELETE FROM #{table_name}
            WHERE project_dir = ?
              AND expires_at IS NOT NULL
              AND datetime(expires_at) <= datetime('now')
          SQL

          count = result || 0
          if count > 0
            Aidp.log_info("model_cache_repo", "cleanup_expired",
              deleted: count)
          end
          count
        end

        # Get model count for a provider
        #
        # @param provider_name [String] Provider name
        # @return [Integer] Number of cached models
        def model_count(provider_name)
          models = get_cached_models(provider_name)
          models&.size || 0
        end
      end
    end
  end
end
