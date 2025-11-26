# frozen_string_literal: true

require_relative "../message_display"

module Aidp
  module Watch
    # Handles the aidp-auto label on issues by delegating to the BuildProcessor
    # and transferring the label to the created PR once work completes.
    class AutoProcessor
      include Aidp::MessageDisplay

      DEFAULT_AUTO_LABEL = "aidp-auto"

      attr_reader :auto_label

      def initialize(repository_client:, state_store:, build_processor:, label_config: {}, verbose: false)
        @repository_client = repository_client
        @state_store = state_store
        @build_processor = build_processor
        @verbose = verbose

        # Allow overrides from watch config
        @auto_label = label_config[:auto_trigger] || label_config["auto_trigger"] || DEFAULT_AUTO_LABEL
      end

      def process(issue)
        number = issue[:number]
        Aidp.log_debug("auto_processor", "process_started", issue: number, title: issue[:title])
        display_message("🤖 Starting autonomous build for issue ##{number}", type: :info)

        @build_processor.process(issue)

        status = @state_store.build_status(number)
        pr_url = status["pr_url"]
        pr_number = extract_pr_number(pr_url)

        unless status["status"] == "completed" && pr_number
          Aidp.log_debug("auto_processor", "no_pr_to_transfer", issue: number, status: status["status"], pr_url: pr_url)
          return
        end

        transfer_label_to_pr(issue_number: number, pr_number: pr_number)
      rescue => e
        Aidp.log_error("auto_processor", "process_failed", issue: issue[:number], error: e.message, error_class: e.class.name)
        display_message("❌ aidp-auto failed for issue ##{issue[:number]}: #{e.message}", type: :error)
      end

      private

      def extract_pr_number(pr_url)
        return nil unless pr_url

        match = pr_url.match(%r{/pull/(\d+)}i)
        match && match[1].to_i
      end

      def transfer_label_to_pr(issue_number:, pr_number:)
        Aidp.log_debug("auto_processor", "transferring_label", issue: issue_number, pr: pr_number, label: @auto_label)

        begin
          @repository_client.add_labels(pr_number, @auto_label)
          display_message("🏷️  Added '#{@auto_label}' to PR ##{pr_number}", type: :info)
        rescue => e
          Aidp.log_warn("auto_processor", "add_label_failed", pr: pr_number, label: @auto_label, error: e.message)
          display_message("⚠️  Failed to add '#{@auto_label}' to PR ##{pr_number}: #{e.message}", type: :warn)
        end

        begin
          @repository_client.remove_labels(issue_number, @auto_label)
          display_message("🏷️  Removed '#{@auto_label}' from issue ##{issue_number}", type: :muted)
        rescue => e
          Aidp.log_warn("auto_processor", "remove_label_failed", issue: issue_number, label: @auto_label, error: e.message)
          display_message("⚠️  Failed to remove '#{@auto_label}' from issue ##{issue_number}: #{e.message}", type: :warn)
        end
      end
    end
  end
end
