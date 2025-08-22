# frozen_string_literal: true

require "open3"
require "timeout"
require_relative "base"
require_relative "../util"

module Aidp
  module Providers
    class Cursor < Base
      def self.available?
        !!Aidp::Util.which("cursor-agent")
      end

      def name = "cursor"

      def send(prompt:, session: nil)
        raise "cursor-agent not available" unless self.class.available?

        # Always use non-interactive mode with -p flag
        cmd = ["cursor-agent", "-p"]
        puts "📝 Sending prompt to cursor-agent"

        # Enable debug output if requested
        if ENV["AIDP_DEBUG"]
          puts "🔍 Debug mode enabled - showing cursor-agent output"
        end

        # Setup logging if log file is specified
        log_file = ENV["AIDP_CURSOR_LOG"]

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        puts "⏱️  Timeout set to #{timeout_seconds} seconds"

        # Set up activity monitoring
        setup_activity_monitoring("cursor-agent", method(:activity_callback))
        record_activity("Starting cursor-agent execution")

        # Start activity display thread
        activity_display_thread = Thread.new do
          loop do
            sleep 0.1 # Update every 100ms for smooth animation
            print_activity_status
            break if @activity_state == :completed || @activity_state == :failed
          end
        end

        Open3.popen3(*cmd) do |stdin, stdout, stderr, wait|
          # Send the prompt to stdin
          stdin.puts prompt
          stdin.close

          # Read stdout and stderr synchronously for better reliability
          output = ""
          error_output = ""

          # Read stdout
          stdout_thread = Thread.new do
            stdout.each_line do |line|
              output += line
              if ENV["AIDP_DEBUG"]
                clear_activity_status
                puts "📤 cursor-agent: #{line.chomp}"
                $stdout.flush # Force output to display immediately
              end
              File.write(log_file, "#{Time.now.iso8601} #{line}\n", mode: "a") if log_file

              # Record activity when we get output
              record_activity("Received output: #{line.chomp[0..50]}...")
            end
          rescue IOError => e
            puts "📤 stdout stream closed: #{e.message}" if ENV["AIDP_DEBUG"]
          end

          # Read stderr
          stderr_thread = Thread.new do
            stderr.each_line do |line|
              error_output += line
              if ENV["AIDP_DEBUG"]
                clear_activity_status
                puts "❌ cursor-agent error: #{line.chomp}"
                $stdout.flush # Force output to display immediately
              end
              File.write(log_file, "#{Time.now.iso8601} #{line}\n", mode: "a") if log_file

              # Record activity when we get error output
              record_activity("Error output: #{line.chomp[0..50]}...")
            end
          rescue IOError => e
            puts "❌ stderr stream closed: #{e.message}" if ENV["AIDP_DEBUG"]
          end

          # Start activity monitoring thread
          activity_thread = Thread.new do
            loop do
              sleep 10 # Check every 10 seconds

              if stuck?
                clear_activity_status
                puts "⚠️  cursor-agent appears stuck (no activity for #{stuck_timeout} seconds)"
                puts "   You can:"
                puts "   1. Wait longer (press Enter)"
                puts "   2. Abort (Ctrl+C)"

                # Give user a chance to respond
                begin
                  Timeout.timeout(30) do
                    gets
                    puts "🔄 Continuing to wait..."
                  end
                rescue Timeout::Error
                  puts "⏰ No response received, continuing to wait..."
                rescue Interrupt
                  puts "\n🛑 User requested abort"
                  Process.kill("TERM", wait.pid)
                  break
                end
              end

              # Stop checking if the process is done
              break if wait.value
            rescue
              break
            end
          end

          # Wait for process to complete with timeout
          begin
            # Start a timeout thread that will kill the process if it takes too long
            timeout_thread = Thread.new do
              sleep timeout_seconds
              begin
                Process.kill("TERM", wait.pid)
                sleep 2
                Process.kill("KILL", wait.pid) if wait.value.nil?
              rescue
                # Process already terminated
              end
            end

            # Wait for the process to complete
            exit_status = wait.value

            # Cancel the timeout thread since we completed successfully
            timeout_thread.kill
          rescue => e
            # Kill the timeout thread
            timeout_thread&.kill

            # Check if this was a timeout
            if e.is_a?(Timeout::Error) || execution_time >= timeout_seconds
              # Kill the process if it times out
              begin
                Process.kill("TERM", wait.pid)
                sleep 1
                Process.kill("KILL", wait.pid) if wait.value.nil?
              rescue
                # Process already terminated
              end

              # Wait for output threads to finish (with timeout)
              [stdout_thread, stderr_thread, activity_thread].each do |thread|
                thread.join(5) # Wait up to 5 seconds for each thread
              end

              # Stop activity display
              activity_display_thread.join

              clear_activity_status
              mark_failed("cursor-agent timed out after #{timeout_seconds} seconds")
              raise Timeout::Error, "cursor-agent timed out after #{timeout_seconds} seconds"
            else
              raise e
            end
          end

          # Wait for output threads to finish (with timeout)
          [stdout_thread, stderr_thread, activity_thread].each do |thread|
            thread.join(5) # Wait up to 5 seconds for each thread
          end

          # Stop activity display
          activity_display_thread.join

          clear_activity_status
          if exit_status.success?
            mark_completed
            output
          else
            mark_failed("cursor-agent failed with exit code #{exit_status.exitstatus}")
            raise "cursor-agent failed with exit code #{exit_status.exitstatus}: #{error_output}"
          end
        end
      rescue Timeout::Error
        clear_activity_status
        mark_failed("cursor-agent timed out after #{timeout_seconds} seconds")
        raise Timeout::Error, "cursor-agent timed out after #{timeout_seconds} seconds"
      rescue => e
        clear_activity_status
        mark_failed("cursor-agent execution was interrupted: #{e.message}")
        raise
      end

      private

      def calculate_timeout
        # Priority order for timeout calculation:
        # 1. Quick mode (for testing)
        # 2. Environment variable override
        # 3. Adaptive timeout based on step type
        # 4. Default timeout

        if ENV["AIDP_QUICK_MODE"]
          puts "⚡ Quick mode enabled - 2 minute timeout"
          return 120
        end

        if ENV["AIDP_CURSOR_TIMEOUT"]
          return ENV["AIDP_CURSOR_TIMEOUT"].to_i
        end

        # Adaptive timeout based on step type
        step_timeout = get_adaptive_timeout
        if step_timeout
          puts "🧠 Using adaptive timeout: #{step_timeout} seconds"
          return step_timeout
        end

        # Default timeout (5 minutes for interactive use)
        puts "📋 Using default timeout: 5 minutes"
        300
      end

      def get_adaptive_timeout
        # Try to get timeout recommendations from metrics storage
        begin
          require_relative "../analyze/metrics_storage"
          storage = Aidp::Analyze::MetricsStorage.new(Dir.pwd)
          recommendations = storage.calculate_timeout_recommendations

          # Get current step name from environment or context
          step_name = ENV["AIDP_CURRENT_STEP"] || "unknown"

          if recommendations[step_name]
            recommended = recommendations[step_name][:recommended_timeout]
            # Add 20% buffer for safety
            return (recommended * 1.2).ceil
          end
        rescue => e
          puts "⚠️  Could not get adaptive timeout: #{e.message}" if ENV["AIDP_DEBUG"]
        end

        # Fallback timeouts based on step type patterns
        step_name = ENV["AIDP_CURRENT_STEP"] || ""

        case step_name
        when /REPOSITORY_ANALYSIS/
          180  # 3 minutes - repository analysis can be quick
        when /ARCHITECTURE_ANALYSIS/
          600  # 10 minutes - architecture analysis needs more time
        when /TEST_ANALYSIS/
          300  # 5 minutes - test analysis is moderate
        when /FUNCTIONALITY_ANALYSIS/
          600  # 10 minutes - functionality analysis is complex
        when /DOCUMENTATION_ANALYSIS/
          300  # 5 minutes - documentation analysis is moderate
        when /STATIC_ANALYSIS/
          450  # 7.5 minutes - static analysis can be intensive
        when /REFACTORING_RECOMMENDATIONS/
          600  # 10 minutes - refactoring recommendations are complex
        else
          nil  # Use default
        end
      end

      def activity_callback(state, message, provider)
        # This is now handled by the animated display thread
        # Only print static messages for state changes
        case state
        when :stuck
          puts "\n⚠️  cursor appears stuck: #{message}"
        when :completed
          puts "\n✅ cursor completed: #{message}"
        when :failed
          puts "\n❌ cursor failed: #{message}"
        end
      end
    end
  end
end
