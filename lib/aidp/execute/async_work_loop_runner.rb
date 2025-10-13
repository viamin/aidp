# frozen_string_literal: true

require_relative "work_loop_runner"
require_relative "work_loop_state"
require_relative "instruction_queue"

module Aidp
  module Execute
    # Asynchronous wrapper around WorkLoopRunner
    # Runs work loop in a separate thread while maintaining REPL responsiveness
    #
    # Responsibilities:
    # - Execute work loop in background thread
    # - Monitor execution state (pause, resume, cancel)
    # - Merge queued instructions at iteration boundaries
    # - Stream output to main thread for display
    # - Handle graceful cancellation with checkpoint save
    class AsyncWorkLoopRunner
      attr_reader :state, :instruction_queue, :work_thread

      def initialize(project_dir, provider_manager, config, options = {})
        @project_dir = project_dir
        @provider_manager = provider_manager
        @config = config
        @options = options
        @state = WorkLoopState.new
        @instruction_queue = InstructionQueue.new
        @work_thread = nil
        @sync_runner = nil
      end

      # Start async work loop execution
      # Returns immediately, work continues in background thread
      def execute_step_async(step_name, step_spec, context = {})
        raise WorkLoopState::StateError, "Work loop already running" unless @state.idle?

        @state.start!
        @step_name = step_name
        @step_spec = step_spec
        @context = context

        @work_thread = Thread.new do
          run_async_loop
        rescue => e
          @state.error!(e)
          @state.append_output("Work loop error: #{e.message}", type: :error)
        ensure
          @work_thread = nil
        end

        # Allow thread to start
        Thread.pass

        {status: "started", state: @state.summary}
      end

      # Wait for work loop to complete (blocking)
      def wait
        return unless @work_thread
        @work_thread.join
        build_final_result
      end

      # Check if work loop is running
      def running?
        @work_thread&.alive? && @state.running?
      end

      # Pause execution
      def pause
        return unless running?
        @state.pause!
        {status: "paused", iteration: @state.iteration}
      end

      # Resume execution
      def resume
        return unless @state.paused?
        @state.resume!
        {status: "resumed", iteration: @state.iteration}
      end

      # Cancel execution gracefully
      def cancel(save_checkpoint: true)
        return if @state.cancelled? || @state.completed?

        @state.cancel!
        @state.append_output("Cancellation requested, waiting for safe stopping point...", type: :warning)

        # Wait for thread to notice cancellation
        @work_thread&.join(5) # 5 second timeout

        if save_checkpoint && @sync_runner
          @state.append_output("Saving checkpoint before exit...", type: :info)
          save_cancellation_checkpoint
        end

        {status: "cancelled", iteration: @state.iteration}
      end

      # Add instruction to queue (will be merged at next iteration)
      def enqueue_instruction(content, type: :user_input, priority: :normal)
        @instruction_queue.enqueue(content, type: type, priority: priority)
        @state.enqueue_instruction(content)

        {
          status: "enqueued",
          queued_count: @instruction_queue.count,
          message: "Instruction will be merged in next iteration"
        }
      end

      # Get streaming output
      def drain_output
        @state.drain_output
      end

      # Get current status
      def status
        summary = @state.summary
        summary[:queued_instructions] = @instruction_queue.summary
        summary[:thread_alive] = @work_thread&.alive? || false
        summary
      end

      private

      # Main async execution loop
      def run_async_loop
        # Create synchronous runner (runs in this thread)
        @sync_runner = WorkLoopRunner.new(
          @project_dir,
          @provider_manager,
          @config,
          @options.merge(async_mode: true)
        )

        @state.append_output("🚀 Starting async work loop: #{@step_name}", type: :info)

        # Hook into sync runner to check for pause/cancel
        result = execute_with_monitoring

        if @state.cancelled?
          @state.append_output("Work loop cancelled at iteration #{@state.iteration}", type: :warning)
        else
          @state.complete!
          @state.append_output("✅ Work loop completed: #{@step_name}", type: :success)
        end

        result
      rescue => e
        @state.error!(e)
        @state.append_output("Error in work loop: #{e.message}\n#{e.backtrace.first(3).join("\n")}", type: :error)
        raise
      end

      # Execute sync runner with monitoring for control signals
      def execute_with_monitoring
        # We need to modify WorkLoopRunner to support iteration callbacks
        # For now, we'll wrap the execute_step call
        #
        # TODO: This requires enhancing WorkLoopRunner to accept iteration callbacks
        # See: https://github.com/viamin/aidp/issues/103
        @sync_runner.execute_step(@step_name, @step_spec, @context)
      end

      # Save checkpoint when cancelling
      def save_cancellation_checkpoint
        return unless @sync_runner

        checkpoint = @sync_runner.instance_variable_get(:@checkpoint)
        return unless checkpoint

        checkpoint.record_checkpoint(
          @step_name,
          @state.iteration,
          {
            cancelled: true,
            reason: "User cancelled via REPL",
            queued_instructions: @instruction_queue.count
          }
        )
      end

      # Build final result from state
      def build_final_result
        if @state.completed?
          {
            status: "completed",
            iterations: @state.iteration,
            message: "Work loop completed successfully"
          }
        elsif @state.cancelled?
          {
            status: "cancelled",
            iterations: @state.iteration,
            message: "Work loop cancelled by user"
          }
        elsif @state.error?
          {
            status: "error",
            iterations: @state.iteration,
            error: @state.last_error&.message,
            message: "Work loop encountered an error"
          }
        else
          {
            status: "unknown",
            iterations: @state.iteration,
            message: "Work loop ended in unknown state"
          }
        end
      end
    end
  end
end
