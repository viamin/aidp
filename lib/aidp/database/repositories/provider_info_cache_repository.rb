# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      # Repository for provider info cache
      # Replaces: .aidp/providers/{provider_name}_info.yml
      #
      # Stores detailed information about AI providers gathered from CLI introspection
      class ProviderInfoCacheRepository < Repository
        DEFAULT_TTL = 86400 # 24 hours in seconds

        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "provider_info_cache")
        end

        # Store provider info in cache
        #
        # @param provider_name [String] Provider name (e.g., "claude", "cursor")
        # @param info [Hash] Provider info hash
        # @param ttl [Integer] Time to live in seconds
        # @return [Boolean] Success status
        def cache(provider_name, info, ttl: DEFAULT_TTL)
          Aidp.log_debug("provider_info_cache_repo", "cache",
            provider: provider_name, ttl: ttl)

          expires_at = Time.now.utc + ttl

          execute(<<~SQL, [project_dir, provider_name, serialize_json(info), current_timestamp, expires_at.strftime("%Y-%m-%d %H:%M:%S")])
            INSERT INTO #{table_name} (project_dir, provider_name, info, cached_at, expires_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(project_dir, provider_name) DO UPDATE SET
              info = excluded.info,
              cached_at = excluded.cached_at,
              expires_at = excluded.expires_at
          SQL

          true
        rescue => e
          Aidp.log_error("provider_info_cache_repo", "cache_failed",
            provider: provider_name, error: e.message)
          false
        end

        # Get cached provider info if not expired
        #
        # @param provider_name [String] Provider name
        # @return [Hash, nil] Cached info or nil if expired/not found
        def get(provider_name)
          Aidp.log_debug("provider_info_cache_repo", "get", provider: provider_name)

          row = query_one(<<~SQL, [project_dir, provider_name])
            SELECT info, cached_at, expires_at
            FROM #{table_name}
            WHERE project_dir = ? AND provider_name = ?
          SQL

          return nil unless row

          # Check expiration
          if row["expires_at"]
            expires_at = Time.parse(row["expires_at"])
            if Time.now.utc > expires_at
              Aidp.log_debug("provider_info_cache_repo", "cache_expired",
                provider: provider_name, expires_at: expires_at)
              return nil
            end
          end

          deserialize_json(row["info"])
        end

        # Get cached info, ignoring expiration
        #
        # @param provider_name [String] Provider name
        # @return [Hash, nil] Cached info or nil if not found
        def get_stale(provider_name)
          row = query_one(<<~SQL, [project_dir, provider_name])
            SELECT info FROM #{table_name}
            WHERE project_dir = ? AND provider_name = ?
          SQL

          return nil unless row

          deserialize_json(row["info"])
        end

        # Check if cache is stale for a provider
        #
        # @param provider_name [String] Provider name
        # @param max_age [Integer] Maximum age in seconds
        # @return [Boolean] True if stale or not found
        def stale?(provider_name, max_age: DEFAULT_TTL)
          row = query_one(<<~SQL, [project_dir, provider_name])
            SELECT cached_at FROM #{table_name}
            WHERE project_dir = ? AND provider_name = ?
          SQL

          return true unless row

          cached_at = Time.parse(row["cached_at"])
          (Time.now.utc - cached_at) > max_age
        end

        # Invalidate cache for a specific provider
        #
        # @param provider_name [String] Provider name
        def invalidate(provider_name)
          Aidp.log_debug("provider_info_cache_repo", "invalidate",
            provider: provider_name)

          execute(<<~SQL, [project_dir, provider_name])
            DELETE FROM #{table_name}
            WHERE project_dir = ? AND provider_name = ?
          SQL
        end

        # Invalidate all cached providers for project
        def invalidate_all
          Aidp.log_debug("provider_info_cache_repo", "invalidate_all")
          delete_by_project
        end

        # List all cached providers
        #
        # @param include_expired [Boolean] Include expired entries
        # @return [Array<String>] Provider names
        def cached_providers(include_expired: false)
          sql = if include_expired
            <<~SQL
              SELECT provider_name FROM #{table_name}
              WHERE project_dir = ?
              ORDER BY provider_name
            SQL
          else
            <<~SQL
              SELECT provider_name FROM #{table_name}
              WHERE project_dir = ?
                AND (expires_at IS NULL OR datetime(expires_at) > datetime('now'))
              ORDER BY provider_name
            SQL
          end

          query(sql, [project_dir]).map { |row| row["provider_name"] }
        end

        # Get cache statistics
        #
        # @return [Hash] Statistics
        def stats
          total = query_value(<<~SQL, [project_dir])
            SELECT COUNT(*) FROM #{table_name} WHERE project_dir = ?
          SQL

          valid = query_value(<<~SQL, [project_dir])
            SELECT COUNT(*) FROM #{table_name}
            WHERE project_dir = ?
              AND (expires_at IS NULL OR datetime(expires_at) > datetime('now'))
          SQL

          expired = query_value(<<~SQL, [project_dir])
            SELECT COUNT(*) FROM #{table_name}
            WHERE project_dir = ?
              AND expires_at IS NOT NULL
              AND datetime(expires_at) <= datetime('now')
          SQL

          {
            total_cached: total || 0,
            valid_entries: valid || 0,
            expired_entries: expired || 0,
            providers: cached_providers(include_expired: true)
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
            Aidp.log_info("provider_info_cache_repo", "cleanup_expired",
              deleted: count)
          end
          count
        end
      end
    end
  end
end
