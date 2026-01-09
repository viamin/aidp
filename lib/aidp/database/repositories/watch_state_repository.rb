# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      # Repository for watch_state table
      # Replaces watch/*.yml files
      # Stores all watch mode state in a single JSON blob per repository
      class WatchStateRepository < Repository
        def initialize(project_dir: Dir.pwd, repository: nil)
          super(project_dir: project_dir, table_name: "watch_state")
          @repository = repository
        end

        attr_reader :repository

        # Get or create state for repository
        #
        # @return [Hash] State data
        def state
          @state ||= load_or_create_state
        end

        # Plan tracking methods

        def plan_processed?(issue_number)
          plans.key?(issue_number.to_s)
        end

        def plan_data(issue_number)
          plans[issue_number.to_s]
        end

        def plan_iteration_count(issue_number)
          plan = plans[issue_number.to_s]
          return 0 unless plan
          plan[:iteration] || 1
        end

        def record_plan(issue_number, data)
          existing_plan = plans[issue_number.to_s]
          iteration = existing_plan ? (existing_plan[:iteration] || 1) + 1 : 1

          plans[issue_number.to_s] = {
            summary: data[:summary],
            tasks: data[:tasks],
            questions: data[:questions],
            comment_body: data[:comment_body],
            comment_hint: data[:comment_hint],
            comment_id: data[:comment_id],
            posted_at: data[:posted_at] || current_timestamp,
            iteration: iteration,
            previous_iteration_at: existing_plan&.dig(:posted_at)
          }.compact

          save!
        end

        # Build tracking methods

        def build_status(issue_number)
          builds[issue_number.to_s] || {}
        end

        def record_build_status(issue_number, status:, details: {})
          builds[issue_number.to_s] = {
            status: status,
            updated_at: current_timestamp
          }.merge(symbolize_keys(details))

          save!
        end

        def workstream_for_issue(issue_number)
          data = build_status(issue_number)
          return nil if data.nil? || data.empty?

          {
            issue_number: issue_number.to_i,
            branch: data[:branch],
            workstream: data[:workstream],
            pr_url: data[:pr_url],
            status: data[:status]
          }
        end

        def find_build_by_pr(pr_number)
          builds.each do |issue_number, data|
            pr_url = data[:pr_url]
            next unless pr_url

            if pr_url.match?(%r{/pull/#{pr_number}\b})
              return {
                issue_number: issue_number.to_i,
                branch: data[:branch],
                workstream: data[:workstream],
                pr_url: pr_url,
                status: data[:status]
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
          reviews[pr_number.to_s] = {
            timestamp: data[:timestamp] || current_timestamp,
            reviewers: data[:reviewers],
            total_findings: data[:total_findings],
            comment_id: data[:comment_id]
          }.compact

          save!
        end

        # CI fix tracking methods

        def ci_fix_completed?(pr_number)
          fix_data = ci_fixes[pr_number.to_s]
          fix_data && fix_data[:status] == "completed"
        end

        def ci_fix_data(pr_number)
          ci_fixes[pr_number.to_s]
        end

        def record_ci_fix(pr_number, data)
          ci_fixes[pr_number.to_s] = {
            status: data[:status],
            timestamp: data[:timestamp] || current_timestamp,
            reason: data[:reason],
            root_causes: data[:root_causes],
            fixes_count: data[:fixes_count]
          }.compact

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
          change_requests[pr_number.to_s] = {
            status: data[:status],
            timestamp: data[:timestamp] || current_timestamp,
            changes_applied: data[:changes_applied],
            commits: data[:commits],
            reason: data[:reason],
            clarification_count: data[:clarification_count],
            verification_reasons: data[:verification_reasons],
            missing_items: data[:missing_items],
            additional_work: data[:additional_work]
          }.compact

          save!
        end

        def reset_change_request_state(pr_number)
          change_requests.delete(pr_number.to_s)
          save!
        end

        # Auto PR tracking methods

        def auto_pr_iteration_count(pr_number)
          data = auto_prs[pr_number.to_s]
          return 0 unless data
          data[:iteration] || 0
        end

        def auto_pr_data(pr_number)
          auto_prs[pr_number.to_s]
        end

        def record_auto_pr_iteration(pr_number, data = {})
          key = pr_number.to_s
          existing = auto_prs[key] || {}
          iteration = (existing[:iteration] || 0) + 1

          auto_prs[key] = {
            iteration: iteration,
            last_processed_at: current_timestamp,
            status: data[:status] || "in_progress",
            metadata: symbolize_keys(data[:metadata] || {})
          }.merge(symbolize_keys(data.except(:status, :metadata)))

          save!
          iteration
        end

        def complete_auto_pr(pr_number, data = {})
          key = pr_number.to_s
          existing = auto_prs[key] || {}

          auto_prs[key] = existing.merge({
            status: "completed",
            completed_at: current_timestamp
          }).merge(symbolize_keys(data))

          save!
        end

        def auto_pr_cap_reached?(pr_number, cap:)
          auto_pr_iteration_count(pr_number) >= cap
        end

        # Detection comment tracking

        def detection_comment_posted?(detection_key)
          detection_comments.key?(detection_key.to_s)
        end

        def record_detection_comment(detection_key, timestamp:)
          detection_comments[detection_key.to_s] = {
            timestamp: timestamp,
            posted_at: current_timestamp
          }
          save!
        end

        # Feedback tracking

        def tracked_comments
          comments = []

          plans.each do |issue_number, data|
            next unless data[:comment_id]
            comments << {
              comment_id: data[:comment_id],
              processor_type: "plan",
              number: issue_number.to_i,
              posted_at: data[:posted_at]
            }
          end

          reviews.each do |pr_number, data|
            next unless data[:comment_id]
            comments << {
              comment_id: data[:comment_id],
              processor_type: "review",
              number: pr_number.to_i,
              posted_at: data[:timestamp]
            }
          end

          builds.each do |issue_number, data|
            next unless data[:comment_id]
            comments << {
              comment_id: data[:comment_id],
              processor_type: "build",
              number: issue_number.to_i,
              posted_at: data[:updated_at]
            }
          end

          feedback_comments.each do |_key, data|
            comments << {
              comment_id: data[:comment_id],
              processor_type: data[:processor_type],
              number: data[:number].to_i,
              posted_at: data[:posted_at]
            }
          end

          comments
        end

        def track_comment_for_feedback(comment_id:, processor_type:, number:)
          key = "#{processor_type}_#{number}"
          feedback_comments[key] = {
            comment_id: comment_id.to_s,
            processor_type: processor_type,
            number: number,
            posted_at: current_timestamp
          }
          save!
        end

        def processed_reaction_ids(comment_id)
          data = processed_reactions[comment_id.to_s]
          return [] unless data
          data[:reaction_ids] || []
        end

        def mark_reaction_processed(comment_id, reaction_id)
          key = comment_id.to_s
          processed_reactions[key] ||= {reaction_ids: [], last_checked: nil}
          processed_reactions[key][:reaction_ids] << reaction_id unless processed_reactions[key][:reaction_ids].include?(reaction_id)
          processed_reactions[key][:last_checked] = current_timestamp
          save!
        end

        private

        def load_or_create_state
          row = query_one(
            "SELECT * FROM watch_state WHERE project_dir = ? AND repository = ?",
            [project_dir, repository]
          )

          if row
            {
              id: row["id"],
              plans: deserialize_json(row["plans"]) || {},
              builds: deserialize_json(row["builds"]) || {},
              reviews: deserialize_json(row["reviews"]) || {},
              ci_fixes: deserialize_json(row["ci_fixes"]) || {},
              change_requests: deserialize_json(row["change_requests"]) || {},
              detection_comments: deserialize_json(row["detection_comments"]) || {},
              feedback_comments: deserialize_json(row["feedback_comments"]) || {},
              processed_reactions: deserialize_json(row["processed_reactions"]) || {},
              auto_prs: deserialize_json(row["auto_prs"]) || {},
              metadata: deserialize_json(row["metadata"]) || {}
            }
          else
            {
              plans: {},
              builds: {},
              reviews: {},
              ci_fixes: {},
              change_requests: {},
              detection_comments: {},
              feedback_comments: {},
              processed_reactions: {},
              auto_prs: {},
              metadata: {}
            }
          end
        end

        def save!
          now = current_timestamp

          existing = query_one(
            "SELECT id FROM watch_state WHERE project_dir = ? AND repository = ?",
            [project_dir, repository]
          )

          if existing
            execute(
              <<~SQL,
                UPDATE watch_state SET
                  plans = ?,
                  builds = ?,
                  reviews = ?,
                  ci_fixes = ?,
                  change_requests = ?,
                  detection_comments = ?,
                  feedback_comments = ?,
                  processed_reactions = ?,
                  auto_prs = ?,
                  metadata = ?,
                  last_poll_at = ?,
                  updated_at = ?
                WHERE project_dir = ? AND repository = ?
              SQL
              [
                serialize_json(plans),
                serialize_json(builds),
                serialize_json(reviews),
                serialize_json(ci_fixes),
                serialize_json(change_requests),
                serialize_json(detection_comments),
                serialize_json(feedback_comments),
                serialize_json(processed_reactions),
                serialize_json(auto_prs),
                serialize_json(state[:metadata]),
                now,
                now,
                project_dir,
                repository
              ]
            )
          else
            execute(
              insert_sql([
                :project_dir, :repository, :plans, :builds, :reviews,
                :ci_fixes, :change_requests, :detection_comments,
                :feedback_comments, :processed_reactions, :auto_prs,
                :metadata, :last_poll_at, :created_at, :updated_at
              ]),
              [
                project_dir,
                repository,
                serialize_json(plans),
                serialize_json(builds),
                serialize_json(reviews),
                serialize_json(ci_fixes),
                serialize_json(change_requests),
                serialize_json(detection_comments),
                serialize_json(feedback_comments),
                serialize_json(processed_reactions),
                serialize_json(auto_prs),
                serialize_json(state[:metadata]),
                now,
                now,
                now
              ]
            )
            @state[:id] = last_insert_row_id
          end

          Aidp.log_debug("watch_state_repository", "saved", repository: repository)
        end

        def plans
          state[:plans]
        end

        def builds
          state[:builds]
        end

        def reviews
          state[:reviews]
        end

        def ci_fixes
          state[:ci_fixes]
        end

        def change_requests
          state[:change_requests]
        end

        def detection_comments
          state[:detection_comments]
        end

        def feedback_comments
          state[:feedback_comments]
        end

        def processed_reactions
          state[:processed_reactions]
        end

        def auto_prs
          state[:auto_prs]
        end

        def symbolize_keys(hash)
          return {} unless hash

          hash.each_with_object({}) do |(key, value), memo|
            memo[key.to_sym] = value
          end
        end
      end
    end
  end
end
