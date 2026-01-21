# frozen_string_literal: true

require_relative "base_activity"

module Aidp
  module Temporal
    module Activities
      # Activity that creates a pull request from implemented changes
      # Handles git operations and GitHub PR creation
      class CreatePrActivity < BaseActivity
        activity_type "create_pr"

        def execute(input)
          with_activity_context do
            project_dir = input[:project_dir]
            issue_number = input[:issue_number]
            implementation = input[:implementation]
            iterations = input[:iterations]

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
          Dir.chdir(project_dir) do
            status = `git status --porcelain 2>/dev/null`.strip
            !status.empty?
          end
        end

        def has_unpushed_commits?(project_dir)
          Dir.chdir(project_dir) do
            # Check if we have commits not on remote
            ahead = `git rev-list --count @{upstream}..HEAD 2>/dev/null`.strip.to_i
            ahead > 0
          rescue
            false
          end
        end

        def ensure_branch(project_dir, issue_number)
          branch_name = "aidp/issue-#{issue_number}"

          Dir.chdir(project_dir) do
            current_branch = `git branch --show-current`.strip

            if current_branch != branch_name
              # Check if branch exists
              branch_exists = system("git show-ref --verify --quiet refs/heads/#{branch_name}")

              if branch_exists
                `git checkout #{branch_name} 2>/dev/null`
              else
                `git checkout -b #{branch_name} 2>/dev/null`
              end
            end
          end

          branch_name
        end

        def commit_changes(project_dir, issue_number, iterations)
          Dir.chdir(project_dir) do
            `git add -A`

            commit_message = build_commit_message(issue_number, iterations)
            `git commit -m "#{commit_message}"`
          end
        end

        def build_commit_message(issue_number, iterations)
          "fix: implement changes for issue ##{issue_number}\\n\\n" \
            "Implemented via AIDP Temporal workflow\\n" \
            "Iterations: #{iterations}\\n\\n" \
            "Closes ##{issue_number}"
        end

        def push_branch(project_dir, branch_name)
          Dir.chdir(project_dir) do
            `git push -u origin #{branch_name} 2>&1`
          end
        end

        def create_pull_request(project_dir:, branch_name:, issue_number:, implementation:, iterations:)
          Dir.chdir(project_dir) do
            title = "Fix ##{issue_number}"
            body = build_pr_body(issue_number, implementation, iterations)

            # Use GitHub CLI to create PR
            result = `gh pr create --title "#{title}" --body "#{body}" 2>&1`

            if $?.success?
              # Extract PR URL from output
              pr_url = result.strip
              pr_number = pr_url.split("/").last.to_i

              {
                success: true,
                pr_url: pr_url,
                pr_number: pr_number
              }
            else
              {
                success: false,
                error: result
              }
            end
          end
        end

        def build_pr_body(issue_number, implementation, iterations)
          <<~BODY.gsub('"', '\\"')
            ## Summary

            Implements changes requested in ##{issue_number}

            ## Implementation Details

            This PR was created via AIDP Temporal workflow after #{iterations} iterations of the fix-forward work loop.

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
