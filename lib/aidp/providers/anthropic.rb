# frozen_string_literal: true

require_relative "base"

module Aidp
  module Providers
    class Anthropic < Base
      def self.available?
        !!Aidp::Util.which("claude")
      end

      def name = "anthropic"

      def send(prompt:, session: nil)
        raise "claude CLI not available" unless self.class.available?

        require "open3"

        # Use Claude CLI for non-interactive mode
        cmd = ["claude", "--print"]

        puts "📝 Sending prompt to claude..."

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        Open3.popen3(*cmd) do |stdin, stdout, stderr, wait|
          # Send the prompt to stdin
          stdin.puts prompt
          stdin.close

          # Start stuck detection thread
          stuck_detection_thread = Thread.new do
            loop do
              sleep 10 # Check every 10 seconds

              if stuck?
                puts "⚠️  claude appears stuck (no activity for #{stuck_timeout} seconds)"
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
                  puts "🛑 Aborting claude..."
                  Process.kill("TERM", wait.pid)
                  raise Interrupt, "User aborted claude execution"
                end
              end

              # Stop checking if the process is done
              break if wait.value
            end
          end

          # Wait for completion with timeout
          begin
            Timeout.timeout(timeout_seconds) do
              result = wait.value

              # Stop stuck detection thread
              stuck_detection_thread&.kill

              if result.success?
                output = stdout.read
                puts "✅ Claude analysis completed"
                mark_completed
                return output.empty? ? :ok : output
              else
                error_output = stderr.read
                mark_failed("claude failed with exit code #{result.exitstatus}: #{error_output}")
                raise "claude failed with exit code #{result.exitstatus}: #{error_output}"
              end
            end
          rescue Timeout::Error
            # Stop stuck detection thread
            stuck_detection_thread&.kill

            # Kill the process if it's taking too long
            begin
              Process.kill("TERM", wait.pid)
            rescue Errno::ESRCH
              # Process already terminated
            end

            mark_failed("claude timed out after #{timeout_seconds} seconds")
            raise Timeout::Error, "claude timed out after #{timeout_seconds} seconds"
          rescue Interrupt
            # Stop stuck detection thread
            stuck_detection_thread&.kill

            # Kill the process
            begin
              Process.kill("TERM", wait.pid)
            rescue Errno::ESRCH
              # Process already terminated
            end

            mark_failed("claude execution was interrupted")
            raise
          end
        end
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

        if ENV["AIDP_ANTHROPIC_TIMEOUT"]
          return ENV["AIDP_ANTHROPIC_TIMEOUT"].to_i
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
    end
  end
end
