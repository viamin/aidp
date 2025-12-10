# frozen_string_literal: true

module Aidp
  module Security
    # Exception raised when a Rule of Two policy violation occurs
    # Contains detailed context about the violation for logging and debugging
    class PolicyViolation < StandardError
      attr_reader :flag, :source, :current_state, :suggested_mitigations

      def initialize(flag:, source:, current_state:, message: nil)
        @flag = flag
        @source = source
        @current_state = current_state
        @suggested_mitigations = build_suggested_mitigations(flag, current_state)

        super(message || default_message)
      end

      # Export violation details for logging
      def to_h
        {
          type: "rule_of_two_violation",
          flag_attempted: @flag,
          source: @source,
          current_state: @current_state,
          suggested_mitigations: @suggested_mitigations,
          timestamp: Time.now.iso8601
        }
      end

      # JSON representation for structured logging
      def to_json(*args)
        to_h.to_json(*args)
      end

      private

      def default_message
        "Rule of Two violation: Cannot enable '#{@flag}' - would create lethal trifecta"
      end

      # Build contextual mitigation suggestions based on which flags are enabled
      def build_suggested_mitigations(flag, state)
        mitigations = []

        # Suggest based on which flags would form the trifecta
        if state[:untrusted_input]
          mitigations << {
            action: "sanitize_input",
            description: "Sanitize the untrusted input before processing to remove the untrusted_input flag",
            command: "aidp security sanitize-input --source <source>"
          }
        end

        if state[:private_data]
          mitigations << {
            action: "use_secrets_proxy",
            description: "Route credential access through the Secrets Proxy to get short-lived tokens",
            command: "aidp security proxy-request --secret <name>"
          }
        end

        if state[:egress]
          mitigations << {
            action: "disable_egress",
            description: "Disable external communication for this operation",
            command: "Use deterministic unit or sandbox the operation"
          }
        end

        # Add flag-specific suggestion for the attempted flag
        case flag
        when :untrusted_input
          mitigations << {
            action: "validate_source",
            description: "Validate and trust the input source (e.g., from trusted author allowlist)",
            command: "Add author to watch.safety.author_allowlist in aidp.yml"
          }
        when :private_data
          mitigations << {
            action: "scope_credentials",
            description: "Use capability-scoped tokens instead of full credentials",
            command: "aidp security register-secret --scoped"
          }
        when :egress
          mitigations << {
            action: "queue_for_approval",
            description: "Queue the operation for manual execution outside the agent context",
            command: "Operation will be logged for manual review"
          }
        end

        mitigations.uniq { |m| m[:action] }
      end
    end

    # Exception raised when secrets proxy cannot fulfill a request
    class SecretsProxyError < StandardError
      attr_reader :secret_name, :reason

      def initialize(secret_name:, reason:)
        @secret_name = secret_name
        @reason = reason
        super("Secrets proxy error for '#{secret_name}': #{reason}")
      end
    end

    # Exception raised when attempting to access an unregistered secret
    class UnregisteredSecretError < SecretsProxyError
      def initialize(secret_name:)
        super(
          secret_name: secret_name,
          reason: "Secret not registered. Use 'aidp security register-secret #{secret_name}' to register."
        )
      end
    end

    # Exception raised when a token has expired
    class TokenExpiredError < SecretsProxyError
      def initialize(secret_name:, expired_at:)
        super(
          secret_name: secret_name,
          reason: "Token expired at #{expired_at}. Request a new token via the secrets proxy."
        )
      end
    end
  end
end
