# frozen_string_literal: true

require_relative "update_check"
require_relative "update_policy"
require_relative "bundler_adapter"
require_relative "rubygems_api_adapter"

module Aidp
  module AutoUpdate
    # Service for detecting available gem versions and enforcing semver policy
    class VersionDetector
      def initialize(
        policy:, current_version: Aidp::VERSION,
        bundler_adapter: BundlerAdapter.new,
        rubygems_adapter: RubyGemsAPIAdapter.new
      )
        @current_version = Gem::Version.new(current_version)
        @policy = policy
        @bundler_adapter = bundler_adapter
        @rubygems_adapter = rubygems_adapter
      end

      # Check for updates according to policy
      # @return [UpdateCheck] Result of update check
      def check_for_update
        Aidp.log_info("version_detector", "checking_for_updates",
          current_version: @current_version.to_s,
          policy: @policy.policy)

        available_version = fetch_latest_version

        unless available_version
          Aidp.log_warn("version_detector", "no_version_available")
          return UpdateCheck.unavailable(current_version: @current_version.to_s)
        end

        update_available = available_version > @current_version
        # Check policy even if disabled - we still want to report update_available
        update_allowed = @policy.disabled? ? false : update_allowed_by_policy?(available_version)
        reason = policy_reason(available_version)

        Aidp.log_info("version_detector", "update_check_complete",
          current: @current_version.to_s,
          available: available_version.to_s,
          update_available: update_available,
          update_allowed: update_allowed,
          reason: reason)

        UpdateCheck.new(
          current_version: @current_version.to_s,
          available_version: available_version.to_s,
          update_available: update_available,
          update_allowed: update_allowed,
          policy_reason: reason
        )
      rescue => e
        Aidp.log_error("version_detector", "check_failed", error: e.message)
        UpdateCheck.failed(e.message, current_version: @current_version.to_s)
      end

      private

      # Fetch latest version using bundler first, fallback to RubyGems API
      # @return [Gem::Version, nil]
      def fetch_latest_version
        # Try bundler first
        version = @bundler_adapter.latest_version_for("aidp")
        return version if version

        # Fallback to RubyGems API
        Aidp.log_debug("version_detector", "falling_back_to_rubygems_api")
        @rubygems_adapter.latest_version_for("aidp", allow_prerelease: @policy.allow_prerelease)
      end

      # Apply semver policy to determine if update is allowed
      # @param available [Gem::Version] Available version
      # @return [Boolean] Whether update is permitted
      def update_allowed_by_policy?(available)
        case @policy.policy
        when "off"
          false
        when "exact"
          # Only update if exact match (essentially disabled)
          available == @current_version
        when "patch"
          # Allow patch updates within same major.minor
          same_major_minor?(available) && available >= @current_version
        when "minor"
          # Allow minor + patch updates within same major
          same_major?(available) && available >= @current_version
        when "major"
          # Allow any update (including major version bumps)
          available >= @current_version
        else
          false
        end
      end

      # Generate human-readable reason for policy decision
      # @param available [Gem::Version] Available version
      # @return [String] Explanation of policy decision
      def policy_reason(available)
        return "No update available" if available <= @current_version

        case @policy.policy
        when "off"
          "Updates disabled by policy"
        when "exact"
          "Policy requires exact version match"
        when "patch"
          if same_major_minor?(available)
            "Patch update allowed by policy"
          else
            "Minor or major version change blocked by patch policy"
          end
        when "minor"
          if same_major?(available)
            "Minor/patch update allowed by policy"
          else
            "Major version change blocked by minor policy"
          end
        when "major"
          "Update allowed by major policy"
        else
          "Unknown policy: #{@policy.policy}"
        end
      end

      # Check if version has same major version
      # @param version [Gem::Version] Version to compare
      # @return [Boolean]
      def same_major?(version)
        version.segments[0] == @current_version.segments[0]
      end

      # Check if version has same major.minor version
      # @param version [Gem::Version] Version to compare
      # @return [Boolean]
      def same_major_minor?(version)
        same_major?(version) && version.segments[1] == @current_version.segments[1]
      end
    end
  end
end
