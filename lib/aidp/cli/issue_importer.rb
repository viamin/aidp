# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "open3"

module Aidp
  # Handles importing GitHub issues into AIDP work loops
  class IssueImporter
    include Aidp::MessageDisplay

    def initialize
      @gh_available = gh_cli_available?
    end

    def import_issue(identifier)
      issue_url = normalize_issue_identifier(identifier)
      return nil unless issue_url

      issue_data = fetch_issue_data(issue_url)
      return nil unless issue_data

      display_imported_issue(issue_data)
      create_work_loop_prompt(issue_data)

      issue_data
    end

    private

    def normalize_issue_identifier(identifier)
      case identifier
      when /^https:\/\/github\.com\/([^\/]+)\/([^\/]+)\/issues\/(\d+)/
        # Full URL: https://github.com/owner/repo/issues/123
        identifier
      when /^(\d+)$/
        # Just issue number - need to detect current repo
        current_repo = detect_current_github_repo
        if current_repo
          "https://github.com/#{current_repo}/issues/#{identifier}"
        else
          display_message("❌ Issue number provided but not in a GitHub repository", type: :error)
          nil
        end
      when /^([^\/]+)\/([^\/]+)#(\d+)$/
        # owner/repo#123 format
        owner, repo, number = $1, $2, $3
        "https://github.com/#{owner}/#{repo}/issues/#{number}"
      else
        display_message("❌ Invalid issue identifier. Use: URL, number, or owner/repo#number", type: :error)
        nil
      end
    end

    def detect_current_github_repo
      return nil unless File.exist?(".git")

      # Try to get origin URL
      stdout, _stderr, status = Open3.capture3("git remote get-url origin")
      return nil unless status.success?

      origin_url = stdout.strip

      # Parse GitHub URL (both SSH and HTTPS)
      if origin_url =~ %r{github\.com[:/]([^/]+)/([^/\s]+?)(?:\.git)?$}
        "#{$1}/#{$2}"
      end
    end

    def fetch_issue_data(issue_url)
      # Extract owner, repo, and issue number from URL
      match = issue_url.match(/github\.com\/([^\/]+)\/([^\/]+)\/issues\/(\d+)/)
      return nil unless match

      owner, repo, number = match[1], match[2], match[3]

      # First try GitHub CLI if available (works for private repos)
      if @gh_available
        display_message("🔍 Fetching issue via GitHub CLI...", type: :info)
        issue_data = fetch_via_gh_cli(owner, repo, number)
        return issue_data if issue_data
      end

      # Fallback to public API
      display_message("🔍 Fetching issue via GitHub API...", type: :info)
      fetch_via_api(owner, repo, number)
    end

    def fetch_via_gh_cli(owner, repo, number)
      cmd = [
        "gh", "issue", "view", number,
        "--repo", "#{owner}/#{repo}",
        "--json", "title,body,labels,milestone,comments,state,assignees,number,url"
      ]

      stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        display_message("⚠️ GitHub CLI failed: #{stderr.strip}", type: :warn)
        return nil
      end

      begin
        data = JSON.parse(stdout)
        normalize_gh_cli_data(data)
      rescue JSON::ParserError => e
        display_message("❌ Failed to parse GitHub CLI response: #{e.message}", type: :error)
        nil
      end
    end

    def fetch_via_api(owner, repo, number)
      uri = URI("https://api.github.com/repos/#{owner}/#{repo}/issues/#{number}")

      begin
        response = Net::HTTP.get_response(uri)

        unless response.code == "200"
          case response.code
          when "404"
            display_message("❌ Issue not found (may be private)", type: :error)
          when "403"
            display_message("❌ API rate limit exceeded", type: :error)
          else
            display_message("❌ GitHub API error: #{response.code}", type: :error)
          end
          return nil
        end

        data = JSON.parse(response.body)
        normalize_api_data(data)
      rescue => e
        display_message("❌ Failed to fetch issue: #{e.message}", type: :error)
        nil
      end
    end

    def normalize_gh_cli_data(data)
      {
        number: data["number"],
        title: data["title"],
        body: data["body"] || "",
        state: data["state"],
        url: data["url"],
        labels: data["labels"]&.map { |l| l["name"] } || [],
        milestone: data["milestone"]&.dig("title"),
        assignees: data["assignees"]&.map { |a| a["login"] } || [],
        comments: data["comments"]&.length || 0,
        source: "gh_cli"
      }
    end

    def normalize_api_data(data)
      {
        number: data["number"],
        title: data["title"],
        body: data["body"] || "",
        state: data["state"],
        url: data["html_url"],
        labels: data["labels"]&.map { |l| l["name"] } || [],
        milestone: data["milestone"]&.dig("title"),
        assignees: data["assignees"]&.map { |a| a["login"] } || [],
        comments: data["comments"] || 0,
        source: "api"
      }
    end

    def display_imported_issue(issue_data)
      display_message("✅ Successfully imported GitHub issue", type: :success)
      display_message("", type: :info)
      display_message("📋 Issue ##{issue_data[:number]}: #{issue_data[:title]}", type: :highlight)
      display_message("🔗 URL: #{issue_data[:url]}", type: :muted)
      display_message("📊 State: #{issue_data[:state]}", type: :info)

      unless issue_data[:labels].empty?
        display_message("🏷️ Labels: #{issue_data[:labels].join(", ")}", type: :info)
      end

      if issue_data[:milestone]
        display_message("🎯 Milestone: #{issue_data[:milestone]}", type: :info)
      end

      unless issue_data[:assignees].empty?
        display_message("👤 Assignees: #{issue_data[:assignees].join(", ")}", type: :info)
      end

      if issue_data[:comments] > 0
        display_message("💬 Comments: #{issue_data[:comments]}", type: :info)
      end

      display_message("", type: :info)
      display_message("📝 Description:", type: :info)
      # Truncate body if too long
      body = issue_data[:body]
      if body.length > 500
        display_message("#{body[0..497]}...", type: :muted)
        display_message("[Truncated - full description available in work loop]", type: :muted)
      else
        display_message(body, type: :muted)
      end
    end

    def create_work_loop_prompt(issue_data)
      # Create PROMPT.md for work loop
      prompt_content = generate_prompt_content(issue_data)

      File.write("PROMPT.md", prompt_content)
      display_message("", type: :info)
      display_message("📄 Created PROMPT.md for work loop", type: :success)
      display_message("   You can now run 'aidp execute' to start working on this issue", type: :info)
    end

    def generate_prompt_content(issue_data)
      <<~PROMPT
        # Work Loop: GitHub Issue ##{issue_data[:number]}

        ## Instructions
        You are working on a GitHub issue imported into AIDP. Your responsibilities:
        1. Read this PROMPT.md file to understand what needs to be done
        2. Complete the work described in the issue below
        3. **IMPORTANT**: Edit this PROMPT.md file yourself to:
           - Remove completed items
           - Update with current status
           - Keep it concise (remove unnecessary context)
           - Mark the issue COMPLETE when 100% done
        4. After you finish, tests and linters will run automatically
        5. If tests/linters fail, you'll see the errors in the next iteration

        ## Completion Criteria
        Mark this issue COMPLETE by adding this line to PROMPT.md:
        ```
        STATUS: COMPLETE
        ```

        ## GitHub Issue Details

        **Issue ##{issue_data[:number]}**: #{issue_data[:title]}
        **URL**: #{issue_data[:url]}
        **State**: #{issue_data[:state]}
        #{"**Labels**: #{issue_data[:labels].join(", ")}" unless issue_data[:labels].empty?}
        #{"**Milestone**: #{issue_data[:milestone]}" if issue_data[:milestone]}
        #{"**Assignees**: #{issue_data[:assignees].join(", ")}" unless issue_data[:assignees].empty?}

        ## Issue Description

        #{issue_data[:body]}

        ## Implementation Plan

        Based on the issue description above, implement the requested changes:

        1. [ ] Analyze the requirements from the issue description
        2. [ ] Plan the implementation approach
        3. [ ] Implement the requested functionality
        4. [ ] Add or update tests as needed
        5. [ ] Update documentation if required
        6. [ ] Verify all tests pass
        7. [ ] Mark STATUS: COMPLETE

        ## Notes

        - This issue was imported via AIDP issue import (source: #{issue_data[:source]})
        - Original issue URL: #{issue_data[:url]}
        - If you need clarification, refer back to the original issue
        - Consider any linked PRs or related issues mentioned in the description
      PROMPT
    end

    def gh_cli_available?
      _stdout, _stderr, status = Open3.capture3("gh", "--version")
      status.success?
    rescue Errno::ENOENT
      false
    end
  end
end
