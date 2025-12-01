# frozen_string_literal: true

require "securerandom"

module Aidp
  module Evaluations
    # Represents a single evaluation record
    #
    # An evaluation captures user feedback (good/neutral/bad) for AIDP outputs
    # such as prompts, work units, or full work loops, along with rich context.
    #
    # @example Creating an evaluation
    #   record = EvaluationRecord.new(
    #     rating: "good",
    #     comment: "Generated code was clean and well-structured",
    #     target_type: "work_unit",
    #     target_id: "01_INIT"
    #   )
    class EvaluationRecord
      VALID_RATINGS = %w[good neutral bad].freeze
      VALID_TARGET_TYPES = %w[prompt work_unit work_loop step plan review build ci_fix change_request].freeze

      attr_reader :id, :rating, :comment, :target_type, :target_id,
        :context, :created_at

      def initialize(rating:, comment: nil, target_type: nil, target_id: nil, context: {}, id: nil, created_at: nil)
        @id = id || generate_id
        @rating = validate_rating(rating)
        @comment = comment
        @target_type = validate_target_type(target_type)
        @target_id = target_id
        @context = context || {}
        @created_at = created_at || Time.now.iso8601

        Aidp.log_debug("evaluation_record", "create",
          id: @id, rating: @rating, target_type: @target_type, target_id: @target_id)
      end

      # Convert to hash for storage
      def to_h
        {
          id: @id,
          rating: @rating,
          comment: @comment,
          target_type: @target_type,
          target_id: @target_id,
          context: @context,
          created_at: @created_at
        }
      end

      # Create record from stored hash
      def self.from_h(hash)
        hash = symbolize_keys(hash)
        new(
          id: hash[:id],
          rating: hash[:rating],
          comment: hash[:comment],
          target_type: hash[:target_type],
          target_id: hash[:target_id],
          context: hash[:context] || {},
          created_at: hash[:created_at]
        )
      end

      # Check if rating is positive
      def good?
        @rating == "good"
      end

      # Check if rating is negative
      def bad?
        @rating == "bad"
      end

      # Check if rating is neutral
      def neutral?
        @rating == "neutral"
      end

      private

      def generate_id
        "eval_#{Time.now.strftime("%Y%m%d_%H%M%S")}_#{SecureRandom.hex(4)}"
      end

      def validate_rating(rating)
        rating_str = rating.to_s.downcase
        unless VALID_RATINGS.include?(rating_str)
          raise ArgumentError, "Invalid rating '#{rating}'. Must be one of: #{VALID_RATINGS.join(", ")}"
        end
        rating_str
      end

      def validate_target_type(target_type)
        return nil if target_type.nil?
        type_str = target_type.to_s.downcase
        unless VALID_TARGET_TYPES.include?(type_str)
          raise ArgumentError, "Invalid target_type '#{target_type}'. Must be one of: #{VALID_TARGET_TYPES.join(", ")}"
        end
        type_str
      end

      class << self
        private

        def symbolize_keys(hash)
          return hash unless hash.is_a?(Hash)
          hash.transform_keys { |k| k.is_a?(String) ? k.to_sym : k }
        end
      end
    end
  end
end
