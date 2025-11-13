# frozen_string_literal: true

require "yaml"
require "fileutils"
require "time"

module Aidp
  module Watch
    # Persists watch mode progress for each repository/issue pair. Used to
    # avoid re-processing plan/build triggers and to retain generated plan
    # context between runs.
    class StateStore
      attr_reader :path

      def initialize(project_dir:, repository:)
        @project_dir = project_dir
        @repository = repository
        @path = File.join(project_dir, ".aidp", "watch", "#{sanitize_repository(repository)}.yml")
        ensure_directory
      end

      def plan_processed?(issue_number)
        plans.key?(issue_number.to_s)
      end

      def plan_data(issue_number)
        plans[issue_number.to_s]
      end

      def record_plan(issue_number, data)
        payload = {
          "summary" => data[:summary],
          "tasks" => data[:tasks],
          "questions" => data[:questions],
          "comment_body" => data[:comment_body],
          "comment_hint" => data[:comment_hint],
          "posted_at" => data[:posted_at] || Time.now.utc.iso8601
        }.compact

        plans[issue_number.to_s] = payload
        save!
      end

      def build_status(issue_number)
        builds[issue_number.to_s] || {}
      end

      def record_build_status(issue_number, status:, details: {})
        builds[issue_number.to_s] = {
          "status" => status,
          "updated_at" => Time.now.utc.iso8601
        }.merge(stringify_keys(details))
        save!
      end

      # Review tracking methods
      def review_processed?(pr_number)
        reviews.key?(pr_number.to_s)
      end

      def review_data(pr_number)
        reviews[pr_number.to_s]
      end

      def record_review(pr_number, data)
        payload = {
          "timestamp" => data[:timestamp] || Time.now.utc.iso8601,
          "reviewers" => data[:reviewers],
          "total_findings" => data[:total_findings]
        }.compact

        reviews[pr_number.to_s] = payload
        save!
      end

      # CI fix tracking methods
      def ci_fix_completed?(pr_number)
        fix_data = ci_fixes[pr_number.to_s]
        fix_data && fix_data["status"] == "completed"
      end

      def ci_fix_data(pr_number)
        ci_fixes[pr_number.to_s]
      end

      def record_ci_fix(pr_number, data)
        payload = {
          "status" => data[:status],
          "timestamp" => data[:timestamp] || Time.now.utc.iso8601,
          "reason" => data[:reason],
          "root_causes" => data[:root_causes],
          "fixes_count" => data[:fixes_count]
        }.compact

        ci_fixes[pr_number.to_s] = payload
        save!
      end

      # Change request tracking methods
      def change_request_processed?(pr_number)
        change_requests.key?(pr_number.to_s)
      end

      def change_request_data(pr_number)
        change_requests[pr_number.to_s]
      end

      def record_change_request(pr_number, data)
        payload = {
          "status" => data[:status],
          "timestamp" => data[:timestamp] || Time.now.utc.iso8601,
          "changes_applied" => data[:changes_applied],
          "commits" => data[:commits],
          "reason" => data[:reason],
          "clarification_count" => data[:clarification_count]
        }.compact

        change_requests[pr_number.to_s] = payload
        save!
      end

      def reset_change_request_state(pr_number)
        change_requests.delete(pr_number.to_s)
        save!
      end

      private

      def ensure_directory
        FileUtils.mkdir_p(File.dirname(@path))
      end

      def sanitize_repository(repository)
        repository.tr("/", "_")
      end

      def load_state
        @state ||= if File.exist?(@path)
          YAML.safe_load_file(@path, permitted_classes: [Time]) || {}
        else
          {}
        end
      end

      def save!
        File.write(@path, YAML.dump(state))
      end

      def state
        @state = nil if @state && !@state.is_a?(Hash)
        @state ||= begin
          base = load_state
          base["plans"] ||= {}
          base["builds"] ||= {}
          base["reviews"] ||= {}
          base["ci_fixes"] ||= {}
          base["change_requests"] ||= {}
          base
        end
      end

      def plans
        state["plans"]
      end

      def builds
        state["builds"]
      end

      def reviews
        state["reviews"]
      end

      def ci_fixes
        state["ci_fixes"]
      end

      def change_requests
        state["change_requests"]
      end

      def stringify_keys(hash)
        return {} unless hash

        hash.each_with_object({}) do |(key, value), memo|
          memo[key.to_s] = value
        end
      end
    end
  end
end
