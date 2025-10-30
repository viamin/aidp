# frozen_string_literal: true

require "tty-prompt"
require "yaml"
require "time"
require "fileutils"

require_relative "../util"
require_relative "../config/paths"

module Aidp
  module Setup
    # Interactive setup wizard for configuring AIDP.
    # Guides the user through provider, work loop, NFR, logging, and mode settings
    # while remaining idempotent and safe to re-run.
    class Wizard
      SCHEMA_VERSION = 1

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
        # Normalize any legacy or label-based model_family entries before prompting
        normalize_existing_model_families!
        return @saved if skip_wizard?

        configure_providers
        configure_work_loop
        configure_branching
        configure_artifacts
        configure_nfrs
        configure_logging
        configure_modes

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

        fallback_selected = prompt.multi_select("Select fallback providers (used if primary fails):", default: fallback_default_names) do |menu|
          fallback_choices.each do |display_name, provider_name|
            menu.choice display_name, provider_name
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
        cleaned_fallbacks.each { |fp| ensure_provider_billing_config(fp) }

        # Offer editing of existing provider configurations (primary + fallbacks)
        editable = ([provider_choice] + cleaned_fallbacks).uniq.reject { |p| p == "custom" }
        if editable.any? && prompt.yes?("Edit provider configuration details (billing/model family)?", default: false)
          loop do
            to_edit = prompt.select("Select a provider to edit:") do |menu|
              editable.each { |prov| menu.choice prov, prov }
              menu.choice "Done", :done
            end
            break if to_edit == :done

            edit_provider_configuration(to_edit)
          end
        end

        # Provide informational note (no secret handling stored)
        show_provider_info_note(provider_choice) unless provider_choice == "custom"
      end

      # Removed MCP configuration step (MCP now expected to be provider-specific if used)

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

        tool = prompt.select("Which coverage tool do you use?", default: existing[:tool]) do |menu|
          menu.choice "SimpleCov (Ruby)", "simplecov"
          menu.choice "NYC/Istanbul (JavaScript)", "nyc"
          menu.choice "Coverage.py (Python)", "coverage.py"
          menu.choice "go test -cover (Go)", "go-cover"
          menu.choice "Jest (JavaScript)", "jest"
          menu.choice "Other", "other"
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

        app_type = prompt.select("What type of application are you testing?", default: existing[:app_type]) do |menu|
          menu.choice "Web application", "web"
          menu.choice "CLI application", "cli"
          menu.choice "Desktop application", "desktop"
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
        vcs_tool = if detected_vcs
          prompt.select("Detected #{detected_vcs}. Use this version control system?", default: existing[:tool] || detected_vcs) do |menu|
            menu.choice "git", "git"
            menu.choice "svn", "svn"
            menu.choice "none (no VCS)", "none"
          end
        else
          prompt.select("Which version control system do you use?", default: existing[:tool] || "git") do |menu|
            menu.choice "git", "git"
            menu.choice "svn", "svn"
            menu.choice "none (no VCS)", "none"
          end
        end

        return set([:work_loop, :version_control], {tool: "none", behavior: "nothing"}) if vcs_tool == "none"

        prompt.say("\n📋 Commit Behavior (applies to copilot/interactive mode only)")
        prompt.say("Note: Watch mode and fully automatic daemon mode will always commit changes.")
        behavior = prompt.select("In copilot mode, should aidp:", default: existing[:behavior] || "nothing") do |menu|
          menu.choice "Do nothing (manual git operations)", "nothing"
          menu.choice "Stage changes only", "stage"
          menu.choice "Stage and commit changes", "commit"
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
          prompt.select("Conventional commit style:", default: existing[:commit_style] || "default") do |menu|
            menu.choice "Default (e.g., 'feat: add user authentication')", "default"
            menu.choice "Angular (with scope: 'feat(auth): add login')", "angular"
            menu.choice "Emoji (e.g., '✨ feat: add user authentication')", "emoji"
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
          pr_strategy = prompt.select("PR creation strategy:", default: existing[:pr_strategy] || "draft") do |menu|
            menu.choice "Create as draft PR (safe, allows review before merge)", "draft"
            menu.choice "Create as ready PR (immediately reviewable)", "ready"
            menu.choice "Create and auto-merge (fully autonomous, requires approval rules)", "auto_merge"
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

        return delete_path([:nfrs]) unless prompt.yes?("Configure NFRs?", default: true)

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

        # TODO: Add default back once TTY-Prompt default validation issue is resolved
        log_level = prompt.select("Log level:") do |menu|
          menu.choice "Debug", "debug"
          menu.choice "Info", "info"
          menu.choice "Error", "error"
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
      end

      def display_warnings
        return if @warnings.empty?

        prompt.warn("\nWarnings:")
        @warnings.each { |warning| prompt.warn("  • #{warning}") }
      end

      def show_next_steps
        prompt.say("\n🎉 Setup complete!")
        prompt.say("\nNext steps:")
        prompt.say("  1. Export provider API keys as environment variables.")
        prompt.say("  2. Run 'aidp init' to analyze the project.")
        prompt.say("  3. Run 'aidp execute' to start a work loop.")
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

      # Ensure a minimal billing configuration exists for a selected provider (no secrets)
      def ensure_provider_billing_config(provider_name)
        return if provider_name.nil? || provider_name == "custom"
        providers_section = get([:providers]) || {}
        existing = providers_section[provider_name.to_sym]

        if existing && existing[:type]
          prompt.say("  • Provider '#{provider_name}' already configured (type: #{existing[:type]})")
          # Still ask for model family if not set
          unless existing[:model_family]
            model_family = ask_model_family(provider_name)
            set([:providers, provider_name.to_sym, :model_family], model_family)
          end
          return
        end

        provider_type = ask_provider_billing_type(provider_name)
        model_family = ask_model_family(provider_name)
        set([:providers, provider_name.to_sym], {type: provider_type, model_family: model_family})
        prompt.say("  • Added provider '#{provider_name}' with billing type '#{provider_type}' and model family '#{model_family}' (no secrets stored)")
      end

      def edit_provider_configuration(provider_name)
        existing = get([:providers, provider_name.to_sym]) || {}
        prompt.say("\n🔧 Editing provider '#{provider_name}' (current: type=#{existing[:type] || 'unset'}, model_family=#{existing[:model_family] || 'unset'})")
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

      BILLING_TYPE_CHOICES = [
        ["Subscription / flat-rate", "subscription"],
        ["Usage-based / metered (API)", "usage_based"],
        ["Passthrough / local (no billing)", "passthrough"]
      ].freeze

      def ask_provider_billing_type_with_default(provider_name, default_value)
        default_label = BILLING_TYPE_CHOICES.find { |label, value| value == default_value }&.first
        suffix = default_value ? " (current: #{default_value})" : ""
        prompt.select("Billing model for #{provider_name}:#{suffix}", default: default_label) do |menu|
          BILLING_TYPE_CHOICES.each do |label, value|
            menu.choice(label, value)
          end
        end
      end

      MODEL_FAMILY_CHOICES = [
        ["Auto (let provider decide)", "auto"],
        ["OpenAI o-series (reasoning models)", "openai_o"],
        ["Anthropic Claude (balanced)", "claude"],
        ["Mistral (European/open)", "mistral"],
        ["Local LLM (self-hosted)", "local"]
      ].freeze

      def ask_model_family(provider_name, default = "auto")
        # TTY::Prompt validates defaults against the displayed choice labels, not values.
        # Map the value default (e.g. "auto") to its corresponding label.
        default_label = MODEL_FAMILY_CHOICES.find { |label, value| value == default }&.first

        prompt.select("Preferred model family for #{provider_name}:", default: default_label) do |menu|
          MODEL_FAMILY_CHOICES.each do |label, value|
            menu.choice(label, value)
          end
        end
      end

      # Canonicalization helpers ------------------------------------------------
      MODEL_FAMILY_LABEL_TO_VALUE = MODEL_FAMILY_CHOICES.each_with_object({}) do |(label, value), h|
        h[label] = value
      end.freeze
      MODEL_FAMILY_VALUES = MODEL_FAMILY_CHOICES.map { |(_, value)| value }.freeze

      def normalize_model_family(value)
        return "auto" if value.nil? || value.to_s.strip.empty?
        # Already a canonical value
        return value if MODEL_FAMILY_VALUES.include?(value)
        # Try label -> value
        mapped = MODEL_FAMILY_LABEL_TO_VALUE[value]
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
    end
  end
end
