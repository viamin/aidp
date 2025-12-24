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

      def plan_iteration_count(issue_number)
        plan = plans[issue_number.to_s]
        return 0 unless plan
        plan["iteration"] || 1
      end

      def record_plan(issue_number, data)
        existing_plan = plans[issue_number.to_s]
        iteration = existing_plan ? (existing_plan["iteration"] || 1) + 1 : 1

        payload = {
          "summary" => data[:summary],
          "tasks" => data[:tasks],
          "questions" => data[:questions],
          "comment_body" => data[:comment_body],
          "comment_hint" => data[:comment_hint],
          "comment_id" => data[:comment_id],
          "posted_at" => data[:posted_at] || Time.now.utc.iso8601,
          "iteration" => iteration,
          "previous_iteration_at" => existing_plan ? existing_plan["posted_at"] : nil
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

      # Retrieve workstream metadata for a given issue
      # @return [Hash, nil] {issue_number:, branch:, workstream:, pr_url:, status:}
      def workstream_for_issue(issue_number)
        data = build_status(issue_number)
        return nil if data.nil? || data.empty?

        {
          issue_number: issue_number.to_i,
          branch: data["branch"],
          workstream: data["workstream"],
          pr_url: data["pr_url"],
          status: data["status"]
        }
      end

      # Find the build/workstream metadata associated with a PR URL
      # This is used to map change-request PRs back to their originating issues/worktrees.
      # @return [Hash, nil] {issue_number:, branch:, workstream:, pr_url:, status:}
      def find_build_by_pr(pr_number)
        builds.each do |issue_number, data|
          pr_url = data["pr_url"]
          next unless pr_url

          if pr_url.match?(%r{/pull/#{pr_number}\b})
            return {
              issue_number: issue_number.to_i,
              branch: data["branch"],
              workstream: data["workstream"],
              pr_url: pr_url,
              status: data["status"]
            }
          end
        end

        nil
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
          "clarification_count" => data[:clarification_count],
          "verification_reasons" => data[:verification_reasons],
          "missing_items" => data[:missing_items],
          "additional_work" => data[:additional_work]
        }.compact

        change_requests[pr_number.to_s] = payload
        save!
      end

      def reset_change_request_state(pr_number)
        change_requests.delete(pr_number.to_s)
        save!
      end

      # Detection comment tracking methods (issue #280)
      def detection_comment_posted?(detection_key)
        detection_comments.key?(detection_key.to_s)
      end

      def record_detection_comment(detection_key, timestamp:)
        detection_comments[detection_key.to_s] = {
          "timestamp" => timestamp,
          "posted_at" => Time.now.utc.iso8601
        }
        save!
      end

      # Feedback tracking methods - track comments for reaction-based evaluations

      # Get all tracked comments with their metadata for feedback collection
      # @return [Array<Hash>] List of comment info hashes
      def tracked_comments
        comments = []

        # Collect from plans
        plans.each do |issue_number, data|
          next unless data["comment_id"]
          comments << {
            comment_id: data["comment_id"],
            processor_type: "plan",
            number: issue_number.to_i,
            posted_at: data["posted_at"]
          }
        end

        # Collect from reviews (if they store comment_id)
        reviews.each do |pr_number, data|
          next unless data["comment_id"]
          comments << {
            comment_id: data["comment_id"],
            processor_type: "review",
            number: pr_number.to_i,
            posted_at: data["timestamp"]
          }
        end

        # Collect from builds (if they store comment_id)
        builds.each do |issue_number, data|
          next unless data["comment_id"]
          comments << {
            comment_id: data["comment_id"],
            processor_type: "build",
            number: issue_number.to_i,
            posted_at: data["updated_at"]
          }
        end

        # Collect from feedback_comments (explicitly tracked)
        feedback_comments.each do |key, data|
          comments << {
            comment_id: data["comment_id"],
            processor_type: data["processor_type"],
            number: data["number"].to_i,
            posted_at: data["posted_at"]
          }
        end

        comments
      end

      # Track a comment for feedback collection
      # @param comment_id [Integer, String] GitHub comment ID
      # @param processor_type [String] Type of processor (plan, review, build, etc.)
      # @param number [Integer] Issue or PR number
      def track_comment_for_feedback(comment_id:, processor_type:, number:)
        key = "#{processor_type}_#{number}"
        feedback_comments[key] = {
          "comment_id" => comment_id.to_s,
          "processor_type" => processor_type,
          "number" => number,
          "posted_at" => Time.now.utc.iso8601
        }
        save!
      end

      # Get IDs of reactions already processed for a comment
      # @param comment_id [Integer, String] GitHub comment ID
      # @return [Array<Integer>] List of processed reaction IDs
      def processed_reaction_ids(comment_id)
        data = processed_reactions[comment_id.to_s]
        return [] unless data
        data["reaction_ids"] || []
      end

      # Mark a reaction as processed
      # @param comment_id [Integer, String] GitHub comment ID
      # @param reaction_id [Integer] GitHub reaction ID
      def mark_reaction_processed(comment_id, reaction_id)
        key = comment_id.to_s
        processed_reactions[key] ||= {"reaction_ids" => [], "last_checked" => nil}
        processed_reactions[key]["reaction_ids"] << reaction_id unless processed_reactions[key]["reaction_ids"].include?(reaction_id)
        processed_reactions[key]["last_checked"] = Time.now.utc.iso8601
        save!
      end

      # Auto PR tracking methods - for aidp-auto label on PRs
      # Tracks iteration counts to enforce iteration cap

      # Get the current iteration count for an auto PR
      # @param pr_number [Integer] PR number
      # @return [Integer] Current iteration count (0 if not tracked)
      def auto_pr_iteration_count(pr_number)
        data = auto_prs[pr_number.to_s]
        return 0 unless data
        data["iteration"] || 0
      end

      # Get full auto PR data
      # @param pr_number [Integer] PR number
      # @return [Hash, nil] Auto PR tracking data
      def auto_pr_data(pr_number)
        auto_prs[pr_number.to_s]
      end

      # Record an auto PR iteration
      # @param pr_number [Integer] PR number
      # @param data [Hash] Additional data to store
      # @return [Integer] New iteration count
      def record_auto_pr_iteration(pr_number, data = {})
        key = pr_number.to_s
        existing = auto_prs[key] || {}
        iteration = (existing["iteration"] || 0) + 1

        auto_prs[key] = {
          "iteration" => iteration,
          "last_processed_at" => Time.now.utc.iso8601,
          "status" => data[:status] || "in_progress",
          "metadata" => stringify_keys(data[:metadata] || {})
        }.merge(stringify_keys(data.except(:status, :metadata)))

        save!
        iteration
      end

      # Mark an auto PR as completed (ready for human review)
      # @param pr_number [Integer] PR number
      # @param data [Hash] Additional completion data
      def complete_auto_pr(pr_number, data = {})
        key = pr_number.to_s
        existing = auto_prs[key] || {}

        auto_prs[key] = existing.merge({
          "status" => "completed",
          "completed_at" => Time.now.utc.iso8601
        }).merge(stringify_keys(data))

        save!
      end

      # Check if an auto PR has reached the iteration cap
      # @param pr_number [Integer] PR number
      # @param cap [Integer] Maximum iterations allowed
      # @return [Boolean] True if cap reached
      def auto_pr_cap_reached?(pr_number, cap:)
        auto_pr_iteration_count(pr_number) >= cap
      end

      # Project tracking methods
      def project_item_id(issue_number)
        projects[issue_number.to_s]&.dig("item_id")
      end

      def record_project_item_id(issue_number, item_id)
        projects[issue_number.to_s] ||= {}
        projects[issue_number.to_s]["item_id"] = item_id
        projects[issue_number.to_s]["synced_at"] = Time.now.utc.iso8601
        save!
      end

      def project_sync_data(issue_number)
        projects[issue_number.to_s] || {}
      end

      def record_project_sync(issue_number, data)
        projects[issue_number.to_s] ||= {}
        projects[issue_number.to_s].merge!(stringify_keys(data))
        projects[issue_number.to_s]["synced_at"] = Time.now.utc.iso8601
        save!
      end

      # Sub-issue tracking methods
      def sub_issues(parent_number)
        hierarchies[parent_number.to_s]&.dig("sub_issues") || []
      end

      def parent_issue(sub_issue_number)
        hierarchies[sub_issue_number.to_s]&.dig("parent")
      end

      def record_sub_issues(parent_number, sub_issue_numbers)
        hierarchies[parent_number.to_s] ||= {}
        hierarchies[parent_number.to_s]["sub_issues"] = Array(sub_issue_numbers)
        hierarchies[parent_number.to_s]["created_at"] = Time.now.utc.iso8601

        # Also record reverse mapping
        sub_issue_numbers.each do |sub_number|
          hierarchies[sub_number.to_s] ||= {}
          hierarchies[sub_number.to_s]["parent"] = parent_number
        end

        save!
      end

      def blocking_status(issue_number)
        # Check if this issue is blocked by any open sub-issues
        sub_issue_numbers = sub_issues(issue_number)
        return {blocked: false, blockers: []} if sub_issue_numbers.empty?

        {
          blocked: true,
          blockers: sub_issue_numbers,
          blocker_count: sub_issue_numbers.size
        }
      end

      # Worktree cleanup tracking methods (issue #367)

      # Get the timestamp of last worktree cleanup
      # @return [Time, nil] Time of last cleanup or nil if never run
      def last_worktree_cleanup
        timestamp = worktree_cleanup_state["last_cleanup_at"]
        return nil unless timestamp

        Time.parse(timestamp)
      rescue ArgumentError
        nil
      end

      # Record a worktree cleanup run
      # @param cleaned [Integer] Number of worktrees cleaned
      # @param skipped [Integer] Number of worktrees skipped
      # @param errors [Array<Hash>] List of errors encountered
      def record_worktree_cleanup(cleaned:, skipped:, errors: [])
        state["worktree_cleanup"] = {
          "last_cleanup_at" => Time.now.utc.iso8601,
          "last_cleaned_count" => cleaned,
          "last_skipped_count" => skipped,
          "last_errors" => errors.map { |e| stringify_keys(e) }
        }
        save!
      end

      # Get the full worktree cleanup state
      # @return [Hash] Cleanup state data
      def worktree_cleanup_data
        worktree_cleanup_state.dup
      end

      private

      def worktree_cleanup_state
        state["worktree_cleanup"] ||= {}
      end

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
          base["detection_comments"] ||= {}
          base["feedback_comments"] ||= {}
          base["processed_reactions"] ||= {}
          base["auto_prs"] ||= {}
          base["projects"] ||= {}
          base["hierarchies"] ||= {}
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

      def detection_comments
        state["detection_comments"]
      end

      def feedback_comments
        state["feedback_comments"]
      end

      def processed_reactions
        state["processed_reactions"]
      end

      def auto_prs
        state["auto_prs"]
      end

      def projects
        state["projects"]
      end

      def hierarchies
        state["hierarchies"]
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
