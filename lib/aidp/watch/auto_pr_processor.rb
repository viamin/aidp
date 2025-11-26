# frozen_string_literal: true

require_relative "../message_display"
require_relative "github_state_extractor"

module Aidp
  module Watch
    # Handles the aidp-auto label on PRs by chaining review and CI-fix flows
    # until the PR is ready for human review.
    class AutoPrProcessor
      include Aidp::MessageDisplay

      DEFAULT_AUTO_LABEL = "aidp-auto"

      def initialize(repository_client:, state_store:, review_processor:, ci_fix_processor:, label_config: {}, verbose: false)
        @repository_client = repository_client
        @state_store = state_store
        @review_processor = review_processor
        @ci_fix_processor = ci_fix_processor
        @state_extractor = GitHubStateExtractor.new(repository_client: repository_client)
        @verbose = verbose
        @auto_label = label_config[:auto_trigger] || label_config["auto_trigger"] || DEFAULT_AUTO_LABEL
      end

      def process(pr)
        number = pr[:number]
        Aidp.log_debug("auto_pr_processor", "process_started", pr: number, title: pr[:title])
        display_message("🤖 Running autonomous review/CI loop for PR ##{number}", type: :info)

        # Run review and CI fix flows. Each processor is responsible for its own guards.
        @review_processor.process(pr)
        @ci_fix_processor.process(pr)

        finalize_if_ready(pr_number: number)
      rescue => e
        Aidp.log_error("auto_pr_processor", "process_failed", pr: pr[:number], error: e.message, error_class: e.class.name)
        display_message("❌ aidp-auto failed on PR ##{pr[:number]}: #{e.message}", type: :error)
      end

      attr_reader :auto_label

      private

      def finalize_if_ready(pr_number:)
        pr_data = @repository_client.fetch_pull_request(pr_number)
        ci_status = @repository_client.fetch_ci_status(pr_number)

        review_done = @state_extractor.review_completed?(pr_data) || @state_store.review_processed?(pr_number)
        ci_passing = ci_status[:state] == "success"

        Aidp.log_debug("auto_pr_processor", "completion_check",
          pr: pr_number,
          review_done: review_done,
          ci_state: ci_status[:state])

        return unless review_done && ci_passing

        post_completion_comment(pr_number)
        remove_auto_label(pr_number)
      end

      def post_completion_comment(pr_number)
        comment = <<~COMMENT
          ## 🤖 aidp-auto

          - Automated review completed
          - CI is passing

          Marking this PR ready for human review and removing the `#{@auto_label}` label.
        COMMENT

        @repository_client.post_comment(pr_number, comment)
        display_message("💬 Posted aidp-auto completion comment on PR ##{pr_number}", type: :success)
      rescue => e
        Aidp.log_warn("auto_pr_processor", "comment_failed", pr: pr_number, error: e.message)
      end

      def remove_auto_label(pr_number)
        @repository_client.remove_labels(pr_number, @auto_label)
        display_message("🏷️  Removed '#{@auto_label}' from PR ##{pr_number}", type: :info)
      rescue => e
        Aidp.log_warn("auto_pr_processor", "remove_label_failed", pr: pr_number, error: e.message)
      end
    end
  end
end
