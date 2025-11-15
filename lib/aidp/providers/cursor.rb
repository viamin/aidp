# frozen_string_literal: true

require "timeout"
require_relative "base"
require_relative "../util"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class Cursor < Base
      include Aidp::DebugMixin

      def self.available?
        !!Aidp::Util.which("cursor-agent")
      end

      # Normalize Cursor's model name to family name
      #
      # Cursor may use different naming conventions (e.g., dots vs hyphens)
      #
      # @param provider_model_name [String] Cursor's model name
      # @return [String] The normalized family name
      def self.model_family(provider_model_name)
        # Normalize cursor naming to standard family names
        # cursor uses dots: "claude-3.5-sonnet" -> "claude-3-5-sonnet"
        provider_model_name.gsub(/(\d)\.(\d)/, '\1-\2')
      end

      # Convert family name to Cursor's naming convention
      #
      # @param family_name [String] The model family name
      # @return [String] Cursor's model name
      def self.provider_model_name(family_name)
        # Cursor uses dots for version numbers
        # "claude-3-5-sonnet" -> "claude-3.5-sonnet"
        family_name.gsub(/(\d)-(\d)/, '\1.\2')
      end

      # Check if this provider supports a given model family
      #
      # Cursor supports Claude, GPT, and Cursor-specific models
      #
      # @param family_name [String] The model family name
      # @return [Boolean] True if likely supported
      def self.supports_model_family?(family_name)
        family_name.match?(/^(claude|gpt|cursor)-/)
      end

      # Discover available models from Cursor
      #
      # Note: Cursor doesn't have a public model listing API
      # Returns registry-based models that match Cursor patterns
      #
      # @return [Array<Hash>] Array of discovered models
      def self.discover_models
        return [] unless available?

        begin
          require_relative "../harness/model_registry"
          registry = Aidp::Harness::ModelRegistry.new

          # Get all models from registry that Cursor might support
          models = registry.all_families.filter_map do |family|
            next unless supports_model_family?(family)

            info = registry.get_model_info(family)
            next unless info

            {
              name: provider_model_name(family),
              family: family,
              tier: info["tier"],
              capabilities: info["capabilities"] || [],
              context_window: info["context_window"],
              provider: "cursor"
            }
          end

          Aidp.log_info("cursor_provider", "using registry models", count: models.size)
          models
        rescue => e
          Aidp.log_debug("cursor_provider", "discovery failed", error: e.message)
          []
        end
      end

      def name
        "cursor"
      end

      def display_name
        "Cursor AI"
      end

      def supports_mcp?
        true
      end

      def fetch_mcp_servers
        # Try cursor-agent CLI first, then fallback to config file
        fetch_mcp_servers_cli || fetch_mcp_servers_config
      end

      def send_message(prompt:, session: nil)
        raise "cursor-agent not available" unless self.class.available?

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        debug_provider("cursor", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to cursor-agent (length: #{prompt.length})", level: :info)

        # Check if streaming mode is enabled
        streaming_enabled = ENV["AIDP_STREAMING"] == "1" || ENV["DEBUG"] == "1"
        if streaming_enabled
          display_message("📺 Display streaming enabled - output buffering reduced (cursor-agent does not support true streaming)", type: :info)
        end

        # Set up activity monitoring
        setup_activity_monitoring("cursor-agent", method(:activity_callback))
        record_activity("Starting cursor-agent execution")

        # Create a spinner for activity display
        spinner = TTY::Spinner.new("[:spinner] :title", format: :dots, hide_cursor: true)
        spinner.auto_spin

        activity_display_thread = Thread.new do
          start_time = Time.now
          loop do
            sleep 0.5 # Update every 500ms to reduce spam
            elapsed = Time.now - start_time

            # Break if we've been running too long or state changed
            break if elapsed > timeout_seconds || @activity_state == :completed || @activity_state == :failed

            update_spinner_status(spinner, elapsed, "🔄 cursor-agent")
          end
        end

        begin
          # Use debug_execute_command for better debugging
          # Use -p mode (designed for non-interactive/script use)
          # No fallback to interactive modes - they would hang AIDP's automation workflow
          result = debug_execute_command("cursor-agent", args: ["-p"], input: prompt, timeout: timeout_seconds, streaming: streaming_enabled)

          # Log the results
          debug_command("cursor-agent", args: ["-p"], input: prompt, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            spinner.success("✓")
            mark_completed
            result.out
          else
            spinner.error("✗")
            mark_failed("cursor-agent failed with exit code #{result.exit_status}")
            debug_error(StandardError.new("cursor-agent failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "cursor-agent failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          spinner&.error("✗")
          mark_failed("cursor-agent execution failed: #{e.message}")
          debug_error(e, {provider: "cursor", prompt_length: prompt.length})
          raise
        ensure
          cleanup_activity_display(activity_display_thread, spinner)
        end
      end

      private

      def activity_callback(state, message, provider)
        # This is now handled by the animated display thread
        # Only print static messages for state changes
        case state
        when :stuck
          display_message("\n⚠️  cursor appears stuck: #{message}", type: :warning)
        when :completed
          display_message("\n✅ cursor completed: #{message}", type: :success)
        when :failed
          display_message("\n❌ cursor failed: #{message}", type: :error)
        end
      end

      # Try to get MCP servers via cursor-agent CLI
      def fetch_mcp_servers_cli
        return nil unless self.class.available?

        begin
          # Try cursor-agent mcp list (if such command exists)
          result = debug_execute_command("cursor-agent", args: ["mcp", "list"], timeout: 5)
          return nil unless result.exit_status == 0

          parse_mcp_servers_output(result.out)
        rescue => e
          debug_log("Failed to fetch MCP servers via CLI: #{e.message}", level: :debug)
          nil
        end
      end

      # Fallback to reading Cursor's config file
      def fetch_mcp_servers_config
        cursor_config_path = File.expand_path("~/.cursor/mcp.json")
        return [] unless File.exist?(cursor_config_path)

        begin
          require "json"
          config_content = File.read(cursor_config_path)
          config = JSON.parse(config_content)

          servers = []
          mcp_servers = config["mcpServers"] || {}

          mcp_servers.each do |name, server_config|
            # Build command description
            command_parts = [server_config["command"]]
            command_parts.concat(server_config["args"]) if server_config["args"]
            command_description = command_parts.join(" ")

            servers << {
              name: name,
              status: "configured",
              description: command_description,
              enabled: true,
              source: "cursor_config",
              env_vars: server_config["env"] || {}
            }
          end

          servers
        rescue JSON::ParserError => e
          debug_log("Failed to parse Cursor MCP configuration: #{e.message}", level: :debug)
          []
        rescue => e
          debug_log("Failed to parse Cursor MCP configuration: #{e.message}", level: :debug)
          []
        end
      end

      # Parse MCP server output from CLI commands
      def parse_mcp_servers_output(output)
        servers = []
        return servers unless output

        lines = output.lines
        lines.reject! { |line| /checking mcp server health/i.match?(line) }

        lines.each do |line|
          line = line.strip
          next if line.empty?

          # Try to parse cursor-agent format: "name: status"
          if line =~ /^([^:]+):\s*(.+)$/
            name = Regexp.last_match(1).strip
            status = Regexp.last_match(2).strip

            servers << {
              name: name,
              status: status,
              description: "MCP server managed by cursor-agent",
              enabled: status == "ready" || status == "connected",
              source: "cursor_cli"
            }
            next
          end

          # Also try to parse extended format: "name: command - ✓ Connected" (for future compatibility)
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
              source: "cursor_cli"
            }
          end
        end

        servers
      end
    end
  end
end
