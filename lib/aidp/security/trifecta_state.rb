# frozen_string_literal: true

module Aidp
  module Security
    # Tracks the three security flags that form the "lethal trifecta"
    # Per Rule of Two: never enable all three simultaneously
    #
    # Flags:
    # - untrusted_input: Processing content from untrusted sources (issues, PRs, external data)
    # - private_data: Access to secrets, credentials, or sensitive data
    # - egress: Ability to communicate externally (git push, API calls, network access)
    #
    # State is tracked per work unit and resets between units.
    class TrifectaState
      attr_reader :untrusted_input, :private_data, :egress, :work_unit_id

      # Track sources for audit logging
      attr_reader :untrusted_input_source, :private_data_source, :egress_source

      def initialize(work_unit_id: nil)
        @work_unit_id = work_unit_id || SecureRandom.hex(8)
        @untrusted_input = false
        @private_data = false
        @egress = false
        @untrusted_input_source = nil
        @private_data_source = nil
        @egress_source = nil
        @frozen = false
      end

      # Check if enabling a flag would create the lethal trifecta
      # @param flag [Symbol] :untrusted_input, :private_data, or :egress
      # @return [Boolean] true if enabling would create lethal trifecta
      def would_create_trifecta?(flag)
        case flag
        when :untrusted_input
          private_data && egress
        when :private_data
          untrusted_input && egress
        when :egress
          untrusted_input && private_data
        else
          raise ArgumentError, "Unknown trifecta flag: #{flag}"
        end
      end

      # Check if the lethal trifecta is currently active
      # @return [Boolean] true if all three flags are enabled
      def lethal_trifecta?
        untrusted_input && private_data && egress
      end

      # Count of currently enabled flags
      # @return [Integer] 0, 1, 2, or 3
      def enabled_count
        [untrusted_input, private_data, egress].count(true)
      end

      # Enable a flag with source tracking
      # @param flag [Symbol] :untrusted_input, :private_data, or :egress
      # @param source [String] Description of what caused this flag to be enabled
      # @raise [PolicyViolation] if enabling would create lethal trifecta
      # @return [TrifectaState] self for chaining
      def enable(flag, source: nil)
        raise FrozenStateError, "Cannot modify frozen trifecta state" if @frozen

        if would_create_trifecta?(flag)
          raise PolicyViolation.new(
            flag: flag,
            source: source,
            current_state: to_h,
            message: build_violation_message(flag, source)
          )
        end

        case flag
        when :untrusted_input
          @untrusted_input = true
          @untrusted_input_source = source
        when :private_data
          @private_data = true
          @private_data_source = source
        when :egress
          @egress = true
          @egress_source = source
        else
          raise ArgumentError, "Unknown trifecta flag: #{flag}"
        end

        log_flag_enabled(flag, source)
        self
      end

      # Disable a flag
      # @param flag [Symbol] :untrusted_input, :private_data, or :egress
      # @return [TrifectaState] self for chaining
      def disable(flag)
        raise FrozenStateError, "Cannot modify frozen trifecta state" if @frozen

        case flag
        when :untrusted_input
          @untrusted_input = false
          @untrusted_input_source = nil
        when :private_data
          @private_data = false
          @private_data_source = nil
        when :egress
          @egress = false
          @egress_source = nil
        else
          raise ArgumentError, "Unknown trifecta flag: #{flag}"
        end

        log_flag_disabled(flag)
        self
      end

      # Freeze state - no further modifications allowed
      # Used when passing state to execution context
      def freeze!
        @frozen = true
        self
      end

      # Check if state is frozen
      def frozen?
        @frozen
      end

      # Create a copy of this state (unfrozen)
      def dup
        new_state = TrifectaState.new(work_unit_id: "#{@work_unit_id}_dup")
        new_state.instance_variable_set(:@untrusted_input, @untrusted_input)
        new_state.instance_variable_set(:@private_data, @private_data)
        new_state.instance_variable_set(:@egress, @egress)
        new_state.instance_variable_set(:@untrusted_input_source, @untrusted_input_source)
        new_state.instance_variable_set(:@private_data_source, @private_data_source)
        new_state.instance_variable_set(:@egress_source, @egress_source)
        new_state
      end

      # Export state as hash for logging/serialization
      def to_h
        {
          work_unit_id: @work_unit_id,
          untrusted_input: @untrusted_input,
          untrusted_input_source: @untrusted_input_source,
          private_data: @private_data,
          private_data_source: @private_data_source,
          egress: @egress,
          egress_source: @egress_source,
          enabled_count: enabled_count,
          lethal_trifecta: lethal_trifecta?,
          frozen: @frozen
        }
      end

      # Human-readable status string
      def status_string
        flags = []
        flags << "untrusted_input" if untrusted_input
        flags << "private_data" if private_data
        flags << "egress" if egress

        if flags.empty?
          "No flags enabled (safe)"
        elsif lethal_trifecta?
          "LETHAL TRIFECTA: #{flags.join(", ")}"
        else
          "Enabled: #{flags.join(", ")} (#{enabled_count}/3 - safe)"
        end
      end

      private

      def build_violation_message(flag, source)
        existing_flags = []
        existing_flags << "untrusted_input (#{@untrusted_input_source || "unknown source"})" if untrusted_input
        existing_flags << "private_data (#{@private_data_source || "unknown source"})" if private_data
        existing_flags << "egress (#{@egress_source || "unknown source"})" if egress

        <<~MSG.strip
          Rule of Two violation: Cannot enable '#{flag}' (#{source || "unknown source"})

          Currently enabled flags:
          #{existing_flags.map { |f| "  - #{f}" }.join("\n")}

          Enabling '#{flag}' would create the lethal trifecta where an agent has:
          1. Access to untrusted input (prompt injection vector)
          2. Access to private data/secrets
          3. Ability to exfiltrate via external communication

          To proceed, you must either:
          - Use the Secrets Proxy to isolate credential access
          - Sanitize untrusted input before processing
          - Disable external communication for this operation
        MSG
      end

      def log_flag_enabled(flag, source)
        Aidp.log_debug("security.trifecta", "flag_enabled",
          work_unit_id: @work_unit_id,
          flag: flag,
          source: source,
          enabled_count: enabled_count,
          state: to_h)
      end

      def log_flag_disabled(flag)
        Aidp.log_debug("security.trifecta", "flag_disabled",
          work_unit_id: @work_unit_id,
          flag: flag,
          enabled_count: enabled_count)
      end
    end

    # Error raised when attempting to modify frozen state
    class FrozenStateError < StandardError; end
  end
end
