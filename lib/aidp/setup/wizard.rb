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

        # Exclude base classes and utility classes
        excluded_files = ["base.rb", "macos_ui.rb"]
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
          return
        end

        provider_type = ask_provider_billing_type(provider_name)
        set([:providers, provider_name.to_sym], {type: provider_type})
        prompt.say("  • Added provider '#{provider_name}' with billing type '#{provider_type}' (no secrets stored)")
      end

      def ask_provider_billing_type(provider_name)
        prompt.select("Billing model for #{provider_name}:") do |menu|
          menu.choice "Subscription / flat-rate", "subscription"
          # e.g. tools that expose an integrated model under a subscription cost
          menu.choice "Usage-based / metered (API)", "usage_based"
          menu.choice "Passthrough / local (no billing)", "passthrough"
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
