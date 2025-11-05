# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "open3"
require "timeout"
require_relative "../execute/prompt_manager"

module Aidp
  # Handles importing GitHub issues into AIDP work loops
  class IssueImporter
    include Aidp::MessageDisplay

    COMPONENT = "issue_importer"

    # Initialize the importer
    #
    # @param gh_available [Boolean, nil] (test-only) forcibly sets whether gh CLI is considered
    #   available. When nil (default) we auto-detect. This enables deterministic specs without
    #   depending on developer environment.
    def initialize(gh_available: nil, enable_bootstrap: true)
      disabled_via_env = ENV["AIDP_DISABLE_GH_CLI"] == "1"
      @gh_available = if disabled_via_env
        false
      else
        gh_available.nil? ? gh_cli_available? : gh_available
      end
      @enable_bootstrap = enable_bootstrap
      Aidp.log_debug(COMPONENT, "Initialized importer", gh_available: @gh_available, enable_bootstrap: @enable_bootstrap, disabled_via_env: disabled_via_env)
      Aidp.log_debug(COMPONENT, "GitHub CLI disabled via env flag") if disabled_via_env
    end

    def import_issue(identifier)
      issue_url = normalize_issue_identifier(identifier)
      return nil unless issue_url

      issue_data = fetch_issue_data(issue_url)
      return nil unless issue_data

      display_imported_issue(issue_data)
      create_work_loop_prompt(issue_data)
      perform_bootstrap(issue_data)

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
      Aidp.log_debug(COMPONENT, "Fetching issue data", owner: owner, repo: repo, number: number, via: (@gh_available ? "gh_cli" : "api"))

      # First try GitHub CLI if available (works for private repos)
      if @gh_available
        display_message("🔍 Fetching issue via GitHub CLI...", type: :info)
        Aidp.log_debug(COMPONENT, "Attempting GitHub CLI fetch", owner: owner, repo: repo, number: number)
        issue_data = fetch_via_gh_cli(owner, repo, number)
        if issue_data
          Aidp.log_debug(COMPONENT, "GitHub CLI fetch succeeded", owner: owner, repo: repo, number: number)
          return issue_data
        end
        Aidp.log_debug(COMPONENT, "GitHub CLI fetch failed, falling back to API", owner: owner, repo: repo, number: number)
      end

      # Fallback to public API
      display_message("🔍 Fetching issue via GitHub API...", type: :info)
      Aidp.log_debug(COMPONENT, "Fetching issue via GitHub API", owner: owner, repo: repo, number: number)
      fixture = test_fixture(owner, repo, number)
      if fixture
        Aidp.log_debug(COMPONENT, "Using test fixture for issue fetch", owner: owner, repo: repo, number: number, status: fixture["status"])
        return handle_test_fixture(fixture, owner, repo, number)
      end
      fetch_via_api(owner, repo, number)
    end

    def fetch_via_gh_cli(owner, repo, number)
      cmd = [
        "gh", "issue", "view", number,
        "--repo", "#{owner}/#{repo}",
        "--json", "title,body,labels,milestone,comments,state,assignees,number,url"
      ]

      Aidp.log_debug(COMPONENT, "Running gh cli", owner: owner, repo: repo, number: number, command: cmd.join(" "))
      stdout, stderr, status = capture3_with_timeout(*cmd, timeout: gh_cli_timeout)
      Aidp.log_debug(COMPONENT, "Completed gh cli", owner: owner, repo: repo, number: number, exitstatus: status.exitstatus)

      unless status.success?
        Aidp.log_warn(COMPONENT, "GitHub CLI fetch failed", owner: owner, repo: repo, number: number, exitstatus: status.exitstatus, error: stderr.strip)
        display_message("⚠️ GitHub CLI failed: #{stderr.strip}", type: :warn)
        return nil
      end

      begin
        data = JSON.parse(stdout)
        normalize_gh_cli_data(data)
      rescue JSON::ParserError => e
        Aidp.log_warn(COMPONENT, "GitHub CLI response parse failed", owner: owner, repo: repo, number: number, error: e.message)
        display_message("❌ Failed to parse GitHub CLI response: #{e.message}", type: :error)
        nil
      end
    rescue Timeout::Error
      Aidp.log_warn(COMPONENT, "GitHub CLI timed out", owner: owner, repo: repo, number: number, timeout: gh_cli_timeout)
      display_message("⚠️ GitHub CLI timed out after #{gh_cli_timeout}s, falling back to API", type: :warn)
      nil
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
      # Create PROMPT.md for work loop using PromptManager (issue #226)
      prompt_content = generate_prompt_content(issue_data)

      # Use PromptManager to write to .aidp/PROMPT.md and archive immediately
      prompt_manager = Aidp::Execute::PromptManager.new(Dir.pwd)
      step_name = "github_issue_#{issue_data[:number]}"
      prompt_manager.write(prompt_content, step_name: step_name)

      display_message("", type: :info)
      display_message("📄 Created PROMPT.md for work loop", type: :success)
      display_message("   Location: .aidp/PROMPT.md", type: :info)
      display_message("   Archived to: .aidp/prompt_archive/", type: :info)
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

    def capture3_with_timeout(*cmd, timeout:)
      stdout_str = +""
      stderr_str = +""
      status = nil
      wait_thr = nil

      Timeout.timeout(timeout) do
        Open3.popen3(*cmd) do |stdin, stdout_io, stderr_io, thread|
          wait_thr = thread
          stdin.close
          stdout_str = stdout_io.read
          stderr_str = stderr_io.read
          status = thread.value
        end
      end

      [stdout_str, stderr_str, status]
    rescue Timeout::Error
      terminate_process(wait_thr)
      raise
    end

    def terminate_process(wait_thr)
      return unless wait_thr&.alive?

      begin
        Process.kill("TERM", wait_thr.pid)
      rescue Errno::ESRCH
        return
      end

      begin
        wait_thr.join(1)
      rescue
        nil
      end

      return unless wait_thr.alive?

      begin
        Process.kill("KILL", wait_thr.pid)
      rescue Errno::ESRCH
        return
      end

      begin
        wait_thr.join(1)
      rescue
        nil
      end
    end

    def gh_cli_timeout
      Integer(ENV.fetch("AIDP_GH_CLI_TIMEOUT", 5))
    rescue ArgumentError, TypeError
      5
    end

    def test_fixture(owner, repo, number)
      fixtures_raw = ENV["AIDP_TEST_ISSUE_FIXTURES"]
      return nil unless fixtures_raw

      fixtures = JSON.parse(fixtures_raw)
      fixtures["#{owner}/#{repo}##{number}"]
    rescue JSON::ParserError => e
      Aidp.log_warn(COMPONENT, "Invalid issue fixtures JSON", error: e.message)
      nil
    end

    def handle_test_fixture(fixture, owner, repo, number)
      status = fixture["status"].to_i
      case status
      when 200
        data = fixture.fetch("data", {})
        Aidp.log_debug(COMPONENT, "Returning fixture issue data", owner: owner, repo: repo, number: number)
        normalize_api_data(stringify_keys(data))
      when 404
        Aidp.log_warn(COMPONENT, "Fixture indicates issue not found", owner: owner, repo: repo, number: number)
        display_message("❌ Issue not found (may be private)", type: :error)
        nil
      when 403
        Aidp.log_warn(COMPONENT, "Fixture indicates API rate limit", owner: owner, repo: repo, number: number)
        display_message("❌ API rate limit exceeded", type: :error)
        nil
      else
        Aidp.log_warn(COMPONENT, "Fixture indicates API error", owner: owner, repo: repo, number: number, status: status)
        display_message("❌ GitHub API error: #{status}", type: :error)
        nil
      end
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(k, v), result|
        result[k.to_s] = v
      end
    end

    def perform_bootstrap(issue_data)
      return if ENV["AIDP_DISABLE_BOOTSTRAP"] == "1"
      return unless @enable_bootstrap
      return unless git_repo?

      ensure_initial_commit

      branch = branch_name(issue_data)
      create_branch(branch)
      create_checkpoint_tag(issue_data)
      detect_and_record_tooling
    rescue => e
      display_message("⚠️ Bootstrap step failed: #{e.message}", type: :warn)
    end

    def git_repo?
      File.exist?(".git")
    end

    # Ensure we have an initial commit so that branch and tag creation succeed in fresh repos.
    # In an empty repo without commits, git checkout -b and git tag will fail due to missing HEAD.
    def ensure_initial_commit
      _stdout, _stderr, status = Open3.capture3("git", "rev-parse", "--verify", "HEAD")
      return if status.success? # already have at least one commit

      # Create a placeholder file if nothing is present so commit has content
      placeholder = ".aidp_bootstrap"
      unless File.exist?(placeholder)
        File.write(placeholder, "Initial commit placeholder for AIDP bootstrap\n")
      end

      Open3.capture3("git", "add", "-A")
      _c_stdout, c_stderr, c_status = Open3.capture3("git", "commit", "-m", "chore(aidp): initial commit before bootstrap")
      unless c_status.success?
        display_message("⚠️ Could not create initial commit: #{c_stderr.strip}", type: :warn)
      end
    end

    def branch_name(issue_data)
      slug = issue_data[:title].downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")[0, 40]
      "aidp/iss-#{issue_data[:number]}-#{slug}"
    end

    def create_branch(name)
      _stdout, stderr, status = Open3.capture3("git", "checkout", "-b", name)
      if status.success?
        display_message("🌿 Created branch #{name}", type: :success)
      else
        display_message("⚠️ Could not create branch: #{stderr.strip}", type: :warn)
      end
    end

    def create_checkpoint_tag(issue_data)
      tag = "aidp-start/#{issue_data[:number]}"
      _stdout, stderr, status = Open3.capture3("git", "tag", tag)
      if status.success?
        display_message("🏷️  Added checkpoint tag #{tag}", type: :success)
      else
        display_message("⚠️ Could not create tag: #{stderr.strip}", type: :warn)
      end
    end

    def detect_and_record_tooling
      require_relative "../tooling_detector"
      result = Aidp::ToolingDetector.detect
      return if result.test_commands.empty? && result.lint_commands.empty?

      tooling_info = "# Detected Tooling\n\n" \
        + (result.test_commands.empty? ? "" : "Test Commands:\n#{result.test_commands.map { |c| "- #{c}" }.join("\n")}\n\n") \
        + (result.lint_commands.empty? ? "" : "Lint Commands:\n#{result.lint_commands.map { |c| "- #{c}" }.join("\n")}\n")

      # Use PromptManager to append to .aidp/PROMPT.md (issue #226)
      prompt_manager = Aidp::Execute::PromptManager.new(Dir.pwd)
      current_prompt = prompt_manager.read
      updated_prompt = current_prompt + "\n---\n\n#{tooling_info}"
      prompt_manager.write(updated_prompt, step_name: "github_issue_tooling")

      display_message("🧪 Detected tooling and appended to PROMPT.md", type: :info)
    end
  end
end
