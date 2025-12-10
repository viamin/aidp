# frozen_string_literal: true

require "securerandom"
require "json"

module Aidp
  module Security
    # Broker for credential access - agents never receive raw secrets
    # Instead, the proxy issues short-lived, capability-scoped tokens
    # that are exchanged for actual credentials at execution time.
    #
    # Flow:
    # 1. User registers secret: aidp security register-secret GITHUB_TOKEN
    # 2. Agent requests credential access via proxy
    # 3. Proxy issues short-lived token (e.g., 5 minutes)
    # 4. At execution time, token is exchanged for actual credential
    # 5. Actual credential is used only in isolated execution context
    #
    # This design ensures:
    # - Agents never see raw credentials
    # - Credential access is auditable
    # - Tokens are scoped and time-limited
    # - Compromised agent output can't leak credentials
    class SecretsProxy
      DEFAULT_TOKEN_TTL = 300 # 5 minutes

      attr_reader :registry, :config

      def initialize(registry:, config: {})
        @registry = registry
        @config = config
        @active_tokens = {}
        @token_usage_log = []
        @mutex = Mutex.new
      end

      # Request a token for accessing a registered secret
      # @param secret_name [String] The registered secret name
      # @param scope [String] The intended use of this token (for audit)
      # @param ttl [Integer] Token time-to-live in seconds
      # @return [Hash] Token details { token:, expires_at:, secret_name:, scope: }
      # @raise [UnregisteredSecretError] if secret is not registered
      def request_token(secret_name:, scope: nil, ttl: nil)
        @mutex.synchronize do
          # Verify secret is registered
          registration = @registry.get(secret_name)
          unless registration
            raise UnregisteredSecretError.new(secret_name: secret_name)
          end

          # Check scope is allowed if scopes are defined
          allowed_scopes = registration[:scopes] || registration["scopes"] || []
          if allowed_scopes.any? && scope && !allowed_scopes.include?(scope)
            raise SecretsProxyError.new(
              secret_name: secret_name,
              reason: "Scope '#{scope}' not allowed. Allowed scopes: #{allowed_scopes.join(", ")}"
            )
          end

          # Generate token
          token = generate_token
          token_ttl = ttl || @config.fetch(:token_ttl, DEFAULT_TOKEN_TTL)
          expires_at = Time.now + token_ttl

          token_data = {
            token: token,
            secret_name: secret_name,
            scope: scope,
            expires_at: expires_at,
            created_at: Time.now,
            env_var: registration[:env_var] || registration["env_var"],
            used: false
          }

          @active_tokens[token] = token_data

          Aidp.log_debug("security.proxy", "token_issued",
            secret_name: secret_name,
            scope: scope,
            expires_in: token_ttl,
            token_prefix: token[0..7])

          {
            token: token,
            expires_at: expires_at.iso8601,
            secret_name: secret_name,
            scope: scope,
            ttl: token_ttl
          }
        end
      end

      # Exchange a token for the actual credential value
      # This should only be called in the isolated execution context
      # @param token [String] The proxy token
      # @return [String] The actual credential value
      # @raise [TokenExpiredError] if token has expired
      # @raise [SecretsProxyError] if token is invalid
      def exchange_token(token)
        @mutex.synchronize do
          token_data = @active_tokens[token]

          unless token_data
            Aidp.log_warn("security.proxy", "invalid_token_exchange",
              token_prefix: token[0..7] || "nil")
            raise SecretsProxyError.new(
              secret_name: "unknown",
              reason: "Invalid or unknown token"
            )
          end

          if Time.now > token_data[:expires_at]
            @active_tokens.delete(token)
            raise TokenExpiredError.new(
              secret_name: token_data[:secret_name],
              expired_at: token_data[:expires_at].iso8601
            )
          end

          # Get actual value from environment
          env_var = token_data[:env_var]
          value = ENV[env_var]

          unless value
            raise SecretsProxyError.new(
              secret_name: token_data[:secret_name],
              reason: "Environment variable '#{env_var}' not set"
            )
          end

          # Mark token as used and log
          token_data[:used] = true
          token_data[:used_at] = Time.now

          log_token_usage(token_data)

          Aidp.log_debug("security.proxy", "token_exchanged",
            secret_name: token_data[:secret_name],
            scope: token_data[:scope],
            token_prefix: token[0..7])

          # Return the actual secret value
          # This value should ONLY be used in isolated execution context
          value
        end
      end

      # Revoke a token before it expires
      # @param token [String] The token to revoke
      # @return [Boolean] true if revoked, false if not found
      def revoke_token(token)
        @mutex.synchronize do
          if @active_tokens.delete(token)
            Aidp.log_info("security.proxy", "token_revoked",
              token_prefix: token[0..7])
            true
          else
            false
          end
        end
      end

      # Revoke all tokens for a specific secret
      # @param secret_name [String] The secret name
      # @return [Integer] Number of tokens revoked
      def revoke_all_for_secret(secret_name)
        @mutex.synchronize do
          tokens_to_revoke = @active_tokens.select { |_t, d| d[:secret_name] == secret_name }
          count = tokens_to_revoke.size

          tokens_to_revoke.keys.each { |t| @active_tokens.delete(t) }

          Aidp.log_info("security.proxy", "tokens_revoked_for_secret",
            secret_name: secret_name,
            count: count)

          count
        end
      end

      # Clean up expired tokens
      # @return [Integer] Number of expired tokens removed
      def cleanup_expired!
        @mutex.synchronize do
          now = Time.now
          expired = @active_tokens.select { |_t, d| now > d[:expires_at] }
          count = expired.size

          expired.keys.each { |t| @active_tokens.delete(t) }

          if count > 0
            Aidp.log_debug("security.proxy", "expired_tokens_cleaned",
              count: count)
          end

          count
        end
      end

      # Get list of active tokens (for status display)
      # @return [Array<Hash>] Token summaries (never includes actual token values)
      def active_tokens_summary
        @mutex.synchronize do
          @active_tokens.values.map do |data|
            {
              secret_name: data[:secret_name],
              scope: data[:scope],
              expires_at: data[:expires_at].iso8601,
              created_at: data[:created_at].iso8601,
              used: data[:used],
              remaining_ttl: [(data[:expires_at] - Time.now).to_i, 0].max
            }
          end
        end
      end

      # Get usage audit log
      # @param limit [Integer] Maximum entries to return
      # @return [Array<Hash>] Recent token usage records
      def usage_log(limit: 50)
        @mutex.synchronize do
          @token_usage_log.last(limit)
        end
      end

      # Build a sanitized environment hash with registered secrets stripped
      # @param base_env [Hash] The base environment (defaults to ENV.to_h)
      # @return [Hash] Environment with registered secrets removed
      def sanitized_environment(base_env = ENV.to_h)
        env = base_env.dup
        vars_to_strip = @registry.env_vars_to_strip

        vars_to_strip.each do |var|
          if env.key?(var)
            env.delete(var)
            Aidp.log_debug("security.proxy", "env_var_stripped",
              env_var: var)
          end
        end

        env
      end

      # Execute a block with a sanitized environment
      # Registered secrets are stripped from ENV during execution
      # @yield The block to execute in sanitized environment
      # @return [Object] The result of the block
      def with_sanitized_environment
        original_env = {}
        vars_to_strip = @registry.env_vars_to_strip

        # Save and clear registered secrets
        vars_to_strip.each do |var|
          if ENV.key?(var)
            original_env[var] = ENV[var]
            ENV.delete(var)
          end
        end

        Aidp.log_debug("security.proxy", "environment_sanitized",
          stripped_count: original_env.size)

        begin
          yield
        ensure
          # Restore secrets
          original_env.each { |k, v| ENV[k] = v }

          Aidp.log_debug("security.proxy", "environment_restored",
            restored_count: original_env.size)
        end
      end

      # Reset proxy state (primarily for testing)
      def reset!
        @mutex.synchronize do
          @active_tokens.clear
          @token_usage_log.clear
        end
      end

      private

      def generate_token
        "aidp_proxy_#{SecureRandom.hex(24)}"
      end

      def log_token_usage(token_data)
        @token_usage_log << {
          secret_name: token_data[:secret_name],
          scope: token_data[:scope],
          created_at: token_data[:created_at].iso8601,
          used_at: token_data[:used_at].iso8601,
          ttl_remaining: (token_data[:expires_at] - token_data[:used_at]).to_i
        }

        # Keep log bounded
        @token_usage_log.shift if @token_usage_log.size > 1000
      end
    end
  end
end
