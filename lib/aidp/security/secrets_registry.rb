# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "time"

module Aidp
  module Security
    # Registry for user-declared secrets that should be proxied
    # Secrets are registered by name, with the actual value stored securely
    # and never exposed directly to agents.
    #
    # Storage: .aidp/security/secrets_registry.json
    # Format: { "SECRET_NAME": { "env_var": "ACTUAL_ENV_VAR", "registered_at": timestamp } }
    #
    # The registry only stores metadata - actual secret values come from environment
    # variables at runtime. This ensures secrets are never persisted to disk.
    class SecretsRegistry
      REGISTRY_FILENAME = "secrets_registry.json"

      attr_reader :project_dir

      def initialize(project_dir: Dir.pwd)
        @project_dir = project_dir
        @cache = nil
        @cache_mtime = nil
        @mutex = Mutex.new
      end

      # Register a secret by name
      # @param name [String] The name to reference this secret by
      # @param env_var [String] The environment variable containing the secret
      # @param description [String] Optional description of what this secret is for
      # @param scopes [Array<String>] Optional list of allowed operations for this secret
      # @return [Hash] Registration details
      def register(name:, env_var:, description: nil, scopes: [])
        @mutex.synchronize do
          registry = load_registry

          # Validate the environment variable exists (but don't store the value)
          unless ENV.key?(env_var)
            Aidp.log_warn("security.registry", "env_var_not_found",
              name: name,
              env_var: env_var)
          end

          registration = {
            env_var: env_var,
            description: description,
            scopes: scopes,
            registered_at: Time.now.iso8601,
            id: SecureRandom.hex(8)
          }

          registry[name] = registration
          save_registry(registry)

          Aidp.log_info("security.registry", "secret_registered",
            name: name,
            env_var: env_var,
            scopes: scopes)

          registration.merge(name: name)
        end
      end

      # Unregister a secret
      # @param name [String] The secret name to remove
      # @return [Boolean] true if removed, false if not found
      def unregister(name:)
        @mutex.synchronize do
          registry = load_registry

          key = registry.key?(name.to_sym) ? name.to_sym : name.to_s
          unless registry.key?(key)
            Aidp.log_warn("security.registry", "secret_not_found_for_unregister",
              name: name)
            return false
          end

          registry.delete(key)
          save_registry(registry)

          Aidp.log_info("security.registry", "secret_unregistered", name: name)
          true
        end
      end

      # Check if a secret is registered
      # @param name [String] The secret name
      # @return [Boolean]
      def registered?(name)
        @mutex.synchronize do
          registry = load_registry
          registry.key?(name.to_sym) || registry.key?(name.to_s)
        end
      end

      # Get registration details for a secret (without the actual value)
      # @param name [String] The secret name
      # @return [Hash, nil] Registration details or nil if not found
      def get(name)
        @mutex.synchronize do
          registry = load_registry
          entry = registry[name.to_sym] || registry[name.to_s]
          return nil unless entry

          entry.merge(name: name)
        end
      end

      # Get the environment variable name for a secret
      # @param name [String] The secret name
      # @return [String, nil] The env var name or nil if not registered
      def env_var_for(name)
        entry = get(name)
        entry&.dig(:env_var) || entry&.dig("env_var")
      end

      # List all registered secrets (names and metadata only, never values)
      # @return [Array<Hash>] List of registered secrets with metadata
      def list
        @mutex.synchronize do
          registry = load_registry
          registry.map do |name, details|
            {
              name: name,
              env_var: details[:env_var] || details["env_var"],
              description: details[:description] || details["description"],
              scopes: details[:scopes] || details["scopes"] || [],
              registered_at: details[:registered_at] || details["registered_at"],
              has_value: ENV.key?(details[:env_var] || details["env_var"])
            }
          end
        end
      end

      # Get list of environment variables that should be stripped from agent environment
      # @return [Array<String>] List of env var names to remove
      def env_vars_to_strip
        @mutex.synchronize do
          registry = load_registry
          registry.values.map { |entry| entry[:env_var] || entry["env_var"] }.compact.uniq
        end
      end

      # Check if an environment variable is registered as a secret
      # @param env_var [String] The environment variable name
      # @return [Boolean]
      def env_var_registered?(env_var)
        @mutex.synchronize do
          registry = load_registry
          registry.values.any? { |entry| (entry[:env_var] || entry["env_var"]) == env_var }
        end
      end

      # Get the secret name for an environment variable
      # @param env_var [String] The environment variable name
      # @return [String, nil] The secret name or nil if not found
      def name_for_env_var(env_var)
        @mutex.synchronize do
          registry = load_registry
          registry.find { |_name, entry| (entry[:env_var] || entry["env_var"]) == env_var }&.first
        end
      end

      # Clear the in-memory cache (forces reload on next access)
      def clear_cache!
        @mutex.synchronize do
          @cache = nil
          @cache_mtime = nil
        end
      end

      private

      def registry_path
        File.join(@project_dir, ".aidp", "security", REGISTRY_FILENAME)
      end

      def ensure_security_dir
        dir = File.dirname(registry_path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end

      def load_registry
        # Check if cache is still valid based on file mtime
        return @cache if cache_valid?

        if File.exist?(registry_path)
          content = File.read(registry_path)
          @cache = JSON.parse(content, symbolize_names: true)
          @cache_mtime = File.mtime(registry_path)
          Aidp.log_debug("security.registry", "cache_loaded", path: registry_path)
        else
          @cache = {}
          @cache_mtime = nil
        end

        @cache
      rescue JSON::ParserError => e
        Aidp.log_error("security.registry", "failed_to_parse_registry",
          error: e.message,
          path: registry_path)
        @cache = {}
        @cache_mtime = nil
        @cache
      end

      def cache_valid?
        return false unless @cache
        return true unless File.exist?(registry_path)

        current_mtime = File.mtime(registry_path)
        @cache_mtime && current_mtime == @cache_mtime
      end

      def save_registry(registry)
        ensure_security_dir
        File.write(registry_path, JSON.pretty_generate(registry))
        @cache = registry
        @cache_mtime = File.mtime(registry_path)
      end
    end
  end
end
