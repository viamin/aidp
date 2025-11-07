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

      def create_pull_request(title:, body:, head:, base:, issue_number:)
        gh_available? ? create_pull_request_via_gh(title: title, body: body, head: head, base: base, issue_number: issue_number) : raise("GitHub CLI not available - cannot create PR")
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

      private

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
        fields = %w[number title body comments labels state assignees url updatedAt author]
        cmd = ["gh", "issue", "view", number.to_s, "--repo", full_repo, "--json", fields.join(",")]

        stdout, stderr, status = Open3.capture3(*cmd)
        raise "GitHub CLI error: #{stderr.strip}" unless status.success?

        data = JSON.parse(stdout)
        normalize_issue_detail(data)
      rescue JSON::ParserError => e
        raise "Failed to parse GitHub CLI issue response: #{e.message}"
      end

      def fetch_issue_via_api(number)
        uri = URI("https://api.github.com/repos/#{full_repo}/issues/#{number}")
        response = Net::HTTP.get_response(uri)
        raise "GitHub API error (#{response.code})" unless response.code == "200"

        data = JSON.parse(response.body)
        comments = fetch_comments_via_api(number)
        data["comments"] = comments
        normalize_issue_detail_api(data)
      end

      def fetch_comments_via_api(number)
        uri = URI("https://api.github.com/repos/#{full_repo}/issues/#{number}/comments")
        response = Net::HTTP.get_response(uri)
        return [] unless response.code == "200"

        JSON.parse(response.body).map do |raw|
          {
            "body" => raw["body"],
            "author" => raw.dig("user", "login"),
            "createdAt" => raw["created_at"]
          }
        end
      rescue
        []
      end

      def post_comment_via_gh(number, body)
        cmd = ["gh", "issue", "comment", number.to_s, "--repo", full_repo, "--body", body]
        stdout, stderr, status = Open3.capture3(*cmd)
        raise "Failed to post comment via gh: #{stderr.strip}" unless status.success?

        stdout.strip
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
        response.body
      end

      def create_pull_request_via_gh(title:, body:, head:, base:, issue_number:, draft: false)
        cmd = [
          "gh", "pr", "create",
          "--repo", full_repo,
          "--title", title,
          "--body", body,
          "--head", head,
          "--base", base
        ]
        cmd += ["--issue", issue_number.to_s] if issue_number
        cmd += ["--draft"] if draft

        stdout, stderr, status = Open3.capture3(*cmd)
        raise "Failed to create PR via gh: #{stderr.strip}" unless status.success?

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
            "body" => comment["body"],
            "author" => comment["author"] || comment.dig("user", "login"),
            "createdAt" => comment["createdAt"] || comment["created_at"]
          }
        else
          {"body" => comment.to_s}
        end
      end
    end
  end
end
