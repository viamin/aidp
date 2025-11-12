# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

require_relative "../message_display"
require_relative "reviewers/senior_dev_reviewer"
require_relative "reviewers/security_reviewer"
require_relative "reviewers/performance_reviewer"

module Aidp
  module Watch
    # Handles the aidp-review label trigger by performing multi-persona code review
    # and posting categorized findings back to the PR.
    class ReviewProcessor
      include Aidp::MessageDisplay

      # Default label names
      DEFAULT_REVIEW_LABEL = "aidp-review"

      COMMENT_HEADER = "## 🤖 AIDP Code Review"

      attr_reader :review_label

      def initialize(repository_client:, state_store:, provider_name: nil, project_dir: Dir.pwd, label_config: {}, verbose: false)
        @repository_client = repository_client
        @state_store = state_store
        @provider_name = provider_name
        @project_dir = project_dir
        @verbose = verbose

        # Load label configuration
        @review_label = label_config[:review_trigger] || label_config["review_trigger"] || DEFAULT_REVIEW_LABEL

        # Initialize reviewers
        @reviewers = [
          Reviewers::SeniorDevReviewer.new(provider_name: provider_name),
          Reviewers::SecurityReviewer.new(provider_name: provider_name),
          Reviewers::PerformanceReviewer.new(provider_name: provider_name)
        ]
      end

      def process(pr)
        number = pr[:number]

        if @state_store.review_processed?(number)
          display_message("ℹ️  Review for PR ##{number} already posted. Skipping.", type: :muted)
          return
        end

        display_message("🔍 Reviewing PR ##{number} (#{pr[:title]})", type: :info)

        # Fetch PR details
        pr_data = @repository_client.fetch_pull_request(number)
        files = @repository_client.fetch_pull_request_files(number)
        diff = @repository_client.fetch_pull_request_diff(number)

        # Run reviews in parallel (conceptually - actual implementation is sequential)
        review_results = run_reviews(pr_data: pr_data, files: files, diff: diff)

        # Log review results
        log_review(number, review_results)

        # Format and post comment
        comment_body = format_review_comment(pr: pr_data, review_results: review_results)
        @repository_client.post_comment(number, comment_body)

        display_message("💬 Posted review comment for PR ##{number}", type: :success)
        @state_store.record_review(number, {
          timestamp: Time.now.utc.iso8601,
          reviewers: review_results.map { |r| r[:persona] },
          total_findings: review_results.sum { |r| r[:findings].length }
        })

        # Remove review label after processing
        begin
          @repository_client.remove_labels(number, @review_label)
          display_message("🏷️  Removed '#{@review_label}' label after review", type: :info)
        rescue StandardError => e
          display_message("⚠️  Failed to remove review label: #{e.message}", type: :warn)
        end
      rescue => e
        display_message("❌ Review failed: #{e.message}", type: :error)
        Aidp.log_error("review_processor", "Review failed", pr: number, error: e.message, backtrace: e.backtrace&.first(10))

        # Post error comment
        error_comment = <<~COMMENT
          #{COMMENT_HEADER}

          ❌ Automated review failed: #{e.message}

          Please review manually or retry by re-adding the `#{@review_label}` label.
        COMMENT
        begin
          @repository_client.post_comment(number, error_comment)
        rescue StandardError
          nil
        end
      end

      private

      def run_reviews(pr_data:, files:, diff:)
        results = []

        @reviewers.each do |reviewer|
          display_message("  Running #{reviewer.persona_name} review...", type: :muted) if @verbose

          begin
            result = reviewer.review(pr_data: pr_data, files: files, diff: diff)
            results << result

            findings_count = result[:findings].length
            display_message("  ✓ #{reviewer.persona_name}: #{findings_count} findings", type: :muted) if @verbose
          rescue => e
            display_message("  ✗ #{reviewer.persona_name} failed: #{e.message}", type: :warn)
            Aidp.log_error("review_processor", "Reviewer failed", reviewer: reviewer.persona_name, error: e.message)
            # Continue with other reviewers
          end
        end

        results
      end

      def format_review_comment(pr:, review_results:)
        parts = []
        parts << COMMENT_HEADER
        parts << ""
        parts << "Automated multi-persona code review for PR ##{pr[:number]}"
        parts << ""

        # Collect all findings by severity
        all_findings = collect_findings_by_severity(review_results)

        if all_findings.empty?
          parts << "✅ **No issues found!** All reviewers approved the changes."
          parts << ""
          parts << "_The code looks good from architecture, security, and performance perspectives._"
        else
          parts << "### Summary"
          parts << ""
          parts << "| Severity | Count |"
          parts << "|----------|-------|"
          parts << "| 🔴 High Priority | #{all_findings[:high].length} |"
          parts << "| 🟠 Major | #{all_findings[:major].length} |"
          parts << "| 🟡 Minor | #{all_findings[:minor].length} |"
          parts << "| ⚪ Nit | #{all_findings[:nit].length} |"
          parts << ""

          # Add findings by severity
          if all_findings[:high].any?
            parts << "### 🔴 High Priority Issues"
            parts << ""
            parts << format_findings(all_findings[:high])
            parts << ""
          end

          if all_findings[:major].any?
            parts << "### 🟠 Major Issues"
            parts << ""
            parts << format_findings(all_findings[:major])
            parts << ""
          end

          if all_findings[:minor].any?
            parts << "### 🟡 Minor Improvements"
            parts << ""
            parts << format_findings(all_findings[:minor])
            parts << ""
          end

          if all_findings[:nit].any?
            parts << "<details>"
            parts << "<summary>⚪ Nit-picks (click to expand)</summary>"
            parts << ""
            parts << format_findings(all_findings[:nit])
            parts << ""
            parts << "</details>"
            parts << ""
          end
        end

        # Add reviewer attribution
        parts << "---"
        parts << "_Reviewed by: #{review_results.map { |r| r[:persona] }.join(", ")}_"

        parts.join("\n")
      end

      def collect_findings_by_severity(review_results)
        findings = {high: [], major: [], minor: [], nit: []}

        review_results.each do |result|
          persona = result[:persona]
          result[:findings].each do |finding|
            severity = finding["severity"]&.to_sym || :minor
            findings[severity] << finding.merge("reviewer" => persona)
          end
        end

        findings
      end

      def format_findings(findings)
        findings.map do |finding|
          parts = []

          # Header with category and reviewer
          header = "**#{finding["category"]}**"
          header += " (#{finding["reviewer"]})" if finding["reviewer"]
          parts << header

          # Location if available
          if finding["file"]
            location = "`#{finding["file"]}"
            location += ":#{finding["line"]}" if finding["line"]
            location += "`"
            parts << location
          end

          # Message
          parts << finding["message"]

          # Suggestion if available
          if finding["suggestion"]
            parts << ""
            parts << "<details>"
            parts << "<summary>💡 Suggested fix</summary>"
            parts << ""
            parts << "```suggestion"
            parts << finding["suggestion"]
            parts << "```"
            parts << "</details>"
          end

          parts.join("\n")
        end.join("\n\n")
      end

      def log_review(pr_number, review_results)
        log_dir = File.join(@project_dir, ".aidp", "logs", "pr_reviews")
        FileUtils.mkdir_p(log_dir)

        log_file = File.join(log_dir, "pr_#{pr_number}_#{Time.now.utc.strftime("%Y%m%d_%H%M%S")}.json")

        log_data = {
          pr_number: pr_number,
          timestamp: Time.now.utc.iso8601,
          reviews: review_results.map do |result|
            {
              persona: result[:persona],
              findings_count: result[:findings].length,
              findings: result[:findings]
            }
          end
        }

        File.write(log_file, JSON.pretty_generate(log_data))
        display_message("📝 Review log saved to #{log_file}", type: :muted) if @verbose
      rescue => e
        display_message("⚠️  Failed to save review log: #{e.message}", type: :warn)
      end
    end
  end
end
