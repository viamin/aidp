# frozen_string_literal: true

module Aidp
  module Security
    # Main enforcement engine for the Rule of Two security policy
    # Tracks trifecta state per work unit and denies operations that would
    # create the lethal trifecta (untrusted_input + private_data + egress)
    #
    # Usage:
    #   enforcer = RuleOfTwoEnforcer.new
    #   state = enforcer.begin_work_unit(work_unit_id: "unit_123")
    #   state.enable(:untrusted_input, source: "github_issue")
    #   state.enable(:egress, source: "git_push")
    #   # This would raise PolicyViolation:
    #   # state.enable(:private_data, source: "env_var_access")
    #   enforcer.end_work_unit("unit_123")
    class RuleOfTwoEnforcer
      attr_reader :config

      def initialize(config: {})
        @config = config
        @active_states = {}
        @completed_states = []
        @mutex = Mutex.new
      end

      # Begin tracking a new work unit
      # @param work_unit_id [String] Unique identifier for the work unit
      # @return [TrifectaState] The state object for this work unit
      def begin_work_unit(work_unit_id:)
        @mutex.synchronize do
          if @active_states.key?(work_unit_id)
            Aidp.log_warn("security.enforcer", "work_unit_already_active",
              work_unit_id: work_unit_id)
            return @active_states[work_unit_id]
          end

          state = TrifectaState.new(work_unit_id: work_unit_id)
          @active_states[work_unit_id] = state

          Aidp.log_debug("security.enforcer", "work_unit_started",
            work_unit_id: work_unit_id,
            active_count: @active_states.size)

          state
        end
      end

      # End tracking for a work unit
      # @param work_unit_id [String] Unique identifier for the work unit
      # @return [Hash] Final state summary
      def end_work_unit(work_unit_id)
        @mutex.synchronize do
          state = @active_states.delete(work_unit_id)

          unless state
            Aidp.log_warn("security.enforcer", "work_unit_not_found",
              work_unit_id: work_unit_id)
            return nil
          end

          summary = state.to_h
          @completed_states << summary

          # Keep only last 100 completed states
          @completed_states.shift if @completed_states.size > 100

          Aidp.log_debug("security.enforcer", "work_unit_ended",
            work_unit_id: work_unit_id,
            final_state: summary,
            active_count: @active_states.size)

          summary
        end
      end

      # Get the state for an active work unit
      # @param work_unit_id [String] Unique identifier for the work unit
      # @return [TrifectaState, nil] The state object or nil if not found
      def state_for(work_unit_id)
        @mutex.synchronize { @active_states[work_unit_id] }
      end

      # Check if a work unit is currently active
      def active?(work_unit_id)
        @mutex.synchronize { @active_states.key?(work_unit_id) }
      end

      # Get count of active work units
      def active_count
        @mutex.synchronize { @active_states.size }
      end

      # Check if an operation would be allowed for a work unit
      # @param work_unit_id [String] Work unit identifier
      # @param flag [Symbol] The flag to check (:untrusted_input, :private_data, :egress)
      # @return [Hash] { allowed: boolean, reason: string }
      def would_allow?(work_unit_id, flag)
        state = state_for(work_unit_id)

        unless state
          return {
            allowed: true,
            reason: "No active work unit - enforcement not applicable"
          }
        end

        if state.would_create_trifecta?(flag)
          {
            allowed: false,
            reason: "Would create lethal trifecta",
            current_state: state.to_h,
            flag: flag
          }
        else
          {
            allowed: true,
            reason: "Operation allowed",
            current_state: state.to_h,
            flag: flag
          }
        end
      end

      # Enforce a flag on a work unit - raises PolicyViolation on failure
      # @param work_unit_id [String] Work unit identifier
      # @param flag [Symbol] The flag to enable
      # @param source [String] Description of the operation causing the flag
      # @raise [PolicyViolation] if enabling would create lethal trifecta
      def enforce!(work_unit_id:, flag:, source:)
        state = state_for(work_unit_id)

        unless state
          Aidp.log_warn("security.enforcer", "enforce_on_inactive_unit",
            work_unit_id: work_unit_id,
            flag: flag,
            source: source)
          return nil
        end

        state.enable(flag, source: source)
      end

      # Check if enforcement is currently enabled
      def enabled?
        # Default to enabled unless explicitly disabled
        @config.fetch(:enabled, true)
      end

      # Get summary of current enforcement status
      def status_summary
        @mutex.synchronize do
          {
            enabled: enabled?,
            active_work_units: @active_states.size,
            completed_work_units: @completed_states.size,
            active_states: @active_states.transform_values(&:to_h),
            recent_completions: @completed_states.last(5)
          }
        end
      end

      # Audit log of all completed work units with their final states
      def audit_log
        @mutex.synchronize { @completed_states.dup }
      end

      # Reset enforcer state (primarily for testing)
      def reset!
        @mutex.synchronize do
          @active_states.clear
          @completed_states.clear
        end
      end

      # Create a scoped execution context that automatically manages work unit lifecycle
      # @param work_unit_id [String] Unique identifier for the work unit
      # @yield [TrifectaState] The state object for this work unit
      # @return [Object] The result of the block
      def with_work_unit(work_unit_id:)
        state = begin_work_unit(work_unit_id: work_unit_id)
        begin
          yield state
        ensure
          end_work_unit(work_unit_id)
        end
      end

      # Convenience method to wrap an agent operation with security enforcement
      # @param work_unit_id [String] Work unit identifier
      # @param untrusted_input_source [String, nil] Source of untrusted input
      # @param private_data_source [String, nil] Source of private data access
      # @param egress_source [String, nil] Source of egress capability
      # @yield The operation to execute
      # @return [Object] The result of the block
      # @raise [PolicyViolation] if the combination would violate Rule of Two
      def wrap_agent_operation(work_unit_id:, untrusted_input_source: nil,
        private_data_source: nil, egress_source: nil)
        with_work_unit(work_unit_id: work_unit_id) do |state|
          # Enable flags based on what's provided
          state.enable(:untrusted_input, source: untrusted_input_source) if untrusted_input_source
          state.enable(:private_data, source: private_data_source) if private_data_source
          state.enable(:egress, source: egress_source) if egress_source

          yield state
        end
      end
    end
  end
end
