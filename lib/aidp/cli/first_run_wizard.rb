#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "tty-prompt"
require_relative "../harness/provider_factory"
require_relative "../config/paths"

module Aidp
  class CLI
    # Handles interactive first-time project setup when no aidp.yml exists
    class FirstRunWizard
      include Aidp::MessageDisplay

      TEMPLATES_DIR = File.expand_path(File.join(__dir__, "..", "..", "..", "templates"))

      def self.ensure_config(project_dir, non_interactive: false, prompt: TTY::Prompt.new)
        return true if Aidp::Config.config_exists?(project_dir)

        wizard = new(project_dir, prompt: prompt)

        if non_interactive
          # Non-interactive environment - create minimal config silently
          path = wizard.send(:write_minimal_config, project_dir)
          wizard.send(:display_message, "Created minimal configuration at #{wizard.send(:relative, path)} (non-interactive default)", type: :success)
          return true
        end

        wizard.run
      end

      def self.setup_config(project_dir, non_interactive: false, prompt: TTY::Prompt.new)
        wizard = new(project_dir, prompt: prompt)

        if non_interactive
          # Non-interactive environment - skip setup
          wizard.send(:display_message, "Configuration setup skipped in non-interactive environment", type: :info)
          return true
        end

        wizard.run_setup_config
      end

      def initialize(project_dir, prompt: TTY::Prompt.new)
        @project_dir = project_dir
        @prompt = prompt
      end

      def run
        banner
        # Always run the full interactive custom configuration flow.
        finish(run_custom)
      end

      def run_setup_config
        @prompt.say("🔧 Configuration Setup", color: :blue)
        @prompt.say("Setting up your configuration file with current values as defaults.")
        @prompt.say("")

        # Load existing config to use as defaults (if it exists)
        existing_config = load_existing_config

        if existing_config
          # Run custom configuration with existing values as defaults
          finish(run_custom_with_defaults(existing_config))
        else
          # No existing config, run the normal setup flow
          @prompt.say("No existing configuration found. Running first-time setup...")
          @prompt.say("")
          run
        end
      end

      private

      def banner
        display_message("\n🚀 First-time setup detected", type: :highlight)
        display_message("No 'aidp.yml' configuration file found in #{relative(@project_dir)}.")
        display_message("Creating a configuration so you can start using AI Dev Pipeline.")
        display_message("")
      end

      def finish(path)
        if path
          display_message("\n✅ Configuration created at #{relative(path)}", type: :success)
          display_message("You can edit this file anytime. Continuing startup...\n")
          true
        else
          display_message("❌ Failed to create configuration file.", type: :error)
          false
        end
      end

      def copy_template(filename)
        src = File.join(TEMPLATES_DIR, filename)
        unless File.exist?(src)
          display_message("Template not found: #{filename}", type: :error)
          return nil
        end
        dest = Aidp::ConfigPaths.config_file(@project_dir)
        Aidp::ConfigPaths.ensure_config_dir(@project_dir)
        File.write(dest, File.read(src))
        dest
      end

      def write_minimal_config(project_dir)
        dest = Aidp::ConfigPaths.config_file(project_dir)
        return dest if File.exist?(dest)
        data = {
          "harness" => {
            "max_retries" => 2,
            "default_provider" => "cursor",
            "fallback_providers" => ["cursor"],
            "no_api_keys_required" => false
          },
          "providers" => {
            "cursor" => {
              "type" => "subscription",
              "default_flags" => []
            }
          }
        }
        Aidp::ConfigPaths.ensure_config_dir(project_dir)
        File.write(dest, YAML.dump(data))
        dest
      end

      def write_example_config(project_dir)
        Aidp::Config.create_example_config(project_dir)
        Aidp::ConfigPaths.config_file(project_dir)
      end

      def run_custom
        dest = Aidp::ConfigPaths.config_file(@project_dir)
        return dest if File.exist?(dest)

        @prompt.say("Interactive custom configuration: press Enter to accept defaults shown in [brackets].")
        @prompt.say("")

        # Get available providers for validation
        available_providers = get_available_providers

        # Use TTY::Prompt select for primary provider
        # Find the formatted string that matches the default
        default_option = available_providers.find { |option| option.start_with?("cursor -") } || available_providers.first
        default_provider = @prompt.select("Default provider?", available_providers, default: default_option)

        # Extract just the provider name from the formatted string
        provider_name = default_provider.split(" - ").first

        # Validate fallback providers
        fallback_providers = select_fallback_providers(available_providers, provider_name)

        restrict = @prompt.yes?("Only use providers that don't require API keys?", default: false)

        # Process providers preserving order
        providers = [provider_name] + fallback_providers
        providers.uniq!

        provider_section = {}
        providers.each do |prov|
          provider_section[prov] = {"type" => (prov == "cursor") ? "subscription" : "usage_based", "default_flags" => []}
        end

        data = {
          "harness" => {
            "max_retries" => 2,
            "default_provider" => provider_name,
            "fallback_providers" => fallback_providers,
            "no_api_keys_required" => restrict
          },
          "providers" => provider_section
        }
        Aidp::ConfigPaths.ensure_config_dir(@project_dir)
        File.write(dest, YAML.dump(data))
        dest
      end

      def run_custom_with_defaults(existing_config)
        dest = Aidp::ConfigPaths.config_file(@project_dir)

        # Extract current values from existing config
        harness_config = existing_config[:harness] || existing_config["harness"] || {}
        providers_config = existing_config[:providers] || existing_config["providers"] || {}

        current_default = harness_config[:default_provider] || harness_config["default_provider"] || "cursor"
        current_fallbacks = harness_config[:fallback_providers] || harness_config["fallback_providers"] || [current_default]
        current_restrict = harness_config[:no_api_keys_required] || harness_config["no_api_keys_required"] || false

        # Use TTY::Prompt for interactive configuration
        @prompt.say("Interactive configuration update: press Enter to keep current values shown in [brackets].")
        @prompt.say("")

        # Get available providers for validation
        available_providers = get_available_providers

        # Use TTY::Prompt select for primary provider
        # Find the formatted string that matches the current default
        default_option = available_providers.find { |option| option.start_with?("#{current_default} -") } || available_providers.first
        default_provider = @prompt.select("Default provider?", available_providers, default: default_option)

        # Extract just the provider name from the formatted string
        provider_name = default_provider.split(" - ").first

        # Validate fallback providers
        fallback_providers = select_fallback_providers(available_providers, provider_name, preselected: current_fallbacks - [provider_name])

        restrict_input = @prompt.yes?("Only use providers that don't require API keys?", default: current_restrict)

        # Process providers preserving order
        providers = [provider_name] + fallback_providers
        providers.uniq!

        # Build provider section
        provider_section = {}
        providers.each do |prov|
          # Try to preserve existing provider config if it exists
          existing_provider = providers_config[prov.to_sym] || providers_config[prov.to_s]
          if existing_provider
            # Convert existing provider config to string keys
            converted_provider = {}
            existing_provider.each { |k, v| converted_provider[k.to_s] = v }
            # Ensure the type is correct (fix old "package" and "api" types)
            if converted_provider["type"] == "package"
              converted_provider["type"] = "subscription"
            elsif converted_provider["type"] == "api"
              converted_provider["type"] = "usage_based"
            end
            provider_section[prov] = converted_provider
          else
            provider_section[prov] = {"type" => (prov == "cursor") ? "subscription" : "usage_based", "default_flags" => []}
          end
        end

        # Build the new config
        data = {
          "harness" => {
            "max_retries" => harness_config[:max_retries] || harness_config["max_retries"] || 2,
            "default_provider" => provider_name,
            "fallback_providers" => fallback_providers,
            "no_api_keys_required" => restrict_input
          },
          "providers" => provider_section
        }

        Aidp::ConfigPaths.ensure_config_dir(@project_dir)
        File.write(dest, YAML.dump(data))
        dest
      end

      def load_existing_config
        config_file = Aidp::ConfigPaths.config_file(@project_dir)
        return nil unless File.exist?(config_file)

        begin
          YAML.load_file(config_file) || {}
        rescue => e
          @prompt.say("❌ Failed to load existing configuration: #{e.message}", color: :red)
          nil
        end
      end

      def ask(prompt, default: nil)
        if default
          @prompt.ask("#{prompt}:", default: default)
        else
          @prompt.ask("#{prompt}:")
        end
      end

      def relative(path)
        pn = Pathname.new(path)
        wd = Pathname.new(@project_dir)
        rel = pn.relative_path_from(wd).to_s
        rel.start_with?("..") ? path : rel
      rescue
        path
      end

      # Get available providers for validation
      def get_available_providers
        # Get all supported providers from the factory (single source of truth)
        all_providers = Aidp::Harness::ProviderFactory::PROVIDER_CLASSES.keys

        # Filter out providers we don't want to show in the wizard
        # - "anthropic" is an internal name, we show "claude" instead
        # - "macos" is disabled (as per issue #73)
        excluded = ["anthropic", "macos"]
        available = all_providers - excluded

        # Get display names from the providers themselves
        available.map do |provider_name|
          provider_class = Aidp::Harness::ProviderFactory::PROVIDER_CLASSES[provider_name]
          if provider_class
            # Instantiate to get display name
            instance = provider_class.new
            display_name = instance.display_name
            "#{provider_name} - #{display_name}"
          else
            provider_name
          end
        end
      end

      # Validate provider list input
      def validate_provider_list(input, available_providers)
        return true if input.nil? || input.empty?

        # Extract provider names from the input
        providers = input.split(/\s*,\s*/).map(&:strip).reject(&:empty?)

        # Check if all providers are valid
        valid_providers = available_providers.map { |p| p.split(" - ").first }
        providers.all? { |provider| valid_providers.include?(provider) }
      end

      # Interactive ordered multi-select for fallback providers
      def select_fallback_providers(available_with_labels, default_provider, preselected: [])
        # Extract provider names and exclude the already chosen default
        options = available_with_labels.map { |o| o.split(" - ").first }
        candidates = options.reject { |p| p == default_provider }

        return [] if candidates.empty?

        selected = preselected.select { |p| candidates.include?(p) }

        loop do
          display_message("\nSelect fallback providers in order of preference (first = highest priority).", type: :info)
          display_message("Current order: #{selected.empty? ? "(none)" : selected.join(" > ")}", type: :muted)
          choice = @prompt.select("Add provider, or choose an action:", cycle: true) do |menu|
            (candidates - selected).each { |prov| menu.choice("Add #{prov}", prov) }
            menu.choice("Done", :done)
            menu.choice("Clear", :clear) unless selected.empty?
            menu.choice("Remove last (#{selected.last})", :remove) unless selected.empty?
          end

          case choice
          when :done
            break
          when :clear
            selected.clear
          when :remove
            selected.pop
          else
            selected << choice unless selected.include?(choice)
          end
        end

        selected
      end
    end
  end
end
