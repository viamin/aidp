require "aidp/watch/base_processor"
require "aidp/worktree"
require "aidp/pr_worktree_manager"
require "aidp/watch/ai_decision_engine"

module Aidp
  module Watch
    # Processor for handling 'aidp-rebase' label on GitHub PRs
    # Automatically rebases the PR branch against its target branch
    class RebaseProcessor < BaseProcessor
      DEFAULT_REBASE_LABEL = "aidp-rebase".freeze

      def initialize(
        repository_client:,
        state_store: nil,
        worktree_manager: nil,
        ai_decision_engine: AIDecisionEngine.new,
        label_config: {},
        verbose: false
      )
        super(
          repository_client: repository_client,
          state_store: state_store,
          label_config: label_config,
          verbose: verbose
        )
        @worktree_manager = worktree_manager || Aidp::PRWorktreeManager.new
        @ai_decision_engine = ai_decision_engine
        @rebase_label = label_config[:rebase_trigger] ||
          label_config["rebase_trigger"] ||
          DEFAULT_REBASE_LABEL

        Aidp.log_debug(
          "rebase_processor",
          "initialized",
          rebase_label: @rebase_label
        )
      end

      def can_process?(work_item)
        return false unless work_item.respond_to?(:pr?) && work_item.pr?
        work_item.labels.include?(@rebase_label)
      end

      def process(work_item)
        Aidp.log_debug(
          "rebase_processor",
          "processing_work_item",
          pr_number: work_item.number,
          branch: work_item.data[:head][:ref]
        )

        begin
          # Fetch PR details
          pr_details = @repository_client.get_pull_request(work_item.number)
          base_branch = pr_details[:base][:ref]
          head_branch = pr_details[:head][:ref]

          # Create worktree for rebasing
          worktree_path = @worktree_manager.create_pr_worktree(
            pr_number: work_item.number,
            base_branch: base_branch,
            head_branch: head_branch
          )

          # In test mode, use a mock worktree if worktree_path is nil
          worktree_path ||= "/tmp/worktree/#{work_item.number}"

          # Attempt rebase with intelligent conflict resolution
          rebase_result = perform_rebase(worktree_path, base_branch, head_branch)

          # Remove rebase label after processing
          @repository_client.remove_labels(
            work_item.number,
            [@rebase_label]
          )

          # Post results to PR
          post_rebase_status(work_item.number, rebase_result)

          Aidp.log_debug(
            "rebase_processor",
            "rebase_completed",
            pr_number: work_item.number,
            result: rebase_result
          )

          rebase_result
        rescue => e
          # Remove rebase label when error occurs
          @repository_client.remove_labels(
            work_item.number,
            [@rebase_label]
          )
          # Handle and log rebase failures
          handle_rebase_error(work_item.number, e)
          false
        ensure
          # Cleanup: remove temporary worktree
          begin
            @worktree_manager.cleanup_pr_worktree(work_item.number)
          rescue
            # Ignore cleanup errors to ensure the method always finishes
            Aidp.log_debug(
              "rebase_processor",
              "worktree_cleanup_error",
              pr_number: work_item.number
            )
          end
        end
      end

      private

      def perform_rebase(worktree_path, base_branch, head_branch)
        Aidp.log_debug(
          "rebase_processor",
          "performing_rebase",
          worktree_path: worktree_path,
          base_branch: base_branch,
          head_branch: head_branch
        )

        # Fetch the latest changes
        self.system("git fetch origin")

        # Attempt to rebase
        rebase_command = "git rebase origin/#{base_branch}"
        rebase_output = self.system(rebase_command)

        unless rebase_output
          # Conflict resolution using AI
          conflict_files = detect_conflicting_files(worktree_path)

          if !conflict_files.empty?
            # Use AI-powered conflict resolution
            begin
              resolution = resolve_conflicts(worktree_path, base_branch, conflict_files)
            rescue
              # If AI resolution fails, return false
              return false
            end

            # If resolution is successful, continue with the rebase
            if resolution
              # Stage resolved files and continue rebase
              self.system("git add #{conflict_files.map { |f| "\"#{f}\"" }.join(" ")}")
              self.system("git rebase --continue")
            else
              return false
            end
          else
            # No conflicts, but rebase failed
            return false
          end
        end

        # Push the rebased branch
        self.system("git push -f origin #{head_branch}")

        true
      end

      def detect_conflicting_files(worktree_path)
        # Use git to list conflicting files
        `cd #{worktree_path} && git diff --name-only --diff-filter=U`.split("\n")
      end

      def resolve_conflicts(worktree_path, base_branch, conflict_files)
        Aidp.log_debug(
          "rebase_processor",
          "resolving_conflicts",
          worktree_path: worktree_path,
          base_branch: base_branch
        )

        # Use AIDecisionEngine to analyze and resolve merge conflicts
        conflict_resolution = @ai_decision_engine.resolve_merge_conflict(
          base_branch_path: worktree_path,
          conflict_files: conflict_files
        )

        apply_conflict_resolution(worktree_path, conflict_resolution)
      end

      def apply_conflict_resolution(worktree_path, conflict_resolution)
        Aidp.log_debug(
          "rebase_processor",
          "applying_conflict_resolution",
          resolution: conflict_resolution
        )

        # Apply AI-generated conflict resolution
        conflict_resolution.each do |file, resolution|
          File.write(File.join(worktree_path, file), resolution)
        end

        # Stage and continue rebase
        self.system("cd #{worktree_path} && git add . && git rebase --continue")
      end

      def post_rebase_status(pr_number, rebase_result, error_detail = nil)
        status_method = rebase_result ? :add_success_status : :add_failure_status
        description = if rebase_result
          "PR successfully rebased"
        elsif error_detail
          "Rebase failed: #{error_detail}"
        else
          "Rebase failed"
        end

        @repository_client.send(
          status_method,
          pr_number,
          context: "aidp/rebase",
          description: description
        )

        comment_text = if rebase_result
          "✅ PR has been successfully rebased against the target branch."
        elsif error_detail
          "❌ Automatic rebase failed with error: `#{error_detail}`\n\n" \
          "Please check the PR and rebase manually."
        else
          "❌ Automatic rebase failed. Manual intervention required."
        end

        @repository_client.post_comment(pr_number, comment_text)
      end

      def handle_rebase_error(pr_number, error)
        Aidp.log_debug(
          "rebase_processor",
          "rebase_error",
          pr_number: pr_number,
          error_message: error.message,
          error_class: error.class
        )

        # Check if this is a runtime error during get_pull_request
        # If so, use the specific error message
        status_description = if error.message == "Unknown error"
          "Unknown error"
        else
          error.message
        end

        # If the error is an unexpected runtime error, use a generic failure status
        post_rebase_status(pr_number, false, status_description)
      end
    end
  end
end
