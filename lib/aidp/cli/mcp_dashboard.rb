# frozen_string_literal: true

require "tty-table"
require_relative "../harness/provider_info"
require_relative "../harness/configuration"

module Aidp
  class CLI
    # Dashboard for viewing MCP servers across all providers
    class McpDashboard
      include Aidp::MessageDisplay

      def initialize(root_dir = nil, configuration: nil, provider_info_class: Aidp::Harness::ProviderInfo)
        @root_dir = root_dir || Dir.pwd
        @configuration = configuration || Aidp::Harness::Configuration.new(@root_dir)
        @provider_info_class = provider_info_class
      end

      # Display MCP dashboard showing all servers across all providers
      def display_dashboard(options = {})
        no_color = options[:no_color] || false

        # Gather MCP server information from all providers
        server_matrix = build_server_matrix

        # Display summary
        display_message("MCP Server Dashboard", type: :highlight)
        display_message("=" * 80, type: :muted)
        display_message("", type: :info)

        # Check if there are any MCP-capable providers
        if server_matrix[:providers].empty?
          display_message("No providers with MCP support configured.", type: :info)
          display_message("MCP is supported by providers like: claude", type: :muted)
          display_message("\n" + "=" * 80, type: :muted)
          return
        end

        # Check if there are any MCP servers configured
        if server_matrix[:servers].empty?
          display_message("No MCP servers configured across any providers.", type: :info)
          display_message("Add MCP servers with: claude mcp add <name> -- <command>", type: :muted)
          display_message("\n" + "=" * 80, type: :muted)
          return
        end

        # Display the main table
        display_server_table(server_matrix, no_color)

        # Display eligibility warnings
        display_eligibility_warnings(server_matrix)

        display_message("\n" + "=" * 80, type: :muted)
      end

      # Get MCP server availability for a specific task requirement
      def check_task_eligibility(required_servers)
        server_matrix = build_server_matrix
        eligible_providers = []

        @configuration.provider_names.each do |provider|
          provider_servers = server_matrix[:provider_servers][provider] || []
          enabled_servers = provider_servers.select { |s| s[:enabled] }.map { |s| s[:name] }

          # Check if provider has all required servers
          if required_servers.all? { |req| enabled_servers.include?(req) }
            eligible_providers << provider
          end
        end

        {
          required_servers: required_servers,
          eligible_providers: eligible_providers,
          total_providers: @configuration.provider_names.size
        }
      end

      # Display eligibility check for specific servers
      def display_task_eligibility(required_servers)
        result = check_task_eligibility(required_servers)

        display_message("\nTask Eligibility Check", type: :highlight)
        display_message("Required MCP Servers: #{required_servers.join(", ")}", type: :info)
        display_message("", type: :info)

        if result[:eligible_providers].any?
          display_message("✓ Eligible Providers (#{result[:eligible_providers].size}/#{result[:total_providers]}):", type: :success)
          result[:eligible_providers].each do |provider|
            display_message("  • #{provider}", type: :success)
          end
        else
          display_message("✗ No providers have all required MCP servers", type: :error)
          display_message("  Consider configuring MCP servers for at least one provider", type: :warning)
        end
      end

      private

      def build_server_matrix
        providers = @configuration.provider_names
        all_servers = {} # server_name => {providers: {provider_name => server_info}}
        provider_servers = {} # provider_name => [server_info]

        providers.each do |provider|
          provider_info = @provider_info_class.new(provider, @root_dir)
          info = provider_info.info

          next unless info[:mcp_support]

          servers = info[:mcp_servers] || []
          provider_servers[provider] = servers

          servers.each do |server|
            server_name = server[:name]
            all_servers[server_name] ||= {providers: {}}
            all_servers[server_name][:providers][provider] = server
          end
        end

        {
          servers: all_servers,
          provider_servers: provider_servers,
          providers: providers.select { |p| provider_servers.key?(p) }
        }
      end

      def display_server_table(matrix, no_color)
        # Check if we have any providers with MCP support
        if matrix[:providers].empty?
          display_message("No providers with MCP support configured.", type: :info)
          return
        end

        # Build table rows
        headers = ["MCP Server"] + matrix[:providers].map { |p| normalize_provider_name(p) }
        rows = []

        matrix[:servers].keys.sort.each do |server_name|
          row = [server_name]

          matrix[:providers].each do |provider|
            server = matrix[:servers][server_name][:providers][provider]
            cell = if server
              format_server_status(server, no_color)
            else
              (no_color || !$stdout.tty?) ? "-" : "\e[90m-\e[0m"
            end
            row << cell
          end

          rows << row
        end

        # Create and display table
        table = TTY::Table.new(headers, rows)
        display_message(table.render(:basic), type: :info)
        display_message("", type: :info)

        # Legend
        display_legend(no_color)
      end

      def format_server_status(server, no_color)
        if no_color || !$stdout.tty?
          server[:enabled] ? "✓" : "✗"
        elsif server[:enabled]
          "\e[32m✓\e[0m" # Green checkmark
        else
          "\e[31m✗\e[0m" # Red X
        end
      end

      def display_legend(no_color)
        if no_color || !$stdout.tty?
          display_message("Legend: ✓ = Enabled  ✗ = Error/Disabled  - = Not configured", type: :muted)
        else
          display_message("Legend: \e[32m✓\e[0m = Enabled  \e[31m✗\e[0m = Error/Disabled  \e[90m-\e[0m = Not configured", type: :muted)
        end
      end

      def display_eligibility_warnings(matrix)
        # Find servers that are only configured on some providers
        partially_configured = matrix[:servers].select do |_name, info|
          configured_count = info[:providers].size
          configured_count > 0 && configured_count < matrix[:providers].size
        end

        return if partially_configured.empty?

        display_message("\n⚠ Eligibility Warnings:", type: :warning)
        partially_configured.each do |server_name, info|
          missing_providers = matrix[:providers] - info[:providers].keys
          if missing_providers.any?
            display_message("  • '#{server_name}' not configured on: #{missing_providers.join(", ")}", type: :warning)
            display_message("    These providers won't be eligible for tasks requiring this MCP server", type: :muted)
          end
        end
      end

      def normalize_provider_name(name)
        return "claude" if name == "anthropic"
        name
      end
    end
  end
end
