# frozen_string_literal: true

# Security module for AIDP - Implements "Rule of Two" security framework
# Based on Meta's agentic security principles to prevent prompt injection attacks
#
# Core concept: Never enable more than two of three dangerous conditions:
# 1. untrusted_input - Processing untrusted content (issues, PRs, external data)
# 2. private_data    - Access to secrets, credentials, or sensitive data
# 3. egress          - Ability to communicate externally (git push, API calls, etc.)
#
# When all three would be active ("lethal trifecta"), the operation is denied.

require_relative "security/trifecta_state"
require_relative "security/rule_of_two_enforcer"
require_relative "security/policy_violation"
require_relative "security/secrets_registry"
require_relative "security/secrets_proxy"
require_relative "security/work_loop_adapter"
require_relative "security/watch_mode_handler"

module Aidp
  module Security
    class << self
      # Get the global enforcer instance
      def enforcer
        @enforcer ||= RuleOfTwoEnforcer.new
      end

      # Get the global secrets registry
      def secrets_registry
        @secrets_registry ||= SecretsRegistry.new
      end

      # Get the global secrets proxy
      def secrets_proxy
        @secrets_proxy ||= SecretsProxy.new(registry: secrets_registry)
      end

      # Reset all security state (primarily for testing)
      def reset!
        @enforcer = nil
        @secrets_registry = nil
        @secrets_proxy = nil
      end

      # Check if security features are enabled
      def enabled?(project_dir = Dir.pwd)
        config = Aidp::Config.load(project_dir)
        security_config = config[:security] || config["security"] || {}
        rule_of_two_config = security_config[:rule_of_two] || security_config["rule_of_two"] || {}
        rule_of_two_config[:enabled] != false # Default to enabled
      end
    end
  end
end
