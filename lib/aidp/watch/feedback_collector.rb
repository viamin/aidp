# frozen_string_literal: true

require_relative "../evaluations"

module Aidp
  module Watch
    # Collects user feedback via GitHub reactions and converts to evaluations
    #
    # Monitors reactions on AIDP-posted comments:
    # - 👍 (+1) = good rating
    # - 👎 (-1) = bad rating
    # - 😕 (confused) = neutral rating
    #
    # @example
    #   collector = FeedbackCollector.new(
    #     repository_client: client,
    #     state_store: store,
    #     project_dir: Dir.pwd
    #   )
    #   collector.collect_feedback
    class FeedbackCollector
      # Mapping from GitHub reaction content to evaluation rating
      REACTION_RATINGS = {
        "+1" => "good",
        "-1" => "bad",
        "confused" => "neutral",
        "heart" => "good",
        "hooray" => "good",
        "rocket" => "good",
        "eyes" => "neutral"
      }.freeze

      # Feedback prompt text to include in comments
      FEEDBACK_PROMPT = <<~PROMPT.strip
        ---
        **Rate this output**: React with 👍 (good), 👎 (bad), or 😕 (neutral) to help improve AIDP.
      PROMPT

      def initialize(repository_client:, state_store:, project_dir: Dir.pwd)
        @repository_client = repository_client
        @state_store = state_store
        @project_dir = project_dir
        @evaluation_storage = Evaluations::EvaluationStorage.new(project_dir: project_dir)

        Aidp.log_debug("feedback_collector", "initialize",
          repo: repository_client.full_repo, project_dir: project_dir)
      end

      # Collect feedback from all tracked comments
      #
      # @return [Array<Hash>] List of new evaluations recorded
      def collect_feedback
        Aidp.log_debug("feedback_collector", "collect_feedback_start")

        tracked_comments = @state_store.tracked_comments
        return [] if tracked_comments.empty?

        new_evaluations = []

        tracked_comments.each do |comment_info|
          evaluations = process_comment_reactions(comment_info)
          new_evaluations.concat(evaluations)
        end

        Aidp.log_debug("feedback_collector", "collect_feedback_complete",
          tracked_count: tracked_comments.size, new_evaluations: new_evaluations.size)

        new_evaluations
      end

      # Process reactions on a specific comment and create evaluations
      #
      # @param comment_info [Hash] Comment tracking info from state store
      # @return [Array<Hash>] New evaluations created
      def process_comment_reactions(comment_info)
        comment_id = comment_info[:comment_id] || comment_info["comment_id"]
        return [] unless comment_id

        processor_type = comment_info[:processor_type] || comment_info["processor_type"]
        target_number = comment_info[:number] || comment_info["number"]

        Aidp.log_debug("feedback_collector", "process_comment",
          comment_id: comment_id, processor_type: processor_type, number: target_number)

        # Fetch reactions from GitHub
        reactions = @repository_client.fetch_comment_reactions(comment_id)
        return [] if reactions.empty?

        # Get already-processed reaction IDs
        processed_ids = @state_store.processed_reaction_ids(comment_id)

        new_evaluations = []

        reactions.each do |reaction|
          reaction_id = reaction[:id]
          next if processed_ids.include?(reaction_id)

          rating = reaction_to_rating(reaction[:content])
          next unless rating

          # Create evaluation record
          evaluation = create_evaluation(
            rating: rating,
            processor_type: processor_type,
            target_number: target_number,
            reaction: reaction
          )

          if evaluation
            new_evaluations << evaluation
            @state_store.mark_reaction_processed(comment_id, reaction_id)
          end
        end

        new_evaluations
      end

      # Convert GitHub reaction content to evaluation rating
      #
      # @param content [String] GitHub reaction content (e.g., "+1", "-1", "confused")
      # @return [String, nil] Rating or nil if not mappable
      def reaction_to_rating(content)
        REACTION_RATINGS[content]
      end

      # Append feedback prompt to a comment body
      #
      # @param body [String] Original comment body
      # @return [String] Comment body with feedback prompt
      def self.append_feedback_prompt(body)
        "#{body}\n\n#{FEEDBACK_PROMPT}"
      end

      private

      def create_evaluation(rating:, processor_type:, target_number:, reaction:)
        repo = @repository_client.full_repo

        context = {
          watch: {
            repo: repo,
            number: target_number,
            processor_type: processor_type
          },
          feedback_source: "github_reaction",
          reaction: {
            content: reaction[:content],
            user: reaction[:user],
            created_at: reaction[:created_at]
          },
          environment: {
            aidp_version: defined?(Aidp::VERSION) ? Aidp::VERSION : nil
          },
          timestamp: Time.now.iso8601
        }

        record = Evaluations::EvaluationRecord.new(
          rating: rating,
          comment: "Feedback via GitHub reaction (#{reaction[:content]}) by #{reaction[:user]}",
          target_type: processor_type,
          target_id: "#{repo}##{target_number}",
          context: context
        )

        result = @evaluation_storage.store(record)

        if result[:success]
          Aidp.log_info("feedback_collector", "evaluation_recorded",
            id: record.id, rating: rating, user: reaction[:user],
            processor_type: processor_type, target: "#{repo}##{target_number}")

          {
            id: record.id,
            rating: rating,
            user: reaction[:user],
            processor_type: processor_type,
            target: "#{repo}##{target_number}"
          }
        else
          Aidp.log_error("feedback_collector", "evaluation_store_failed",
            error: result[:error], reaction_id: reaction[:id])
          nil
        end
      rescue => e
        Aidp.log_error("feedback_collector", "create_evaluation_failed",
          error: e.message, reaction: reaction)
        nil
      end
    end
  end
end
