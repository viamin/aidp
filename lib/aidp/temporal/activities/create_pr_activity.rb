# frozen_string_literal: true

require "open3"
require_relative "base_activity"

module Aidp
  module Temporal
    module Activities
      # Activity that creates a pull request from implemented changes
      # Handles git operations and GitHub PR creation
      class CreatePrActivity < BaseActivity

        def execute(input)
          with_activity_context do
            project_dir = input[:project_dir]
            issue_number = input[:issue_number]
            implementation = input[:implementation]
            iterations = input[:iterations]

            # Validate issue_number is numeric to prevent injection
            unless issue_number.to_s.match?(/\A\d+\z/)
              return error_result("Invalid issue number: must be numeric")
            end

            log_activity("creating_pr",
              project_dir: project_dir,
              issue_number: issue_number)

            # Ensure we have commits to push
            unless has_uncommitted_changes?(project_dir) || has_unpushed_commits?(project_dir)
              return error_result("No changes to create PR from")
            end

            # Create branch if needed
            branch_name = ensure_branch(project_dir, issue_number)

            heartbeat(phase: "branch_created", branch: branch_name)

            # Commit any uncommitted changes
            if has_uncommitted_changes?(project_dir)
              commit_changes(project_dir, issue_number, iterations)
            end

            heartbeat(phase: "changes_committed")

            # Push branch
            push_branch(project_dir, branch_name)

            heartbeat(phase: "branch_pushed")

            # Create PR
            pr_result = create_pull_request(
              project_dir: project_dir,
              branch_name: branch_name,
              issue_number: issue_number,
              implementation: implementation,
              iterations: iterations
            )

            if pr_result[:success]
              success_result(
                pr_url: pr_result[:pr_url],
                pr_number: pr_result[:pr_number],
                branch: branch_name
              )
            else
              error_result(pr_result[:error] || "Failed to create PR")
            end
          end
        end

        private

        def has_uncommitted_changes?(project_dir)
          stdout, _stderr, status = Open3.capture3("git", "status", "--porcelain", chdir: project_dir)
          status.success? && !stdout.strip.empty?
        end

        def has_unpushed_commits?(project_dir)
          stdout, _stderr, status = Open3.capture3(
            "git", "rev-list", "--count", "@{upstream}..HEAD",
            chdir: project_dir
          )
          status.success? && stdout.strip.to_i > 0
        rescue
          false
        end

        def ensure_branch(project_dir, issue_number)
          # issue_number is validated as numeric in execute()
          branch_name = "aidp/issue-#{issue_number}"

          stdout, _stderr, _status = Open3.capture3("git", "branch", "--show-current", chdir: project_dir)
          current_branch = stdout.strip

          if current_branch != branch_name
            # Check if branch exists using array-style system call
            ref_path = "refs/heads/#{branch_name}"
            _stdout, _stderr, status = Open3.capture3(
              "git", "show-ref", "--verify", "--quiet", ref_path,
              chdir: project_dir
            )

            if status.success?
              Open3.capture3("git", "checkout", branch_name, chdir: project_dir)
            else
              Open3.capture3("git", "checkout", "-b", branch_name, chdir: project_dir)
            end
          end

          branch_name
        end

        def commit_changes(project_dir, issue_number, iterations)
          # Stage all changes
          Open3.capture3("git", "add", "-A", chdir: project_dir)

          # Build commit message (issue_number validated as numeric)
          commit_message = build_commit_message(issue_number, iterations)

          # Use array-style to avoid shell injection
          Open3.capture3("git", "commit", "-m", commit_message, chdir: project_dir)
        end

        def build_commit_message(issue_number, iterations)
          # issue_number is validated as numeric, iterations is an integer
          safe_iterations = iterations.to_i

          "fix: implement changes for issue ##{issue_number}\n\n" \
            "Implemented via AIDP Temporal workflow\n" \
            "Iterations: #{safe_iterations}\n\n" \
            "Closes ##{issue_number}"
        end

        def push_branch(project_dir, branch_name)
          # branch_name is constructed from validated issue_number
          Open3.capture3("git", "push", "-u", "origin", branch_name, chdir: project_dir)
        end

        def create_pull_request(project_dir:, branch_name:, issue_number:, implementation:, iterations:)
          # issue_number is validated as numeric
          title = "Fix ##{issue_number}"
          body = build_pr_body(issue_number, implementation, iterations)

          # Use array-style Open3 to avoid shell injection
          stdout, stderr, status = Open3.capture3(
            "gh", "pr", "create", "--title", title, "--body", body,
            chdir: project_dir
          )

          if status.success?
            # Extract PR URL from output
            pr_url = stdout.strip
            pr_number = pr_url.split("/").last.to_i

            {
              success: true,
              pr_url: pr_url,
              pr_number: pr_number
            }
          else
            {
              success: false,
              error: stderr.empty? ? stdout : stderr
            }
          end
        end

        def build_pr_body(issue_number, implementation, iterations)
          # issue_number validated as numeric, iterations is integer
          safe_iterations = iterations.to_i

          <<~BODY
            ## Summary

            Implements changes requested in ##{issue_number}

            ## Implementation Details

            This PR was created via AIDP Temporal workflow after #{safe_iterations} iterations of the fix-forward work loop.

            ## Testing

            - [ ] All tests pass
            - [ ] Lint checks pass
            - [ ] Manual testing completed

            Closes ##{issue_number}
          BODY
        end
      end
    end
  end
end
