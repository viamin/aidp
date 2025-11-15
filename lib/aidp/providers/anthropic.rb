# frozen_string_literal: true

require "json"
require_relative "base"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class Anthropic < Base
      include Aidp::DebugMixin

      # Supported model families (without version dates)
      SUPPORTED_FAMILIES = [
        "claude-3-5-sonnet",
        "claude-3-5-haiku",
        "claude-3-opus",
        "claude-3-sonnet",
        "claude-3-haiku"
      ].freeze

      # Track latest version per family (updated periodically)
      LATEST_VERSIONS = {
        "claude-3-5-sonnet" => "claude-3-5-sonnet-20241022",
        "claude-3-5-haiku" => "claude-3-5-haiku-20241022",
        "claude-3-opus" => "claude-3-opus-20240229",
        "claude-3-sonnet" => "claude-3-sonnet-20240229",
        "claude-3-haiku" => "claude-3-haiku-20240307"
      }.freeze

      def self.available?
        !!Aidp::Util.which("claude")
      end

      # Normalize a provider-specific model name to its model family
      #
      # Anthropic uses date-versioned models (e.g., "claude-3-5-sonnet-20241022").
      # This method strips the date suffix to get the family name.
      #
      # @param provider_model_name [String] The versioned model name
      # @return [String] The model family name (e.g., "claude-3-5-sonnet")
      def self.model_family(provider_model_name)
        # Strip date suffix: "claude-3-5-sonnet-20241022" → "claude-3-5-sonnet"
        provider_model_name.sub(/-\d{8}$/, "")
      end

      # Convert a model family name to the provider's preferred model name
      #
      # For Anthropic, we use the latest known version for the family.
      #
      # @param family_name [String] The model family name
      # @return [String] The provider-specific model name
      def self.provider_model_name(family_name)
        LATEST_VERSIONS[family_name] || family_name
      end

      # Check if this provider supports a given model family
      #
      # @param family_name [String] The model family name
      # @return [Boolean] True if the family is supported
      def self.supports_model_family?(family_name)
        SUPPORTED_FAMILIES.include?(family_name)
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

      # ProviderAdapter interface methods

      def capabilities
        {
          reasoning_tiers: ["mini", "standard", "thinking"],
          context_window: 200_000,
          supports_json_mode: true,
          supports_tool_use: true,
          supports_vision: false,
          supports_file_upload: true,
          streaming: true
        }
      end

      def supports_dangerous_mode?
        true
      end

      def dangerous_mode_flags
        ["--dangerously-skip-permissions"]
      end

      def error_patterns
        {
          rate_limited: [
            /rate.?limit/i,
            /too.?many.?requests/i,
            /429/,
            /overloaded/i
          ],
          auth_expired: [
            /oauth.*token.*expired/i,
            /authentication.*error/i,
            /invalid.*api.*key/i,
            /unauthorized/i,
            /401/
          ],
          quota_exceeded: [
            /quota.*exceeded/i,
            /usage.*limit/i,
            /credit.*exhausted/i
          ],
          transient: [
            /timeout/i,
            /connection.*reset/i,
            /temporary.*error/i,
            /service.*unavailable/i,
            /503/,
            /502/,
            /504/
          ],
          permanent: [
            /invalid.*model/i,
            /unsupported.*operation/i,
            /not.*found/i,
            /404/,
            /bad.*request/i,
            /400/
          ]
        }
      end

      def send_message(prompt:, session: nil)
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

        # Check if we should skip permissions (devcontainer support)
        if should_skip_permissions?
          args << "--dangerously-skip-permissions"
          debug_log("🔓 Running with elevated permissions (devcontainer mode)", level: :info)
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
          when /IMPLEMENTATION/
            TIMEOUT_IMPLEMENTATION
          else
            nil # Use default
          end
        end
      end

      # Check if we should skip permissions based on devcontainer configuration
      # Overrides base class to add logging and Claude-specific config check
      def should_skip_permissions?
        # Use base class devcontainer detection
        if in_devcontainer_or_codespace?
          debug_log("🔓 Detected devcontainer/codespace environment - enabling full permissions", level: :info)
          return true
        end

        # Fallback: Check harness context for Claude-specific configuration
        if @harness_context&.config&.respond_to?(:should_use_full_permissions?)
          return @harness_context.config.should_use_full_permissions?("claude")
        end

        false
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
