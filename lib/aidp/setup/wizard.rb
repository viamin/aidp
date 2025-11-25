# frozen_string_literal: true

require "tty-prompt"
require "tty-table"
require "yaml"
require "time"
require "fileutils"
require "json"

require_relative "../util"
require_relative "../config/paths"
require_relative "../harness/capability_registry"
require_relative "provider_registry"
require_relative "devcontainer/parser"
require_relative "devcontainer/generator"
require_relative "devcontainer/port_manager"
require_relative "devcontainer/backup_manager"

module Aidp
  module Setup
    # Interactive setup wizard for configuring AIDP.
    # Guides the user through provider, work loop, NFR, logging, and mode settings
    # while remaining idempotent and safe to re-run.
    class Wizard
      SCHEMA_VERSION = 1
      DEVCONTAINER_COMPONENT = "setup_wizard.devcontainer"

      DEFAULT_AUTOCONFIG_TIERS = %w[mini standard pro].freeze
      LEGACY_TIER_ALIASES = {
        advanced: :pro
      }.freeze

      attr_reader :project_dir, :prompt, :dry_run

      def initialize(project_dir = Dir.pwd, prompt: nil, dry_run: false)
        @project_dir = project_dir
        @prompt = prompt || TTY::Prompt.new
        @dry_run = dry_run
        @warnings = []
        @existing_config = load_existing_config
        @config = deep_symbolize(@existing_config)
        @saved = false
      end

      def run
        display_welcome
        # Normalize any legacy tier/model_family entries before prompting
        normalize_existing_model_families!
        normalize_existing_thinking_tiers!
        return @saved if skip_wizard?

        configure_providers
        configure_thinking_tiers
        configure_work_loop
        configure_branching
        configure_artifacts
        configure_nfrs
        configure_logging
        configure_modes
        configure_devcontainer

        yaml_content = generate_yaml
        display_preview(yaml_content)
        display_diff(yaml_content) if @existing_config.any?

        return true if dry_run_mode?(yaml_content)

        if prompt.yes?("Save this configuration?", default: true)
          save_config(yaml_content)
          prompt.ok("✅ Configuration saved to #{relative_config_path}")
          show_next_steps
          display_warnings
          @saved = true
        else
          prompt.warn("Configuration not saved")
          display_warnings
        end

        @saved
      end

      def saved?
        @saved
      end

      private

      def display_welcome
        prompt.say("\n" + "=" * 80)
        prompt.say("🧙 AIDP Setup Wizard")
        prompt.say("=" * 80)
        prompt.say("\nThis wizard will help you configure AIDP for your project.")
        prompt.say("Press Enter to keep defaults. Type 'clear' to remove a value.")
        prompt.say("Run 'aidp config --interactive' anytime to revisit these settings.")
        prompt.say("=" * 80 + "\n")
      end

      def skip_wizard?
        return false unless @existing_config.any?

        prompt.say("📝 Found existing configuration at #{relative_config_path}")
        skip = !prompt.yes?("Would you like to update it?", default: true)
        @saved = true if skip
        skip
      end

      # -------------------------------------------
      # Provider configuration
      # -------------------------------------------
      def discover_available_providers
        providers_dir = File.join(__dir__, "../providers")
        provider_files = Dir.glob("*.rb", base: providers_dir)

        # Exclude base classes
        excluded_files = ["base.rb"]
        provider_files -= excluded_files

        providers = {}

        provider_files.each do |file|
          provider_name = File.basename(file, ".rb")
          begin
            # Require the provider file if not already loaded
            require_relative "../providers/#{provider_name}"

            # Convert to class name (e.g., "anthropic" -> "Anthropic")
            class_name = provider_name.split("_").map(&:capitalize).join
            provider_class = Aidp::Providers.const_get(class_name)

            # Create a temporary instance to get the display name
            if provider_class.respond_to?(:new)
              instance = provider_class.new
              display_name = instance.respond_to?(:display_name) ? instance.display_name : provider_name.capitalize
              providers[display_name] = provider_name
            end
          rescue => e
            # Skip providers that can't be loaded, but don't fail the entire discovery
            warn "Warning: Could not load provider #{provider_name}: #{e.message}" if ENV["DEBUG"]
          end
        end

        providers
      end

      def configure_providers
        prompt.say("\n📦 Provider configuration")
        prompt.say("-" * 40)

        @config.fetch(:providers, {}).fetch(:llm, {})

        available_providers = discover_available_providers

        # TODO: Add default selection back once TTY-Prompt default validation issue is resolved
        # For now, the user will select manually from the dynamically discovered providers
        provider_choice = prompt.select("Select your primary provider:") do |menu|
          available_providers.each do |display_name, provider_name|
            menu.choice display_name, provider_name
          end
          menu.choice "Other/Custom", "custom"
        end

        # Save primary provider
        set([:harness, :default_provider], provider_choice) unless provider_choice == "custom"

        ensure_provider_billing_config(provider_choice) unless provider_choice == "custom"

        # Prompt for fallback providers (excluding the primary), pre-select existing
        existing_fallbacks = Array(get([:harness, :fallback_providers])).map(&:to_s) - [provider_choice]
        fallback_choices = available_providers.reject { |_, name| name == provider_choice }
        fallback_default_names = existing_fallbacks.filter_map { |provider_name| fallback_choices.key(provider_name) }

        prompt.say("\n💡 Use ↑/↓ arrows to navigate, SPACE to select/deselect, ENTER to confirm")
        fallback_selected = prompt.multi_select("Select fallback providers (used if primary fails):", default: fallback_default_names) do |menu|
          fallback_choices.each do |display_name, provider_name|
            menu.choice display_name, provider_name
          end
        end
        if ENV["AIDP_FALLBACK_DEBUG"] == "1"
          prompt.say("[debug] raw multi_select fallback_selected=#{fallback_selected.inspect}")
        end
        # Recovery: if multi_select unexpectedly returns empty and there were no existing fallbacks, offer a single-select
        if fallback_selected.empty? && existing_fallbacks.empty? && !fallback_choices.empty?
          if ENV["AIDP_FALLBACK_DEBUG"] == "1"
            prompt.say("[debug] invoking recovery single-select for first fallback")
          end
          if prompt.yes?("No fallback selected. Add one?", default: true)
            recovery_choice = prompt.select("Select a fallback provider:") do |menu|
              fallback_choices.each do |display_name, provider_name|
                menu.choice display_name, provider_name
              end
              menu.choice "Skip", :skip
            end
            fallback_selected = [recovery_choice] unless recovery_choice == :skip
          end
        end

        # If user selected none but we had existing fallbacks, confirm removal
        if fallback_selected.empty? && existing_fallbacks.any?
          keep = prompt.no?("No fallbacks selected. Remove existing fallbacks (#{existing_fallbacks.join(", ")})?", default: false)
          fallback_selected = existing_fallbacks if keep
        end

        # Remove any accidental duplication of primary provider & save (preserve order)
        cleaned_fallbacks = fallback_selected.reject { |name| name == provider_choice }
        set([:harness, :fallback_providers], cleaned_fallbacks)

        # Auto-create minimal provider configs for fallbacks if missing
        cleaned_fallbacks.each do |fp|
          prompt.say("[debug] ensuring billing config for fallback '#{fp}'") if ENV["AIDP_FALLBACK_DEBUG"] == "1"
          ensure_provider_billing_config(fp, force: true)
        end

        # Offer editing of existing provider configurations (primary + fallbacks)
        # (editable will be recomputed after any additional fallback additions)
        ([provider_choice] + cleaned_fallbacks).uniq.reject { |p| p == "custom" }

        # Optional: allow adding more fallbacks iteratively
        if prompt.yes?("Add another fallback provider?", default: false)
          loop do
            remaining = available_providers.reject { |_, name| ([provider_choice] + cleaned_fallbacks).include?(name) }
            break if remaining.empty?
            add_choice = prompt.select("Select additional fallback provider:") do |menu|
              remaining.each { |display, name| menu.choice display, name }
              menu.choice "Done", :done
            end
            break if add_choice == :done
            unless cleaned_fallbacks.include?(add_choice)
              cleaned_fallbacks << add_choice
              set([:harness, :fallback_providers], cleaned_fallbacks)
              ensure_provider_billing_config(add_choice, force: true)
            end
          end
        end
        # Recompute editable after additions
        editable = ([provider_choice] + cleaned_fallbacks).uniq.reject { |p| p == "custom" }
        if editable.any? && prompt.yes?("Edit provider configuration details (billing/model family)?", default: false)
          loop do
            # Build dynamic mapping of display names -> internal names for edit menu
            available_map = discover_available_providers # {display_name => internal_name}
            display_name_for = available_map.invert # {internal_name => display_name}
            to_edit = prompt.select("Select a provider to edit or add:") do |menu|
              editable.each do |prov|
                display_label = display_name_for.fetch(prov, prov.capitalize)
                menu.choice display_label, prov
              end
              # Sentinel option: add a new fallback provider that isn't yet in editable list
              remaining = available_map.values - editable
              if remaining.any?
                menu.choice "➕ Add fallback provider…", :add_fallback
              end
              menu.choice "Done", :done
            end

            case to_edit
            when :done
              break
            when :add_fallback
              # Allow user to pick from remaining providers by display name
              remaining_map = available_map.select { |disp, internal| !editable.include?(internal) && internal != provider_choice }
              add_choice = prompt.select("Select provider to add as fallback:") do |menu|
                remaining_map.each { |disp, internal| menu.choice disp, internal }
                menu.choice "Cancel", :cancel
              end
              next if add_choice == :cancel
              unless cleaned_fallbacks.include?(add_choice)
                cleaned_fallbacks << add_choice
                set([:harness, :fallback_providers], cleaned_fallbacks)
                prompt.say("[debug] ensuring billing config for newly added fallback '#{add_choice}'") if ENV["AIDP_FALLBACK_DEBUG"] == "1"
                ensure_provider_billing_config(add_choice, force: true)
                editable = ([provider_choice] + cleaned_fallbacks).uniq.reject { |p| p == "custom" }
              end
            else
              # Edit the selected provider or offer to remove it
              edit_or_remove_provider(to_edit, provider_choice, cleaned_fallbacks)
              # Refresh editable list after potential removal
              editable = ([provider_choice] + cleaned_fallbacks).uniq.reject { |p| p == "custom" }
            end
          end
        end

        # Provide informational note (no secret handling stored)
        show_provider_info_note(provider_choice) unless provider_choice == "custom"

        # Show summary of configured providers (replaces the earlier inline summary)
        show_provider_summary(provider_choice, cleaned_fallbacks) unless provider_choice == "custom"
      end

      # Removed MCP configuration step (MCP now expected to be provider-specific if used)

      # -------------------------------------------
      # Thinking tier configuration (automated model discovery)
      # -------------------------------------------
      def configure_thinking_tiers
        prompt.say("\n🧠 Thinking Tier Configuration")
        prompt.say("-" * 40)

        # Get configured providers
        primary_provider = get([:harness, :default_provider])
        fallback_providers = Array(get([:harness, :fallback_providers]))
        all_providers = ([primary_provider] + fallback_providers).compact.uniq

        if all_providers.empty?
          prompt.warn("⚠️  No providers configured. Skipping tier configuration.")
          return
        end

        # Check if user wants to use automated discovery
        has_existing_tiers = all_providers.any? do |provider|
          existing_tiers = get([:providers, provider.to_sym, :thinking_tiers])
          existing_tiers && !existing_tiers.empty?
        end

        if has_existing_tiers
          prompt.say("📝 Found existing tier configuration")
          unless prompt.yes?("Would you like to update it with discovered models?", default: false)
            return
          end
        elsif !prompt.yes?("Auto-configure thinking tiers with discovered models?", default: true)
          prompt.say("💡 You can run 'aidp models discover' later to see available models")
          return
        end

        # Run model discovery
        prompt.say("\n🔍 Discovering available models...")
        discovered_models = discover_models_for_providers(all_providers)

        if discovered_models.empty?
          prompt.warn("⚠️  No models discovered. Ensure provider CLIs are installed.")
          prompt.say("💡 You can configure tiers manually or run 'aidp models discover' later")
          return
        end

        # Display discovered models
        display_discovered_models(discovered_models)

        # Generate tier configuration (now provider-specific)
        tier_configs = generate_provider_tier_configurations(discovered_models)

        # Show preview
        prompt.say("\n📋 Proposed tier configuration:")
        display_provider_tier_preview(tier_configs)

        # Confirm and save
        if prompt.yes?("\nSave this tier configuration?", default: true)
          # Write to provider-specific paths
          tier_configs.each do |provider, provider_tiers|
            set([:providers, provider.to_sym, :thinking_tiers], provider_tiers)
          end
          prompt.ok("✅ Thinking tiers configured successfully")
        else
          prompt.say("💡 Skipped tier configuration. You can run 'aidp models discover' later")
        end
      end

      def discover_models_for_providers(providers)
        require_relative "../harness/ruby_llm_registry"

        registry = Aidp::Harness::RubyLLMRegistry.new
        all_models = {}

        providers.each do |provider|
          models = discover_models_from_registry(provider, registry)
          all_models[provider] = models if models.any?
        rescue => e
          Aidp.log_debug("setup_wizard", "discovery failed", provider: provider, error: e.message)
          # Continue with other providers
        end

        all_models
      end

      # Discover models for a provider from RubyLLM registry
      #
      # @param provider [String] Provider name (e.g., "anthropic")
      # @param registry [RubyLLMRegistry] Registry instance
      # @return [Array<Hash>] Models with tier classification
      def discover_models_from_registry(provider, registry)
        model_ids = registry.models_for_provider(provider)

        # Convert to model info hashes with tier classification
        model_ids.map do |model_id|
          info = registry.get_model_info(model_id)
          {
            name: model_id,
            tier: info[:tier],
            context_window: info[:context_window],
            capabilities: info[:capabilities]
          }
        end
      rescue => e
        Aidp.log_error("setup_wizard", "failed to discover models from registry",
          provider: provider, error: e.message)
        []
      end

      def display_discovered_models(discovered_models)
        discovered_models.each do |provider, models|
          prompt.say("\n✓ Found #{models.size} models for #{provider}:")
          by_tier = models.group_by { |m| m[:tier] }
          valid_thinking_tiers.each do |tier|
            tier_models = by_tier[tier] || []
            next if tier_models.empty?

            prompt.say("  #{tier.capitalize} tier: #{tier_models.size} model#{"s" unless tier_models.size == 1}")
          end
        end
      end

      def generate_provider_tier_configurations(discovered_models)
        provider_configs = {}

        # Organize by provider first, then by tier
        discovered_models.each do |provider, models|
          provider_tiers = {}

          # Configure the three most common tiers: mini, standard, and pro
          DEFAULT_AUTOCONFIG_TIERS.each do |tier|
            tier_models = find_models_for_tier(models, tier)

            # Add to config if we found any models for this tier
            if tier_models.any?
              provider_tiers[tier.to_sym] = {
                models: tier_models.map { |m| m[:name] }
              }
            end
          end

          # Only add provider if it has at least one tier configured
          provider_configs[provider] = provider_tiers if provider_tiers.any?
        end

        provider_configs
      end

      def find_model_for_tier(models, target_tier)
        return nil unless models

        # Map pro -> advanced for registry compatibility
        registry_tier = (target_tier == "pro") ? "advanced" : target_tier

        models.find { |m| m[:tier] == registry_tier }
      end

      def find_models_for_tier(models, target_tier)
        return [] unless models

        # Map pro -> advanced for registry compatibility
        registry_tier = (target_tier == "pro") ? "advanced" : target_tier

        models.select { |m| m[:tier] == registry_tier }
      end

      def display_provider_tier_preview(provider_configs)
        return if provider_configs.empty?

        provider_configs.each do |provider, provider_tiers|
          prompt.say("  #{provider}:")
          provider_tiers.each do |tier, tier_config|
            models = tier_config[:models] || []
            prompt.say("    #{tier}:")
            models.each do |model_name|
              prompt.say("      - #{model_name}")
            end
          end
          prompt.say("") # Blank line between providers
        end
      end

      # -------------------------------------------
      # Work loop configuration
      # -------------------------------------------
      def configure_work_loop
        prompt.say("\n⚙️  Work loop configuration")
        prompt.say("-" * 40)

        configure_test_commands
        configure_linting
        configure_watch_patterns
        configure_guards
        configure_coverage
        configure_interactive_testing
        configure_vcs_behavior
      end

      def configure_test_commands
        existing = get([:work_loop, :test]) || {}

        unit = ask_with_default("Unit test command", existing[:unit] || detect_unit_test_command)
        integration = ask_with_default("Integration test command", existing[:integration])
        e2e = ask_with_default("End-to-end test command", existing[:e2e])

        timeout = ask_with_default("Test timeout (seconds)", (existing[:timeout_seconds] || 1800).to_s) { |value| value.to_i }

        set([:work_loop, :test], {
          unit: unit,
          integration: integration,
          e2e: e2e,
          timeout_seconds: timeout
        }.compact)

        validate_command(unit)
        validate_command(integration)
        validate_command(e2e)
      end

      def configure_linting
        existing = get([:work_loop, :lint]) || {}

        lint_cmd = ask_with_default("Lint command", existing[:command] || detect_lint_command)
        format_cmd = ask_with_default("Format command", existing[:format] || detect_format_command)
        autofix = prompt.yes?("Run formatter automatically?", default: existing.fetch(:autofix, false))

        set([:work_loop, :lint], {
          command: lint_cmd,
          format: format_cmd,
          autofix: autofix
        })

        validate_command(lint_cmd)
        validate_command(format_cmd)
      end

      def configure_watch_patterns
        existing = get([:work_loop, :test, :watch]) || {}
        default_patterns = detect_watch_patterns

        watch_patterns = ask_list("Test watch patterns (comma-separated)", existing.fetch(:patterns, default_patterns))
        set([:work_loop, :test, :watch], {patterns: watch_patterns}) if watch_patterns.any?
      end

      def configure_guards
        existing = get([:work_loop, :guards]) || {}

        include_patterns = ask_list("Guard include patterns", existing[:include] || detect_source_patterns)
        exclude_patterns = ask_list("Guard exclude patterns", existing[:exclude] || ["node_modules/**", "dist/**", "build/**"])
        max_lines = ask_with_default("Max lines changed per commit", (existing[:max_lines_changed_per_commit] || 300).to_s) { |value| value.to_i }
        protected_paths = ask_list("Protected paths (require confirmation)", existing[:protected_paths] || [], allow_empty: true)
        confirmation_required = prompt.yes?("Require confirmation before editing protected paths?", default: existing.fetch(:confirm_protected, true))

        set([:work_loop, :guards], {
          include: include_patterns,
          exclude: exclude_patterns,
          max_lines_changed_per_commit: max_lines,
          protected_paths: protected_paths,
          confirm_protected: confirmation_required
        })
      end

      def configure_coverage
        prompt.say("\n📊 Coverage configuration")
        existing = get([:work_loop, :coverage]) || {}

        enabled = prompt.yes?("Enable coverage tracking?", default: existing.fetch(:enabled, false))
        return set([:work_loop, :coverage], {enabled: false}) unless enabled

        coverage_tool_choices = [
          ["SimpleCov (Ruby)", "simplecov"],
          ["NYC/Istanbul (JavaScript)", "nyc"],
          ["Coverage.py (Python)", "coverage.py"],
          ["go test -cover (Go)", "go-cover"],
          ["Jest (JavaScript)", "jest"],
          ["Other", "other"]
        ]
        coverage_tool_default = existing[:tool]
        coverage_tool_default_label = coverage_tool_choices.find { |label, value| value == coverage_tool_default }&.first

        tool = prompt.select("Which coverage tool do you use?", default: coverage_tool_default_label) do |menu|
          coverage_tool_choices.each { |label, value| menu.choice label, value }
        end

        run_command = ask_with_default("Coverage run command", existing[:run_command] || detect_coverage_command(tool))
        report_paths = ask_list("Coverage report paths", existing[:report_paths] || detect_coverage_report_paths(tool))
        fail_on_drop = prompt.yes?("Fail on coverage drop?", default: existing.fetch(:fail_on_drop, false))

        minimum_coverage_default = existing[:minimum_coverage]&.to_s
        minimum_coverage_answer = ask_with_default("Minimum coverage % (optional - press enter to skip)", minimum_coverage_default)
        minimum_coverage = if minimum_coverage_answer && !minimum_coverage_answer.to_s.strip.empty?
          minimum_coverage_answer.to_f
        end

        set([:work_loop, :coverage], {
          enabled: true,
          tool: tool,
          run_command: run_command,
          report_paths: report_paths,
          fail_on_drop: fail_on_drop,
          minimum_coverage: minimum_coverage
        }.compact)

        validate_command(run_command)
      end

      def configure_interactive_testing
        prompt.say("\n🎯 Interactive testing configuration")
        existing = get([:work_loop, :interactive_testing]) || {}

        enabled = prompt.yes?("Enable interactive testing tools?", default: existing.fetch(:enabled, false))
        return set([:work_loop, :interactive_testing], {enabled: false}) unless enabled

        app_type_choices = [
          ["Web application", "web"],
          ["CLI application", "cli"],
          ["Desktop application", "desktop"]
        ]
        app_type_default = existing[:app_type]
        app_type_default_label = app_type_choices.find { |label, value| value == app_type_default }&.first

        app_type = prompt.select("What type of application are you testing?", default: app_type_default_label) do |menu|
          app_type_choices.each { |label, value| menu.choice label, value }
        end

        tools = {}

        case app_type
        when "web"
          tools[:web] = configure_web_testing_tools(existing.dig(:tools, :web) || {})
        when "cli"
          tools[:cli] = configure_cli_testing_tools(existing.dig(:tools, :cli) || {})
        when "desktop"
          tools[:desktop] = configure_desktop_testing_tools(existing.dig(:tools, :desktop) || {})
        end

        set([:work_loop, :interactive_testing], {
          enabled: true,
          app_type: app_type,
          tools: tools
        })
      end

      def configure_web_testing_tools(existing)
        tools = {}

        playwright_enabled = prompt.yes?("Enable Playwright MCP?", default: existing.dig(:playwright_mcp, :enabled) || false)
        if playwright_enabled
          playwright_run = ask_with_default("Playwright run command", existing.dig(:playwright_mcp, :run) || "npx playwright test")
          playwright_specs = ask_with_default("Playwright specs directory", existing.dig(:playwright_mcp, :specs_dir) || ".aidp/tests/web")
          tools[:playwright_mcp] = {enabled: true, run: playwright_run, specs_dir: playwright_specs}
        end

        chrome_enabled = prompt.yes?("Enable Chrome DevTools MCP?", default: existing.dig(:chrome_devtools_mcp, :enabled) || false)
        if chrome_enabled
          chrome_run = ask_with_default("Chrome DevTools run command", existing.dig(:chrome_devtools_mcp, :run) || "")
          chrome_specs = ask_with_default("Chrome DevTools specs directory", existing.dig(:chrome_devtools_mcp, :specs_dir) || ".aidp/tests/web")
          tools[:chrome_devtools_mcp] = {enabled: true, run: chrome_run, specs_dir: chrome_specs}
        end

        tools
      end

      def configure_cli_testing_tools(existing)
        tools = {}

        expect_enabled = prompt.yes?("Enable expect scripts?", default: existing.dig(:expect, :enabled) || false)
        if expect_enabled
          expect_run = ask_with_default("Expect run command", existing.dig(:expect, :run) || "expect .aidp/tests/cli/smoke.exp")
          expect_specs = ask_with_default("Expect specs directory", existing.dig(:expect, :specs_dir) || ".aidp/tests/cli")
          tools[:expect] = {enabled: true, run: expect_run, specs_dir: expect_specs}
        end

        tools
      end

      def configure_desktop_testing_tools(existing)
        tools = {}

        applescript_enabled = prompt.yes?("Enable AppleScript testing?", default: existing.dig(:applescript, :enabled) || false)
        if applescript_enabled
          applescript_run = ask_with_default("AppleScript run command", existing.dig(:applescript, :run) || "osascript .aidp/tests/desktop/smoke.scpt")
          applescript_specs = ask_with_default("AppleScript specs directory", existing.dig(:applescript, :specs_dir) || ".aidp/tests/desktop")
          tools[:applescript] = {enabled: true, run: applescript_run, specs_dir: applescript_specs}
        end

        screen_reader_enabled = prompt.yes?("Enable screen reader testing?", default: existing.dig(:screen_reader, :enabled) || false)
        if screen_reader_enabled
          screen_reader_notes = ask_with_default("Screen reader testing notes (optional)", existing.dig(:screen_reader, :notes) || "VoiceOver scripted checks")
          tools[:screen_reader] = {enabled: true, notes: screen_reader_notes}
        end

        tools
      end

      def configure_vcs_behavior
        prompt.say("\n🗂️  Version control configuration")
        existing = get([:work_loop, :version_control]) || {}

        # Detect VCS
        detected_vcs = detect_vcs_tool
        vcs_choices = [
          ["git", "git"],
          ["svn", "svn"],
          ["none (no VCS)", "none"]
        ]
        vcs_default = existing[:tool] || detected_vcs || "git"
        vcs_default_label = vcs_choices.find { |label, value| value == vcs_default }&.first

        vcs_tool = if detected_vcs
          prompt.select("Detected #{detected_vcs}. Use this version control system?", default: vcs_default_label) do |menu|
            vcs_choices.each { |label, value| menu.choice label, value }
          end
        else
          prompt.select("Which version control system do you use?", default: vcs_default_label) do |menu|
            vcs_choices.each { |label, value| menu.choice label, value }
          end
        end

        return set([:work_loop, :version_control], {tool: "none", behavior: "nothing"}) if vcs_tool == "none"

        prompt.say("\n📋 Commit Behavior (applies to copilot/interactive mode only)")
        prompt.say("Note: Watch mode and fully automatic daemon mode will always commit changes.")

        # Map value defaults to choice labels for TTY::Prompt validation
        behavior_choices = [
          ["Do nothing (manual git operations)", "nothing"],
          ["Stage changes only", "stage"],
          ["Stage and commit changes", "commit"]
        ]
        behavior_default = existing[:behavior] || "nothing"
        behavior_default_label = behavior_choices.find { |label, value| value == behavior_default }&.first

        behavior = prompt.select("In copilot mode, should aidp:", default: behavior_default_label) do |menu|
          behavior_choices.each { |label, value| menu.choice label, value }
        end

        # Commit message configuration
        commit_config = configure_commit_messages(existing, behavior)

        # PR configuration (only relevant for git with remote)
        pr_config = if vcs_tool == "git" && behavior == "commit"
          configure_pull_requests(existing)
        else
          {auto_create_pr: false}
        end

        set([:work_loop, :version_control], {
          tool: vcs_tool,
          behavior: behavior,
          **commit_config,
          **pr_config
        })
      end

      def configure_commit_messages(existing, behavior)
        return {} unless behavior == "commit"

        prompt.say("\n💬 Commit Message Configuration")

        # Conventional commits
        conventional_commits = prompt.yes?(
          "Use conventional commit format (e.g., 'feat:', 'fix:', 'docs:')?",
          default: existing.fetch(:conventional_commits, false)
        )

        # Commit message style
        commit_style = if conventional_commits
          commit_style_choices = [
            ["Default (e.g., 'feat: add user authentication')", "default"],
            ["Angular (with scope: 'feat(auth): add login')", "angular"],
            ["Emoji (e.g., '✨ feat: add user authentication')", "emoji"]
          ]
          commit_style_default = existing[:commit_style] || "default"
          commit_style_default_label = commit_style_choices.find { |label, value| value == commit_style_default }&.first

          prompt.select("Conventional commit style:", default: commit_style_default_label) do |menu|
            commit_style_choices.each { |label, value| menu.choice label, value }
          end
        else
          "default"
        end

        # Co-authored-by attribution
        co_author = prompt.yes?(
          "Include 'Co-authored-by: <AI Provider>' in commit messages?",
          default: existing.fetch(:co_author_ai, true)
        )

        {
          conventional_commits: conventional_commits,
          commit_style: commit_style,
          co_author_ai: co_author
        }
      end

      def configure_pull_requests(existing)
        prompt.say("\n🔀 Pull Request Configuration")

        # Check if remote exists
        has_remote = system("git remote -v > /dev/null 2>&1")

        unless has_remote
          prompt.say("No git remote detected. PR creation will be disabled.")
          return {auto_create_pr: false}
        end

        auto_create_pr = prompt.yes?(
          "Automatically create pull requests after successful builds? (watch/daemon mode only)",
          default: existing.fetch(:auto_create_pr, false)
        )

        if auto_create_pr
          pr_strategy_choices = [
            ["Create as draft PR (safe, allows review before merge)", "draft"],
            ["Create as ready PR (immediately reviewable)", "ready"],
            ["Create and auto-merge (fully autonomous, requires approval rules)", "auto_merge"]
          ]
          pr_strategy_default = existing[:pr_strategy] || "draft"
          pr_strategy_default_label = pr_strategy_choices.find { |label, value| value == pr_strategy_default }&.first

          pr_strategy = prompt.select("PR creation strategy:", default: pr_strategy_default_label) do |menu|
            pr_strategy_choices.each { |label, value| menu.choice label, value }
          end

          {
            auto_create_pr: true,
            pr_strategy: pr_strategy
          }
        else
          {auto_create_pr: false}
        end
      end

      def configure_branching
        prompt.say("\n🌿 Branching strategy")
        prompt.say("-" * 40)
        existing = get([:work_loop, :branching]) || {}

        prefix = ask_with_default("Branch prefix for work loops", existing[:prefix] || "aidp")
        slug_format = ask_with_default("Slug format (use %{id} and %{title})", existing[:slug_format] || "issue-%{id}-%{title}")
        checkpoint_tag = ask_with_default("Checkpoint tag template", existing[:checkpoint_tag] || "aidp-start/%{id}")

        set([:work_loop, :branching], {
          prefix: prefix,
          slug_format: slug_format,
          checkpoint_tag: checkpoint_tag
        })
      end

      def configure_artifacts
        prompt.say("\n📁 Artifact storage")
        prompt.say("-" * 40)
        existing = get([:work_loop, :artifacts]) || {}

        evidence_dir = ask_with_default("Evidence pack directory", existing[:evidence_dir] || ".aidp/evidence")
        logs_dir = ask_with_default("Logs directory", existing[:logs_dir] || ".aidp/logs")
        screenshots_dir = ask_with_default("Screenshots directory", existing[:screenshots_dir] || ".aidp/screenshots")

        set([:work_loop, :artifacts], {
          evidence_dir: evidence_dir,
          logs_dir: logs_dir,
          screenshots_dir: screenshots_dir
        })
      end

      # -------------------------------------------
      # NFRs & libraries
      # -------------------------------------------
      def configure_nfrs
        prompt.say("\n📋 Non-functional requirements & preferred libraries")
        prompt.say("-" * 40)

        # Check existing configuration for previous choice
        existing_configure = @config.dig(:nfrs, :configure)
        default_configure = existing_configure.nil? || existing_configure

        configure = prompt.yes?("Configure NFRs?", default: default_configure)

        unless configure
          Aidp.log_debug("setup_wizard.nfrs", "opt_out")
          return set([:nfrs, :configure], false)
        end

        set([:nfrs, :configure], true)
        categories = %i[performance security reliability accessibility internationalization]
        categories.each do |category|
          existing = get([:nfrs, category])
          value = ask_multiline("#{category.to_s.capitalize} requirements", existing)
          value.nil? ? delete_path([:nfrs, category]) : set([:nfrs, category], value)
        end

        configure_preferred_libraries
        configure_environment_overrides
      end

      def configure_preferred_libraries
        return unless prompt.yes?("Configure preferred libraries/tools?", default: true)

        stack = detect_stack
        prompt.say("\n📚 Detected stack: #{(stack == :other) ? "Custom" : stack.to_s.capitalize}")
        case stack
        when :rails
          set([:nfrs, :preferred_libraries, :rails], configure_rails_libraries)
        when :node
          set([:nfrs, :preferred_libraries, :node], configure_node_libraries)
        when :python
          set([:nfrs, :preferred_libraries, :python], configure_python_libraries)
        else
          custom_stack = ask_with_default("Name this stack (e.g. go, php)", "custom")
          libs = ask_list("Preferred libraries (comma-separated)", [])
          set([:nfrs, :preferred_libraries, custom_stack.to_sym], libs)
        end
      end

      def configure_environment_overrides
        return unless prompt.yes?("Add environment-specific overrides?", default: false)

        environments = prompt.multi_select("Select environments:", default: []) do |menu|
          menu.choice "Development", :development
          menu.choice "Test", :test
          menu.choice "Production", :production
        end

        environments.each do |env|
          categories = ask_multiline("#{env.to_s.capitalize} overrides", get([:nfrs, :environment_overrides, env]))
          set([:nfrs, :environment_overrides, env], categories) unless categories.nil? || categories.empty?
        end
      end

      def configure_rails_libraries
        existing = get([:nfrs, :preferred_libraries, :rails]) || {}
        {
          auth: ask_with_default("Authentication gem", existing[:auth] || "devise"),
          authz: ask_with_default("Authorization gem", existing[:authz] || "pundit"),
          jobs: ask_with_default("Background jobs", existing[:jobs] || "sidekiq"),
          testing: ask_list("Testing gems", existing[:testing] || %w[rspec factory_bot])
        }
      end

      def configure_node_libraries
        existing = get([:nfrs, :preferred_libraries, :node]) || {}
        {
          validation: ask_with_default("Validation library", existing[:validation] || "zod"),
          orm: ask_with_default("ORM/Database", existing[:orm] || "prisma"),
          testing: ask_with_default("Testing framework", existing[:testing] || "jest")
        }
      end

      def configure_python_libraries
        existing = get([:nfrs, :preferred_libraries, :python]) || {}
        linting = ask_list("Linting tools", existing[:linting] || %w[ruff mypy])
        {
          validation: ask_with_default("Validation library", existing[:validation] || "pydantic"),
          testing: ask_with_default("Testing framework", existing[:testing] || "pytest"),
          linting: linting
        }
      end

      # -------------------------------------------
      # Logging & modes
      # -------------------------------------------
      def configure_logging
        prompt.say("\n📝 Logging configuration")
        prompt.say("-" * 40)
        existing = get([:logging]) || {}

        log_level_choices = [
          ["Debug", "debug"],
          ["Info", "info"],
          ["Error", "error"]
        ]
        log_level_default = existing[:level] || "info"
        log_level_default_label = log_level_choices.find { |label, value| value == log_level_default }&.first

        log_level = prompt.select("Log level:", default: log_level_default_label) do |menu|
          log_level_choices.each { |label, value| menu.choice label, value }
        end
        json = prompt.yes?("Use JSON log format?", default: existing.fetch(:json, false))
        max_size = ask_with_default("Max log size (MB)", (existing[:max_size_mb] || 10).to_s) { |value| value.to_i }
        max_backups = ask_with_default("Max backup files", (existing[:max_backups] || 5).to_s) { |value| value.to_i }

        set([:logging], {
          level: log_level,
          json: json,
          max_size_mb: max_size,
          max_backups: max_backups
        })
      end

      def configure_modes
        prompt.say("\n🚀 Operational modes")
        prompt.say("-" * 40)
        existing = get([:modes]) || {}

        background = prompt.yes?("Run in background mode by default?", default: existing.fetch(:background_default, false))
        watch = prompt.yes?("Enable watch mode integrations?", default: existing.fetch(:watch_enabled, false))
        quick_mode = prompt.yes?("Enable quick mode (short timeouts) by default?", default: existing.fetch(:quick_mode_default, false))

        set([:modes], {
          background_default: background,
          watch_enabled: watch,
          quick_mode_default: quick_mode
        })

        # Configure watch mode settings if enabled
        configure_watch_mode if watch
      end

      def configure_watch_mode
        prompt.say("\n👀 Watch Mode Configuration")
        prompt.say("-" * 40)

        configure_watch_safety
        configure_watch_labels
        configure_watch_label_creation
      end

      def configure_watch_safety
        prompt.say("\n🔒 Watch mode safety settings")
        existing = get([:watch, :safety]) || {}

        allow_public_repos = prompt.yes?(
          "Allow watch mode on public repositories?",
          default: existing.fetch(:allow_public_repos, false)
        )

        prompt.say("\n📝 Author allowlist (GitHub usernames allowed to trigger watch mode)")
        prompt.say("  Leave empty to allow all authors (not recommended for public repos)")
        author_allowlist = ask_list(
          "Author allowlist (comma-separated GitHub usernames)",
          existing[:author_allowlist] || [],
          allow_empty: true
        )

        require_container = prompt.yes?(
          "Require watch mode to run in a container?",
          default: existing.fetch(:require_container, true)
        )

        set([:watch, :safety], {
          allow_public_repos: allow_public_repos,
          author_allowlist: author_allowlist,
          require_container: require_container
        })
      end

      def configure_watch_labels
        prompt.say("\n🏷️  Watch mode label configuration")
        prompt.say("  Configure GitHub issue and PR labels that trigger watch mode actions")
        existing = get([:watch, :labels]) || {}

        plan_trigger = ask_with_default(
          "Label to trigger plan generation",
          existing[:plan_trigger] || "aidp-plan"
        )

        needs_input = ask_with_default(
          "Label for plans needing user input",
          existing[:needs_input] || "aidp-needs-input"
        )

        ready_to_build = ask_with_default(
          "Label for plans ready to build",
          existing[:ready_to_build] || "aidp-ready"
        )

        build_trigger = ask_with_default(
          "Label to trigger implementation",
          existing[:build_trigger] || "aidp-build"
        )

        review_trigger = ask_with_default(
          "Label to trigger code review",
          existing[:review_trigger] || "aidp-review"
        )

        ci_fix_trigger = ask_with_default(
          "Label to trigger CI remediation",
          existing[:ci_fix_trigger] || "aidp-fix-ci"
        )

        change_request_trigger = ask_with_default(
          "Label to trigger PR change implementation",
          existing[:change_request_trigger] || "aidp-request-changes"
        )

        set([:watch, :labels], {
          plan_trigger: plan_trigger,
          needs_input: needs_input,
          ready_to_build: ready_to_build,
          build_trigger: build_trigger,
          review_trigger: review_trigger,
          ci_fix_trigger: ci_fix_trigger,
          change_request_trigger: change_request_trigger
        })
      end

      def configure_watch_label_creation
        prompt.say("\n🏷️  GitHub Label Auto-Creation")
        prompt.say("  Automatically create GitHub labels for watch mode if they don't exist")

        Aidp.log_debug("setup_wizard.label_creation", "start")

        # Ask if user wants to auto-create labels
        unless prompt.yes?("Auto-create GitHub labels if missing?", default: true)
          Aidp.log_debug("setup_wizard.label_creation", "user_declined")
          return
        end

        # Check if gh CLI is available
        unless gh_cli_available?
          prompt.warn("⚠️  GitHub CLI (gh) not found. Install it to enable label auto-creation.")
          prompt.say("   Visit: https://cli.github.com/")
          Aidp.log_debug("setup_wizard.label_creation", "gh_not_available")
          return
        end

        # Extract repository info
        repo_info = extract_repo_info
        unless repo_info
          prompt.warn("⚠️  Could not determine GitHub repository from git remote.")
          prompt.say("   Ensure you're in a git repository with a GitHub remote configured.")
          Aidp.log_debug("setup_wizard.label_creation", "repo_info_failed")
          return
        end

        owner, repo = repo_info
        Aidp.log_debug("setup_wizard.label_creation", "repo_detected", owner: owner, repo: repo)
        prompt.say("📦 Repository: #{owner}/#{repo}")

        # Fetch existing labels
        existing_labels = fetch_existing_labels(owner, repo)
        unless existing_labels
          prompt.warn("⚠️  Failed to fetch existing labels. Check your GitHub authentication.")
          Aidp.log_debug("setup_wizard.label_creation", "fetch_labels_failed")
          return
        end

        Aidp.log_debug("setup_wizard.label_creation", "existing_labels_fetched", count: existing_labels.size)

        # Get configured label names
        labels_config = get([:watch, :labels]) || {}
        required_labels = collect_required_labels(labels_config)

        # Determine which labels need to be created
        labels_to_create = required_labels.reject { |label| existing_labels.include?(label[:name]) }

        if labels_to_create.empty?
          prompt.ok("✅ All required labels already exist!")
          Aidp.log_debug("setup_wizard.label_creation", "all_labels_exist")
          return
        end

        # Show labels to be created
        prompt.say("\n📝 Labels to create:")
        labels_to_create.each do |label|
          prompt.say("  • #{label[:name]} (#{label[:color]})")
        end

        # Confirm creation
        unless prompt.yes?("Create these labels?", default: true)
          Aidp.log_debug("setup_wizard.label_creation", "creation_declined")
          return
        end

        # Create labels
        create_labels(owner, repo, labels_to_create)
      end

      # Check if gh CLI is available
      def gh_cli_available?
        require "open3"
        _stdout, _stderr, status = Open3.capture3("gh", "--version")
        Aidp.log_debug("setup_wizard.gh_check", "version_check", success: status.success?)
        status.success?
      rescue Errno::ENOENT
        Aidp.log_debug("setup_wizard.gh_check", "not_found")
        false
      end

      # Extract repository owner and name from git remote
      def extract_repo_info
        require "open3"
        stdout, stderr, status = Open3.capture3("git", "remote", "get-url", "origin")

        unless status.success?
          Aidp.log_debug("setup_wizard.repo_extraction", "git_remote_failed", error: stderr)
          return nil
        end

        remote_url = stdout.strip
        Aidp.log_debug("setup_wizard.repo_extraction", "remote_url_found", url: remote_url)

        # Parse GitHub URL (supports both HTTPS and SSH formats)
        # HTTPS: https://github.com/owner/repo.git
        # SSH: git@github.com:owner/repo.git
        if remote_url =~ %r{github\.com[:/]([^/]+)/(.+?)(?:\.git)?$}
          owner = Regexp.last_match(1)
          repo = Regexp.last_match(2)
          Aidp.log_debug("setup_wizard.repo_extraction", "parsed", owner: owner, repo: repo)
          [owner, repo]
        else
          Aidp.log_debug("setup_wizard.repo_extraction", "parse_failed", url: remote_url)
          nil
        end
      rescue => e
        Aidp.log_error("setup_wizard.repo_extraction", "exception", error: e.message)
        nil
      end

      # Fetch existing labels from GitHub
      def fetch_existing_labels(owner, repo)
        require "open3"
        stdout, stderr, status = Open3.capture3("gh", "label", "list", "-R", "#{owner}/#{repo}", "--json", "name", "--jq", ".[].name")

        unless status.success?
          Aidp.log_error("setup_wizard.fetch_labels", "gh_failed", error: stderr)
          return nil
        end

        labels = stdout.strip.split("\n").map(&:strip).reject(&:empty?)
        Aidp.log_debug("setup_wizard.fetch_labels", "fetched", count: labels.size)
        labels
      rescue => e
        Aidp.log_error("setup_wizard.fetch_labels", "exception", error: e.message)
        nil
      end

      # Collect required labels with their default colors
      def collect_required_labels(labels_config)
        default_colors = {
          plan_trigger: "0E8A16",        # Green
          needs_input: "D93F0B",         # Red
          ready_to_build: "0075CA",      # Blue
          build_trigger: "5319E7",       # Purple
          review_trigger: "FBCA04",      # Yellow
          ci_fix_trigger: "D93F0B",      # Red
          change_request_trigger: "F9D0C4",  # Light pink
          in_progress: "1D76DB"          # Dark blue (internal coordination)
        }

        required = []
        labels_config.each do |key, name|
          next if name.nil? || name.to_s.strip.empty?

          color = default_colors[key] || "EDEDED"  # Gray fallback
          required << {name: name, color: color, key: key}
        end

        # Always include the internal in-progress label for coordination
        required << {
          name: "aidp-in-progress",
          color: default_colors[:in_progress],
          key: :in_progress,
          internal: true
        }

        Aidp.log_debug("setup_wizard.collect_labels", "collected", count: required.size)
        required
      end

      # Create labels on GitHub
      def create_labels(owner, repo, labels)
        require "open3"

        created = 0
        failed = 0

        labels.each do |label|
          Aidp.log_debug("setup_wizard.create_label", "creating", name: label[:name], color: label[:color])

          _stdout, stderr, status = Open3.capture3(
            "gh", "label", "create", label[:name],
            "--color", label[:color],
            "-R", "#{owner}/#{repo}"
          )

          if status.success?
            prompt.ok("  ✅ Created: #{label[:name]}")
            Aidp.log_info("setup_wizard.create_label", "success", name: label[:name])
            created += 1
          else
            prompt.warn("  ⚠️  Failed to create: #{label[:name]} - #{stderr.strip}")
            Aidp.log_error("setup_wizard.create_label", "failed", name: label[:name], error: stderr.strip)
            failed += 1
          end
        rescue => e
          prompt.warn("  ⚠️  Error creating #{label[:name]}: #{e.message}")
          Aidp.log_error("setup_wizard.create_label", "exception", name: label[:name], error: e.message)
          failed += 1
        end

        # Summary
        prompt.say("")
        if created > 0
          prompt.ok("✅ Successfully created #{created} label#{"s" unless created == 1}")
        end
        if failed > 0
          prompt.warn("⚠️  Failed to create #{failed} label#{"s" unless failed == 1}")
        end

        Aidp.log_info("setup_wizard.create_labels", "complete", created: created, failed: failed)
      end

      # -------------------------------------------
      # Preview & persistence
      # -------------------------------------------
      def generate_yaml
        payload = @config.dup
        payload[:schema_version] = SCHEMA_VERSION
        payload[:generated_by] = "aidp setup wizard v#{Aidp::VERSION}"
        payload[:generated_at] = Time.now.utc.iso8601

        yaml = deep_stringify(payload).to_yaml
        comment_header + annotate_yaml(yaml)
      end

      def comment_header
        <<~HEADER
          # AIDP configuration generated by the interactive setup wizard.
          # Re-run `aidp config --interactive` to update. Manual edits are preserved.
        HEADER
      end

      def annotate_yaml(yaml)
        yaml
          .sub(/^schema_version:/, "# Tracks configuration migrations\nschema_version:")
          .sub(/^providers:/, "# Provider configuration (no secrets stored)\nproviders:")
          .sub(/^work_loop:/, "# Work loop execution settings\nwork_loop:")
          .sub(/^nfrs:/, "# Non-functional requirements to reference during planning\nnfrs:")
          .sub(/^logging:/, "# Logging configuration\nlogging:")
          .sub(/^modes:/, "# Defaults for background/watch/quick modes\nmodes:")
          .sub(/^watch:/, "# Watch mode safety and label configuration\nwatch:")
      end

      def display_preview(yaml_content)
        prompt.say("\n" + "=" * 80)
        prompt.say("📄 Configuration preview")
        prompt.say("=" * 80)
        prompt.say(yaml_content)
        prompt.say("=" * 80 + "\n")
      end

      def display_diff(yaml_content)
        existing_yaml = File.read(config_path)
        diff_lines = line_diff(existing_yaml, yaml_content)
        return if diff_lines.empty?

        prompt.say("🔍 Diff with existing configuration:")
        diff_lines.each do |line|
          case line[0]
          when "+"
            prompt.say(line, color: :green)
          when "-"
            prompt.say(line, color: :red)
          else
            prompt.say(line, color: :bright_black)
          end
        end
        prompt.say("")
      rescue Errno::ENOENT
        nil
      end

      def dry_run_mode?(yaml_content)
        return false unless dry_run

        prompt.ok("Dry run mode active – configuration was NOT written.")
        display_warnings
        @saved = false
        true
      end

      def save_config(yaml_content)
        Aidp::ConfigPaths.ensure_config_dir(project_dir)
        File.write(config_path, yaml_content)

        # Generate devcontainer if managed
        generate_devcontainer_file
      end

      def display_warnings
        return if @warnings.empty?

        prompt.warn("\nWarnings:")
        @warnings.each { |warning| prompt.warn("  • #{warning}") }
      end

      def show_next_steps
        prompt.say("\n🎉 Setup complete!")
        prompt.say("\nNext steps:")
        prompt.say("  1. Configure provider tools (set required API keys or connections).")
        prompt.say("  2. Run 'aidp' to start a work loop.")
        prompt.say("  3. Run 'aidp watch <owner/repo>' to enable watch mode automation.")
        prompt.say("")
      end

      # -------------------------------------------
      # Helpers
      # -------------------------------------------
      def ask_with_default(question, default = nil)
        existing_text = default.nil? ? "" : " [#{display_value(default)}]"
        answer = prompt.ask("#{question}#{existing_text}:")

        if answer.nil? || answer.strip.empty?
          return default if default.nil? || !block_given?
          return yield(default)
        end

        return nil if answer.strip.casecmp("clear").zero?

        block_given? ? yield(answer) : answer
      end

      def ask_multiline(question, default)
        prompt.say("#{question}:")
        prompt.say("  (Enter text; submit empty line to finish. Type 'clear' alone to remove.)")
        lines = []
        loop do
          line = prompt.ask("", default: nil)
          break if line.nil? || line.empty?
          return nil if line.strip.casecmp("clear").zero?
          lines << line
        end
        return default if lines.empty?

        lines.join("\n")
      end

      def ask_list(question, existing = [], allow_empty: false)
        existing = Array(existing).compact
        display = existing.any? ? " [#{existing.join(", ")}]" : ""
        answer = prompt.ask("#{question}#{display}:")

        return existing if answer.nil? || answer.strip.empty?
        return [] if answer.strip.casecmp("clear").zero? && allow_empty

        answer.split(",").map { |item| item.strip }.reject(&:empty?)
      end

      def validate_command(command)
        return if command.nil? || command.strip.empty?
        return if command.start_with?("echo")

        executable = command.split(/\s+/).first
        return if Aidp::Util.which(executable)

        @warnings << "Command '#{command}' not found in PATH."
      end

      def fetch_retry_attempts(llm)
        policy = llm[:retry_policy] || {}
        (policy[:attempts] || 3).to_s
      end

      def fetch_retry_backoff(llm)
        policy = llm[:retry_policy] || {}
        (policy[:backoff_seconds] || 10).to_s
      end

      def detect_unit_test_command
        return "bundle exec rspec" if project_file?("Gemfile") && Dir.exist?(File.join(project_dir, "spec"))
        return "npm test" if project_file?("package.json")
        return "pytest" if project_file?("pytest.ini") || Dir.exist?(File.join(project_dir, "tests"))
        "echo 'No tests configured'"
      end

      def detect_lint_command
        return "bundle exec rubocop" if project_file?(".rubocop.yml")
        return "npm run lint" if project_file?("package.json")
        return "ruff check ." if project_file?("pyproject.toml")
        "echo 'No linter configured'"
      end

      def detect_format_command
        return "bundle exec rubocop -A" if project_file?(".rubocop.yml")
        return "npm run format" if project_file?("package.json")
        return "ruff format ." if project_file?("pyproject.toml")
        "echo 'No formatter configured'"
      end

      def detect_watch_patterns
        if project_file?("Gemfile")
          ["spec/**/*_spec.rb", "lib/**/*.rb"]
        elsif project_file?("package.json")
          ["src/**/*.ts", "src/**/*.tsx", "tests/**/*.ts"]
        else
          ["**/*"]
        end
      end

      def detect_source_patterns
        if project_file?("Gemfile")
          %w[app/**/* lib/**/*]
        elsif project_file?("package.json")
          %w[src/**/* app/**/*]
        elsif project_file?("pyproject.toml")
          %w[src/**/*]
        else
          %w[**/*]
        end
      end

      def detect_coverage_command(tool)
        case tool
        when "simplecov"
          "bundle exec rspec"
        when "nyc", "istanbul"
          "nyc npm test"
        when "coverage.py"
          "coverage run -m pytest"
        when "go-cover"
          "go test -cover ./..."
        when "jest"
          "jest --coverage"
        else
          "echo 'Configure coverage command'"
        end
      end

      def detect_coverage_report_paths(tool)
        case tool
        when "simplecov"
          ["coverage/index.html", "coverage/.resultset.json"]
        when "nyc", "istanbul"
          ["coverage/lcov-report/index.html", "coverage/lcov.info"]
        when "coverage.py"
          [".coverage", "htmlcov/index.html"]
        when "go-cover"
          ["coverage.out"]
        when "jest"
          ["coverage/lcov-report/index.html"]
        else
          []
        end
      end

      def detect_vcs_tool
        return "git" if Dir.exist?(File.join(project_dir, ".git"))
        return "svn" if Dir.exist?(File.join(project_dir, ".svn"))
        nil
      end

      def detect_stack
        return :rails if project_file?("Gemfile") && project_file?("config/application.rb")
        return :node if project_file?("package.json")
        return :python if project_file?("pyproject.toml") || project_file?("requirements.txt")

        :other
      end

      def show_provider_info_note(provider)
        prompt.say("\n💡 Provider integration:")
        prompt.say("AIDP does not store API keys or model lists. Configure the agent (#{provider}) externally.")
        prompt.say("Only the billing model (subscription vs usage_based) is recorded for fallback decisions.")
      end

      def show_provider_summary(primary, fallbacks)
        Aidp.log_debug("wizard.provider_summary", "displaying provider configuration table", primary: primary, fallback_count: fallbacks&.size || 0)
        prompt.say("\n📋 Provider Configuration Summary:")
        providers_config = get([:providers]) || {}

        rows = []

        # Add primary provider to table
        if primary && primary != "custom"
          primary_cfg = providers_config[primary.to_sym] || {}
          rows << [
            "Primary",
            primary,
            primary_cfg[:type] || "not configured",
            primary_cfg[:model_family] || "auto"
          ]
        end

        # Add fallback providers to table
        if fallbacks && !fallbacks.empty?
          fallbacks.each_with_index do |fallback, index|
            fallback_cfg = providers_config[fallback.to_sym] || {}
            rows << [
              "Fallback #{index + 1}",
              fallback,
              fallback_cfg[:type] || "not configured",
              fallback_cfg[:model_family] || "auto"
            ]
          end
        end

        # Detect duplicate providers with identical characteristics
        duplicates = detect_duplicate_providers(rows)
        if duplicates.any?
          Aidp.log_warn("wizard.provider_summary", "duplicate provider configurations detected", duplicates: duplicates)
        end

        if rows.any?
          table = TTY::Table.new(
            header: ["Role", "Provider", "Billing Type", "Model Family"],
            rows: rows
          )
          prompt.say(table.render(:unicode, padding: [0, 1]))

          # Show warning for duplicates
          if duplicates.any?
            prompt.say("")
            prompt.warn("⚠️  Duplicate configurations detected:")
            duplicates.each do |dup|
              prompt.say("   • #{dup[:providers].join(" and ")} have identical billing type (#{dup[:type]}) and model family (#{dup[:family]})")
            end
            prompt.say("   Consider using different providers or model families for better redundancy.")
          end
        else
          prompt.say("  (No providers configured)")
        end
      end

      def detect_duplicate_providers(rows)
        # Group providers by their billing type and model family
        # Returns array of duplicate groups with identical characteristics
        duplicates = []
        config_groups = rows.group_by { |row| [row[2], row[3]] }

        config_groups.each do |(type, family), group|
          next if group.size < 2
          next if type == "not configured" # Skip unconfigured providers

          duplicates << {
            providers: group.map { |row| row[1] },
            type: type,
            family: family
          }
        end

        duplicates
      end

      # Ensure a minimal billing configuration exists for a selected provider (no secrets)
      def ensure_provider_billing_config(provider_name, force: false)
        return if provider_name.nil? || provider_name == "custom"
        providers_section = get([:providers]) || {}
        existing = providers_section[provider_name.to_sym]

        if existing && existing[:type] && !force
          prompt.say("  • Provider '#{provider_name}' already configured (type: #{existing[:type]})")
          unless existing[:model_family]
            model_family = ask_model_family(provider_name)
            set([:providers, provider_name.to_sym, :model_family], model_family)
          end
          return
        end

        provider_type = ask_provider_billing_type_with_default(provider_name, existing&.dig(:type))
        model_family = ask_model_family(provider_name, existing&.dig(:model_family) || "auto")
        merged = (existing || {}).merge(type: provider_type, model_family: model_family)
        set([:providers, provider_name.to_sym], merged)
        normalize_existing_model_families!
        action_word = if existing
          force ? "reconfigured" : "updated"
        else
          "added"
        end
        # Enhance messaging with display name when available
        display_name = discover_available_providers.invert.fetch(provider_name, provider_name)
        prompt.say("  • #{action_word.capitalize} provider '#{display_name}' (#{provider_name}) with billing type '#{provider_type}' and model family '#{model_family}'")
      end

      def edit_or_remove_provider(provider_name, primary_provider, fallbacks)
        is_primary = (provider_name == primary_provider)
        display_name = discover_available_providers.invert.fetch(provider_name, provider_name)

        action = prompt.select("What would you like to do with '#{display_name}'?") do |menu|
          menu.choice "Edit configuration", :edit
          unless is_primary
            menu.choice "Remove from configuration", :remove
          end
          menu.choice "Cancel", :cancel
        end

        case action
        when :edit
          edit_provider_configuration(provider_name)
        when :remove
          if is_primary
            prompt.warn("Cannot remove primary provider. Change primary provider first.")
          else
            remove_fallback_provider(provider_name, fallbacks)
          end
        when :cancel
          Aidp.log_debug("wizard.edit_provider", "user cancelled edit operation", provider: provider_name)
        end
      end

      def remove_fallback_provider(provider_name, fallbacks)
        display_name = discover_available_providers.invert.fetch(provider_name, provider_name)
        if prompt.yes?("Remove '#{display_name}' from fallback providers?", default: false)
          fallbacks.delete(provider_name)
          set([:harness, :fallback_providers], fallbacks)
          Aidp.log_info("wizard.remove_provider", "removed fallback provider", provider: provider_name)
          prompt.ok("Removed '#{display_name}' from fallback providers")
        end
      end

      def edit_provider_configuration(provider_name)
        existing = get([:providers, provider_name.to_sym]) || {}
        prompt.say("\n🔧 Editing provider '#{provider_name}' (current: type=#{existing[:type] || "unset"}, model_family=#{existing[:model_family] || "unset"})")
        new_type = ask_provider_billing_type_with_default(provider_name, existing[:type])
        new_family = ask_model_family(provider_name, existing[:model_family] || "auto")
        set([:providers, provider_name.to_sym], {type: new_type, model_family: new_family})
        # Normalize immediately so tests relying on canonical value see 'claude' rather than label
        normalize_existing_model_families!
        prompt.ok("Updated '#{provider_name}' → type=#{new_type}, model_family=#{new_family}")
      end

      def ask_provider_billing_type(provider_name)
        ask_provider_billing_type_with_default(provider_name, nil)
      end

      def ask_provider_billing_type_with_default(provider_name, default_value)
        choices = ProviderRegistry.billing_type_choices
        default_label = choices.find { |label, value| value == default_value }&.first
        suffix = default_value ? " (current: #{default_value})" : ""
        prompt.select("Billing model for #{provider_name}:#{suffix}", default: default_label) do |menu|
          choices.each do |label, value|
            menu.choice(label, value)
          end
        end
      end

      def ask_model_family(provider_name, default = "auto")
        # TTY::Prompt validates defaults against the displayed choice labels, not values.
        # Map the value default (e.g. "auto") to its corresponding label.
        choices = ProviderRegistry.model_family_choices
        default_label = choices.find { |label, value| value == default }&.first

        prompt.select("Preferred model family for #{provider_name}:", default: default_label) do |menu|
          choices.each do |label, value|
            menu.choice(label, value)
          end
        end
      end

      # Canonicalization helpers ------------------------------------------------
      def normalize_model_family(value)
        return "auto" if value.nil? || value.to_s.strip.empty?

        normalized_input = value.to_s.strip.downcase

        # Check for exact canonical value match (case-insensitive)
        canonical_match = ProviderRegistry.model_family_values.find do |v|
          v.downcase == normalized_input
        end
        return canonical_match if canonical_match

        # Try label -> value mapping (case-insensitive)
        choices = ProviderRegistry.model_family_choices
        mapped = choices.find { |label, _| label.downcase == value.to_s.downcase }&.last
        return mapped if mapped

        # Unknown legacy entry -> fallback to auto
        "auto"
      end

      def normalize_existing_model_families!
        providers_cfg = @config[:providers]
        return unless providers_cfg.is_a?(Hash)
        providers_cfg.each do |prov_name, prov_cfg|
          next unless prov_cfg.is_a?(Hash)
          mf = prov_cfg[:model_family]
          # Normalize and write back only if different to avoid unnecessary YAML churn
          normalized = normalize_model_family(mf)
          prov_cfg[:model_family] = normalized
        end
      end

      def normalize_existing_thinking_tiers!
        tiers_cfg = @config.dig(:thinking, :tiers)
        return unless tiers_cfg.is_a?(Hash)

        LEGACY_TIER_ALIASES.each do |legacy, canonical|
          next unless tiers_cfg.key?(legacy)

          legacy_cfg = tiers_cfg.delete(legacy) || {}
          canonical_cfg = tiers_cfg[canonical] || {}
          merged_models = merge_tier_models(canonical_cfg[:models], legacy_cfg[:models])
          tiers_cfg[canonical] = canonical_cfg.merge(models: merged_models)
          @warnings << "Normalized thinking tier '#{legacy}' to '#{canonical}'"
        end

        valid = valid_thinking_tiers
        tiers_cfg.keys.each do |tier|
          next if valid.include?(tier.to_s)

          tiers_cfg.delete(tier)
          @warnings << "Removed unsupported thinking tier '#{tier}' from configuration"
        end
      end

      def merge_tier_models(existing_models, new_models)
        combined = []
        (Array(existing_models) + Array(new_models)).each do |entry|
          next unless entry.is_a?(Hash)
          provider = entry[:provider]
          model = entry[:model]
          next unless provider && model

          unless combined.any? { |m| m[:provider] == provider && m[:model] == model }
            combined << entry
          end
        end
        combined
      end

      def load_existing_config
        return {} unless File.exist?(config_path)
        YAML.safe_load_file(config_path, permitted_classes: [Time]) || {}
      rescue => e
        @warnings << "Failed to parse existing configuration: #{e.message}"
        {}
      end

      def config_path
        Aidp::ConfigPaths.config_file(project_dir)
      end

      def relative_config_path
        config_path.sub("#{project_dir}/", "")
      end

      # -------------------------------------------
      # Hash utilities
      # -------------------------------------------
      def get(path)
        path.reduce(@config) do |acc, key|
          acc.is_a?(Hash) ? acc[key.to_sym] : nil
        end
      end

      def set(path, value)
        parent = path[0...-1].reduce(@config) do |acc, key|
          acc[key.to_sym] ||= {}
          acc[key.to_sym]
        end
        parent[path.last.to_sym] = value
      end

      def delete_path(path)
        parent = path[0...-1].reduce(@config) do |acc, key|
          acc[key.to_sym] ||= {}
          acc[key.to_sym]
        end
        parent.delete(path.last.to_sym)
      end

      def deep_symbolize(object)
        case object
        when Hash
          object.each_with_object({}) do |(key, value), memo|
            memo[key.to_sym] = deep_symbolize(value)
          end
        when Array
          object.map { |item| deep_symbolize(item) }
        else
          object
        end
      end

      def deep_stringify(object)
        case object
        when Hash
          object.each_with_object({}) do |(key, value), memo|
            memo[key.to_s] = deep_stringify(value)
          end
        when Array
          object.map { |item| deep_stringify(item) }
        else
          object
        end
      end

      # -------------------------------------------
      # Diff utilities
      # -------------------------------------------
      def line_diff(old_str, new_str)
        old_lines = old_str.split("\n")
        new_lines = new_str.split("\n")
        lcs_matrix = build_lcs_matrix(old_lines, new_lines)
        backtrack_diff(lcs_matrix, old_lines, new_lines).reverse
      end

      def build_lcs_matrix(a_lines, b_lines)
        Array.new(a_lines.length + 1) do
          Array.new(b_lines.length + 1, 0)
        end.tap do |matrix|
          a_lines.each_index do |i|
            b_lines.each_index do |j|
              matrix[i + 1][j + 1] = if a_lines[i] == b_lines[j]
                matrix[i][j] + 1
              else
                [matrix[i + 1][j], matrix[i][j + 1]].max
              end
            end
          end
        end
      end

      def backtrack_diff(matrix, a_lines, b_lines)
        diff = []
        i = a_lines.length
        j = b_lines.length

        while i > 0 && j > 0
          if a_lines[i - 1] == b_lines[j - 1]
            diff << "  #{a_lines[i - 1]}"
            i -= 1
            j -= 1
          elsif matrix[i - 1][j] >= matrix[i][j - 1]
            diff << "- #{a_lines[i - 1]}"
            i -= 1
          else
            diff << "+ #{b_lines[j - 1]}"
            j -= 1
          end
        end

        while i > 0
          diff << "- #{a_lines[i - 1]}"
          i -= 1
        end

        while j > 0
          diff << "+ #{b_lines[j - 1]}"
          j -= 1
        end

        diff
      end

      def display_value(value)
        value.is_a?(Array) ? value.join(", ") : value
      end

      def project_file?(relative_path)
        File.exist?(File.join(project_dir, relative_path))
      end

      def valid_thinking_tiers
        Aidp::Harness::CapabilityRegistry::VALID_TIERS
      rescue NameError
        %w[mini standard thinking pro max]
      end

      def configure_devcontainer
        prompt.say("\n🐳 Devcontainer Configuration")
        Aidp.log_debug(DEVCONTAINER_COMPONENT, "configure.start")

        # Detect existing devcontainer
        parser = Devcontainer::Parser.new(project_dir)
        existing_devcontainer = parser.devcontainer_exists? ? parser.parse : nil

        if existing_devcontainer
          prompt.say("✓ Found existing devcontainer.json")
          Aidp.log_debug(DEVCONTAINER_COMPONENT, "configure.detected_existing",
            path: parser.detect)
        end

        # Check existing configuration for previous choice
        existing_manage = @config.dig(:devcontainer, :manage)
        default_manage = if existing_manage.nil?
          existing_devcontainer ? true : false
        else
          existing_manage
        end

        # Ask if user wants AIDP to manage devcontainer
        manage = prompt.yes?(
          "Would you like AIDP to manage your devcontainer configuration?",
          default: default_manage
        )

        unless manage
          Aidp.log_debug(DEVCONTAINER_COMPONENT, "configure.opt_out")
          return set([:devcontainer, :manage], false)
        end

        # Build wizard config and detect ports
        wizard_config = build_wizard_config_for_devcontainer
        port_manager = Devcontainer::PortManager.new(wizard_config)
        detected_ports = port_manager.detect_required_ports

        # Show detected ports
        if detected_ports.any?
          prompt.say("\nDetected ports:")
          detected_ports.each do |port|
            prompt.say("  • #{port[:number]} - #{port[:label]}")
          end
          Aidp.log_debug(DEVCONTAINER_COMPONENT, "configure.detected_ports",
            ports: detected_ports.map { |port| port[:number] })
        end

        # Ask about custom ports
        custom_ports = []
        if prompt.yes?("Add custom ports?", default: false)
          loop do
            port_num = prompt.ask("Port number (or press Enter to finish):")
            break if port_num.nil? || port_num.to_s.strip.empty?

            unless port_num.to_s.match?(/^\d+$/)
              prompt.error("Port must be a number")
              next
            end

            port_label = prompt.ask("Port label:", default: "Custom")
            custom_ports << {number: port_num.to_i, label: port_label}
          end
          Aidp.log_debug(DEVCONTAINER_COMPONENT, "configure.custom_ports_selected",
            ports: custom_ports.map { |port| port[:number] })
        end

        # Save configuration
        set([:devcontainer, :manage], true)
        set([:devcontainer, :custom_ports], custom_ports) if custom_ports.any?
        set([:devcontainer, :last_generated], Time.now.utc.iso8601)
        Aidp.log_debug(DEVCONTAINER_COMPONENT, "configure.enabled",
          custom_port_count: custom_ports.count,
          detected_port_count: detected_ports.count)
      end

      def build_wizard_config_for_devcontainer
        {
          providers: @config[:providers]&.keys,
          test_framework: @config.dig(:work_loop, :test_commands)&.first&.dig(:framework),
          linters: @config.dig(:work_loop, :linting, :tools),
          watch_mode: @config.dig(:work_loop, :watch, :enabled),
          app_type: detect_app_type,
          services: detect_services,
          custom_ports: @config.dig(:devcontainer, :custom_ports)
        }.compact
      end

      def detect_app_type
        return "rails_web" if project_file?("config/routes.rb")
        return "sinatra" if project_file?("config.ru")
        return "express" if project_file?("app.js") && project_file?("package.json")
        "cli"
      end

      def detect_services
        services = []
        services << "postgres" if project_file?("config/database.yml")
        services << "redis" if project_file?("config/redis.yml")
        services
      end

      def generate_devcontainer_file
        unless @config.dig(:devcontainer, :manage)
          Aidp.log_debug(DEVCONTAINER_COMPONENT, "generate.skip_unmanaged")
          return
        end

        Aidp.log_debug(DEVCONTAINER_COMPONENT, "generate.start")

        wizard_config = build_wizard_config_for_devcontainer
        Aidp.log_debug(DEVCONTAINER_COMPONENT, "generate.wizard_config",
          keys: wizard_config.keys)

        parser = Devcontainer::Parser.new(project_dir)
        existing = parser.devcontainer_exists? ? parser.parse : nil

        generator = Devcontainer::Generator.new(project_dir, @config)
        new_config = generator.generate(wizard_config, existing)

        # Create backup if existing file
        if existing
          backup_manager = Devcontainer::BackupManager.new(project_dir)
          backup_manager.create_backup(
            parser.detect,
            {reason: "wizard_update", timestamp: Time.now.utc.iso8601}
          )
          prompt.say("  └─ Backup created")
          Aidp.log_debug(DEVCONTAINER_COMPONENT, "generate.backup_created",
            path: parser.detect)
        end

        # Write devcontainer.json
        devcontainer_path = File.join(project_dir, ".devcontainer", "devcontainer.json")
        FileUtils.mkdir_p(File.dirname(devcontainer_path))
        File.write(devcontainer_path, JSON.pretty_generate(new_config))

        prompt.ok("✅ Generated #{devcontainer_path}")
        Aidp.log_debug(DEVCONTAINER_COMPONENT, "generate.complete",
          devcontainer_path: devcontainer_path,
          forward_ports: new_config["forwardPorts"]&.length)
      end
    end
  end
end
