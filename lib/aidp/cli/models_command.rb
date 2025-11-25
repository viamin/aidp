# frozen_string_literal: true

require "tty-table"
require "tty-prompt"
require "tty-spinner"
require_relative "../harness/model_registry"
require_relative "../harness/ruby_llm_registry"

module Aidp
  class CLI
    # Command handler for `aidp models` subcommand group
    #
    # Provides commands for viewing AI models from the RubyLLM registry:
    #   - list: Show all available models with tier information
    #   - discover: Discover models from RubyLLM registry for a provider
    #   - validate: Validate model configuration
    #
    # Usage:
    #   aidp models list [--provider=<name>] [--tier=<tier>]
    #   aidp models discover [--provider=<name>]
    #   aidp models validate
    class ModelsCommand
      include Aidp::MessageDisplay

      def initialize(prompt: TTY::Prompt.new, registry: nil, ruby_llm_registry: nil)
        @prompt = prompt
        @registry = registry
        @ruby_llm_registry = ruby_llm_registry
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
        when "validate"
          args.shift
          run_validate_command(args)
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

      def ruby_llm_registry
        @ruby_llm_registry ||= Aidp::Harness::RubyLLMRegistry.new
      end

      def display_help
        display_message("\nUsage: aidp models <subcommand> [options]", type: :info)
        display_message("\nSubcommands:", type: :info)
        display_message("  list              List all available models with tier information", type: :info)
        display_message("  discover          Discover models from RubyLLM registry for a provider", type: :info)
        display_message("  validate          Validate model configuration for all tiers", type: :info)
        display_message("\nOptions:", type: :info)
        display_message("  --provider=<name> Filter/target specific provider", type: :info)
        display_message("  --tier=<tier>     Filter by tier (mini, standard, advanced)", type: :info)
        display_message("\nExamples:", type: :info)
        display_message("  aidp models list", type: :info)
        display_message("  aidp models list --tier=mini", type: :info)
        display_message("  aidp models list --provider=anthropic", type: :info)
        display_message("  aidp models discover --provider=anthropic", type: :info)
        display_message("  aidp models validate", type: :info)
      end

      def run_list_command(args)
        options = parse_list_options(args)

        begin
          # Get models from RubyLLM registry
          all_model_ids = if options[:provider]
            ruby_llm_registry.models_for_provider(options[:provider])
          else
            # Get all models by iterating known providers
            known_providers = %w[anthropic openai google azure bedrock openrouter]
            known_providers.flat_map { |p| ruby_llm_registry.models_for_provider(p) }.uniq
          end

          # Build table rows
          rows = []
          all_model_ids.each do |model_id|
            info = ruby_llm_registry.get_model_info(model_id)
            next unless info

            # Map advanced -> pro for display consistency
            display_tier = (info[:tier] == "advanced") ? "pro" : info[:tier]

            # Apply tier filter if specified (handle pro/advanced mapping)
            if options[:tier]
              filter_tier = (options[:tier] == "pro") ? "advanced" : options[:tier]
              next unless info[:tier] == filter_tier
            end

            rows << build_table_row(info[:provider], model_id, info, display_tier)
          end

          # Sort rows by tier, then provider, then model name
          tier_order = {"mini" => 0, "standard" => 1, "pro" => 2, "advanced" => 2}
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
        valid_tiers = %w[mini standard pro advanced]

        args.each do |arg|
          case arg
          when /^--provider=(.+)$/
            options[:provider] = Regexp.last_match(1)
          when /^--tier=(.+)$/
            tier = Regexp.last_match(1)
            unless valid_tiers.include?(tier)
              display_message("Invalid tier: #{tier}. Valid tiers: #{valid_tiers.join(", ")}", type: :error)
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

      def build_table_row(provider_name, model_id, info, display_tier)
        capabilities = (info[:capabilities] || []).join(",")
        context = format_context_window(info[:context_window])

        [
          provider_name || "-",
          model_id,
          display_tier || "unknown",
          capabilities.empty? ? "-" : capabilities,
          context,
          "-" # Speed not available in registry
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
          "💡 Showing #{count} model#{"s" unless count == 1} from RubyLLM registry",
          "💡 Registry updated regularly via ruby_llm gem updates"
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

        unless options[:provider]
          display_message("\n⚠️  Please specify a provider with --provider=<name>", type: :warning)
          display_message("Example: aidp models discover --provider=anthropic\n", type: :info)
          return 1
        end

        begin
          display_message("\n🔍 Discovering models for #{options[:provider]} from RubyLLM registry...\n", type: :highlight)

          # Get models from registry
          model_ids = ruby_llm_registry.models_for_provider(options[:provider])

          if model_ids.empty?
            display_message("\n⚠️  No models found for provider '#{options[:provider]}'.", type: :warning)
            display_message("Provider may not be supported or name may be incorrect.\n", type: :info)
            return 1
          end

          # Group by tier
          models_by_tier = Hash.new { |h, k| h[k] = [] }
          model_ids.each do |model_id|
            info = ruby_llm_registry.get_model_info(model_id)
            next unless info

            # Map advanced -> pro for display
            tier = (info[:tier] == "advanced") ? "pro" : info[:tier]
            models_by_tier[tier] << model_id
          end

          # Display results
          display_message("\n✓ Found #{model_ids.size} models for #{options[:provider]}:", type: :success)

          %w[mini standard pro].each do |tier|
            tier_models = models_by_tier[tier]
            next if tier_models.empty?

            display_message("\n  #{tier.capitalize} tier (#{tier_models.size} model#{"s" unless tier_models.size == 1}):", type: :info)
            tier_models.first(5).each do |model|
              display_message("    - #{model}", type: :info)
            end
            if tier_models.size > 5
              display_message("    ... and #{tier_models.size - 5} more", type: :info)
            end
          end

          display_message("\n💡 Use 'aidp models list --provider=#{options[:provider]}' to see full details\n", type: :info)
          0
        rescue => e
          display_message("Error discovering models: #{e.message}", type: :error)
          Aidp.log_error("models_command", "discovery error", error: e.message, backtrace: e.backtrace.first(5))
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

      def run_validate_command(args)
        parse_validate_options(args)

        begin
          # Load configuration
          config = load_configuration
          return 1 unless config

          display_message("\n🔍 Validating model configuration...\n", type: :highlight)

          # Collect validation issues
          issues = []
          warnings = []

          # Validate tier coverage
          tier_issues = validate_tier_coverage(config)
          issues.concat(tier_issues[:errors])
          warnings.concat(tier_issues[:warnings])

          # Validate provider models
          provider_issues = validate_provider_models(config)
          issues.concat(provider_issues[:errors])
          warnings.concat(provider_issues[:warnings])

          # Display results
          display_validation_results(issues, warnings)

          # Return exit code
          issues.empty? ? 0 : 1
        rescue => e
          display_message("Error validating configuration: #{e.message}", type: :error)
          Aidp.log_error("models_command", "validation error",
            error: e.message, backtrace: e.backtrace.first(5))
          1
        end
      end

      def parse_validate_options(args)
        args.each do |arg|
          case arg
          when "--help", "-h"
            display_help
            exit 0
          end
        end
      end

      def load_configuration
        project_dir = Dir.pwd
        unless Aidp::Config.config_exists?(project_dir)
          display_message("❌ No aidp.yml configuration file found", type: :error)
          display_message("Run 'aidp config --interactive' to create one", type: :info)
          return nil
        end

        config_data = Aidp::Config.load(project_dir) || {}
        providers_section = config_data[:providers] || config_data["providers"] || {}
        SimpleConfiguration.new(providers_section)
      rescue => e
        display_message("Error validating configuration: #{e.message}", type: :error)
        nil
      end

      def validate_tier_coverage(config)
        errors = []
        warnings = []

        # Check each tier for model coverage
        Aidp::Harness::ModelRegistry::VALID_TIERS.each do |tier|
          has_model = tier_has_model?(config, tier)

          unless has_model
            errors << {
              tier: tier,
              message: "No model configured for '#{tier}' tier",
              fix: generate_tier_fix_suggestion(tier, config)
            }
          end
        end

        {errors: errors, warnings: warnings}
      end

      def tier_has_model?(config, tier)
        # Check if any provider has a model for this tier
        configured_providers = config.configured_providers

        configured_providers.any? do |provider_name|
          provider_cfg = config.provider_config(provider_name)
          tier_config = provider_cfg.dig(:thinking_tiers, tier.to_sym) ||
            provider_cfg.dig(:thinking_tiers, tier)

          tier_config && tier_config[:models] && !tier_config[:models].empty?
        end
      end

      def validate_provider_models(config)
        errors = []
        warnings = []

        configured_providers = config.configured_providers

        configured_providers.each do |provider_name|
          provider_class = get_provider_class(provider_name)
          next unless provider_class

          provider_cfg = config.provider_config(provider_name)
          tiers_cfg = provider_cfg[:thinking_tiers] || {}

          # Validate models in each tier
          tiers_cfg.each do |tier, tier_config|
            next unless tier_config[:models]

            tier_config[:models].each do |model_entry|
              model_name = model_entry.is_a?(Hash) ? model_entry[:model] : model_entry
              next unless model_name

              # Check if provider supports this model family
              family = get_model_family(provider_class, model_name)
              next unless family

              unless provider_supports_model?(provider_class, family)
                errors << {
                  provider: provider_name,
                  tier: tier,
                  model: model_name,
                  message: "Model '#{model_name}' not supported by provider '#{provider_name}'",
                  fix: suggest_alternative_model(provider_name, tier, model_name)
                }
              end

              # Check if model exists in registry
              model_info = registry.get_model_info(family)
              unless model_info
                warnings << {
                  provider: provider_name,
                  tier: tier,
                  model: model_name,
                  message: "Model family '#{family}' not found in registry (may still work)"
                }
              end
            end
          end
        end

        {errors: errors, warnings: warnings}
      end

      def get_provider_class(provider_name)
        class_name = "Aidp::Providers::#{provider_name.capitalize}"
        Object.const_get(class_name)
      rescue NameError
        nil
      end

      def get_model_family(provider_class, model_name)
        return model_name unless provider_class.respond_to?(:model_family)
        provider_class.model_family(model_name)
      end

      def provider_supports_model?(provider_class, family)
        return true unless provider_class.respond_to?(:supports_model_family?)
        provider_class.supports_model_family?(family)
      end

      def generate_tier_fix_suggestion(tier, config)
        # Get a model from registry for this tier
        tier_models = registry.models_for_tier(tier)
        return "Configure a model for this tier in aidp.yml" if tier_models.empty?

        # Find a model that works with configured providers
        configured_providers = config.configured_providers
        suggested_model = nil

        tier_models.each do |family|
          configured_providers.each do |provider_name|
            provider_class = get_provider_class(provider_name)
            next unless provider_class

            if provider_supports_model?(provider_class, family)
              suggested_model = {family: family, provider: provider_name}
              break
            end
          end
          break if suggested_model
        end

        if suggested_model
          "Add to aidp.yml under providers.#{suggested_model[:provider]}.thinking_tiers.#{tier}.models:\n" \
          "  - #{suggested_model[:family]}"
        else
          "Configure a model for this tier in aidp.yml"
        end
      end

      def suggest_alternative_model(provider_name, tier, invalid_model)
        # Get models from registry for this tier and provider
        tier_models = if registry.is_a?(Aidp::Harness::ModelRegistry)
          registry.models_for_tier(tier.to_s)
        else
          []
        end
        provider_class = get_provider_class(provider_name)
        return "Check model name or use a different provider" unless provider_class

        # Find valid alternatives
        alternatives = tier_models.select do |family|
          provider_supports_model?(provider_class, family)
        end

        if alternatives.any?
          "Try using: #{alternatives.first(3).join(", ")}"
        else
          "Provider '#{provider_name}' doesn't support any models for tier '#{tier}'"
        end
      end

      def display_validation_results(issues, warnings)
        if issues.empty? && warnings.empty?
          display_message("✅ Configuration is valid!\n", type: :success)
          display_message("All tiers have models configured", type: :info)
          display_message("All configured models are valid for their providers\n", type: :info)
          return
        end

        # Display errors
        if issues.any?
          display_message("❌ Found #{issues.size} configuration error#{"s" unless issues.size == 1}:\n", type: :error)

          issues.each_with_index do |issue, idx|
            display_message("\n#{idx + 1}. #{issue[:message]}", type: :error)

            if issue[:tier]
              display_message("   Tier: #{issue[:tier]}", type: :info)
            end

            if issue[:provider]
              display_message("   Provider: #{issue[:provider]}", type: :info)
            end

            if issue[:model]
              display_message("   Model: #{issue[:model]}", type: :info)
            end

            if issue[:fix]
              display_message("\n   💡 Suggested fix:", type: :highlight)
              display_message("   #{issue[:fix]}", type: :info)
            end
          end
          display_message("\n", type: :info)
        end

        # Display warnings
        if warnings.any?
          display_message("⚠️  Found #{warnings.size} warning#{"s" unless warnings.size == 1}:\n", type: :warning)

          warnings.each_with_index do |warning, idx|
            display_message("\n#{idx + 1}. #{warning[:message]}", type: :warning)

            if warning[:provider]
              display_message("   Provider: #{warning[:provider]}", type: :info)
            end

            if warning[:model]
              display_message("   Model: #{warning[:model]}", type: :info)
            end
          end
          display_message("\n", type: :info)
        end

        # Display helpful tips
        display_message("💡 Run 'aidp models discover' to see available models", type: :info)
        display_message("💡 Run 'aidp models list --tier=<tier>' to see models for a specific tier\n", type: :info)
      end

      # Lightweight configuration wrapper for CLI validation
      class SimpleConfiguration
        def initialize(providers_section)
          @providers = (providers_section || {}).each_with_object({}) do |(name, cfg), result|
            result[name.to_s] = deep_symbolize(cfg || {})
          end
        end

        def configured_providers
          @providers.keys
        end

        def provider_config(name)
          @providers[name.to_s] || {}
        end

        private

        def deep_symbolize(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, val), result|
              result_key = key.is_a?(String) ? key.to_sym : key
              result[result_key] = deep_symbolize(val)
            end
          when Array
            value.map { |item| deep_symbolize(item) }
          else
            value
          end
        end
      end
      private_constant :SimpleConfiguration
    end
  end
end
