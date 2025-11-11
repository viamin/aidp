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

      # Default label names
      DEFAULT_PLAN_LABEL = "aidp-plan"
      DEFAULT_NEEDS_INPUT_LABEL = "aidp-needs-input"
      DEFAULT_READY_LABEL = "aidp-ready"
      DEFAULT_BUILD_LABEL = "aidp-build"

      COMMENT_HEADER = "## 🤖 AIDP Plan Proposal"

      attr_reader :plan_label, :needs_input_label, :ready_label, :build_label

      def initialize(repository_client:, state_store:, plan_generator:, label_config: {})
        @repository_client = repository_client
        @state_store = state_store
        @plan_generator = plan_generator

        # Load label configuration with defaults
        @plan_label = label_config[:plan_trigger] || label_config["plan_trigger"] || DEFAULT_PLAN_LABEL
        @needs_input_label = label_config[:needs_input] || label_config["needs_input"] || DEFAULT_NEEDS_INPUT_LABEL
        @ready_label = label_config[:ready_to_build] || label_config["ready_to_build"] || DEFAULT_READY_LABEL
        @build_label = label_config[:build_trigger] || label_config["build_trigger"] || DEFAULT_BUILD_LABEL
      end

      # For backward compatibility
      def self.plan_label_from_config(config)
        labels = config[:labels] || config["labels"] || {}
        labels[:plan_trigger] || labels["plan_trigger"] || DEFAULT_PLAN_LABEL
      end

      def process(issue)
        number = issue[:number]
        if @state_store.plan_processed?(number)
          display_message("ℹ️  Plan for issue ##{number} already posted. Skipping.", type: :muted)
          return
        end

        display_message("🧠 Generating plan for issue ##{number} (#{issue[:title]})", type: :info)
        plan_data = @plan_generator.generate(issue)

        # Fetch the user who added the most recent label
        label_actor = @repository_client.most_recent_label_actor(number)

        comment_body = build_comment(issue: issue, plan: plan_data, label_actor: label_actor)
        @repository_client.post_comment(number, comment_body)

        display_message("💬 Posted plan comment for issue ##{number}", type: :success)
        @state_store.record_plan(number, plan_data.merge(comment_body: comment_body, comment_hint: COMMENT_HEADER))

        # Update labels: remove plan trigger, add appropriate status label
        update_labels_after_plan(number, plan_data)
      end

      private

      def update_labels_after_plan(number, plan_data)
        questions = Array(plan_data[:questions])
        has_questions = questions.any? && !questions.all? { |q| q.to_s.strip.empty? }

        # Determine which label to add based on whether there are questions
        new_label = has_questions ? @needs_input_label : @ready_label
        status_text = has_questions ? "needs input" : "ready to build"

        begin
          @repository_client.replace_labels(
            number,
            old_labels: [@plan_label],
            new_labels: [new_label]
          )
          display_message("🏷️  Updated labels: removed '#{@plan_label}', added '#{new_label}' (#{status_text})", type: :info)
        rescue => e
          display_message("⚠️  Failed to update labels for issue ##{number}: #{e.message}", type: :warn)
          # Don't fail the whole process if label update fails
        end
      end

      def build_comment(issue:, plan:, label_actor: nil)
        summary = plan[:summary].to_s.strip
        tasks = Array(plan[:tasks])
        questions = Array(plan[:questions])
        has_questions = questions.any? && !questions.all? { |q| q.to_s.strip.empty? }

        parts = []
        parts << COMMENT_HEADER
        parts << ""

        # Tag the label actor if available
        if label_actor
          parts << "cc @#{label_actor}"
          parts << ""
        end

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

        # Add instructions based on whether there are questions
        parts << if has_questions
          "**Next Steps**: Please reply with answers to the questions above. Once resolved, remove the `#{@needs_input_label}` label and add the `#{@build_label}` label to begin implementation."
        else
          "**Next Steps**: This plan is ready for implementation. Add the `#{@build_label}` label to begin."
        end

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
