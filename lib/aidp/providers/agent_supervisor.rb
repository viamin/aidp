# frozen_string_literal: true

require "timeout"
require "open3"

module Aidp
  module Providers
    # Supervisor for managing agent execution with progressive warnings instead of hard timeouts
    class AgentSupervisor
      # Execution states
      STATES = {
        idle: "⏳",
        starting: "🚀",
        running: "🔄",
        warning: "⚠️",
        user_aborted: "🛑",
        completed: "✅",
        failed: "❌"
      }.freeze

      attr_reader :state, :start_time, :end_time, :duration, :output, :error_output, :exit_code

      def initialize(command, timeout_seconds: 300, debug: false)
        @command = command
        @timeout_seconds = timeout_seconds
        @debug = debug
        @state = :idle
        @start_time = nil
        @end_time = nil
        @duration = 0
        @output = ""
        @error_output = ""
        @exit_code = nil
        @process_pid = nil
        @output_count = 0
        @last_output_time = nil
        @supervisor_thread = nil
        @output_threads = []
        @warning_shown = false
        @user_aborted = false
      end

      # Execute the command with supervision
      def execute(input = nil)
        @state = :starting
        @start_time = Time.now
        @last_output_time = @start_time

        puts "🚀 Starting agent execution (will warn at #{@timeout_seconds}s)"

        begin
          # Start the process
          Open3.popen3(*@command) do |stdin, stdout, stderr, wait|
            @process_pid = wait.pid
            @state = :running

            # Send input if provided
            if input
              stdin.puts input
              stdin.close
            end

            # Start timeout thread that will warn but not kill
            timeout_thread = Thread.new do
              sleep @timeout_seconds
              if @state == :running && !@warning_shown
                show_timeout_warning
              end
            end

            # Start supervisor thread
            start_supervisor_thread(wait)

            # Start output collection threads
            start_output_threads(stdout, stderr)

            # Wait for completion
            result = wait_for_completion(wait)

            # Kill timeout thread since we're done
            timeout_thread.kill

            # Clean up threads
            cleanup_threads

            @end_time = Time.now
            @duration = @end_time - @start_time

            return result
          end
        rescue => e
          @state = :failed
          @end_time = Time.now
          @duration = @end_time - @start_time if @start_time
          puts "❌ Agent execution failed: #{e.message}"
          raise
        end
      end

      # Get current execution status
      def status
        elapsed = @start_time ? Time.now - @start_time : 0
        minutes = (elapsed / 60).to_i
        seconds = (elapsed % 60).to_i
        time_str = (minutes > 0) ? "#{minutes}m #{seconds}s" : "#{seconds}s"

        case @state
        when :idle
          "⏳ Idle"
        when :starting
          "🚀 Starting..."
        when :running
          output_info = (@output_count > 0) ? " (#{@output_count} outputs)" : ""
          "🔄 Running #{time_str}#{output_info}"
        when :warning
          "⚠️ Taking longer than expected #{time_str}"
        when :user_aborted
          "🛑 Aborted by user after #{time_str}"
        when :completed
          "✅ Completed in #{time_str}"
        when :failed
          "❌ Failed after #{time_str}"
        end
      end

      # Check if execution is still active
      def active?
        [:starting, :running, :warning].include?(@state)
      end

      # Check if execution completed successfully
      def success?
        @state == :completed && @exit_code == 0
      end

      # Show timeout warning and give user control
      def show_timeout_warning
        return if @warning_shown
        @warning_shown = true
        @state = :warning

        puts "\n⚠️  Agent has been running for #{@timeout_seconds} seconds"
        puts "   This is longer than expected, but the agent may still be working."
        puts "   You can:"
        puts "   1. Continue waiting (press Enter)"
        puts "   2. Abort execution (type 'abort' and press Enter)"
        puts "   3. Wait 5 more minutes (type 'wait' and press Enter)"

        begin
          Timeout.timeout(30) do
            response = gets&.chomp&.downcase
            case response
            when "abort"
              puts "🛑 Aborting execution..."
              @user_aborted = true
              @state = :user_aborted
              kill!
            when "wait"
              puts "⏰ Will warn again in 5 minutes..."
              @warning_shown = false
              @state = :running
              # Start another warning thread for 5 more minutes
              Thread.new do
                sleep 300 # 5 minutes
                if @state == :running && !@warning_shown
                  show_timeout_warning
                end
              end
            else
              puts "🔄 Continuing to wait..."
              @state = :running
            end
          end
        rescue Timeout::Error
          puts "⏰ No response received, continuing to wait..."
          @state = :running
        rescue Interrupt
          puts "\n🛑 User interrupted, aborting..."
          @user_aborted = true
          @state = :user_aborted
          kill!
        end
      end

      # Force kill the process
      def kill!
        return unless @process_pid && active?

        puts "💀 Force killing agent process (PID: #{@process_pid})"

        begin
          # Try graceful termination first
          Process.kill("TERM", @process_pid)
          sleep 1

          # Force kill if still running
          if process_running?(@process_pid)
            Process.kill("KILL", @process_pid)
            sleep 1
          end

          # Double-check and force kill again if needed
          if process_running?(@process_pid)
            puts "⚠️ Process still running, using SIGKILL..."
            Process.kill("KILL", @process_pid)
            sleep 1
          end

          @state = :user_aborted
        rescue Errno::ESRCH
          # Process already dead
          @state = :user_aborted
        rescue => e
          puts "⚠️ Error killing process: #{e.message}"
          # Try one more time with KILL
          begin
            Process.kill("KILL", @process_pid) if process_running?(@process_pid)
          rescue
            # Give up
          end
        end
      end

      private

      def start_supervisor_thread(wait)
        @supervisor_thread = Thread.new do
          loop do
            sleep 10 # Check every 10 seconds

            # Check if process is done
            if wait.value
              break
            end

            # Check for stuck condition (no output for 3 minutes)
            if @last_output_time && Time.now - @last_output_time > 180
              puts "⚠️ Agent appears stuck (no output for 3+ minutes)"
              # Don't kill, just warn
            end
          end
        rescue => e
          puts "⚠️ Supervisor thread error: #{e.message}" if @debug
        end

        @supervisor_thread
      end

      def start_output_threads(stdout, stderr)
        # Stdout thread
        @output_threads << Thread.new do
          stdout.each_line do |line|
            @output += line
            @output_count += 1
            @last_output_time = Time.now

            if @debug
              puts "📤 #{line.chomp}"
            end
          end
        rescue IOError => e
          puts "📤 stdout closed: #{e.message}" if @debug
        rescue => e
          puts "⚠️ stdout thread error: #{e.message}" if @debug
        end

        # Stderr thread
        @output_threads << Thread.new do
          stderr.each_line do |line|
            @error_output += line
            @output_count += 1
            @last_output_time = Time.now

            if @debug
              puts "❌ #{line.chomp}"
            end
          end
        rescue IOError => e
          puts "❌ stderr closed: #{e.message}" if @debug
        rescue => e
          puts "⚠️ stderr thread error: #{e.message}" if @debug
        end
      end

      def wait_for_completion(wait)
        # Wait for process to complete
        exit_status = wait.value
        @exit_code = exit_status.exitstatus

        # Update duration
        @duration = Time.now - @start_time

        if @user_aborted || @state == :user_aborted
          # Process was killed by user
          {
            success: false,
            state: @state,
            output: @output,
            error_output: @error_output,
            exit_code: @exit_code,
            duration: @duration,
            reason: "user_aborted"
          }
        elsif exit_status.success?
          @state = :completed
          {
            success: true,
            state: @state,
            output: @output,
            error_output: @error_output,
            exit_code: @exit_code,
            duration: @duration
          }
        else
          @state = :failed
          {
            success: false,
            state: @state,
            output: @output,
            error_output: @error_output,
            exit_code: @exit_code,
            duration: @duration,
            reason: "non_zero_exit"
          }
        end
      end

      def cleanup_threads
        # Wait for output threads to finish (with timeout)
        @output_threads.each do |thread|
          thread.join(5) # Wait up to 5 seconds
        rescue => e
          puts "⚠️ Error joining thread: #{e.message}" if @debug
        end

        # Kill supervisor thread
        @supervisor_thread&.kill
      end

      def process_running?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      end
    end
  end
end
