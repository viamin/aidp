# frozen_string_literal: true

require "monitor"

module Aidp
  module Execute
    # Thread-safe state container for async work loop execution
    # Manages execution state, control signals, and queued modifications
    class WorkLoopState
      include MonitorMixin

      STATES = {
        idle: "IDLE",
        running: "RUNNING",
        paused: "PAUSED",
        cancelled: "CANCELLED",
        completed: "COMPLETED",
        error: "ERROR"
      }.freeze

      attr_reader :current_state, :iteration, :queued_instructions, :last_error

      def initialize
        super # Initialize MonitorMixin
        @current_state = :idle
        @iteration = 0
        @queued_instructions = []
        @guard_updates = {}
        @config_reload_requested = false
        @last_error = nil
        @output_buffer = []
      end

      # Check current state
      def idle? = @current_state == :idle
      def running? = @current_state == :running
      def paused? = @current_state == :paused
      def cancelled? = @current_state == :cancelled
      def completed? = @current_state == :completed
      def error? = @current_state == :error

      # State transitions (thread-safe)
      def start!
        synchronize do
          raise StateError, "Cannot start from #{@current_state}" unless idle?
          @current_state = :running
          @iteration = 0
        end
      end

      def pause!
        synchronize do
          raise StateError, "Cannot pause from #{@current_state}" unless running?
          @current_state = :paused
        end
      end

      def resume!
        synchronize do
          raise StateError, "Cannot resume from #{@current_state}" unless paused?
          @current_state = :running
        end
      end

      def cancel!
        synchronize do
          raise StateError, "Cannot cancel from #{@current_state}" if completed? || error?
          @current_state = :cancelled
        end
      end

      def complete!
        synchronize do
          @current_state = :completed
        end
      end

      def error!(error)
        synchronize do
          @current_state = :error
          @last_error = error
        end
      end

      # Iteration management
      def increment_iteration!
        synchronize { @iteration += 1 }
      end

      # Instruction queueing
      def enqueue_instruction(instruction)
        synchronize { @queued_instructions << instruction }
      end

      def dequeue_instructions
        synchronize do
          instructions = @queued_instructions.dup
          @queued_instructions.clear
          instructions
        end
      end

      def queued_count
        synchronize { @queued_instructions.size }
      end

      # Guard/config updates
      def request_guard_update(key, value)
        synchronize { @guard_updates[key] = value }
      end

      def pending_guard_updates
        synchronize do
          updates = @guard_updates.dup
          @guard_updates.clear
          updates
        end
      end

      def request_config_reload
        synchronize { @config_reload_requested = true }
      end

      def config_reload_requested?
        synchronize do
          requested = @config_reload_requested
          @config_reload_requested = false
          requested
        end
      end

      # Output buffering for streaming display
      def append_output(message, type: :info)
        synchronize do
          @output_buffer << {message: message, type: type, timestamp: Time.now}
        end
      end

      def drain_output
        synchronize do
          output = @output_buffer.dup
          @output_buffer.clear
          output
        end
      end

      # Status summary
      def summary
        synchronize do
          {
            state: STATES[@current_state],
            iteration: @iteration,
            queued_instructions: @queued_instructions.size,
            has_error: !@last_error.nil?
          }
        end
      end

      class StateError < StandardError; end
    end
  end
end
