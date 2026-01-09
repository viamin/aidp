# frozen_string_literal: true

require_relative "../repository"
require "securerandom"

module Aidp
  module Database
    module Repositories
      # Repository for secrets_registry table
      # Replaces security/secrets_registry.json
      # Note: Only stores metadata about secrets, never actual values
      class SecretsRepository < Repository
        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "secrets_registry")
        end

        # Register a secret
        #
        # @param name [String] Secret name
        # @param env_var [String] Environment variable containing the secret
        # @param description [String, nil] Description
        # @param scopes [Array<String>] Allowed operation scopes
        # @return [Hash] Registration details
        def register(name:, env_var:, description: nil, scopes: [])
          now = current_timestamp
          secret_id = SecureRandom.hex(8)

          # Warn if env var doesn't exist
          unless ENV.key?(env_var)
            Aidp.log_warn("secrets_repository", "env_var_not_found",
              name: name, env_var: env_var)
          end

          execute(
            insert_sql([
              :project_dir, :secret_id, :secret_name, :env_var,
              :description, :scopes, :registered_at
            ]),
            [
              project_dir,
              secret_id,
              name,
              env_var,
              description,
              serialize_json(scopes),
              now
            ]
          )

          Aidp.log_debug("secrets_repository", "registered",
            name: name, env_var: env_var)

          {
            id: secret_id,
            name: name,
            env_var: env_var,
            description: description,
            scopes: scopes,
            registered_at: now
          }
        end

        # Unregister a secret
        #
        # @param name [String] Secret name
        # @return [Boolean] true if removed
        def unregister(name:)
          existing = find(name)
          return false unless existing

          execute(
            "DELETE FROM secrets_registry WHERE project_dir = ? AND secret_name = ?",
            [project_dir, name]
          )

          Aidp.log_debug("secrets_repository", "unregistered", name: name)
          true
        end

        # Check if secret is registered
        #
        # @param name [String] Secret name
        # @return [Boolean]
        def registered?(name)
          count = query_value(
            "SELECT COUNT(*) FROM secrets_registry WHERE project_dir = ? AND secret_name = ?",
            [project_dir, name]
          )
          count.positive?
        end

        # Get registration details
        #
        # @param name [String] Secret name
        # @return [Hash, nil] Registration or nil
        def find(name)
          row = query_one(
            "SELECT * FROM secrets_registry WHERE project_dir = ? AND secret_name = ?",
            [project_dir, name]
          )
          deserialize_secret(row)
        end

        # Alias for find
        alias_method :get, :find

        # Get env var for a secret
        #
        # @param name [String] Secret name
        # @return [String, nil] Env var name or nil
        def env_var_for(name)
          row = query_one(
            "SELECT env_var FROM secrets_registry WHERE project_dir = ? AND secret_name = ?",
            [project_dir, name]
          )
          row&.dig("env_var")
        end

        # List all registered secrets
        #
        # @return [Array<Hash>]
        def list
          rows = query(
            "SELECT * FROM secrets_registry WHERE project_dir = ? ORDER BY registered_at",
            [project_dir]
          )

          rows.map do |row|
            secret = deserialize_secret(row)
            secret[:has_value] = ENV.key?(secret[:env_var]) if secret
            secret
          end.compact
        end

        # Get env vars that should be stripped
        #
        # @return [Array<String>]
        def env_vars_to_strip
          rows = query(
            "SELECT DISTINCT env_var FROM secrets_registry WHERE project_dir = ?",
            [project_dir]
          )
          rows.map { |r| r["env_var"] }.compact
        end

        # Check if an env var is registered
        #
        # @param env_var [String] Environment variable name
        # @return [Boolean]
        def env_var_registered?(env_var)
          count = query_value(
            "SELECT COUNT(*) FROM secrets_registry WHERE project_dir = ? AND env_var = ?",
            [project_dir, env_var]
          )
          count.positive?
        end

        # Get secret name for an env var
        #
        # @param env_var [String] Environment variable name
        # @return [String, nil] Secret name or nil
        def name_for_env_var(env_var)
          row = query_one(
            "SELECT secret_name FROM secrets_registry WHERE project_dir = ? AND env_var = ?",
            [project_dir, env_var]
          )
          row&.dig("secret_name")
        end

        private

        def deserialize_secret(row)
          return nil unless row

          {
            id: row["secret_id"],
            name: row["secret_name"],
            env_var: row["env_var"],
            description: row["description"],
            scopes: deserialize_json(row["scopes"]) || [],
            registered_at: row["registered_at"]
          }
        end
      end
    end
  end
end
