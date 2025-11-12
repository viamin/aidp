# frozen_string_literal: true

require "time"

module Aidp
  module AutoUpdate
    # Value object representing the result of an update check
    class UpdateCheck
      attr_reader :current_version, :available_version, :update_available,
        :update_allowed, :policy_reason, :checked_at, :error

      def initialize(
        current_version:,
        available_version:,
        update_available:,
        update_allowed:,
        policy_reason: nil,
        checked_at: Time.now,
        error: nil
      )
        @current_version = current_version
        @available_version = available_version
        @update_available = update_available
        @update_allowed = update_allowed
        @policy_reason = policy_reason
        @checked_at = checked_at
        @error = error
      end

      # Create a failed update check
      # @param error_message [String] Error message
      # @param current_version [String] Current version
      # @return [UpdateCheck]
      def self.failed(error_message, current_version: Aidp::VERSION)
        new(
          current_version: current_version,
          available_version: current_version,
          update_available: false,
          update_allowed: false,
          policy_reason: "Update check failed",
          error: error_message
        )
      end

      # Create an unavailable update check (service temporarily unavailable)
      # @param current_version [String] Current version
      # @return [UpdateCheck]
      def self.unavailable(current_version: Aidp::VERSION)
        new(
          current_version: current_version,
          available_version: current_version,
          update_available: false,
          update_allowed: false,
          policy_reason: "Update service temporarily unavailable"
        )
      end

      # Check if update check was successful
      # @return [Boolean]
      def success?
        @error.nil?
      end

      # Check if update check failed
      # @return [Boolean]
      def failed?
        !success?
      end

      # Check if update should be performed
      # @return [Boolean]
      def should_update?
        success? && @update_available && @update_allowed
      end

      # Convert to hash for serialization
      # @return [Hash]
      def to_h
        {
          current_version: @current_version,
          available_version: @available_version,
          update_available: @update_available,
          update_allowed: @update_allowed,
          policy_reason: @policy_reason,
          checked_at: @checked_at.utc.iso8601,
          error: @error
        }
      end

      # Create from hash
      # @param hash [Hash] Serialized update check
      # @return [UpdateCheck]
      def self.from_h(hash)
        new(
          current_version: hash[:current_version] || hash["current_version"],
          available_version: hash[:available_version] || hash["available_version"],
          update_available: hash[:update_available] || hash["update_available"],
          update_allowed: hash[:update_allowed] || hash["update_allowed"],
          policy_reason: hash[:policy_reason] || hash["policy_reason"],
          checked_at: Time.parse(hash[:checked_at] || hash["checked_at"]),
          error: hash[:error] || hash["error"]
        )
      end
    end
  end
end
