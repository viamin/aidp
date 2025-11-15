# frozen_string_literal: true

require "tty-table"
require "tty-prompt"
require "tty-spinner"
require_relative "../harness/model_registry"
require_relative "../harness/model_discovery_service"

module Aidp
  module CLI
    # Command handler for `aidp models` subcommand group
    #
    # Provides commands for viewing and discovering AI models:
    #   - list: Show all available models with tier information
    #   - discover: Discover models from configured providers
    #   - refresh: Refresh the model cache
    #
    # Usage:
    #   aidp models list [--provider=<name>] [--tier=<tier>]
    #   aidp models discover [--provider=<name>]
    #   aidp models refresh [--provider=<name>]
    class ModelsCommand
      include Aidp::MessageDisplay

      def initialize(prompt: TTY::Prompt.new)
        @prompt = prompt
        @registry = nil
        @discovery_service = nil
      end

      # Main entry point for models subcommand
      def run(args)
        subcommand = args.first if args.first && !args.first.start_with?("--")

        case subcommand
        when "list", nil
          args.shift if subcommand == "list"
          run_list_command(args)
        when "discover"
          args.shift
          run_discover_command(args)
        when "refresh"
          args.shift
          run_refresh_command(args)
        else
          display_message("Unknown models subcommand: #{subcommand}", type: :error)
          display_help
          1
        end
      end

      private

      def registry
        @registry ||= Aidp::Harness::ModelRegistry.new
      end

      def discovery_service
        @discovery_service ||= Aidp::Harness::ModelDiscoveryService.new
      end

      def display_help
        display_message("\nUsage: aidp models <subcommand> [options]", type: :info)
        display_message("\nSubcommands:", type: :info)
        display_message("  list              List all available models with tier information", type: :info)
        display_message("  discover          Discover models from configured providers", type: :info)
        display_message("  refresh           Refresh the model discovery cache", type: :info)
        display_message("\nOptions:", type: :info)
        display_message("  --provider=<name> Filter/target specific provider", type: :info)
        display_message("  --tier=<tier>     Filter by tier (mini, standard, advanced)", type: :info)
        display_message("\nExamples:", type: :info)
        display_message("  aidp models list", type: :info)
        display_message("  aidp models list --tier=mini", type: :info)
        display_message("  aidp models list --provider=anthropic", type: :info)
        display_message("  aidp models discover", type: :info)
        display_message("  aidp models discover --provider=anthropic", type: :info)
        display_message("  aidp models refresh", type: :info)
      end

      def run_list_command(args)
        options = parse_list_options(args)

        begin
          # Get all model families from registry
          families = registry.all_families

          # Apply tier filter if specified
          if options[:tier]
            families = families.select { |family|
              info = registry.get_model_info(family)
              info && info["tier"] == options[:tier]
            }
          end

          # Build table rows
          rows = []
          families.each do |family|
            info = registry.get_model_info(family)
            next unless info

            # Get providers that support this family
            providers = find_providers_for_family(family)

            # Apply provider filter if specified
            next if options[:provider] && !providers.include?(options[:provider])

            # Add a row for each provider that supports this family
            if providers.empty?
              # No provider support - show as registry-only
              rows << build_table_row(nil, family, info, "registry")
            else
              providers.each do |provider_name|
                rows << build_table_row(provider_name, family, info, "registry")
              end
            end
          end

          # Sort rows by tier, then provider, then model name
          tier_order = {"mini" => 0, "standard" => 1, "advanced" => 2}
          rows.sort_by! { |r| [tier_order[r[2]] || 3, r[0] || "", r[1]] }

          # Display table
          if rows.empty?
            display_message("No models found matching the specified criteria.", type: :info)
            return 0
          end

          display_message("\n#{build_header(options)}\n", type: :highlight)

          table = TTY::Table.new(
            header: ["Provider", "Model Family", "Tier", "Capabilities", "Context", "Speed"],
            rows: rows
          )

          # Use simple renderer for consistent formatting
          renderer = table.render(:basic, padding: [0, 1])
          display_message(renderer, type: :info)

          display_message("\n#{build_footer(rows.size)}\n", type: :info)
          0
        rescue Aidp::Harness::ModelRegistry::RegistryError => e
          display_message("Error loading model registry: #{e.message}", type: :error)
          Aidp.log_error("models_command", "registry error", error: e.message)
          1
        rescue => e
          display_message("Error listing models: #{e.message}", type: :error)
          Aidp.log_error("models_command", "unexpected error", error: e.message, backtrace: e.backtrace.first(5))
          1
        end
      end

      def parse_list_options(args)
        options = {}

        args.each do |arg|
          case arg
          when /^--provider=(.+)$/
            options[:provider] = Regexp.last_match(1)
          when /^--tier=(.+)$/
            tier = Regexp.last_match(1)
            unless Aidp::Harness::ModelRegistry::VALID_TIERS.include?(tier)
              display_message("Invalid tier: #{tier}. Valid tiers: #{Aidp::Harness::ModelRegistry::VALID_TIERS.join(", ")}", type: :error)
              exit 1
            end
            options[:tier] = tier
          when "--help", "-h"
            display_help
            exit 0
          end
        end

        options
      end

      def build_table_row(provider_name, family, info, source)
        capabilities = (info["capabilities"] || []).join(",")
        context = format_context_window(info["context_window"])
        speed = info["speed"] || "unknown"

        [
          provider_name || "-",
          family,
          info["tier"] || "unknown",
          capabilities.empty? ? "-" : capabilities,
          context,
          speed
        ]
      end

      def format_context_window(tokens)
        return "-" unless tokens

        if tokens >= 1_000_000
          "#{tokens / 1_000_000}M"
        elsif tokens >= 1_000
          "#{tokens / 1_000}K"
        else
          tokens.to_s
        end
      end

      def build_header(options)
        parts = ["Available Models"]
        parts << "(Provider: #{options[:provider]})" if options[:provider]
        parts << "(Tier: #{options[:tier]})" if options[:tier]
        parts.join(" ")
      end

      def build_footer(count)
        tips = [
          "💡 Showing #{count} model#{count == 1 ? "" : "s"} from the static registry",
          "💡 Model families are provider-agnostic (e.g., 'claude-3-5-sonnet' works across providers)"
        ]
        tips.join("\n")
      end

      def find_providers_for_family(family_name)
        providers = []

        # Check each provider adapter for support
        provider_classes = [
          Aidp::Providers::Anthropic,
          Aidp::Providers::Cursor,
          Aidp::Providers::Gemini
        ]

        provider_classes.each do |provider_class|
          next unless provider_class.respond_to?(:supports_model_family?)

          if provider_class.supports_model_family?(family_name)
            # Get the provider name from an instance (need to instantiate to call name method)
            # Or use a simple name mapping
            provider_name = provider_class.name.split("::").last.downcase
            providers << provider_name
          end
        rescue => e
          # Log but don't fail if provider check fails
          Aidp.log_debug("models_command", "provider check failed", provider: provider_class.name, error: e.message)
        end

        providers
      end

      def run_discover_command(args)
        options = parse_discover_options(args)

        begin
          display_message("\n🔍 Discovering models from configured providers...\n", type: :highlight)

          spinner = TTY::Spinner.new("[:spinner] Querying provider APIs...", format: :dots)
          spinner.auto_spin

          # Discover models
          if options[:provider]
            results = {options[:provider] => discovery_service.discover_models(options[:provider], use_cache: false)}
          else
            results = discovery_service.discover_all_models(use_cache: false)
          end

          spinner.success("✓")

          # Display results
          total_models = 0
          results.each do |provider, models|
            next if models.empty?

            total_models += models.size
            display_message("\n✓ Found #{models.size} models for #{provider}:", type: :success)

            # Group by tier
            by_tier = models.group_by { |m| m[:tier] }
            %w[mini standard advanced].each do |tier|
              tier_models = by_tier[tier] || []
              next if tier_models.empty?

              display_message("  #{tier.capitalize} tier:", type: :info)
              tier_models.each do |model|
                display_message("    - #{model[:name]}", type: :info)
              end
            end
          end

          if total_models == 0
            display_message("\n⚠️  No models discovered. Ensure provider CLIs are installed and configured.", type: :warning)
            return 1
          end

          display_message("\n✅ Discovered #{total_models} total model#{total_models == 1 ? "" : "s"}", type: :success)
          display_message("💾 Models cached for 24 hours\n", type: :info)
          0
        rescue => e
          display_message("Error discovering models: #{e.message}", type: :error)
          Aidp.log_error("models_command", "discovery error", error: e.message, backtrace: e.backtrace.first(5))
          1
        end
      end

      def run_refresh_command(args)
        options = parse_refresh_options(args)

        begin
          display_message("\n♻️  Refreshing model cache...\n", type: :highlight)

          spinner = TTY::Spinner.new("[:spinner] Clearing cache and re-discovering...", format: :dots)
          spinner.auto_spin

          if options[:provider]
            discovery_service.refresh_cache(options[:provider])
            spinner.success("✓")
            display_message("\n✅ Refreshed cache for #{options[:provider]}", type: :success)
          else
            discovery_service.refresh_all_caches
            spinner.success("✓")
            display_message("\n✅ Refreshed cache for all providers", type: :success)
          end

          display_message("💡 Run 'aidp models discover' to see the updated models\n", type: :info)
          0
        rescue => e
          display_message("Error refreshing cache: #{e.message}", type: :error)
          Aidp.log_error("models_command", "refresh error", error: e.message, backtrace: e.backtrace.first(5))
          1
        end
      end

      def parse_discover_options(args)
        options = {}

        args.each do |arg|
          case arg
          when /^--provider=(.+)$/
            options[:provider] = Regexp.last_match(1)
          when "--help", "-h"
            display_help
            exit 0
          end
        end

        options
      end

      def parse_refresh_options(args)
        parse_discover_options(args)
      end
    end
  end
end
