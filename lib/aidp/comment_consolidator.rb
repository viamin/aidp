# frozen_string_literal: true

module Aidp
  # Consolidates comments for GitHub issues and PRs by category
  class CommentConsolidator
    CATEGORY_HEADERS = {
      progress: "## 🔄 Progress Report",
      exceptions: "## 🚨 Exceptions and Errors",
      completion: "## ✅ Completion Summary"
    }

    # @param repository_client [Aidp::Watch::RepositoryClient] GitHub repository client
    # @param number [Integer] Issue or PR number
    def initialize(repository_client:, number:)
      @client = repository_client
      @number = number
    end

    # Search for an existing comment by its category header
    # @param category [Symbol] Comment category (:progress, :exceptions, :completion)
    # @return [Hash, nil] Existing comment or nil if not found
    def find_category_comment(category)
      Aidp.log_debug("comment_consolidator", "searching_category_comment",
        number: @number, category: category)

      header = CATEGORY_HEADERS[category]
      raise ArgumentError, "Invalid category: #{category}" unless header

      comment = @client.find_comment(@number, header)
      Aidp.log_debug("comment_consolidator", "find_category_comment_result",
        found: !comment.nil?)
      comment
    end

    # Update an existing category comment or create a new one
    # @param category [Symbol] Comment category (:progress, :exceptions, :completion)
    # @param new_content [String] New content to add to the comment
    # @param append [Boolean] Whether to append or replace existing content
    # @return [String] Result of comment operation (comment ID or response body)
    def consolidate_comment(category:, new_content:, append: true)
      Aidp.log_debug("comment_consolidator", "consolidating_comment", number: @number, category: category, append: append)

      header = CATEGORY_HEADERS[category]
      raise ArgumentError, "Invalid category: #{category}" unless header

      existing_comment = find_category_comment(category)

      content = if existing_comment && append
        # Append new content with timestamp
        existing_body = existing_comment[:body]
        updated_body = if existing_body.include?(header)
          existing_body.lines.first(1).join +
            "### #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}\n\n" +
            new_content + "\n\n" +
            existing_body.lines[1..]&.join
        else
          # Reconstruct comment if header is missing
          "#{header}\n\n### #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}\n\n" +
            new_content + "\n\n" +
            existing_body
        end
        updated_body
      else
        # Create new or replace content
        "#{header}\n\n### #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}\n\n" + new_content
      end

      # Update or create comment
      if existing_comment
        Aidp.log_debug("comment_consolidator", "updating_existing_comment", comment_id: existing_comment[:id])
        @client.update_comment(existing_comment[:id], content)
      else
        Aidp.log_debug("comment_consolidator", "creating_new_comment")
        @client.post_comment(@number, content)
      end
    end
  end
end
