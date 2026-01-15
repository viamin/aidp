# frozen_string_literal: true

require_relative "work_item"

module Aidp
  module Watch
    # Schedules work items using a round-robin strategy across all tagged
    # issues and PRs. Processes one iteration per work item before rotating
    # to the next, ensuring fair distribution of attention.
    #
    # Priority handling:
    # - aidp-plan items receive higher priority in rotation
    # - Within the same priority, items are processed in queue order
    #
    # Paused items (aidp-needs-input label) are skipped during their turn
    # but remain in the queue for later processing.
    class RoundRobinScheduler
      attr_reader :queue, :last_processed_key

      def initialize(state_store:)
        @state_store = state_store
        @queue = []
        @last_processed_key = state_store.round_robin_last_key

        Aidp.log_debug("round_robin_scheduler", "initialized",
          last_key: @last_processed_key)
      end

      # Refresh the queue with current work items from GitHub.
      # Maintains position in rotation when possible.
      #
      # @param work_items [Array<WorkItem>] Current work items from all processors
      def refresh_queue(work_items)
        Aidp.log_debug("round_robin_scheduler", "refresh_queue.start",
          incoming_count: work_items.size,
          current_queue_size: @queue.size)

        # Group by priority and sort within groups
        prioritized = work_items.group_by(&:priority)
        sorted_items = []

        prioritized.keys.sort.each do |priority|
          sorted_items.concat(prioritized[priority])
        end

        @queue = sorted_items

        Aidp.log_debug("round_robin_scheduler", "refresh_queue.complete",
          queue_size: @queue.size,
          priorities: prioritized.keys.sort)
      end

      # Get the next work item to process using round-robin rotation.
      # Skips paused items but keeps them in queue.
      #
      # @param paused_numbers [Array<Integer>] Issue/PR numbers that are paused
      # @return [WorkItem, nil] Next item to process, or nil if none available
      def next_item(paused_numbers: [])
        return nil if @queue.empty?

        Aidp.log_debug("round_robin_scheduler", "next_item.start",
          queue_size: @queue.size,
          paused_count: paused_numbers.size,
          last_key: @last_processed_key)

        # Find starting position based on last processed key
        start_index = find_start_index

        # Iterate through queue starting from rotation point
        @queue.size.times do |offset|
          index = (start_index + offset) % @queue.size
          item = @queue[index]

          # Skip paused items
          if paused_numbers.include?(item.number)
            Aidp.log_debug("round_robin_scheduler", "next_item.skip_paused",
              key: item.key, number: item.number)
            next
          end

          Aidp.log_debug("round_robin_scheduler", "next_item.selected",
            key: item.key, number: item.number, processor_type: item.processor_type)

          return item
        end

        Aidp.log_debug("round_robin_scheduler", "next_item.all_paused",
          queue_size: @queue.size)
        nil
      end

      # Mark a work item as processed and persist the rotation state.
      #
      # @param item [WorkItem] The item that was just processed
      def mark_processed(item)
        @last_processed_key = item.key
        @state_store.record_round_robin_position(
          last_key: item.key,
          processed_at: Time.now.utc.iso8601
        )

        Aidp.log_debug("round_robin_scheduler", "mark_processed",
          key: item.key, number: item.number)
      end

      # Check if there are any non-paused items in the queue.
      #
      # @param paused_numbers [Array<Integer>] Issue/PR numbers that are paused
      # @return [Boolean] True if there's work to do
      def work?(paused_numbers: [])
        @queue.any? { |item| !paused_numbers.include?(item.number) }
      end

      # Get queue statistics for debugging/monitoring.
      #
      # @return [Hash] Queue statistics
      def stats
        by_processor = @queue.group_by(&:processor_type)
        by_priority = @queue.group_by(&:priority)

        {
          total: @queue.size,
          by_processor: by_processor.transform_values(&:size),
          by_priority: by_priority.transform_values(&:size),
          last_processed_key: @last_processed_key
        }
      end

      private

      # Find the index to start searching from based on last processed item.
      # Returns the index AFTER the last processed item for round-robin.
      #
      # @return [Integer] Starting index for rotation
      def find_start_index
        return 0 if @last_processed_key.nil?
        return 0 if @queue.empty?

        # Find the last processed item in the current queue
        last_index = @queue.find_index { |item| item.key == @last_processed_key }

        # If not found (item was removed), start from beginning
        return 0 unless last_index

        # Start from the next item (wrap around)
        (last_index + 1) % @queue.size
      end
    end
  end
end
