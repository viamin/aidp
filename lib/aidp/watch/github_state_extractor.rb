# frozen_string_literal: true

require "time"

module Aidp
  module Watch
    # Extracts state information from GitHub issues/PRs using labels and comments
    # as the single source of truth, enabling multiple AIDP instances to coordinate
    # without local state files.
    class GitHubStateExtractor
      # Pattern for detecting completion comments
      COMPLETION_PATTERN = /✅ Implementation complete for #(\d+)/i

      # Pattern for detecting detection comments
      DETECTION_PATTERN = /aidp detected `([^`]+)` at ([^\n]+) and is working on it/i

      # Pattern for detecting plan proposal comments
      PLAN_PROPOSAL_PATTERN = /<!-- PLAN_SUMMARY_START -->/i

      # Pattern for detecting in-progress label
      IN_PROGRESS_LABEL = "aidp-in-progress"

      def initialize(repository_client:)
        @repository_client = repository_client
      end

      # Check if an issue/PR is currently being worked on by another instance
      def in_progress?(item)
        has_label?(item, IN_PROGRESS_LABEL)
      end

      # Check if build is already completed for an issue
      # Looks for completion comment from AIDP
      def build_completed?(issue)
        return false unless issue[:comments]

        issue[:comments].any? do |comment|
          comment["body"]&.match?(COMPLETION_PATTERN)
        end
      end

      # Check if a plan has been posted for an issue
      def plan_posted?(issue)
        return false unless issue[:comments]

        issue[:comments].any? do |comment|
          comment["body"]&.match?(PLAN_PROPOSAL_PATTERN)
        end
      end

      # Extract the most recent plan data from comments
      def extract_plan_data(issue)
        return nil unless issue[:comments]

        # Find the most recent plan proposal comment
        plan_comment = issue[:comments].reverse.find do |comment|
          comment["body"]&.match?(PLAN_PROPOSAL_PATTERN)
        end

        return nil unless plan_comment

        body = plan_comment["body"]

        {
          summary: extract_section(body, "PLAN_SUMMARY"),
          tasks: extract_tasks(body),
          questions: extract_questions(body),
          comment_body: body,
          comment_hint: "## 🤖 AIDP Plan Proposal",
          comment_id: plan_comment["id"],
          posted_at: plan_comment["createdAt"] || Time.now.utc.iso8601
        }
      end

      # Check if detection comment was already posted for this label
      def detection_comment_posted?(item, label)
        return false unless item[:comments]

        item[:comments].any? do |comment|
          next unless comment["body"]

          match = comment["body"].match(DETECTION_PATTERN)
          match && match[1] == label
        end
      end

      # Check if review has been completed for a PR
      def review_completed?(pr)
        return false unless pr[:comments]

        pr[:comments].any? do |comment|
          comment["body"]&.match?(/🔍.*Review complete/i)
        end
      end

      # Check if CI fix has been completed for a PR
      def ci_fix_completed?(pr)
        return false unless pr[:comments]

        pr[:comments].any? do |comment|
          body = comment["body"]
          next false unless body

          body.include?("✅") && (
            body.match?(/CI fixes applied/i) ||
            (body.match?(/CI check/i) && body.match?(/passed/i))
          )
        end
      end

      # Check if change request has been processed for a PR
      def change_request_processed?(pr)
        return false unless pr[:comments]

        pr[:comments].any? do |comment|
          body = comment["body"]
          next false unless body

          body.include?("✅") && body.match?(/Change requests? (?:addressed|applied|complete)/i)
        end
      end

      private

      def has_label?(item, label_name)
        Array(item[:labels]).any? do |label|
          name = label.is_a?(Hash) ? label["name"] : label.to_s
          name.casecmp?(label_name)
        end
      end

      def extract_section(body, section_name)
        start_marker = "<!-- #{section_name}_START -->"
        end_marker = "<!-- #{section_name}_END -->"

        start_idx = body.index(start_marker)
        end_idx = body.index(end_marker)

        return nil unless start_idx && end_idx

        content = body[(start_idx + start_marker.length)...end_idx]

        # Remove markdown heading if present (e.g., "## Heading\n" or "### Heading\n")
        # Strip lines starting with ## or ### to avoid ReDoS
        content.lines.reject { |line| line.start_with?("##", "###") }.join.strip
      end

      def extract_tasks(body)
        tasks_section = extract_section(body, "PLAN_TASKS")
        return [] unless tasks_section

        # Extract markdown list items (- followed by space and content)
        tasks_section.scan(/^- (.+)$/).flatten
      end

      def extract_questions(body)
        questions_section = extract_section(body, "CLARIFYING_QUESTIONS")
        return [] unless questions_section

        # Extract numbered list items (number, dot, space, content)
        questions_section.scan(/^\d+\. (.+)$/).flatten
      end
    end
  end
end
