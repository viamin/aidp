# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require_relative "../message_display"

module Aidp
  module Watch
    # Validates watch mode safety requirements for public repositories
    # and enforces author allowlists to prevent untrusted input execution.
    class RepositorySafetyChecker
      include Aidp::MessageDisplay

      class UnsafeRepositoryError < StandardError; end
      class UnauthorizedAuthorError < StandardError; end

      def initialize(repository_client:, config: {})
        @repository_client = repository_client
        @config = config
        @repo_visibility_cache = {}
      end

      # Check if watch mode is safe to run for this repository
      # @param force [Boolean] Skip safety checks (dangerous!)
      # @return [Boolean] true if safe, raises error otherwise
      def validate_watch_mode_safety!(force: false)
        Aidp.log_debug("repository_safety", "validate watch mode safety",
          repo: @repository_client.full_repo,
          force: force)

        # Skip checks if forced (user takes responsibility)
        if force
          display_message("⚠️  Watch mode safety checks BYPASSED (--force)", type: :warning)
          return true
        end

        # Check repository visibility
        unless repository_safe_for_watch_mode?
          raise UnsafeRepositoryError, unsafe_repository_message
        end

        # Check if running in safe environment
        unless safe_environment?
          display_message("⚠️  Watch mode running outside container/sandbox", type: :warning)
          display_message("   Consider using a containerized environment for additional safety", type: :muted)
        end

        display_message("✅ Watch mode safety checks passed", type: :success)
        true
      end

      # Check if an issue author is allowed to trigger automated work
      # @param issue [Hash] Issue data with :author or :assignees
      # @return [Boolean] true if authorized
      def author_authorized?(issue)
        author = extract_author(issue)
        return false unless author

        # If no allowlist configured, allow all (backward compatible)
        return true if author_allowlist.empty?

        # Check if author is in allowlist
        authorized = author_allowlist.include?(author)

        Aidp.log_debug("repository_safety", "check author authorization",
          author: author,
          authorized: authorized,
          allowlist_size: author_allowlist.size)

        authorized
      end

      # Check if an issue should be processed based on author authorization
      # @param issue [Hash] Issue data
      # @param enforce [Boolean] Raise error if unauthorized
      # @return [Boolean] true if should process
      def should_process_issue?(issue, enforce: true)
        unless author_authorized?(issue)
          author = extract_author(issue)
          if enforce && author_allowlist.any?
            raise UnauthorizedAuthorError,
              "Issue ##{issue[:number]} author '#{author}' not in allowlist. " \
              "Add to watch.safety.author_allowlist in aidp.yml to allow."
          end

          display_message("⏭️  Skipping issue ##{issue[:number]} - author '#{author}' not authorized",
            type: :muted)
          return false
        end

        true
      end

      private

      def repository_safe_for_watch_mode?
        # Check if repository is private
        return true if repository_private?

        # Public repositories require explicit opt-in
        if public_repos_allowed?
          display_message("⚠️  Watch mode enabled for PUBLIC repository", type: :warning)
          display_message("   Ensure you trust all contributors and have proper safety measures", type: :muted)
          return true
        end

        false
      end

      def repository_private?
        # Cache visibility check to avoid repeated API calls
        return @repo_visibility_cache[:private] if @repo_visibility_cache.key?(:private)

        is_private = if @repository_client.gh_available?
          check_visibility_via_gh
        else
          check_visibility_via_api
        end

        @repo_visibility_cache[:private] = is_private
        Aidp.log_debug("repository_safety", "repository visibility check",
          repo: @repository_client.full_repo,
          private: is_private)

        is_private
      end

      def check_visibility_via_gh
        cmd = ["gh", "repo", "view", @repository_client.full_repo, "--json", "visibility"]
        stdout, stderr, status = Open3.capture3(*cmd)

        unless status.success?
          Aidp.log_warn("repository_safety", "failed to check repo visibility via gh",
            error: stderr.strip)
          # Assume public if we can't determine (safer default)
          return false
        end

        data = JSON.parse(stdout)
        data["visibility"]&.downcase == "private"
      rescue JSON::ParserError => e
        Aidp.log_error("repository_safety", "failed to parse gh repo response", error: e.message)
        false # Assume public on error
      end

      def check_visibility_via_api
        uri = URI("https://api.github.com/repos/#{@repository_client.full_repo}")
        response = Net::HTTP.get_response(uri)

        unless response.code == "200"
          Aidp.log_warn("repository_safety", "failed to check repo visibility via API",
            status: response.code)
          # Assume public if we can't determine
          return false
        end

        data = JSON.parse(response.body)
        data["private"] == true
      rescue => e
        Aidp.log_error("repository_safety", "failed to check repo visibility", error: e.message)
        false # Assume public on error
      end

      def public_repos_allowed?
        @config.dig(:safety, :allow_public_repos) == true
      end

      def author_allowlist
        @author_allowlist ||= Array(@config.dig(:safety, :author_allowlist)).compact.map(&:to_s)
      end

      def safe_environment?
        # Check if running in a container
        in_container? || @config.dig(:safety, :require_container) == false
      end

      def in_container?
        # Check for container indicators
        File.exist?("/.dockerenv") ||
          File.exist?("/run/.containerenv") ||
          ENV["AIDP_ENV"] == "development" # devcontainer
      end

      def extract_author(issue)
        # Try different author fields
        issue[:author] ||
          issue.dig(:assignees, 0) ||
          issue["author"] ||
          issue.dig("assignees", 0)
      end

      def unsafe_repository_message
        <<~MSG
          🛑 Watch mode is DISABLED for public repositories by default.

          Running automated code execution on untrusted public input is dangerous!

          To enable watch mode for this public repository, add to your aidp.yml:

            watch:
              safety:
                allow_public_repos: true
                author_allowlist:  # Only these users can trigger automation
                  - trusted_maintainer
                  - another_admin
                require_container: true  # Require sandboxed environment

          Alternatively, use --force to bypass this check (NOT RECOMMENDED).
        MSG
      end
    end
  end
end
