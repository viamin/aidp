# frozen_string_literal: true

require "json"
require "yaml"
require "fileutils"

module Aidp
  module Harness
    # Stores detailed information about AI providers gathered from their CLI tools
    class ProviderInfo
      attr_reader :provider_name, :info_file_path

      def initialize(provider_name, root_dir = nil)
        @provider_name = provider_name
        @root_dir = root_dir || Dir.pwd
        @info_file_path = File.join(@root_dir, ".aidp", "providers", "#{provider_name}_info.yml")
        ensure_directory_exists
      end

      # Gather information about the provider by introspecting its CLI
      def gather_info
        info = {
          provider: @provider_name,
          last_checked: Time.now.iso8601,
          cli_available: false,
          help_output: nil,
          capabilities: {},
          permission_modes: [],
          mcp_support: false,
          mcp_servers: [],
          auth_method: nil,
          flags: {}
        }

        # Try to get help output from the provider CLI
        help_output = fetch_help_output
        if help_output
          info[:cli_available] = true
          info[:help_output] = help_output
          info.merge!(parse_help_output(help_output))
        end

        # Try to get MCP server list if supported
        if info[:mcp_support]
          mcp_servers = fetch_mcp_servers
          info[:mcp_servers] = mcp_servers if mcp_servers
        end

        save_info(info)
        info
      end

      # Load stored provider info
      def load_info
        return nil unless File.exist?(@info_file_path)

        YAML.safe_load_file(@info_file_path, permitted_classes: [Time, Symbol])
      rescue => e
        warn "Failed to load provider info for #{@provider_name}: #{e.message}"
        nil
      end

      # Get provider info, refreshing if needed
      def info(force_refresh: false, max_age: 86400)
        existing_info = load_info

        # Refresh if forced, missing, or stale
        if force_refresh || existing_info.nil? || info_stale?(existing_info, max_age)
          gather_info
        else
          existing_info
        end
      end

      # Check if provider supports MCP servers
      def supports_mcp?
        info = load_info
        return false unless info

        info[:mcp_support] == true
      end

      # Get permission modes available
      def permission_modes
        info = load_info
        return [] unless info

        info[:permission_modes] || []
      end

      # Get authentication method
      def auth_method
        info = load_info
        return nil unless info

        info[:auth_method]
      end

      # Get available flags/options
      def available_flags
        info = load_info
        return {} unless info

        info[:flags] || {}
      end

      # Get configured MCP servers
      def mcp_servers
        info = load_info
        return [] unless info

        info[:mcp_servers] || []
      end

      # Check if provider has MCP servers configured
      def has_mcp_servers?
        mcp_servers.any?
      end

      private

      def ensure_directory_exists
        dir = File.dirname(@info_file_path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end

      def save_info(info)
        File.write(@info_file_path, YAML.dump(info))
      end

      def info_stale?(info, max_age)
        return true unless info[:last_checked]

        last_checked = Time.parse(info[:last_checked].to_s)
        (Time.now - last_checked) > max_age
      rescue
        true
      end

      def fetch_help_output
        execute_provider_command("--help")
      end

      def fetch_mcp_servers
        # Use the provider class to fetch MCP servers
        return [] unless provider_instance

        provider_instance.fetch_mcp_servers
      rescue => e
        warn "Failed to fetch MCP servers for #{@provider_name}: #{e.message}" if ENV["AIDP_DEBUG"]
        []
      end

      def execute_provider_command(*args)
        return nil unless binary_name

        # Try to find the binary
        path = begin
          Aidp::Util.which(binary_name)
        rescue
          nil
        end
        return nil unless path

        # Execute command with timeout
        begin
          r, w = IO.pipe
          pid = Process.spawn(binary_name, *args, out: w, err: w)
          w.close

          # Wait with timeout
          deadline = Time.now + 5
          status = nil
          while Time.now < deadline
            pid_done, status = Process.waitpid2(pid, Process::WNOHANG)
            break if pid_done
            sleep 0.05
          end

          # Kill if timed out
          unless status
            begin
              Process.kill("TERM", pid)
              sleep 0.1
              Process.kill("KILL", pid)
            rescue
              nil
            end
            return nil
          end

          output = r.read
          r.close
          output
        rescue
          nil
        end
      end

      def parse_mcp_servers(output)
        servers = []
        return servers unless output

        # Parse MCP server list output
        # Claude format (as of 2025):
        # dash-api: uvx --from git+https://... - ✓ Connected
        # or
        # server-name: command - ✗ Error message
        #
        # Legacy format:
        # Name              Status    Description
        # filesystem        enabled   File system access

        lines = output.lines

        # Skip header lines
        lines.reject! { |line| /checking mcp server health/i.match?(line) }

        lines.each do |line|
          line = line.strip
          next if line.empty?

          # Try to parse new Claude format: "name: command - ✓ Connected"
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
              error: (status_symbol == "✗") ? status_text : nil
            }
            next
          end

          # Try to parse legacy table format
          # Skip header line
          next if /Name.*Status/i.match?(line)
          next if /^[-=]+$/.match?(line) # Skip separator lines

          # Parse table format: columns separated by multiple spaces
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
            enabled: status&.downcase == "enabled" || status&.downcase == "connected"
          }
        end

        servers
      end

      def binary_name
        case @provider_name
        when "claude", "anthropic"
          "claude"
        when "cursor"
          "cursor-agent"  # Use cursor-agent CLI, not cursor IDE shortcut
        when "gemini"
          "gemini"
        when "codex"
          "codex"
        when "github_copilot"
          "gh"
        when "opencode"
          "opencode"
        else
          @provider_name
        end
      end

      def parse_help_output(help_text)
        parsed = {
          capabilities: {},
          permission_modes: [],
          mcp_support: false,
          auth_method: nil,
          flags: {}
        }

        # Check for MCP support using provider class
        provider_inst = provider_instance
        parsed[:mcp_support] = if provider_inst
          provider_inst.supports_mcp?
        else
          # Fallback to text-based detection
          !!(help_text =~ /mcp|MCP|Model Context Protocol/i)
        end

        # Extract permission modes
        if help_text =~ /--permission-mode\s+<mode>\s+.*?\(choices:\s*([^)]+)\)/m
          modes = Regexp.last_match(1).split(",").map(&:strip).map { |m| m.gsub(/["']/, "") }
          parsed[:permission_modes] = modes
        end

        # Check for dangerous skip permissions
        parsed[:capabilities][:bypass_permissions] = !!(help_text =~ /--dangerously-skip-permissions/)

        # Check for API key / subscription patterns
        if /--api-key|API_KEY|setup-token|subscription/i.match?(help_text)
          parsed[:auth_method] = if /setup-token|subscription/i.match?(help_text)
            "subscription"
          else
            "api_key"
          end
        end

        # Extract model configuration
        parsed[:capabilities][:model_selection] = !!(help_text =~ /--model\s+<model>/)

        # Extract MCP configuration
        parsed[:capabilities][:mcp_config] = !!(help_text =~ /--mcp-config/)

        # Extract allowed/disallowed tools
        parsed[:capabilities][:tool_restrictions] = !!(help_text =~ /--allowed-tools|--disallowed-tools/)

        # Extract session management
        parsed[:capabilities][:session_management] = !!(help_text =~ /--continue|--resume|--fork-session/)

        # Extract output formats
        if help_text =~ /--output-format\s+.*?\(choices:\s*([^)]+)\)/m
          formats = Regexp.last_match(1).split(",").map(&:strip).map { |f| f.gsub(/["']/, "") }
          parsed[:capabilities][:output_formats] = formats
        end

        # Extract notable flags
        extract_flags(help_text, parsed[:flags])

        parsed
      end

      # Get provider instance for MCP operations
      def provider_instance
        return @provider_instance if @provider_instance

        # Load provider factory and get provider class
        require_relative "provider_factory"

        provider_class = Aidp::Harness::ProviderFactory::PROVIDER_CLASSES[@provider_name]
        return nil unless provider_class

        # Create provider instance
        @provider_instance = provider_class.new
      rescue => e
        warn "Failed to create provider instance for #{@provider_name}: #{e.message}" if ENV["AIDP_DEBUG"]
        nil
      end

      def extract_flags(help_text, flags_hash)
        # Extract all flags with their descriptions
        help_text.scan(/^\s+(--[\w-]+(?:\s+<\w+>)?)\s+(.+?)(?=^\s+(?:--|\w|$))/m).each do |flag, desc|
          flag_name = flag.split.first.gsub(/^--/, "")
          flags_hash[flag_name] = {
            flag: flag.strip,
            description: desc.strip.gsub(/\s+/, " ")
          }
        end

        # Also capture short flags
        help_text.scan(/^\s+(-\w),\s+(--[\w-]+(?:\s+<\w+>)?)\s+(.+?)(?=^\s+(?:--|-\w|$))/m).each do |short, long, desc|
          flag_name = long.split.first.gsub(/^--/, "")
          flags_hash[flag_name] ||= {}
          flags_hash[flag_name][:short] = short
          flags_hash[flag_name][:flag] = long.strip
          flags_hash[flag_name][:description] = desc.strip.gsub(/\s+/, " ")
        end
      end
    end
  end
end
