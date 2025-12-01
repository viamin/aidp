# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "uri"

module Aidp
  module Watch
    # Lightweight adapter around GitHub for watch mode. Prefers the GitHub CLI
    # (works for private repositories) and falls back to public REST endpoints
    # when the CLI is unavailable.
    class RepositoryClient
      # Binary availability checker for testing
      class BinaryChecker
        def gh_cli_available?
          _stdout, _stderr, status = Open3.capture3("gh", "--version")
          status.success?
        rescue Errno::ENOENT
          false
        end
      end

      attr_reader :owner, :repo

      def self.parse_issues_url(issues_url)
        case issues_url
        when %r{\Ahttps://github\.com/([^/]+)/([^/]+)(?:/issues)?/?\z}
          [$1, $2]
        when %r{\A([^/]+)/([^/]+)\z}
          [$1, $2]
        else
          raise ArgumentError, "Unsupported issues URL: #{issues_url}"
        end
      end

      def initialize(owner:, repo:, gh_available: nil, binary_checker: BinaryChecker.new)
        @owner = owner
        @repo = repo
        @binary_checker = binary_checker
        @gh_available = gh_available.nil? ? @binary_checker.gh_cli_available? : gh_available
      end

      def gh_available?
        @gh_available
      end

      def full_repo
        "#{owner}/#{repo}"
      end

      def list_issues(labels: [], state: "open")
        gh_available? ? list_issues_via_gh(labels: labels, state: state) : list_issues_via_api(labels: labels, state: state)
      end

      def fetch_issue(number)
        gh_available? ? fetch_issue_via_gh(number) : fetch_issue_via_api(number)
      end

      def post_comment(number, body)
        gh_available? ? post_comment_via_gh(number, body) : post_comment_via_api(number, body)
      end

      def find_comment(number, header_text)
        gh_available? ? find_comment_via_gh(number, header_text) : find_comment_via_api(number, header_text)
      end

      def update_comment(comment_id, body)
        gh_available? ? update_comment_via_gh(comment_id, body) : update_comment_via_api(comment_id, body)
      end

      def create_pull_request(title:, body:, head:, base:, issue_number:, draft: false, assignee: nil)
        gh_available? ? create_pull_request_via_gh(title: title, body: body, head: head, base: base, issue_number: issue_number, draft: draft, assignee: assignee) : raise("GitHub CLI not available - cannot create PR")
      end

      def add_labels(number, *labels)
        gh_available? ? add_labels_via_gh(number, labels.flatten) : add_labels_via_api(number, labels.flatten)
      end

      def remove_labels(number, *labels)
        gh_available? ? remove_labels_via_gh(number, labels.flatten) : remove_labels_via_api(number, labels.flatten)
      end

      def replace_labels(number, old_labels:, new_labels:)
        # Remove old labels and add new ones atomically where possible
        remove_labels(number, *old_labels) unless old_labels.empty?
        add_labels(number, *new_labels) unless new_labels.empty?
      end

      def most_recent_label_actor(number)
        gh_available? ? most_recent_label_actor_via_gh(number) : nil
      end

      # PR-specific operations
      def fetch_pull_request(number)
        gh_available? ? fetch_pull_request_via_gh(number) : fetch_pull_request_via_api(number)
      end

      def fetch_pull_request_diff(number)
        gh_available? ? fetch_pull_request_diff_via_gh(number) : fetch_pull_request_diff_via_api(number)
      end

      def fetch_pull_request_files(number)
        gh_available? ? fetch_pull_request_files_via_gh(number) : fetch_pull_request_files_via_api(number)
      end

      def fetch_ci_status(number)
        gh_available? ? fetch_ci_status_via_gh(number) : fetch_ci_status_via_api(number)
      end

      def post_review_comment(number, body, commit_id: nil, path: nil, line: nil)
        gh_available? ? post_review_comment_via_gh(number, body, commit_id: commit_id, path: path, line: line) : post_review_comment_via_api(number, body, commit_id: commit_id, path: path, line: line)
      end

      def list_pull_requests(labels: [], state: "open")
        gh_available? ? list_pull_requests_via_gh(labels: labels, state: state) : list_pull_requests_via_api(labels: labels, state: state)
      end

      def fetch_pr_comments(number)
        gh_available? ? fetch_pr_comments_via_gh(number) : fetch_pr_comments_via_api(number)
      end

      # Fetch reactions on a specific comment
      # Returns array of reactions with user and content (emoji type)
      def fetch_comment_reactions(comment_id)
        gh_available? ? fetch_comment_reactions_via_gh(comment_id) : fetch_comment_reactions_via_api(comment_id)
      end

      # Create or update a categorized comment (e.g., under a header) on an issue.
      # If a comment with the category header exists, either append to it or
      # replace it while archiving the previous content inline.
      def consolidate_category_comment(issue_number, category_header, content, append: false)
        existing_comment = find_comment(issue_number, category_header)

        if existing_comment.nil?
          Aidp.log_debug("repository_client", "creating_category_comment",
            issue: issue_number,
            header: category_header)
          return post_comment(issue_number, "#{category_header}\n\n#{content}")
        end

        existing_body = existing_comment[:body] || existing_comment["body"] || ""
        content_without_header = existing_body.sub(/\A#{Regexp.escape(category_header)}\s*/, "").strip

        new_body =
          if append
            Aidp.log_debug("repository_client", "appending_category_comment",
              issue: issue_number,
              header: category_header)
            segments = [category_header, content_without_header, content].reject(&:empty?)
            segments.join("\n\n")
          else
            Aidp.log_debug("repository_client", "replacing_category_comment",
              issue: issue_number,
              header: category_header)
            timestamp = Time.now.utc.iso8601
            archive_marker = "<!-- ARCHIVED_PLAN_START #{timestamp} ARCHIVED_PLAN_END -->"
            [category_header, content, archive_marker, content_without_header].join("\n\n")
          end

        update_comment(existing_comment[:id] || existing_comment["id"], new_body)
      rescue => e
        Aidp.log_error("repository_client", "consolidate_category_comment_failed",
          issue: issue_number,
          header: category_header,
          error: e.message)
        raise "GitHub error: #{e.message}"
      end

      private

      # Retry a GitHub CLI operation with exponential backoff
      # Rescues network-related RuntimeErrors from gh CLI
      def with_gh_retry(operation_name, max_retries: 3, initial_delay: 1.0)
        retries = 0
        begin
          yield
        rescue RuntimeError => e
          # Only retry on network-related errors from gh CLI
          if e.message.include?("unexpected EOF") ||
              e.message.include?("connection") ||
              e.message.include?("timeout") ||
              e.message.include?("Request to https://api.github.com")
            retries += 1
            if retries <= max_retries
              delay = initial_delay * (2**(retries - 1))
              Aidp.log_warn("repository_client", "gh_retry",
                operation: operation_name,
                attempt: retries,
                max_retries: max_retries,
                delay: delay,
                error: e.message.lines.first&.strip)
              sleep(delay)
              retry
            else
              Aidp.log_error("repository_client", "gh_retry_exhausted",
                operation: operation_name,
                error: e.message)
              raise
            end
          else
            # Non-network errors should not be retried
            raise
          end
        end
      end

      def list_issues_via_gh(labels:, state:)
        json_fields = %w[number title labels updatedAt state url assignees]
        cmd = ["gh", "issue", "list", "--repo", full_repo, "--state", state, "--json", json_fields.join(",")]
        labels.each do |label|
          cmd += ["--label", label]
        end

        stdout, stderr, status = Open3.capture3(*cmd)
        unless status.success?
          warn("GitHub CLI list failed: #{stderr}")
          return []
        end

        JSON.parse(stdout).map { |raw| normalize_issue(raw) }
      rescue JSON::ParserError => e
        warn("Failed to parse GH CLI response: #{e.message}")
        []
      end

      def list_issues_via_api(labels:, state:)
        label_param = labels.join(",")
        uri = URI("https://api.github.com/repos/#{full_repo}/issues?state=#{state}")
        uri.query = [uri.query, "labels=#{URI.encode_www_form_component(label_param)}"].compact.join("&") unless label_param.empty?

        response = Net::HTTP.get_response(uri)
        return [] unless response.code == "200"

        JSON.parse(response.body).reject { |item| item["pull_request"] }.map { |raw| normalize_issue_api(raw) }
      rescue => e
        warn("GitHub API list failed: #{e.message}")
        []
      end

      def fetch_issue_via_gh(number)
        with_gh_retry("fetch_issue") do
          fields = %w[number title body comments labels state assignees url updatedAt author]
          cmd = ["gh", "issue", "view", number.to_s, "--repo", full_repo, "--json", fields.join(",")]

          stdout, stderr, status = Open3.capture3(*cmd)
          raise "GitHub CLI error: #{stderr.strip}" unless status.success?

          data = JSON.parse(stdout)
          normalize_issue_detail(data)
        end
      rescue JSON::ParserError => e
        raise "Failed to parse GitHub CLI issue response: #{e.message}"
      end

      def fetch_issue_via_api(number)
        uri = URI("https://api.github.com/repos/#{full_repo}/issues/#{number}")
        response = Net::HTTP.get_response(uri)
        raise "GitHub API error (#{response.code})" unless response.code == "200"

        data = JSON.parse(response.body)
        comments = fetch_pr_comments_via_api(number)
        data["comments"] = comments
        normalize_issue_detail_api(data)
      end

      def post_comment_via_gh(number, body)
        # Use gh api to post comment and get structured response with comment ID
        with_gh_retry("post_comment") do
          cmd = ["gh", "api", "repos/#{full_repo}/issues/#{number}/comments",
            "-X", "POST", "-f", "body=#{body}"]
          stdout, stderr, status = Open3.capture3(*cmd)
          raise "Failed to post comment via gh: #{stderr.strip}" unless status.success?

          response = JSON.parse(stdout)
          {
            id: response["id"],
            url: response["html_url"],
            body: response["body"]
          }
        end
      end

      def post_comment_via_api(number, body)
        uri = URI("https://api.github.com/repos/#{full_repo}/issues/#{number}/comments")
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.dump({body: body})

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        raise "GitHub API comment failed (#{response.code})" unless response.code.start_with?("2")

        data = JSON.parse(response.body)
        {
          id: data["id"],
          url: data["html_url"],
          body: data["body"]
        }
      end

      def find_comment_via_gh(number, header_text)
        comments = fetch_pr_comments_via_gh(number)
        comments.find { |comment| comment[:body]&.include?(header_text) }
      rescue => e
        Aidp.log_warn("repository_client", "Failed to find comment", error: e.message)
        nil
      end

      def find_comment_via_api(number, header_text)
        comments = fetch_pr_comments_via_api(number)
        comments.find { |comment| comment[:body]&.include?(header_text) }
      rescue => e
        Aidp.log_warn("repository_client", "Failed to find comment", error: e.message)
        nil
      end

      def update_comment_via_gh(comment_id, body)
        cmd = ["gh", "api", "repos/#{full_repo}/issues/comments/#{comment_id}", "-X", "PATCH", "-f", "body=#{body}"]
        stdout, stderr, status = Open3.capture3(*cmd)
        raise "Failed to update comment via gh: #{stderr.strip}" unless status.success?

        stdout.strip
      end

      def update_comment_via_api(comment_id, body)
        uri = URI("https://api.github.com/repos/#{full_repo}/issues/comments/#{comment_id}")
        request = Net::HTTP::Patch.new(uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.dump({body: body})

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        raise "GitHub API update comment failed (#{response.code})" unless response.code.start_with?("2")
        response.body
      end

      def fetch_comment_reactions_via_gh(comment_id)
        with_gh_retry("fetch_comment_reactions") do
          cmd = ["gh", "api", "repos/#{full_repo}/issues/comments/#{comment_id}/reactions"]
          stdout, stderr, status = Open3.capture3(*cmd)
          raise "Failed to fetch reactions via gh: #{stderr.strip}" unless status.success?

          reactions = JSON.parse(stdout)
          reactions.map do |r|
            {
              id: r["id"],
              user: r.dig("user", "login"),
              content: r["content"],
              created_at: r["created_at"]
            }
          end
        end
      rescue => e
        Aidp.log_error("repository_client", "fetch_reactions_failed", comment_id: comment_id, error: e.message)
        []
      end

      def fetch_comment_reactions_via_api(comment_id)
        uri = URI("https://api.github.com/repos/#{full_repo}/issues/comments/#{comment_id}/reactions")
        request = Net::HTTP::Get.new(uri)
        # Reactions API requires special Accept header
        request["Accept"] = "application/vnd.github+json"

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        return [] unless response.code.start_with?("2")

        reactions = JSON.parse(response.body)
        reactions.map do |r|
          {
            id: r["id"],
            user: r.dig("user", "login"),
            content: r["content"],
            created_at: r["created_at"]
          }
        end
      rescue => e
        Aidp.log_error("repository_client", "fetch_reactions_api_failed", comment_id: comment_id, error: e.message)
        []
      end

      def create_pull_request_via_gh(title:, body:, head:, base:, issue_number:, draft: false, assignee: nil)
        Aidp.log_debug(
          "repository_client",
          "preparing_gh_pr_create",
          repo: full_repo,
          head: head,
          base: base,
          draft: draft,
          assignee: assignee,
          issue_number: issue_number,
          gh_available: gh_available?,
          title_length: title.length,
          body_length: body.length
        )

        unless gh_available?
          error_msg = "GitHub CLI (gh) is not available - cannot create PR"
          Aidp.log_error(
            "repository_client",
            "gh_cli_not_available",
            repo: full_repo,
            head: head,
            base: base,
            message: error_msg
          )
          raise error_msg
        end

        cmd = [
          "gh", "pr", "create",
          "--repo", full_repo,
          "--title", title,
          "--body", body,
          "--head", head,
          "--base", base
        ]
        cmd += ["--draft"] if draft
        cmd += ["--assignee", assignee] if assignee

        Aidp.log_debug(
          "repository_client",
          "executing_gh_pr_create",
          repo: full_repo,
          head: head,
          base: base,
          draft: draft,
          assignee: assignee,
          command: cmd.join(" ")
        )

        stdout, stderr, status = Open3.capture3(*cmd)

        Aidp.log_debug(
          "repository_client",
          "gh_pr_create_result",
          repo: full_repo,
          success: status.success?,
          exit_code: status.exitstatus,
          stdout_length: stdout.length,
          stderr_length: stderr.length,
          stdout_preview: stdout[0, 200],
          stderr: stderr
        )

        unless status.success?
          Aidp.log_error(
            "repository_client",
            "gh_pr_create_failed",
            repo: full_repo,
            head: head,
            base: base,
            issue_number: issue_number,
            exit_code: status.exitstatus,
            stderr: stderr,
            stdout: stdout,
            command: cmd.join(" ")
          )
          raise "Failed to create PR via gh: #{stderr.strip}"
        end

        Aidp.log_info(
          "repository_client",
          "gh_pr_create_success",
          repo: full_repo,
          head: head,
          base: base,
          issue_number: issue_number,
          output_preview: stdout[0, 200]
        )

        stdout.strip
      end

      def add_labels_via_gh(number, labels)
        return if labels.empty?

        cmd = ["gh", "issue", "edit", number.to_s, "--repo", full_repo]
        labels.each { |label| cmd += ["--add-label", label] }

        stdout, stderr, status = Open3.capture3(*cmd)
        raise "Failed to add labels via gh: #{stderr.strip}" unless status.success?

        stdout.strip
      end

      def add_labels_via_api(number, labels)
        return if labels.empty?

        uri = URI("https://api.github.com/repos/#{full_repo}/issues/#{number}/labels")
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.dump({labels: labels})

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        raise "Failed to add labels via API (#{response.code})" unless response.code.start_with?("2")
        response.body
      end

      def remove_labels_via_gh(number, labels)
        return if labels.empty?

        cmd = ["gh", "issue", "edit", number.to_s, "--repo", full_repo]
        labels.each { |label| cmd += ["--remove-label", label] }

        stdout, stderr, status = Open3.capture3(*cmd)
        raise "Failed to remove labels via gh: #{stderr.strip}" unless status.success?

        stdout.strip
      end

      def remove_labels_via_api(number, labels)
        return if labels.empty?

        labels.each do |label|
          # URL encode the label name
          encoded_label = URI.encode_www_form_component(label)
          uri = URI("https://api.github.com/repos/#{full_repo}/issues/#{number}/labels/#{encoded_label}")
          request = Net::HTTP::Delete.new(uri)

          response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
            http.request(request)
          end

          # 404 is OK - label didn't exist
          unless response.code.start_with?("2") || response.code == "404"
            raise "Failed to remove label '#{label}' via API (#{response.code})"
          end
        end
      end

      def most_recent_label_actor_via_gh(number)
        # Use GitHub GraphQL API via gh cli to fetch the most recent label event actor
        query = <<~GRAPHQL
          query($owner: String!, $repo: String!, $number: Int!) {
            repository(owner: $owner, name: $repo) {
              issue(number: $number) {
                timelineItems(last: 100, itemTypes: [LABELED_EVENT]) {
                  nodes {
                    ... on LabeledEvent {
                      createdAt
                      actor {
                        login
                      }
                    }
                  }
                }
              }
            }
          }
        GRAPHQL

        cmd = [
          "gh", "api", "graphql",
          "-f", "query=#{query}",
          "-F", "owner=#{owner}",
          "-F", "repo=#{repo}",
          "-F", "number=#{number}"
        ]

        stdout, stderr, status = Open3.capture3(*cmd)
        unless status.success?
          Aidp.log_warn("repository_client", "Failed to fetch label events via GraphQL", error: stderr.strip)
          return nil
        end

        data = JSON.parse(stdout)
        events = data.dig("data", "repository", "issue", "timelineItems", "nodes") || []

        # Filter out events without actors and sort by createdAt to get most recent
        valid_events = events.select { |event| event.dig("actor", "login") }
        return nil if valid_events.empty?

        most_recent = valid_events.max_by { |event| event["createdAt"] }
        most_recent.dig("actor", "login")
      rescue JSON::ParserError => e
        Aidp.log_warn("repository_client", "Failed to parse GraphQL response", error: e.message)
        nil
      rescue => e
        Aidp.log_warn("repository_client", "Unexpected error fetching label actor", error: e.message)
        nil
      end

      # PR operations via gh CLI
      def list_pull_requests_via_gh(labels:, state:)
        json_fields = %w[number title labels updatedAt state url headRefName baseRefName]
        cmd = ["gh", "pr", "list", "--repo", full_repo, "--state", state, "--json", json_fields.join(",")]
        labels.each do |label|
          cmd += ["--label", label]
        end

        stdout, stderr, status = Open3.capture3(*cmd)
        unless status.success?
          warn("GitHub CLI PR list failed: #{stderr}")
          return []
        end

        JSON.parse(stdout).map { |raw| normalize_pull_request(raw) }
      rescue JSON::ParserError => e
        warn("Failed to parse GH CLI PR list response: #{e.message}")
        []
      end

      def list_pull_requests_via_api(labels:, state:)
        label_param = labels.join(",")
        uri = URI("https://api.github.com/repos/#{full_repo}/pulls?state=#{state}")
        uri.query = [uri.query, "labels=#{URI.encode_www_form_component(label_param)}"].compact.join("&") unless label_param.empty?

        response = Net::HTTP.get_response(uri)
        return [] unless response.code == "200"

        JSON.parse(response.body).map { |raw| normalize_pull_request_api(raw) }
      rescue => e
        warn("GitHub API PR list failed: #{e.message}")
        []
      end

      def fetch_pull_request_via_gh(number)
        fields = %w[number title body labels state url headRefName baseRefName commits author mergeable]
        cmd = ["gh", "pr", "view", number.to_s, "--repo", full_repo, "--json", fields.join(",")]

        stdout, stderr, status = Open3.capture3(*cmd)
        raise "GitHub CLI error: #{stderr.strip}" unless status.success?

        data = JSON.parse(stdout)
        normalize_pull_request_detail(data)
      rescue JSON::ParserError => e
        raise "Failed to parse GitHub CLI PR response: #{e.message}"
      end

      def fetch_pull_request_via_api(number)
        uri = URI("https://api.github.com/repos/#{full_repo}/pulls/#{number}")
        response = Net::HTTP.get_response(uri)
        raise "GitHub API error (#{response.code})" unless response.code == "200"

        data = JSON.parse(response.body)
        normalize_pull_request_detail_api(data)
      end

      def fetch_pull_request_diff_via_gh(number)
        cmd = ["gh", "pr", "diff", number.to_s, "--repo", full_repo]
        stdout, stderr, status = Open3.capture3(*cmd)
        raise "Failed to fetch PR diff via gh: #{stderr.strip}" unless status.success?

        stdout
      end

      def fetch_pull_request_diff_via_api(number)
        uri = URI("https://api.github.com/repos/#{full_repo}/pulls/#{number}")
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/vnd.github.v3.diff"

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        raise "GitHub API diff failed (#{response.code})" unless response.code == "200"
        response.body
      end

      def fetch_pull_request_files_via_gh(number)
        # Use gh api to fetch changed files
        cmd = ["gh", "api", "repos/#{full_repo}/pulls/#{number}/files", "--jq", "."]
        stdout, stderr, status = Open3.capture3(*cmd)
        raise "Failed to fetch PR files via gh: #{stderr.strip}" unless status.success?

        JSON.parse(stdout).map { |file| normalize_pr_file(file) }
      rescue JSON::ParserError => e
        raise "Failed to parse PR files response: #{e.message}"
      end

      def fetch_pull_request_files_via_api(number)
        uri = URI("https://api.github.com/repos/#{full_repo}/pulls/#{number}/files")
        response = Net::HTTP.get_response(uri)
        raise "GitHub API files failed (#{response.code})" unless response.code == "200"

        JSON.parse(response.body).map { |file| normalize_pr_file(file) }
      rescue JSON::ParserError => e
        raise "Failed to parse PR files response: #{e.message}"
      end

      def fetch_ci_status_via_gh(number)
        # Fetch PR to get the head SHA
        pr_data = fetch_pull_request_via_gh(number)
        head_sha = pr_data[:head_sha]

        # Fetch check runs for the commit
        cmd = ["gh", "api", "repos/#{full_repo}/commits/#{head_sha}/check-runs", "--jq", "."]
        stdout, _stderr, status = Open3.capture3(*cmd)

        check_runs = if status.success?
          data = JSON.parse(stdout)
          data["check_runs"] || []
        else
          Aidp.log_warn("repository_client", "Failed to fetch check runs", sha: head_sha)
          []
        end

        # Also fetch commit statuses (for OAuth apps, webhooks, etc.)
        commit_statuses = fetch_commit_statuses_via_gh(head_sha)

        # Combine and normalize both check runs and commit statuses
        normalize_ci_status_combined(check_runs, commit_statuses, head_sha)
      rescue => e
        Aidp.log_warn("repository_client", "Failed to fetch CI status", error: e.message)
        {sha: nil, state: "unknown", checks: []}
      end

      def fetch_ci_status_via_api(number)
        pr_data = fetch_pull_request_via_api(number)
        head_sha = pr_data[:head_sha]

        uri = URI("https://api.github.com/repos/#{full_repo}/commits/#{head_sha}/check-runs")
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/vnd.github.v3+json"

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        check_runs = if response.code == "200"
          data = JSON.parse(response.body)
          data["check_runs"] || []
        else
          Aidp.log_warn("repository_client", "Failed to fetch check runs via API", sha: head_sha, code: response.code)
          []
        end

        # Also fetch commit statuses (for OAuth apps, webhooks, etc.)
        commit_statuses = fetch_commit_statuses_via_api(head_sha)

        # Combine and normalize both check runs and commit statuses
        normalize_ci_status_combined(check_runs, commit_statuses, head_sha)
      rescue => e
        Aidp.log_warn("repository_client", "Failed to fetch CI status", error: e.message)
        {sha: nil, state: "unknown", checks: []}
      end

      def post_review_comment_via_gh(number, body, commit_id: nil, path: nil, line: nil)
        if path && line && commit_id
          # Note: gh CLI doesn't support inline comments directly, so we use the API
          # For inline comments, we need to use the GitHub API
          post_review_comment_via_api(number, body, commit_id: commit_id, path: path, line: line)
        else
          # Post general review comment
          cmd = ["gh", "pr", "comment", number.to_s, "--repo", full_repo, "--body", body]
          stdout, stderr, status = Open3.capture3(*cmd)
          raise "Failed to post review comment via gh: #{stderr.strip}" unless status.success?

          stdout.strip
        end
      end

      def post_review_comment_via_api(number, body, commit_id: nil, path: nil, line: nil)
        uri, request = if path && line && commit_id
          # Post inline review comment
          review_uri = URI("https://api.github.com/repos/#{full_repo}/pulls/#{number}/reviews")
          review_request = Net::HTTP::Post.new(review_uri)
          review_request["Content-Type"] = "application/json"
          review_request["Accept"] = "application/vnd.github.v3+json"

          review_data = {
            body: body,
            event: "COMMENT",
            comments: [
              {
                path: path,
                line: line,
                body: body
              }
            ]
          }

          review_request.body = JSON.dump(review_data)
          [review_uri, review_request]
        else
          # Post general comment on the PR
          comment_uri = URI("https://api.github.com/repos/#{full_repo}/issues/#{number}/comments")
          comment_request = Net::HTTP::Post.new(comment_uri)
          comment_request["Content-Type"] = "application/json"
          comment_request.body = JSON.dump({body: body})
          [comment_uri, comment_request]
        end

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        error_msg = (path && line && commit_id) ? "GitHub API review comment failed (#{response.code}): #{response.body}" : "GitHub API comment failed (#{response.code})"
        raise error_msg unless response.code.start_with?("2")

        response.body
      end

      def fetch_pr_comments_via_gh(number)
        cmd = ["gh", "api", "repos/#{full_repo}/issues/#{number}/comments", "--jq", "."]
        stdout, stderr, status = Open3.capture3(*cmd)
        raise "Failed to fetch PR comments via gh: #{stderr.strip}" unless status.success?

        JSON.parse(stdout).map { |raw| normalize_pr_comment(raw) }
      rescue JSON::ParserError => e
        raise "Failed to parse PR comments response: #{e.message}"
      end

      def fetch_pr_comments_via_api(number)
        uri = URI("https://api.github.com/repos/#{full_repo}/issues/#{number}/comments")
        response = Net::HTTP.get_response(uri)
        return [] unless response.code == "200"

        JSON.parse(response.body).map { |raw| normalize_pr_comment(raw) }
      rescue => e
        Aidp.log_warn("repository_client", "Failed to fetch PR comments", error: e.message)
        []
      end

      # Normalization methods for PRs
      def normalize_pull_request(raw)
        {
          number: raw["number"],
          title: raw["title"],
          labels: Array(raw["labels"]).map { |label| label.is_a?(Hash) ? label["name"] : label },
          updated_at: raw["updatedAt"],
          state: raw["state"],
          url: raw["url"],
          head_ref: raw["headRefName"],
          base_ref: raw["baseRefName"]
        }
      end

      def normalize_pull_request_api(raw)
        {
          number: raw["number"],
          title: raw["title"],
          labels: Array(raw["labels"]).map { |label| label["name"] },
          updated_at: raw["updated_at"],
          state: raw["state"],
          url: raw["html_url"],
          head_ref: raw.dig("head", "ref"),
          base_ref: raw.dig("base", "ref")
        }
      end

      def normalize_pull_request_detail(raw)
        {
          number: raw["number"],
          title: raw["title"],
          body: raw["body"] || "",
          author: raw.dig("author", "login") || raw["author"],
          labels: Array(raw["labels"]).map { |label| label.is_a?(Hash) ? label["name"] : label },
          state: raw["state"],
          url: raw["url"],
          head_ref: raw["headRefName"],
          base_ref: raw["baseRefName"],
          head_sha: raw.dig("commits", 0, "oid") || raw["headRefOid"],
          mergeable: raw["mergeable"]
        }
      end

      def normalize_pull_request_detail_api(raw)
        {
          number: raw["number"],
          title: raw["title"],
          body: raw["body"] || "",
          author: raw.dig("user", "login"),
          labels: Array(raw["labels"]).map { |label| label["name"] },
          state: raw["state"],
          url: raw["html_url"],
          head_ref: raw.dig("head", "ref"),
          base_ref: raw.dig("base", "ref"),
          head_sha: raw.dig("head", "sha"),
          mergeable: raw["mergeable"]
        }
      end

      def normalize_pr_file(raw)
        {
          filename: raw["filename"],
          status: raw["status"],
          additions: raw["additions"],
          deletions: raw["deletions"],
          changes: raw["changes"],
          patch: raw["patch"]
        }
      end

      def fetch_commit_statuses_via_gh(head_sha)
        cmd = ["gh", "api", "repos/#{full_repo}/commits/#{head_sha}/status", "--jq", "."]
        stdout, _stderr, status = Open3.capture3(*cmd)

        if status.success?
          data = JSON.parse(stdout)
          data["statuses"] || []
        else
          Aidp.log_debug("repository_client", "No commit statuses found", sha: head_sha)
          []
        end
      rescue => e
        Aidp.log_warn("repository_client", "Failed to fetch commit statuses", error: e.message, sha: head_sha)
        []
      end

      def fetch_commit_statuses_via_api(head_sha)
        uri = URI("https://api.github.com/repos/#{full_repo}/commits/#{head_sha}/status")
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/vnd.github.v3+json"

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        if response.code == "200"
          data = JSON.parse(response.body)
          data["statuses"] || []
        else
          Aidp.log_debug("repository_client", "No commit statuses found via API", sha: head_sha, code: response.code)
          []
        end
      rescue => e
        Aidp.log_warn("repository_client", "Failed to fetch commit statuses via API", error: e.message, sha: head_sha)
        []
      end

      def normalize_ci_status_combined(check_runs, commit_statuses, head_sha)
        # Convert commit statuses to same format as check runs for unified processing
        # normalize_ci_status expects string keys, so we use string keys here
        checks_from_statuses = commit_statuses.map do |status|
          {
            "name" => status["context"],
            "status" => (status["state"] == "pending") ? "in_progress" : "completed",
            "conclusion" => normalize_commit_status_to_conclusion(status["state"]),
            "details_url" => status["target_url"],
            "output" => status["description"] ? {"summary" => status["description"]} : nil
          }
        end

        # Combine check runs and converted commit statuses
        # check_runs should already have string keys from API/CLI responses
        all_checks = check_runs + checks_from_statuses

        Aidp.log_debug("repository_client", "combined_ci_checks",
          check_run_count: check_runs.length,
          commit_status_count: commit_statuses.length,
          total_checks: all_checks.length)

        # Use existing normalize logic
        normalize_ci_status(all_checks, head_sha)
      end

      def normalize_commit_status_to_conclusion(state)
        # Map commit status states to check run conclusions
        # Commit status states: error, failure, pending, success
        # Check run conclusions: success, failure, neutral, cancelled, timed_out, action_required, skipped, stale
        case state
        when "success"
          "success"
        when "failure"
          "failure"
        when "error"
          "failure" # Treat error as failure for consistency
        when "pending", nil
          nil # pending means not completed yet
        end
      end

      def normalize_ci_status(check_runs, head_sha)
        checks = check_runs.map do |run|
          {
            name: run["name"],
            status: run["status"],
            conclusion: run["conclusion"],
            details_url: run["details_url"],
            output: run["output"]
          }
        end

        Aidp.log_debug("repository_client", "normalize_ci_status",
          check_count: checks.length,
          checks: checks.map { |c| {name: c[:name], status: c[:status], conclusion: c[:conclusion]} })

        # Determine overall state
        # CRITICAL: Empty check list should be "unknown", not "success"
        # This guard must come FIRST to prevent vacuous truth from [].all? { condition }
        state = if checks.empty?
          Aidp.log_debug("repository_client", "ci_status_empty", message: "No checks found")
          "unknown"
        elsif checks.any? { |c| c[:conclusion] == "failure" }
          failing_checks = checks.select { |c| c[:conclusion] == "failure" }
          Aidp.log_debug("repository_client", "ci_status_failure",
            failing_count: failing_checks.length,
            failing_checks: failing_checks.map { |c| c[:name] })
          "failure"
        elsif checks.any? { |c| c[:status] != "completed" }
          pending_checks = checks.select { |c| c[:status] != "completed" }
          Aidp.log_debug("repository_client", "ci_status_pending",
            pending_count: pending_checks.length,
            pending_checks: pending_checks.map { |c| {name: c[:name], status: c[:status]} })
          "pending"
        elsif checks.all? { |c| c[:conclusion] == "success" }
          Aidp.log_debug("repository_client", "ci_status_success",
            success_count: checks.length)
          "success"
        else
          non_success_checks = checks.reject { |c| c[:conclusion] == "success" }
          Aidp.log_debug("repository_client", "ci_status_unknown",
            non_success_count: non_success_checks.length,
            non_success_checks: non_success_checks.map { |c| {name: c[:name], conclusion: c[:conclusion]} })
          "unknown"
        end

        Aidp.log_debug("repository_client", "ci_status_determined", sha: head_sha, state: state)

        {
          sha: head_sha,
          state: state,
          checks: checks
        }
      end

      def normalize_issue(raw)
        {
          number: raw["number"],
          title: raw["title"],
          labels: Array(raw["labels"]).map { |label| label.is_a?(Hash) ? label["name"] : label },
          updated_at: raw["updatedAt"],
          state: raw["state"],
          url: raw["url"],
          assignees: Array(raw["assignees"]).map { |assignee| assignee.is_a?(Hash) ? assignee["login"] : assignee }
        }
      end

      def normalize_issue_api(raw)
        {
          number: raw["number"],
          title: raw["title"],
          labels: Array(raw["labels"]).map { |label| label["name"] },
          updated_at: raw["updated_at"],
          state: raw["state"],
          url: raw["html_url"],
          assignees: Array(raw["assignees"]).map { |assignee| assignee["login"] }
        }
      end

      def normalize_issue_detail(raw)
        {
          number: raw["number"],
          title: raw["title"],
          body: raw["body"] || "",
          author: raw.dig("author", "login") || raw["author"],
          comments: Array(raw["comments"]).map { |comment| normalize_comment(comment) },
          labels: Array(raw["labels"]).map { |label| label.is_a?(Hash) ? label["name"] : label },
          state: raw["state"],
          assignees: Array(raw["assignees"]).map { |assignee| assignee.is_a?(Hash) ? assignee["login"] : assignee },
          url: raw["url"],
          updated_at: raw["updatedAt"]
        }
      end

      def normalize_issue_detail_api(raw)
        {
          number: raw["number"],
          title: raw["title"],
          body: raw["body"] || "",
          author: raw.dig("user", "login"),
          comments: Array(raw["comments"]).map { |comment| normalize_comment(comment) },
          labels: Array(raw["labels"]).map { |label| label["name"] },
          state: raw["state"],
          assignees: Array(raw["assignees"]).map { |assignee| assignee["login"] },
          url: raw["html_url"],
          updated_at: raw["updated_at"]
        }
      end

      def normalize_comment(comment)
        if comment.is_a?(Hash)
          {
            "body" => comment["body"] || comment[:body],
            "author" => comment["author"] || comment[:author] || comment.dig("user", "login"),
            "createdAt" => comment["createdAt"] || comment[:created_at] || comment["created_at"]
          }
        else
          {"body" => comment.to_s}
        end
      end

      def normalize_pr_comment(raw)
        {
          id: raw["id"],
          body: raw["body"],
          author: raw.dig("user", "login"),
          created_at: raw["created_at"],
          updated_at: raw["updated_at"]
        }
      end
    end
  end
end
