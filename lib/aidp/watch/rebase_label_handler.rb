require "open3"
require "shellwords"

module Aidp
  module Watch
    # Handles the 'aidp-rebase' label workflow for automatic PR rebasing
    class RebaseLabelHandler
      REBASE_LABEL = "aidp-rebase"

      def initialize(repository_client:, pr_worktree_manager:, ai_decision_engine: nil)
        @repository_client = repository_client
        @pr_worktree_manager = pr_worktree_manager
        @ai_decision_engine = ai_decision_engine || AIDecisionEngine.new
      end

      # Main method to handle rebase label workflow
      # @param pr_number [Integer] The pull request number
      # @return [Hash] Result of the rebase operation
      def handle_rebase(pr_number)
        Aidp.log_debug(
          "rebase_label_handler",
          "initiating_rebase",
          pr_number: pr_number
        )

        # Fetch PR details
        pr_details = fetch_pr_details(pr_number)
        return {success: false, error: "Unable to fetch PR details"} unless pr_details

        # Create worktree for the PR
        worktree_path = create_pr_worktree(pr_details)
        return {success: false, error: "Failed to create worktree"} unless worktree_path

        # Perform the rebase and get result
        rebase_result = perform_rebase(pr_details, worktree_path)

        # Post-rebase processing
        process_rebase_result(pr_number, rebase_result)

        # Clean up worktree
        @pr_worktree_manager.remove_worktree(pr_number)

        rebase_result
      rescue => e
        Aidp.log_error(
          "rebase_label_handler",
          "rebase_failed",
          pr_number: pr_details&.fetch(:number, "unknown"),
          error: e.message
        )
        {
          success: false,
          error: e.message,
          base_branch: pr_details&.fetch(:base_branch, "unknown"),
          head_branch: pr_details&.fetch(:head_branch, "unknown")
        }
      end

      private

      # Perform the rebase operation in the worktree
      # @param pr_details [Hash] Details of the pull request
      # @param worktree_path [String] Path to the worktree
      # @return [Hash] Result of the rebase operation
      def perform_rebase(pr_details, worktree_path)
        Dir.chdir(worktree_path) do
          system("git fetch origin #{pr_details[:base_branch]} 2>/dev/null")

          # First attempt: direct rebase
          base_ref = "origin/#{pr_details[:base_branch]}"
          rebase_output = `git rebase #{base_ref} 2>&1`
          rebase_success = $?.success?

          # If rebase fails, try AI conflict resolution
          if !rebase_success
            Aidp.log_debug(
              "rebase_label_handler",
              "rebase_conflict_detected",
              pr_number: pr_details[:number]
            )

            # Call AI decision engine to resolve conflicts
            conflict_resolution = @ai_decision_engine.resolve_merge_conflicts(
              base_branch: pr_details[:base_branch],
              head_branch: pr_details[:head_branch]
            )

            # If AI could resolve conflicts
            if conflict_resolution[:resolved]
              conflict_resolution[:files].each do |file, content|
                File.write(file, content)
                system("git add #{Shellwords.escape(file)}")
              end

              # Re-attempt rebase
              rebase_output = `git rebase --continue 2>&1`
              rebase_success = $?.success?
            end
          end

          # Prepare rebase result
          {
            success: rebase_success,
            output: rebase_output,
            base_branch: pr_details[:base_branch],
            head_branch: pr_details[:head_branch]
          }
        end
      end

      # Fetch details of the pull request
      # @param pr_number [Integer] The pull request number
      # @return [Hash, nil] PR details or nil if fetch fails
      def fetch_pr_details(pr_number)
        pr_details = @repository_client.get_pr(pr_number)
        Aidp.log_debug(
          "rebase_label_handler",
          "pr_details_fetched",
          base_branch: pr_details[:base_branch],
          head_branch: pr_details[:head_branch]
        )
        pr_details
      rescue => e
        Aidp.log_error(
          "rebase_label_handler",
          "fetch_pr_details_failed",
          pr_number: pr_number,
          error: e.message
        )
        nil
      end

      # Create a worktree for the PR
      # @param pr_details [Hash] Details of the pull request
      # @return [String, nil] Worktree path or nil if creation fails
      def create_pr_worktree(pr_details)
        @pr_worktree_manager.create_worktree(
          pr_details[:number],
          pr_details[:base_branch],
          pr_details[:head_branch]
        )
      rescue => e
        Aidp.log_error(
          "rebase_label_handler",
          "worktree_creation_failed",
          pr_number: pr_details[:number],
          error: e.message
        )
        nil
      end

      # Process and report rebase result
      # @param pr_number [Integer] The pull request number
      # @param rebase_result [Hash] Result of the rebase operation
      def process_rebase_result(pr_number, rebase_result)
        if rebase_result[:success]
          # Post success comment to PR
          success_comment = <<~COMMENT
            ## 🔄 Automatic Rebase Successful

            The branch has been successfully rebased against #{rebase_result[:base_branch]}.

            Rebase details:
            - Base branch: #{rebase_result[:base_branch]}
            - Head branch: #{rebase_result[:head_branch]}
          COMMENT

          @repository_client.add_pr_comment(pr_number, success_comment)

          # Remove rebase label
          @repository_client.remove_label(pr_number, REBASE_LABEL)
        else
          # Post failure comment to PR
          failure_comment = <<~COMMENT
            ## ❌ Automatic Rebase Failed

            Rebase against #{rebase_result[:base_branch]} encountered issues:

            ```
            #{rebase_result[:output] || rebase_result[:error]}
            ```

            Please resolve conflicts manually or seek assistance.
          COMMENT

          @repository_client.add_pr_comment(pr_number, failure_comment)
        end

        Aidp.log_debug(
          "rebase_label_handler",
          "rebase_result_processed",
          pr_number: pr_number,
          success: rebase_result[:success]
        )
      end
    end
  end
end
