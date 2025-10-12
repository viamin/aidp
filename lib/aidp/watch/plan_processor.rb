# frozen_string_literal: true

require_relative "../message_display"
require_relative "plan_generator"
require_relative "state_store"

module Aidp
  module Watch
    # Handles the aidp-plan label trigger by generating an implementation plan
    # and posting it back to the originating GitHub issue.
    class PlanProcessor
      include Aidp::MessageDisplay

      PLAN_LABEL = "aidp-plan"
      COMMENT_HEADER = "## 🤖 AIDP Plan Proposal"

      def initialize(repository_client:, state_store:, plan_generator:)
        @repository_client = repository_client
        @state_store = state_store
        @plan_generator = plan_generator
      end

      def process(issue)
        number = issue[:number]
        if @state_store.plan_processed?(number)
          display_message("ℹ️  Plan for issue ##{number} already posted. Skipping.", type: :muted)
          return
        end

        display_message("🧠 Generating plan for issue ##{number} (#{issue[:title]})", type: :info)
        plan_data = @plan_generator.generate(issue)

        comment_body = build_comment(issue: issue, plan: plan_data)
        @repository_client.post_comment(number, comment_body)

        display_message("💬 Posted plan comment for issue ##{number}", type: :success)
        @state_store.record_plan(number, plan_data.merge(comment_body: comment_body, comment_hint: COMMENT_HEADER))
      end

      private

      def build_comment(issue:, plan:)
        summary = plan[:summary].to_s.strip
        tasks = Array(plan[:tasks])
        questions = Array(plan[:questions])

        parts = []
        parts << COMMENT_HEADER
        parts << ""
        parts << "**Issue**: [##{issue[:number]}](#{issue[:url]})"
        parts << "**Title**: #{issue[:title]}"
        parts << ""
        parts << "### Plan Summary"
        parts << (summary.empty? ? "_No summary generated_" : summary)
        parts << ""
        parts << "### Proposed Tasks"
        parts << format_bullets(tasks, placeholder: "_Pending task breakdown_")
        parts << ""
        parts << "### Clarifying Questions"
        parts << format_numbered(questions, placeholder: "_No questions identified_")
        parts << ""
        parts << "Please reply inline with answers to the questions above. Once the discussion is resolved, apply the `aidp-build` label to begin implementation."
        parts.join("\n")
      end

      def format_bullets(items, placeholder:)
        if items.empty?
          placeholder
        else
          items.map { |item| "- #{item}" }.join("\n")
        end
      end

      def format_numbered(items, placeholder:)
        if items.empty?
          placeholder
        else
          items.each_with_index.map { |item, index| "#{index + 1}. #{item}" }.join("\n")
        end
      end
    end
  end
end
