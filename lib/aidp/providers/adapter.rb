# frozen_string_literal: true

module Aidp
  module Providers
    # ProviderAdapter defines the standardized interface that all provider implementations
    # must conform to. This ensures consistent behavior across different AI model providers
    # while allowing for provider-specific implementations.
    #
    # Design Philosophy:
    # - Adapters are stateless; delegate throttling, retries, and escalation to coordinator
    # - Store provider-specific regex matchers adjacent to adapters for maintainability
    # - Single semantic flags map to provider-specific equivalents
    #
    # @see https://github.com/viamin/aidp/issues/243
    module Adapter
      # Core interface methods that all providers must implement

      # Provider identifier (e.g., "anthropic", "cursor", "gemini")
      # @return [String] unique lowercase identifier for this provider
      def name
        raise NotImplementedError, "#{self.class} must implement #name"
      end

      # Human-friendly display name for UI
      # @return [String] display name (e.g., "Anthropic Claude", "Cursor AI")
      def display_name
        name
      end

      # Send a message to the provider and get a response
      # @param prompt [String] the prompt to send
      # @param session [String, nil] optional session identifier for context
      # @param options [Hash] additional options for the request
      # @return [Hash, String] provider response
      def send_message(prompt:, session: nil, **options)
        raise NotImplementedError, "#{self.class} must implement #send_message"
      end

      # Capability declaration methods

      # Check if the provider supports Model Context Protocol
      # @return [Boolean] true if MCP is supported
      def supports_mcp?
        false
      end

      # Fetch MCP servers configured for this provider
      # @return [Array<Hash>] array of MCP server configurations
      def fetch_mcp_servers
        []
      end

      # Check if the provider is available on this system
      # @return [Boolean] true if provider CLI or API is accessible
      def available?
        true
      end

      # Declare provider capabilities
      # @return [Hash] capabilities hash with feature flags
      # @example
      #   {
      #     reasoning_tiers: ["mini", "standard", "thinking"],
      #     context_window: 200_000,
      #     supports_json_mode: true,
      #     supports_tool_use: true,
      #     supports_vision: false,
      #     supports_file_upload: true
      #   }
      def capabilities
        {
          reasoning_tiers: [],
          context_window: 100_000,
          supports_json_mode: false,
          supports_tool_use: false,
          supports_vision: false,
          supports_file_upload: false
        }
      end

      # Dangerous permissions abstraction

      # Check if the provider supports dangerous/elevated permissions mode
      # @return [Boolean] true if dangerous mode is supported
      def supports_dangerous_mode?
        false
      end

      # Get the provider-specific flag(s) for enabling dangerous mode
      # Maps the semantic `dangerous: true` flag to provider-specific equivalents
      # @return [Array<String>] provider-specific CLI flags
      # @example Anthropic
      #   ["--dangerously-skip-permissions"]
      # @example Gemini (hypothetical)
      #   ["--yolo"]
      def dangerous_mode_flags
        []
      end

      # Check if dangerous mode is currently enabled
      # @return [Boolean] true if dangerous mode is active
      def dangerous_mode_enabled?
        @dangerous_mode_enabled ||= false
      end

      # Enable or disable dangerous mode
      # @param enabled [Boolean] whether to enable dangerous mode
      # @return [void]
      def dangerous_mode=(enabled)
        @dangerous_mode_enabled = enabled
      end

      # Session management abstraction
      #
      # Sessions allow providers to maintain conversation context across multiple
      # interactions. The session parameter in send_message is an opaque string
      # that is passed to the provider CLI in a provider-specific way.
      #
      # Provider implementations:
      # - Anthropic Claude: Currently not used (Claude CLI manages sessions internally)
      # - GitHub Copilot: --resume <session_id>
      # - Codex: --session <session_id>
      # - Aider: --history-file <path>
      # - Others: May not support sessions
      #
      # Consumers should:
      # - Check supports_sessions? before using session parameter
      # - Generate unique session IDs (UUIDs recommended)
      # - Store session IDs for later continuation
      # - Not assume session persistence across provider restarts

      # Check if the provider supports session continuation.
      # Providers that don't support sessions return false (the default).
      # Callers should check this before using the session parameter in send_message.
      #
      # @return [Boolean] true if session parameter is supported, false otherwise
      def supports_sessions?
        false
      end

      # Get the provider-specific flag for session continuation.
      # Returns nil for providers that don't support sessions (supports_sessions? == false).
      # Callers should check supports_sessions? before using this value.
      #
      # @return [String, nil] CLI flag name (e.g., "--resume", "--session"),
      #   or nil if sessions are not supported
      def session_flag
        nil
      end

      # Error classification and handling

      # Get error classification regex patterns for this provider
      # @return [Hash<Symbol, Array<Regexp>>] mapping of error categories to regex patterns
      # @example
      #   {
      #     rate_limited: [/rate.?limit/i, /quota.*exceeded/i],
      #     auth_expired: [/authentication.*failed/i, /invalid.*api.*key/i],
      #     quota_exceeded: [/quota.*exceeded/i, /usage.*limit/i],
      #     transient: [/timeout/i, /connection.*reset/i, /temporary.*error/i],
      #     permanent: [/invalid.*model/i, /unsupported.*operation/i]
      #   }
      def error_patterns
        {}
      end

      # Classify an error into the standardized error taxonomy
      # @param error [StandardError] the error to classify
      # @return [Symbol] error category (:rate_limited, :auth_expired, :quota_exceeded, :transient, :permanent)
      def classify_error(error)
        message = error.message.to_s

        # First check provider-specific patterns
        error_patterns.each do |category, patterns|
          patterns.each do |pattern|
            return category if message.match?(pattern)
          end
        end

        # Fall back to ErrorTaxonomy for classification
        require_relative "error_taxonomy"
        Aidp::Providers::ErrorTaxonomy.classify_message(message)
      end

      # Get normalized error metadata
      # @param error [StandardError] the error to process
      # @return [Hash] normalized error information
      def error_metadata(error)
        {
          provider: name,
          error_category: classify_error(error),
          error_class: error.class.name,
          message: redact_secrets(error.message),
          timestamp: Time.now.iso8601,
          retryable: retryable_error?(error)
        }
      end

      # Check if an error is retryable
      # @param error [StandardError] the error to check
      # @return [Boolean] true if the error should be retried
      def retryable_error?(error)
        category = classify_error(error)
        [:transient].include?(category)
      end

      # Logging and metrics

      # Get logging metadata for this provider
      # @return [Hash] metadata for structured logging
      def logging_metadata
        {
          provider: name,
          display_name: display_name,
          supports_mcp: supports_mcp?,
          available: available?,
          dangerous_mode: dangerous_mode_enabled?
        }
      end

      # Redact secrets from log messages
      # @param message [String] message potentially containing secrets
      # @return [String] message with secrets redacted
      def redact_secrets(message)
        # Redact common secret patterns
        message = message.gsub(/api[_-]?key[:\s=]+[^\s&]+/i, "api_key=[REDACTED]")
        message = message.gsub(/token[:\s=]+[^\s&]+/i, "token=[REDACTED]")
        message = message.gsub(/password[:\s=]+[^\s&]+/i, "password=[REDACTED]")
        message = message.gsub(/bearer\s+[^\s&]+/i, "bearer [REDACTED]")
        message.gsub(/sk-[a-zA-Z0-9_-]{20,}/i, "sk-[REDACTED]")
      end

      # Configuration validation

      # Validate provider configuration
      # @param config [Hash] configuration to validate
      # @return [Hash] validation result with :valid, :errors, :warnings keys
      def validate_config(config)
        errors = []
        warnings = []

        # Validate required fields
        unless config[:type]
          errors << "Provider type is required"
        end

        unless ["usage_based", "subscription", "passthrough"].include?(config[:type])
          errors << "Provider type must be one of: usage_based, subscription, passthrough"
        end

        # Validate models if present
        if config[:models] && !config[:models].is_a?(Array)
          errors << "Models must be an array"
        end

        {
          valid: errors.empty?,
          errors: errors,
          warnings: warnings
        }
      end

      # Provider health and status

      # Check provider health
      # @return [Hash] health status information
      def health_status
        {
          provider: name,
          available: available?,
          healthy: available?,
          timestamp: Time.now.iso8601
        }
      end
    end
  end
end
