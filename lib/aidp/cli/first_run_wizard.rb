#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "tty-prompt"

module Aidp
  class CLI
    # Handles interactive first-time project setup when no aidp.yml exists
    class FirstRunWizard
      TEMPLATES_DIR = File.expand_path(File.join(__dir__, "..", "..", "..", "templates"))

      def self.ensure_config(project_dir, input: $stdin, output: $stdout, non_interactive: false)
        return true if Aidp::Config.config_exists?(project_dir)

        wizard = new(project_dir, input: input, output: output)

        if non_interactive || !input.tty? || !output.tty?
          # Non-interactive environment - create minimal config silently
          path = wizard.send(:write_minimal_config, project_dir)
          output.puts "Created minimal configuration at #{wizard.send(:relative, path)} (non-interactive default)"
          return true
        end

        wizard.run
      end

      def self.setup_config(project_dir, input: $stdin, output: $stdout, non_interactive: false)
        wizard = new(project_dir, input: input, output: output)

        if non_interactive || !input.tty? || !output.tty?
          # Non-interactive environment - skip setup
          output.puts "Configuration setup skipped in non-interactive environment"
          return true
        end

        wizard.run_setup_config
      end

      def initialize(project_dir, input: $stdin, output: $stdout)
        @project_dir = project_dir
        @input = input
        @output = output
        @prompt = TTY::Prompt.new
      end

      def run
        banner
        loop do
          choice = ask_choice
          case choice
          when "1" then return finish(write_minimal_config(@project_dir))
          when "2" then return finish(copy_template("aidp-development.yml.example"))
          when "3" then return finish(copy_template("aidp-production.yml.example"))
          when "4" then return finish(write_example_config(@project_dir))
          when "5" then return finish(run_custom)
          when "q", "Q" then @output.puts("Exiting without creating configuration.")
                             return false
          else
            @output.puts "Invalid selection. Please choose one of the listed options."
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
        @output.puts "\n🚀 First-time setup detected"
        @output.puts "No 'aidp.yml' configuration file found in #{relative(@project_dir)}."
        @output.puts "Let's create one so you can start using AI Dev Pipeline."
        @output.puts
      end

      def ask_choice
        @output.puts "Choose a configuration style:" unless @asking
        @output.puts <<~MENU
          1) Minimal (single provider: cursor)
          2) Development template (multiple providers, safe defaults)
          3) Production template (full features, review required)
          4) Full example (verbose example config)
          5) Custom (interactive prompts)
          q) Quit
        MENU
        @output.print "Enter choice [1]: "
        @output.flush
        ans = @input.gets&.strip
        ans = "1" if ans.nil? || ans.empty?
        ans
      end

      def finish(path)
        if path
          @output.puts "\n✅ Configuration created at #{relative(path)}"
          @output.puts "You can edit this file anytime. Continuing startup...\n"
          true
        else
          @output.puts "❌ Failed to create configuration file."
          false
        end
      end

      def copy_template(filename)
        src = File.join(TEMPLATES_DIR, filename)
        unless File.exist?(src)
          @output.puts "Template not found: #{filename}"
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
          harness: {
            max_retries: 2,
            default_provider: "cursor",
            fallback_providers: ["cursor"],
            no_api_keys_required: false
          },
          providers: {
            cursor: {
              type: "package",
              default_flags: []
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
          provider_section[prov] = {"type" => (prov == "cursor") ? "package" : "usage_based", "default_flags" => []}
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
            provider_section[prov] = converted_provider
          else
            provider_section[prov] = {"type" => (prov == "cursor") ? "package" : "usage_based", "default_flags" => []}
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
          @output.print "#{prompt} [#{default}]: "
        else
          @output.print "#{prompt}: "
        end
        @output.flush
        ans = @input.gets&.strip
        return default if (ans.nil? || ans.empty?) && default
        ans
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
