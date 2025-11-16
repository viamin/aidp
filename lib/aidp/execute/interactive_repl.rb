# frozen_string_literal: true

require "tty-prompt"
require "tty-spinner"
require_relative "async_work_loop_runner"
require_relative "repl_macros"
require_relative "../rescue_logging"
require_relative "../concurrency"

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
      include Aidp::RescueLogging

      def initialize(project_dir, provider_manager, config, options = {})
        @project_dir = project_dir
        @provider_manager = provider_manager
        @config = config
        @options = options
        @prompt = options[:prompt] || TTY::Prompt.new
        @async_runner_class = options[:async_runner_class] || AsyncWorkLoopRunner
        @async_runner = nil
        @repl_macros = ReplMacros.new
        @output_display_thread = nil
        @running = false
        @completion_setup_needed = true
      end

      # Start work loop and enter interactive REPL
      def start_work_loop(step_name, step_spec, context = {})
        @async_runner = @async_runner_class.new(
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
            log_rescue(e, component: "interactive_repl", action: "repl_command_loop", fallback: "error_display")
            @prompt.error("REPL error: #{e.message}")
          end
        end
      end

      # Read command with timeout to allow checking work loop status
      def read_command_with_timeout
        # Use Reline for readline-style editing with tab completion
        require "reline"
        setup_completion if @completion_setup_needed

        print_prompt_text
        Reline.output = $stdout
        Reline.input = $stdin
        Reline.completion_append_character = " "

        command = Reline.readline("", false)
        return nil if command.nil? # Ctrl-D

        command&.strip
      rescue => e
        log_rescue(e, component: "interactive_repl", action: "read_command", fallback: nil)
        @prompt.error("Input error: #{e.message}")
        nil
      end

      # Setup tab completion for REPL commands
      def setup_completion
        require "reline"

        # Define completion proc
        Reline.completion_proc = proc do |input|
          # Get list of commands from repl_macros
          all_commands = @repl_macros.list_commands

          # Extract the word being completed
          words = input.split(/\s+/)
          current_word = words.last || ""

          # If we're completing the first word (command), offer command names
          if words.size <= 1 || (words.size == 1 && !input.end_with?(" "))
            all_commands.select { |cmd| cmd.start_with?(current_word) }
          # If completing after /ws, offer subcommands
          elsif words.first == "/ws"
            if words.size == 2 && !input.end_with?(" ")
              # Completing subcommand
              subcommands = %w[list new switch rm status pause resume complete dashboard pause-all resume-all stop-all]
              subcommands.select { |sc| sc.start_with?(current_word) }
            elsif %w[switch rm status pause resume complete].include?(words[1])
              # Completing workstream slug
              require_relative "../worktree"
              workstreams = Aidp::Worktree.list(project_dir: @project_dir)
              slugs = workstreams.map { |ws| ws[:slug] }
              slugs.select { |slug| slug.start_with?(current_word) }
            else
              []
            end
          # If completing after /skill, offer subcommands or skill IDs
          elsif words.first == "/skill"
            if words.size == 2 && !input.end_with?(" ")
              # Completing subcommand
              subcommands = %w[list show search]
              subcommands.select { |sc| sc.start_with?(current_word) }
            elsif %w[show].include?(words[1])
              # Completing skill ID
              require_relative "../skills"
              registry = Aidp::Skills::Registry.new(project_dir: @project_dir)
              registry.load_skills
              skill_ids = registry.all.map(&:id)
              skill_ids.select { |id| id.start_with?(current_word) }
            else
              []
            end
          else
            []
          end
        end

        @completion_setup_needed = false
      end

      # Print REPL prompt text (for Reline)
      def print_prompt_text
        status = @async_runner.status
        state = status[:state]
        iteration = status[:iteration]
        queued = status.dig(:queued_instructions, :total) || 0
        # Workstream context (if any)
        current_ws = if @repl_macros.respond_to?(:current_workstream)
          @repl_macros.current_workstream
        elsif @repl_macros.instance_variable_defined?(:@current_workstream)
          @repl_macros.instance_variable_get(:@current_workstream)
        end

        ws_fragment = ""
        if current_ws
          begin
            require_relative "../workstream_state"
            ws_state = Aidp::WorkstreamState.read(slug: current_ws, project_dir: @project_dir) || {}
            iter = ws_state[:iterations] || 0
            elapsed = Aidp::WorkstreamState.elapsed_seconds(slug: current_ws, project_dir: @project_dir)
            ws_fragment = "|ws:#{current_ws}:#{iter}i/#{elapsed}s"
          rescue
            ws_fragment = "|ws:#{current_ws}"
          end
        end

        prompt_text = case state
        when "RUNNING"
          "aidp[#{iteration}#{ws_fragment}]"
        when "PAUSED"
          "aidp[#{iteration}|PAUSED#{ws_fragment}]"
        when "CANCELLED"
          "aidp[#{iteration}|CANCELLED#{ws_fragment}]"
        when "IDLE"
          queued_suffix = (queued > 0) ? "+#{queued}" : ""
          "aidp[#{iteration}#{queued_suffix}#{ws_fragment}]"
        else
          "aidp[#{iteration}#{ws_fragment}]"
        end

        prompt_text += " > "
        print prompt_text
      end

      # Print REPL prompt
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
        log_rescue(e, component: "interactive_repl", action: "handle_command", fallback: "error_display", command: result[:data])
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
        log_rescue(e, component: "interactive_repl", action: "git_reset", fallback: "error_result", count: count)
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
        @prompt.say("  /skill list, /skill show <id> - Manage skills/personas")
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
