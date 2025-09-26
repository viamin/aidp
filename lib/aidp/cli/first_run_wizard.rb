#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "tty-prompt"

module Aidp
  class CLI
    # Handles interactive first-time project setup when no aidp.yml exists
    class FirstRunWizard
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

      # Helper method for consistent message display using TTY::Prompt
      def display_message(message, type: :info)
        color = case type
        when :error then :red
        when :success then :green
        when :warning then :yellow
        when :info then :blue
        when :highlight then :cyan
        when :muted then :bright_black
        else :white
        end

        @prompt.say(message, color: color)
      end

      def run
        banner
        loop do
          choice = ask_choice
          case choice
          when "1" then return finish(write_quick_config(@project_dir))
          when "2" then return finish(run_custom)
          when "q", "Q" then display_message("Exiting without creating configuration.")
                             return false
          else
            display_message("Invalid selection. Please choose one of the listed options.", type: :warning)
          end
        end
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
        display_message("Let's create one so you can start using AI Dev Pipeline.")
        display_message("")
      end

      def ask_choice
        display_message("Choose a configuration style:") unless @asking

        options = {
          "Quick setup (cursor + macos, no API keys needed)" => "1",
          "Custom setup (choose your own providers and settings)" => "2",
          "Quit" => "q"
        }

        @prompt.select("Select an option:", options, default: "Quick setup (cursor + macos, no API keys needed)")
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
        dest = File.join(@project_dir, "aidp.yml")
        File.write(dest, File.read(src))
        dest
      end

      def write_minimal_config(project_dir)
        dest = File.join(project_dir, "aidp.yml")
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
        File.write(dest, YAML.dump(data))
        dest
      end

      def write_quick_config(project_dir)
        dest = File.join(project_dir, "aidp.yml")
        return dest if File.exist?(dest)
        data = {
          "harness" => {
            "max_retries" => 2,
            "default_provider" => "cursor",
            "fallback_providers" => ["macos"],
            "no_api_keys_required" => true
          },
          "providers" => {
            "cursor" => {
              "type" => "subscription",
              "default_flags" => []
            },
            "macos" => {
              "type" => "usage_based",
              "default_flags" => []
            }
          }
        }
        File.write(dest, YAML.dump(data))
        dest
      end

      def write_example_config(project_dir)
        Aidp::Config.create_example_config(project_dir)
        File.join(project_dir, "aidp.yml")
      end

      def run_custom
        dest = File.join(@project_dir, "aidp.yml")
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
        fallback_input = @prompt.ask("Fallback providers (comma-separated)?", default: provider_name) do |q|
          q.validate(/^[a-zA-Z0-9_,\s]+$/, "Invalid characters. Use only letters, numbers, commas, and spaces.")
          q.validate(->(input) { validate_provider_list(input, available_providers) }, "One or more providers are not supported.")
        end

        restrict = @prompt.yes?("Only use providers that don't require API keys?", default: false)

        # Process the inputs
        fallback_providers = fallback_input.split(/\s*,\s*/).map(&:strip).reject(&:empty?)
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
        File.write(dest, YAML.dump(data))
        dest
      end

      def run_custom_with_defaults(existing_config)
        dest = File.join(@project_dir, "aidp.yml")

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
        fallback_input = @prompt.ask("Fallback providers (comma-separated)?", default: current_fallbacks.join(", ")) do |q|
          q.validate(/^[a-zA-Z0-9_,\s]+$/, "Invalid characters. Use only letters, numbers, commas, and spaces.")
          q.validate(->(input) { validate_provider_list(input, available_providers) }, "One or more providers are not supported.")
        end

        restrict_input = @prompt.yes?("Only use providers that don't require API keys?", default: current_restrict)

        # Process the inputs
        fallback_providers = fallback_input.split(/\s*,\s*/).map(&:strip).reject(&:empty?)
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

        File.write(dest, YAML.dump(data))
        dest
      end

      def load_existing_config
        config_file = File.join(@project_dir, "aidp.yml")
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
        # Define the available providers based on the system
        available = ["cursor", "anthropic", "gemini", "macos", "opencode"]

        # Add descriptions for better UX
        available.map do |provider|
          case provider
          when "cursor"
            "cursor - Cursor AI (no API key required)"
          when "anthropic"
            "anthropic - Anthropic Claude (requires API key)"
          when "gemini"
            "gemini - Google Gemini (requires API key)"
          when "macos"
            "macos - macOS UI Automation (no API key required)"
          when "opencode"
            "opencode - OpenCode (no API key required)"
          else
            provider
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
    end
  end
end
