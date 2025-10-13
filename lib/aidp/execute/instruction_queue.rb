# frozen_string_literal: true

module Aidp
  module Execute
    # Manages queued instructions and plan modifications during work loop execution
    # Instructions are merged into PROMPT.md at the next iteration
    class InstructionQueue
      Instruction = Struct.new(:content, :type, :priority, :timestamp, keyword_init: true)

      INSTRUCTION_TYPES = {
        user_input: "USER_INPUT",           # Direct user instructions
        plan_update: "PLAN_UPDATE",         # Changes to implementation contract
        constraint: "CONSTRAINT",           # New constraints or requirements
        clarification: "CLARIFICATION",     # Clarifications on existing work
        acceptance: "ACCEPTANCE_CRITERIA"   # New acceptance criteria
      }.freeze

      PRIORITIES = {
        critical: 1,
        high: 2,
        normal: 3,
        low: 4
      }.freeze

      def initialize
        @instructions = []
      end

      # Add instruction to queue
      def enqueue(content, type: :user_input, priority: :normal)
        validate_type!(type)
        validate_priority!(priority)

        instruction = Instruction.new(
          content: content,
          type: type,
          priority: PRIORITIES[priority],
          timestamp: Time.now
        )

        @instructions << instruction
        instruction
      end

      # Retrieve and remove all instructions (sorted by priority, then time)
      def dequeue_all
        instructions = @instructions.sort_by { |i| [i.priority, i.timestamp] }
        @instructions.clear
        instructions
      end

      # Peek at instructions without removing
      def peek_all
        @instructions.sort_by { |i| [i.priority, i.timestamp] }
      end

      # Get count of queued instructions
      def count
        @instructions.size
      end

      # Check if queue is empty
      def empty?
        @instructions.empty?
      end

      # Clear all instructions
      def clear
        @instructions.clear
      end

      # Format instructions for merging into PROMPT.md
      def format_for_prompt(instructions = nil)
        instructions ||= peek_all
        return "" if instructions.empty?

        parts = []
        parts << "## 🔄 Queued Instructions from REPL"
        parts << ""
        parts << "The following instructions were added during execution and should be"
        parts << "incorporated into your next iteration:"
        parts << ""

        instructions.group_by(&:type).each do |type, type_instructions|
          parts << "### #{INSTRUCTION_TYPES[type]}"
          type_instructions.each_with_index do |instruction, idx|
            priority_marker = (instruction.priority == 1) ? " 🔴 CRITICAL" : ""
            parts << "#{idx + 1}. #{instruction.content}#{priority_marker}"
          end
          parts << ""
        end

        parts << "**Note**: Address these instructions while continuing your current work."
        parts << "Do not restart from scratch - build on what exists."
        parts << ""

        parts.join("\n")
      end

      # Summary for display
      def summary
        return "No queued instructions" if empty?

        by_type = @instructions.group_by(&:type).transform_values(&:size)
        by_priority = @instructions.group_by { |i| priority_name(i.priority) }.transform_values(&:size)

        {
          total: count,
          by_type: by_type,
          by_priority: by_priority
        }
      end

      private

      def validate_type!(type)
        return if INSTRUCTION_TYPES.key?(type)
        raise ArgumentError, "Invalid instruction type: #{type}. Must be one of #{INSTRUCTION_TYPES.keys.join(", ")}"
      end

      def validate_priority!(priority)
        return if PRIORITIES.key?(priority)
        raise ArgumentError, "Invalid priority: #{priority}. Must be one of #{PRIORITIES.keys.join(", ")}"
      end

      def priority_name(priority_value)
        PRIORITIES.invert[priority_value] || :unknown
      end
    end
  end
end
