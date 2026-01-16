# frozen_string_literal: true

module Aidp
  module Watch
    # Value object representing a work item in the round-robin queue.
    # Encapsulates issue/PR data with metadata needed for scheduling.
    class WorkItem
      include Comparable

      ITEM_TYPES = %i[issue pr].freeze
      PROCESSOR_TYPES = %i[plan build auto_issue review ci_fix auto_pr change_request].freeze

      # Priority levels for scheduling (lower = higher priority)
      PRIORITY_PLAN = 1
      PRIORITY_NORMAL = 2

      attr_reader :number, :item_type, :processor_type, :label, :data, :priority

      def initialize(number:, item_type:, processor_type:, label:, data:, priority: nil)
        validate_item_type!(item_type)
        validate_processor_type!(processor_type)

        @number = number
        @item_type = item_type
        @processor_type = processor_type
        @label = label
        @data = data
        @priority = priority || default_priority
      end

      # Unique key for this work item (used for queue tracking)
      # @return [String] Unique identifier
      def key
        "#{item_type}_#{number}_#{processor_type}"
      end

      # Check if this work item is for the same issue/PR
      # @param other [WorkItem] Other work item to compare
      # @return [Boolean] True if same entity
      def same_entity?(other)
        item_type == other.item_type && number == other.number
      end

      # Check if item is an issue (vs PR)
      # @return [Boolean]
      def issue?
        item_type == :issue
      end

      # Check if item is a PR
      # @return [Boolean]
      def pr?
        item_type == :pr
      end

      # Check if this is a high-priority plan item
      # @return [Boolean]
      def plan?
        processor_type == :plan
      end

      def to_h
        {
          number: number,
          item_type: item_type,
          processor_type: processor_type,
          label: label,
          priority: priority
        }
      end

      # Comparison for sorting by priority
      def <=>(other)
        priority <=> other.priority
      end

      private

      def default_priority
        plan? ? PRIORITY_PLAN : PRIORITY_NORMAL
      end

      def validate_item_type!(type)
        return if ITEM_TYPES.include?(type)

        raise ArgumentError, "Invalid item_type: #{type}. Must be one of: #{ITEM_TYPES.join(", ")}"
      end

      def validate_processor_type!(type)
        return if PROCESSOR_TYPES.include?(type)

        raise ArgumentError, "Invalid processor_type: #{type}. Must be one of: #{PROCESSOR_TYPES.join(", ")}"
      end
    end
  end
end
