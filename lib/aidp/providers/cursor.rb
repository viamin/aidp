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
        log_file = ENV["AIDP_LOG_FILE"]
        if log_file
          puts "📝 Logging to: #{log_file}"
        end

        Open3.popen3(*cmd) do |stdin, stdout, stderr, wait|
          # Send the prompt to stdin
          stdin.puts prompt
          stdin.close

          # Log the prompt if debugging
          if ENV["AIDP_DEBUG"] || log_file
            prompt_log = "📝 Sending prompt to cursor-agent:\n#{prompt}"
            puts prompt_log if ENV["AIDP_DEBUG"]
            File.write(log_file, "#{Time.now.iso8601} #{prompt_log}\n", mode: "a") if log_file
          end

          # Handle debug output and logging
          if ENV["AIDP_DEBUG"] || log_file
            # Start threads to capture and display output in real-time
            stdout_thread = Thread.new do
              stdout.each_line do |line|
                output = "📤 cursor-agent: #{line.chomp}"
                puts output if ENV["AIDP_DEBUG"]
                File.write(log_file, "#{Time.now.iso8601} #{output}\n", mode: "a") if log_file
              end
            end

            stderr_thread = Thread.new do
              stderr.each_line do |line|
                output = "❌ cursor-agent error: #{line.chomp}"
                puts output if ENV["AIDP_DEBUG"]
                File.write(log_file, "#{Time.now.iso8601} #{output}\n", mode: "a") if log_file
              end
            end
          end

          # Wait for completion with a reasonable timeout
          begin
            Timeout.timeout(300) do # 5 minutes timeout
              result = wait.value

              # Stop debug threads
              if ENV["AIDP_DEBUG"]
                stdout_thread&.kill
                stderr_thread&.kill
              end

              return :ok if result.success?
              raise "cursor-agent failed with exit code #{result.exitstatus}"
            end
          rescue Timeout::Error
            # Stop debug threads
            if ENV["AIDP_DEBUG"]
              stdout_thread&.kill
              stderr_thread&.kill
            end

            # Kill the process if it's taking too long
            begin
              Process.kill("TERM", wait.pid)
            rescue
              nil
            end
            raise Timeout::Error, "cursor-agent timed out after 5 minutes"
          end
        end
      end
    end
  end
end
