# frozen_string_literal: true

module Aidp
  module AutoUpdate
    # Value object representing auto-update configuration policy
    class UpdatePolicy
      attr_reader :enabled, :policy, :allow_prerelease, :check_interval_seconds,
        :supervisor, :max_consecutive_failures

      VALID_POLICIES = %w[off exact patch minor major].freeze
      VALID_SUPERVISORS = %w[none supervisord s6 runit].freeze

      def initialize(
        enabled: false,
        policy: "off",
        allow_prerelease: false,
        check_interval_seconds: 3600,
        supervisor: "none",
        max_consecutive_failures: 3
      )
        @enabled = enabled
        @policy = validate_policy(policy)
        @allow_prerelease = allow_prerelease
        @check_interval_seconds = validate_interval(check_interval_seconds)
        @supervisor = validate_supervisor(supervisor)
        @max_consecutive_failures = validate_max_failures(max_consecutive_failures)
      end

      # Create from configuration hash
      # @param config [Hash] Configuration hash from aidp.yml
      # @return [UpdatePolicy]
      def self.from_config(config)
        return disabled unless config

        new(
          enabled: config[:enabled] || config["enabled"] || false,
          policy: config[:policy] || config["policy"] || "off",
          allow_prerelease: config[:allow_prerelease] || config["allow_prerelease"] || false,
          check_interval_seconds: config[:check_interval_seconds] || config["check_interval_seconds"] || 3600,
          supervisor: config[:supervisor] || config["supervisor"] || "none",
          max_consecutive_failures: config[:max_consecutive_failures] || config["max_consecutive_failures"] || 3
        )
      end

      # Create a disabled policy
      # @return [UpdatePolicy]
      def self.disabled
        new(enabled: false, policy: "off")
      end

      # Check if updates are completely disabled
      # @return [Boolean]
      def disabled?
        !@enabled || @policy == "off"
      end

      # Check if a supervisor is configured
      # @return [Boolean]
      def supervised?
        @supervisor != "none"
      end

      # Convert to hash for serialization
      # @return [Hash]
      def to_h
        {
          enabled: @enabled,
          policy: @policy,
          allow_prerelease: @allow_prerelease,
          check_interval_seconds: @check_interval_seconds,
          supervisor: @supervisor,
          max_consecutive_failures: @max_consecutive_failures
        }
      end

      private

      def validate_policy(policy)
        unless VALID_POLICIES.include?(policy.to_s)
          raise ArgumentError, "Invalid policy: #{policy}. Must be one of: #{VALID_POLICIES.join(", ")}"
        end
        policy.to_s
      end

      def validate_supervisor(supervisor)
        unless VALID_SUPERVISORS.include?(supervisor.to_s)
          raise ArgumentError, "Invalid supervisor: #{supervisor}. Must be one of: #{VALID_SUPERVISORS.join(", ")}"
        end
        supervisor.to_s
      end

      def validate_interval(interval)
        interval = interval.to_i
        if interval < 300 || interval > 86400
          raise ArgumentError, "Invalid check_interval_seconds: #{interval}. Must be between 300 and 86400"
        end
        interval
      end

      def validate_max_failures(max_failures)
        max_failures = max_failures.to_i
        if max_failures < 1 || max_failures > 10
          raise ArgumentError, "Invalid max_consecutive_failures: #{max_failures}. Must be between 1 and 10"
        end
        max_failures
      end
    end
  end
end
