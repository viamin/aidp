# frozen_string_literal: true

require "tty-prompt"
require "tty-spinner"
require_relative "async_work_loop_runner"
require_relative "repl_macros"

module Aidp
  module Execute
    # Interactive REPL for controlling async work loops
    # Provides live control during work loop execution:
    # - Pause/resume/cancel work loop
    # - Inject instructions mid-execution
    # - Update configuration live
    # - View streaming output
    # - Rollback commits
    #
    # Usage:
    #   repl = InteractiveRepl.new(project_dir, provider_manager, config)
    #   repl.start_work_loop(step_name, step_spec, context)
    class InteractiveRepl
      def initialize(project_dir, provider_manager, config, options = {})
        @project_dir = project_dir
        @provider_manager = provider_manager
        @config = config
        @options = options
        @prompt = options[:prompt] || TTY::Prompt.new
        @async_runner = nil
        @repl_macros = ReplMacros.new
        @output_display_thread = nil
        @running = false
      end

      # Start work loop and enter interactive REPL
      def start_work_loop(step_name, step_spec, context = {})
        @async_runner = AsyncWorkLoopRunner.new(
          @project_dir,
          @provider_manager,
          @config,
          @options
        )

        display_welcome(step_name)

        # Start async work loop
        result = @async_runner.execute_step_async(step_name, step_spec, context)
        @prompt.say("Work loop started (#{result[:state][:state]})")

        # Start output display thread
        start_output_display

        # Enter REPL loop
        @running = true
        repl_loop

        # Wait for completion
        final_result = @async_runner.wait

        # Stop output display
        stop_output_display

        display_completion(final_result)
        final_result
      end

      private

      # Main REPL loop
      def repl_loop
        while @running
          begin
            # Check if work loop is still running
            unless @async_runner.running? || @async_runner.state.paused?
              @running = false
              break
            end

            # Read command (non-blocking with timeout)
            command = read_command_with_timeout

            next unless command

            # Execute command
            handle_command(command)
          rescue Interrupt
            handle_interrupt
          rescue => e
            @prompt.error("REPL error: #{e.message}")
          end
        end
      end

      # Read command with timeout to allow checking work loop status
      def read_command_with_timeout
        # Use TTY::Prompt's ask with timeout is not directly supported
        # So we'll use a simple gets with a prompt
        print_prompt
        command = $stdin.gets&.chomp
        command&.strip
      rescue => e
        @prompt.error("Input error: #{e.message}")
        nil
      end

      # Print REPL prompt
      def print_prompt
        status = @async_runner.status
        state = status[:state]
        iteration = status[:iteration]
        queued = status.dig(:queued_instructions, :total) || 0

        prompt_text = case state
        when "RUNNING"
          "aidp[#{iteration}]"
        when "PAUSED"
          "aidp[#{iteration}|PAUSED]"
        else
          "aidp"
        end

        prompt_text += " (#{queued} queued)" if queued > 0
        print "#{prompt_text}> "
      end

      # Handle REPL command
      def handle_command(command)
        return if command.empty?

        # Try REPL macros first
        result = @repl_macros.execute(command)

        if result[:success]
          @prompt.say(result[:message]) if result[:message]

          # Handle actions that interact with async runner
          case result[:action]
          when :pause_work_loop
            pause_result = @async_runner.pause
            @prompt.say("Work loop paused at iteration #{pause_result[:iteration]}")
          when :resume_work_loop
            resume_result = @async_runner.resume
            @prompt.say("Work loop resumed at iteration #{resume_result[:iteration]}")
          when :cancel_work_loop
            cancel_result = @async_runner.cancel(save_checkpoint: result.dig(:data, :save_checkpoint))
            @prompt.say("Work loop cancelled at iteration #{cancel_result[:iteration]}")
            @running = false
          when :enqueue_instruction
            data = result[:data]
            @async_runner.enqueue_instruction(
              data[:instruction],
              type: data[:type],
              priority: data[:priority]
            )
          when :update_guard
            data = result[:data]
            @async_runner.state.request_guard_update(data[:key], data[:value])
            @prompt.say("Guard update will apply at next iteration")
          when :reload_config
            @async_runner.state.request_config_reload
            @prompt.say("Config reload will apply at next iteration")
          when :rollback_commits
            handle_rollback(result[:data][:count])
          end
        else
          @prompt.error(result[:message])
        end
      rescue => e
        @prompt.error("Command error: #{e.message}")
      end

      # Handle rollback command
      def handle_rollback(count)
        # Pause work loop first
        if @async_runner.running?
          @async_runner.pause
          @prompt.say("Work loop paused for rollback")
        end

        # Execute rollback
        @prompt.say("Rolling back #{count} commit(s)...")

        result = execute_git_rollback(count)

        if result[:success]
          @prompt.ok("Rollback complete: #{result[:message]}")
        else
          @prompt.error("Rollback failed: #{result[:message]}")
        end

        # Ask if user wants to resume
        if @async_runner.state.paused?
          resume = @prompt.yes?("Resume work loop?")
          @async_runner.resume if resume
        end
      end

      # Execute git rollback
      def execute_git_rollback(count)
        # Safety check: only rollback on current branch
        current_branch = `git branch --show-current`.strip

        if current_branch.empty? || current_branch == "main" || current_branch == "master"
          return {
            success: false,
            message: "Refusing to rollback on #{current_branch || "detached HEAD"}"
          }
        end

        # Execute reset
        output = `git reset --hard HEAD~#{count} 2>&1`
        success = $?.success?

        {
          success: success,
          message: success ? "Reset #{count} commit(s)" : output
        }
      rescue => e
        {success: false, message: e.message}
      end

      # Handle Ctrl-C interrupt
      def handle_interrupt
        @prompt.warn("\nInterrupt received")

        choice = @prompt.select("What would you like to do?") do |menu|
          menu.choice "Cancel work loop", :cancel
          menu.choice "Pause work loop", :pause
          menu.choice "Continue REPL", :continue
        end

        case choice
        when :cancel
          @async_runner.cancel(save_checkpoint: true)
          @running = false
        when :pause
          @async_runner.pause
          @prompt.say("Work loop paused")
        when :continue
          # Just continue
        end
      rescue Interrupt
        # Double interrupt - force exit
        @prompt.error("Force exit requested")
        @async_runner.cancel(save_checkpoint: false)
        @running = false
      end

      # Start output display thread
      def start_output_display
        @output_display_thread = Thread.new do
          loop do
            sleep 0.5 # Poll every 500ms

            # Drain output from async runner
            output = @async_runner.drain_output

            output.each do |entry|
              display_output_entry(entry)
            end

            # Exit thread if work loop not running
            break unless @async_runner.running? || @async_runner.state.paused?
          end
        rescue
          # Silently exit thread on error
        end
      end

      # Stop output display thread
      def stop_output_display
        @output_display_thread&.kill
        @output_display_thread&.join(1)
        @output_display_thread = nil

        # Drain any remaining output
        output = @async_runner.drain_output
        output.each { |entry| display_output_entry(entry) }
      end

      # Display output entry
      def display_output_entry(entry)
        message = entry[:message]
        type = entry[:type]

        case type
        when :error
          @prompt.error(message)
        when :warning
          @prompt.warn(message)
        when :success
          @prompt.ok(message)
        else
          @prompt.say(message)
        end
      end

      # Display welcome message
      def display_welcome(step_name)
        @prompt.say("\n" + "=" * 80)
        @prompt.say("🎮 Interactive REPL - Work Loop: #{step_name}")
        @prompt.say("=" * 80)
        @prompt.say("\nCommands:")
        @prompt.say("  /pause, /resume, /cancel - Control work loop")
        @prompt.say("  /inject <instruction> - Add instruction for next iteration")
        @prompt.say("  /merge <plan> - Update plan/contract")
        @prompt.say("  /update guard <key>=<value> - Update guard rails")
        @prompt.say("  /rollback <n>, /undo last - Rollback commits")
        @prompt.say("  /status - Show current state")
        @prompt.say("  /help - Show all commands")
        @prompt.say("\nPress Ctrl-C for interrupt menu")
        @prompt.say("=" * 80 + "\n")
      end

      # Display completion message
      def display_completion(result)
        @prompt.say("\n" + "=" * 80)

        case result[:status]
        when "completed"
          @prompt.ok("✅ Work loop completed successfully!")
        when "cancelled"
          @prompt.warn("⚠️  Work loop cancelled by user")
        when "error"
          @prompt.error("❌ Work loop encountered an error")
        else
          @prompt.say("Work loop ended: #{result[:status]}")
        end

        @prompt.say("Iterations: #{result[:iterations]}")
        @prompt.say(result[:message]) if result[:message]
        @prompt.say("=" * 80 + "\n")
      end
    end
  end
end
