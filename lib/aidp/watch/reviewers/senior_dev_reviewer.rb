# frozen_string_literal: true

require_relative "base_reviewer"

module Aidp
  module Watch
    module Reviewers
      # Senior Developer Reviewer - focuses on correctness, architecture, and best practices
      class SeniorDevReviewer < BaseReviewer
        PERSONA_NAME = "Senior Developer"
        FOCUS_AREAS = [
          "Code correctness and logic errors",
          "Architecture and design patterns",
          "API design and consistency",
          "Error handling and edge cases",
          "Code maintainability and readability",
          "Testing coverage and quality",
          "Documentation completeness"
        ].freeze

        def review(pr_data:, files:, diff:)
          user_prompt = build_review_prompt(pr_data: pr_data, files: files, diff: diff)
          findings = analyze_with_provider(user_prompt)

          {
            persona: PERSONA_NAME,
            findings: findings
          }
        end
      end
    end
  end
end
