# frozen_string_literal: true

require "json"
require_relative "base"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class Anthropic < Base
      include Aidp::DebugMixin

      def self.available?
        !!Aidp::Util.which("claude")
      end

      def name
        "anthropic"
      end

      def display_name
        "Anthropic Claude CLI"
      end

      def supports_mcp?
        true
      end

      def fetch_mcp_servers
        return [] unless self.class.available?

        begin
          # Use claude mcp list command
          result = debug_execute_command("claude", args: ["mcp", "list"], timeout: 5)
          return [] unless result.exit_status == 0

          parse_claude_mcp_output(result.out)
        rescue => e
          debug_log("Failed to fetch MCP servers via Claude CLI: #{e.message}", level: :debug)
          []
        end
      end

      def available?
        self.class.available?
      end

      def send(prompt:, session: nil)
        raise "claude CLI not available" unless self.class.available?

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        debug_provider("claude", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to claude...", level: :info)

        # Check if streaming mode is enabled
        streaming_enabled = ENV["AIDP_STREAMING"] == "1" || ENV["DEBUG"] == "1"

        # Build command arguments with proper streaming support
        args = ["--print"]
        if streaming_enabled
          # Claude CLI requires --verbose when using --print with --output-format=stream-json
          args += ["--verbose", "--output-format=stream-json", "--include-partial-messages"]
          display_message("📺 True streaming enabled - real-time chunks from Claude API", type: :info)
        else
          # Use text format for non-streaming (default behavior)
          args += ["--output-format=text"]
        end

        begin
          # Use debug_execute_command with streaming support
          result = debug_execute_command("claude", args: args, input: prompt, timeout: timeout_seconds, streaming: streaming_enabled)

          # Log the results
          debug_command("claude", args: args, input: prompt, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            # Handle different output formats
            if streaming_enabled && args.include?("--output-format=stream-json")
              # Parse stream-json output and extract final content
              parse_stream_json_output(result.out)
            else
              # Return text output as-is
              result.out
            end
          else
            # Detect auth issues in stdout/stderr (Claude sometimes prints JSON with auth error to stdout)
            combined = [result.out, result.err].compact.join("\n")
            if combined.downcase.include?("oauth token has expired") || combined.downcase.include?("authentication_error")
              error_message = "Authentication error from Claude CLI: token expired or invalid. Run 'claude /login' or refresh credentials."
              debug_error(StandardError.new(error_message), {exit_code: result.exit_status, stdout: result.out, stderr: result.err})
              # Raise a recognizable error for classifier
              raise error_message
            end

            debug_error(StandardError.new("claude failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "claude failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          debug_error(e, {provider: "claude", prompt_length: prompt.length})
          raise
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
          display_message("⚡ Quick mode enabled - #{TIMEOUT_QUICK_MODE / 60} minute timeout", type: :highlight)
          return TIMEOUT_QUICK_MODE
        end

        if ENV["AIDP_ANTHROPIC_TIMEOUT"]
          return ENV["AIDP_ANTHROPIC_TIMEOUT"].to_i
        end

        if adaptive_timeout
          display_message("🧠 Using adaptive timeout: #{adaptive_timeout} seconds", type: :info)
          return adaptive_timeout
        end

        # Default timeout
        display_message("📋 Using default timeout: #{TIMEOUT_DEFAULT / 60} minutes", type: :info)
        TIMEOUT_DEFAULT
      end

      def adaptive_timeout
        @adaptive_timeout ||= begin
          # Timeout recommendations based on step type patterns
          step_name = ENV["AIDP_CURRENT_STEP"] || ""

          case step_name
          when /REPOSITORY_ANALYSIS/
            TIMEOUT_REPOSITORY_ANALYSIS
          when /ARCHITECTURE_ANALYSIS/
            TIMEOUT_ARCHITECTURE_ANALYSIS
          when /TEST_ANALYSIS/
            TIMEOUT_TEST_ANALYSIS
          when /FUNCTIONALITY_ANALYSIS/
            TIMEOUT_FUNCTIONALITY_ANALYSIS
          when /DOCUMENTATION_ANALYSIS/
            TIMEOUT_DOCUMENTATION_ANALYSIS
          when /STATIC_ANALYSIS/
            TIMEOUT_STATIC_ANALYSIS
          when /REFACTORING_RECOMMENDATIONS/
            TIMEOUT_REFACTORING_RECOMMENDATIONS
          else
            nil # Use default
          end
        end
      end

      # Parse stream-json output from Claude CLI
      def parse_stream_json_output(output)
        return output if output.nil? || output.empty?

        # Stream-json output contains multiple JSON objects, one per line
        # We want to extract the final content from the last complete message
        lines = output.strip.split("\n")
        content_parts = []

        lines.each do |line|
          next if line.strip.empty?

          begin
            json_obj = JSON.parse(line)

            # Look for content in various possible structures
            if json_obj["type"] == "content_block_delta" && json_obj["delta"] && json_obj["delta"]["text"]
              content_parts << json_obj["delta"]["text"]
            elsif json_obj["content"]&.is_a?(Array)
              json_obj["content"].each do |content_item|
                content_parts << content_item["text"] if content_item["text"]
              end
            elsif json_obj["message"] && json_obj["message"]["content"]
              if json_obj["message"]["content"].is_a?(Array)
                json_obj["message"]["content"].each do |content_item|
                  content_parts << content_item["text"] if content_item["text"]
                end
              elsif json_obj["message"]["content"].is_a?(String)
                content_parts << json_obj["message"]["content"]
              end
            end
          rescue JSON::ParserError => e
            debug_log("⚠️ Failed to parse JSON line: #{e.message}", level: :warn, data: {line: line})
            # If JSON parsing fails, treat as plain text
            content_parts << line
          end
        end

        result = content_parts.join

        # Fallback: if no content found in JSON, return original output
        result.empty? ? output : result
      rescue => e
        debug_log("⚠️ Failed to parse stream-json output: #{e.message}", level: :warn)
        # Return original output if parsing fails
        output
      end

      # Parse Claude MCP server list output
      def parse_claude_mcp_output(output)
        servers = []
        return servers unless output

        lines = output.lines
        lines.reject! { |line| /checking mcp server health/i.match?(line) }

        lines.each do |line|
          line = line.strip
          next if line.empty?

          # Try to parse Claude format: "name: command - ✓ Connected"
          if line =~ /^([^:]+):\s*(.+?)\s*-\s*(✓|✗)\s*(.+)$/
            name = Regexp.last_match(1).strip
            command = Regexp.last_match(2).strip
            status_symbol = Regexp.last_match(3)
            status_text = Regexp.last_match(4).strip

            servers << {
              name: name,
              status: (status_symbol == "✓") ? "connected" : "error",
              description: command,
              enabled: status_symbol == "✓",
              error: (status_symbol == "✗") ? status_text : nil,
              source: "claude_cli"
            }
            next
          end

          # Try to parse legacy table format
          next if /Name.*Status/i.match?(line)
          next if /^[-=]+$/.match?(line)

          parts = line.split(/\s{2,}/)
          next if parts.size < 2

          name = parts[0]&.strip
          status = parts[1]&.strip
          description = parts[2..]&.join(" ")&.strip

          next unless name && !name.empty?

          servers << {
            name: name,
            status: status || "unknown",
            description: description,
            enabled: status&.downcase == "enabled" || status&.downcase == "connected",
            source: "claude_cli"
          }
        end

        servers
      end
    end
  end
end
