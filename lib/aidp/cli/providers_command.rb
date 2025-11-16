# frozen_string_literal: true

require "tty-table"
require "tty-prompt"
require "tty-spinner"
require_relative "../harness/provider_info"
require_relative "../harness/capability_registry"
require_relative "../harness/config_manager"

module Aidp
  class CLI
    # Command handler for `aidp providers info` and `aidp providers refresh` subcommands
    #
    # Provides commands for viewing and managing provider information:
    #   - info: Show detailed information about a specific provider or models catalog
    #   - refresh: Refresh provider information cache
    #
    # Usage:
    #   aidp providers info <provider> [--refresh]
    #   aidp providers refresh [<provider>]
    class ProvidersCommand
      include Aidp::MessageDisplay

      def initialize(prompt: TTY::Prompt.new, provider_info_class: nil, capability_registry_class: nil, config_manager_class: nil, project_dir: nil)
        @prompt = prompt
        @provider_info_class = provider_info_class || Aidp::Harness::ProviderInfo
        @capability_registry_class = capability_registry_class || Aidp::Harness::CapabilityRegistry
        @config_manager_class = config_manager_class || Aidp::Harness::ConfigManager
        @project_dir = project_dir || Dir.pwd
      end

      # Main entry point for providers info/refresh subcommands
      def run(args, subcommand:)
        case subcommand
        when "info"
          run_info_command(args)
        when "refresh"
          run_refresh_command(args)
        when "catalog"
          run_models_catalog_command
        else
          display_message("Unknown providers subcommand: #{subcommand}", type: :error)
          display_help
          1
        end
      end

      private

      def run_info_command(args)
        provider_name = args.shift

        # If no provider specified, show models catalog table
        unless provider_name
          run_models_catalog_command
          return
        end

        force_refresh = args.include?("--refresh")

        display_message("Provider Information: #{provider_name}", type: :highlight)
        display_message("=" * 60, type: :muted)

        provider_info = @provider_info_class.new(provider_name, @project_dir)
        info = provider_info.info(force_refresh: force_refresh)

        if info.nil?
          display_message("No information available for provider: #{provider_name}", type: :error)
          return
        end

        # Display basic info
        display_message("Last Checked: #{info[:last_checked]}", type: :info)
        display_message("CLI Available: #{info[:cli_available] ? "Yes" : "No"}", type: info[:cli_available] ? :success : :error)

        # Display authentication
        if info[:auth_method]
          display_message("\nAuthentication Method: #{info[:auth_method]}", type: :info)
        end

        # Display MCP support
        display_message("\nMCP Support: #{info[:mcp_support] ? "Yes" : "No"}", type: info[:mcp_support] ? :success : :info)

        # Display MCP servers if available
        if info[:mcp_servers]&.any?
          display_message("\nMCP Servers: (#{info[:mcp_servers].size} configured)", type: :highlight)
          info[:mcp_servers].each do |server|
            status_symbol = server[:enabled] ? "✓" : "○"
            display_message("  #{status_symbol} #{server[:name]} (#{server[:status]})", type: server[:enabled] ? :success : :muted)
            display_message("    #{server[:description]}", type: :muted) if server[:description]
          end
        elsif info[:mcp_support]
          display_message("\nMCP Servers: None configured", type: :muted)
        end

        # Display permission modes
        if info[:permission_modes]&.any?
          display_message("\nPermission Modes:", type: :highlight)
          info[:permission_modes].each do |mode|
            if mode.is_a?(Hash)
              display_message("  • #{mode[:name]}: #{mode[:description]}", type: :info)
            else
              display_message("  • #{mode}", type: :info)
            end
          end
        end

        # Display capabilities
        if info[:capabilities]&.any?
          display_message("\nCapabilities:", type: :highlight)
          info[:capabilities].each do |cap_name, enabled|
            status = enabled ? "✓" : "✗"
            status_type = enabled ? :success : :muted
            display_message("  #{status} #{cap_name}", type: status_type)
          end
        end

        # Display CLI flags
        if info[:flags]&.any?
          display_message("\nAvailable CLI Flags:", type: :highlight)
          info[:flags].each do |flag_name, flag_data|
            display_message("  #{flag_data[:flag]}: #{flag_data[:description]}", type: :info)
          end
        end
      end

      def run_models_catalog_command
        display_message("Models Catalog - Thinking Depth Tiers", type: :highlight)
        display_message("=" * 80, type: :muted)

        registry = @capability_registry_class.new
        unless registry.load_catalog
          display_message("No models catalog found. Create .aidp/models_catalog.yml first.", type: :error)
          return
        end

        rows = []
        registry.provider_names.sort.each do |provider|
          models = registry.models_for_provider(provider)
          models.each do |model_name, model_data|
            tier = model_data["tier"] || "-"
            context = model_data["context_window"] ? "#{model_data["context_window"] / 1000}k" : "-"
            tools = model_data["supports_tools"] ? "yes" : "no"
            cost_input = model_data["cost_per_mtok_input"]
            cost = cost_input ? "$#{cost_input}/MTok" : "-"

            rows << [provider, model_name, tier, context, tools, cost]
          end
        end

        if rows.empty?
          display_message("No models found in catalog", type: :info)
          return
        end

        header = ["Provider", "Model", "Tier", "Context", "Tools", "Cost"]
        table = TTY::Table.new(header, rows)
        display_message(table.render(:basic), type: :info)

        display_message("\n" + "=" * 80, type: :muted)
        display_message("Use '/thinking show' in REPL to see current tier configuration", type: :muted)
      end

      def run_refresh_command(args)
        provider_name = args.shift
        config_manager = @config_manager_class.new(@project_dir)
        providers_to_refresh = if provider_name
          [provider_name]
        else
          config_manager.provider_names
        end

        if providers_to_refresh.empty?
          display_message("No providers configured", type: :error)
          return
        end

        display_message("Refreshing provider information...", type: :highlight)
        display_message("=" * 60, type: :muted)

        providers_to_refresh.each do |prov_name|
          spinner = TTY::Spinner.new("[:spinner] Refreshing #{prov_name}...", format: :dots)
          spinner.auto_spin

          begin
            provider_info = @provider_info_class.new(prov_name, @project_dir)
            result = provider_info.info(force_refresh: true)

            spinner.stop
            if result
              display_message("✓ #{prov_name} refreshed successfully", type: :success)
            else
              display_message("✗ #{prov_name} failed to refresh", type: :error)
            end
          rescue => e
            spinner.stop
            display_message("✗ #{prov_name} error: #{e.message}", type: :error)
          end
        end

        display_message("\n" + "=" * 60, type: :muted)
        display_message("Refresh complete", type: :highlight)
      end

      def display_help
        display_message("\nUsage: aidp providers <subcommand> [options]", type: :info)
        display_message("\nSubcommands:", type: :info)
        display_message("  info <provider>   Show detailed information about a provider", type: :info)
        display_message("  info              Show models catalog (no provider specified)", type: :info)
        display_message("  refresh           Refresh all provider information", type: :info)
        display_message("  refresh <provider>  Refresh specific provider information", type: :info)
        display_message("\nOptions:", type: :info)
        display_message("  --refresh         Force refresh when showing info", type: :info)
        display_message("\nExamples:", type: :info)
        display_message("  aidp providers info anthropic", type: :info)
        display_message("  aidp providers info anthropic --refresh", type: :info)
        display_message("  aidp providers info", type: :info)
        display_message("  aidp providers refresh", type: :info)
        display_message("  aidp providers refresh anthropic", type: :info)
      end
    end
  end
end
