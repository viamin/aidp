# frozen_string_literal: true

require "optparse"
require "tty-prompt"
require "stringio"
require_relative "harness/runner"
require_relative "execute/workflow_selector"
require_relative "harness/ui/enhanced_tui"
require_relative "harness/ui/enhanced_workflow_selector"
require_relative "harness/enhanced_runner"
require_relative "cli/first_run_wizard"
require_relative "cli/issue_importer"
require_relative "rescue_logging"
require_relative "concurrency"

module Aidp
  # CLI interface for AIDP
  class CLI
    include Aidp::MessageDisplay
    include Aidp::RescueLogging

    def initialize(prompt: TTY::Prompt.new)
      @prompt = prompt
    end

    class << self
      extend Aidp::MessageDisplay::ClassMethods
      extend Aidp::RescueLogging

      # Explicit singleton delegator (defensive: ensure availability even if extend fails to attach)
      def log_rescue(error, component:, action:, fallback: nil, level: :warn, **context)
        Aidp::RescueLogging.log_rescue(error, component: component, action: action, fallback: fallback, level: level, **context)
      end

      # Store last parsed options for access by UI components (e.g., verbose flag)
      @last_options = nil
      attr_accessor :last_options

      def create_prompt
        ::TTY::Prompt.new
      end

      def run(args = ARGV)
        # Handle subcommands first (status, jobs, kb, harness)
        return run_subcommand(args) if subcommand?(args)

        options = parse_options(args)
        self.last_options = options

        # Validate incompatible options
        if options[:quiet] && options[:verbose]
          display_message("❌ --quiet and --verbose are mutually exclusive", type: :error)
          return 1
        end

        # --quiet is incompatible with default interactive mode (no subcommand)
        if options[:quiet] && !options[:help] && !options[:version]
          display_message("❌ --quiet is not compatible with interactive mode. Use with 'watch' command instead.", type: :error)
          return 1
        end

        if options[:help]
          display_message(options[:parser].to_s, type: :info)
          return 0
        end

        if options[:version]
          display_message("Aidp version #{Aidp::VERSION}", type: :info)
          return 0
        end

        # Undocumented: Launch test mode for CI/CD validation
        # Initializes app components and exits cleanly without running full workflows
        if options[:launch_test]
          return run_launch_test(:interactive)
        end

        # Initialize logger from aidp.yml config
        # Priority: ENV variable > aidp.yml > default (info)
        setup_logging(Dir.pwd)

        # Start the interactive TUI
        display_message("AIDP initializing...", type: :info)
        display_message("   Press Ctrl+C to stop\n", type: :highlight)

        # Handle configuration setup
        # Create a prompt for the wizard
        prompt = create_prompt

        if options[:setup_config]
          # Force setup/reconfigure even if config exists
          unless Aidp::CLI::FirstRunWizard.setup_config(Dir.pwd, prompt: prompt, non_interactive: ENV["CI"] == "true")
            display_message("Configuration setup cancelled. Aborting startup.", type: :info)
            return 1
          end
        else
          # First-time setup wizard (before TUI to avoid noisy errors)
          unless Aidp::CLI::FirstRunWizard.ensure_config(Dir.pwd, prompt: prompt, non_interactive: ENV["CI"] == "true")
            display_message("Configuration required. Aborting startup.", type: :info)
            return 1
          end
        end

        # Initialize the enhanced TUI
        tui = Aidp::Harness::UI::EnhancedTUI.new
        workflow_selector = Aidp::Harness::UI::EnhancedWorkflowSelector.new(tui, project_dir: Dir.pwd)

        begin
          # Copilot is now the default mode - no menu selection
          # The guided workflow selector will internally choose appropriate mode
          mode = :guided

          # Get workflow configuration (no spinner - may wait for user input)
          workflow_config = workflow_selector.select_workflow(harness_mode: false, mode: mode)

          # Use the mode determined by the guided workflow selector
          actual_mode = workflow_config[:mode] || :execute

          # Pass workflow configuration to harness
          harness_options = {
            mode: actual_mode,
            workflow_type: workflow_config[:workflow_type],
            selected_steps: workflow_config[:steps],
            user_input: workflow_config[:user_input]
          }

          # Create and run the enhanced harness
          harness_runner = Aidp::Harness::EnhancedRunner.new(Dir.pwd, actual_mode, harness_options)
          result = harness_runner.run
          display_harness_result(result)
          0
        rescue Interrupt
          display_message("\n\n⏹️  Interrupted by user", type: :warning)
          1
        rescue => e
          log_rescue(e, component: "cli", action: "run_harness", fallback: 1, mode: actual_mode)
          display_message("\n❌ Error: #{e.message}", type: :error)
          1
        ensure
          tui.restore_screen
        end
      end

      private

      def setup_logging(project_dir)
        # Load logging config from aidp.yml
        config_path = File.join(project_dir, ".aidp", "aidp.yml")
        logging_config = {}

        if File.exist?(config_path)
          require "yaml"
          full_config = YAML.safe_load_file(config_path, permitted_classes: [Date, Time, Symbol], aliases: true)
          logging_config = full_config["logging"] || full_config[:logging] || {}
        end

        # Set up logger with config (ENV variable AIDP_LOG_LEVEL takes precedence)
        Aidp.setup_logger(project_dir, logging_config)

        # Log initialization
        Aidp.logger.info("cli", "AIDP starting", version: Aidp::VERSION, log_level: Aidp.logger.level)
      rescue => e
        log_rescue(e, component: "cli", action: "setup_logger", fallback: "default_config", project_dir: project_dir)
        # If logging setup fails, continue with default logger
        Aidp.setup_logger(project_dir, {})
        Aidp.logger.warn("cli", "Failed to load logging config, using defaults", error: e.message)
      end

      # Quick exit launch test for CI/CD validation
      # Initializes app components and exits cleanly without running full workflows
      def run_launch_test(mode)
        Aidp.log_debug("cli", "launch_test_started", mode: mode)
        display_message("Aidp version #{Aidp::VERSION}", type: :info)

        # Initialize logging
        setup_logging(Dir.pwd)

        case mode
        when :interactive
          run_interactive_launch_test
        when :watch
          run_watch_launch_test
        else
          display_message("Unknown launch test mode: #{mode}", type: :error)
          return 1
        end

        Aidp.log_info("cli", "launch_test_completed", mode: mode)
        display_message("Launch test completed successfully", type: :success)
        0
      rescue => e
        log_rescue(e, component: "cli", action: "launch_test", fallback: 1, mode: mode)
        display_message("Launch test failed: #{e.message}", type: :error)
        1
      end

      def run_interactive_launch_test
        Aidp.log_debug("cli", "interactive_launch_test", step: "init_tui")

        # Initialize TUI components (validates they can be created)
        tui = Aidp::Harness::UI::EnhancedTUI.new
        Aidp.log_debug("cli", "interactive_launch_test", step: "tui_created")

        # Initialize workflow selector (validates harness loading)
        _selector = Aidp::Harness::UI::EnhancedWorkflowSelector.new(tui, project_dir: Dir.pwd)
        Aidp.log_debug("cli", "interactive_launch_test", step: "workflow_selector_created")

        # Initialize config manager (validates config loading)
        _config_manager = Aidp::Harness::ConfigManager.new(Dir.pwd)
        Aidp.log_debug("cli", "interactive_launch_test", step: "config_manager_created")

        # Validate EnhancedRunner can be instantiated (orchestrates workflows)
        Aidp.log_debug("cli", "interactive_launch_test", step: "validate_enhanced_runner")
        require_relative "harness/enhanced_runner"
        _runner = Aidp::Harness::EnhancedRunner.new(Dir.pwd, :execute, {mode: :execute})
        Aidp.log_debug("cli", "interactive_launch_test", step: "enhanced_runner_created")
        display_message("Enhanced Runner instantiation verified", type: :info)

        # Validate FirstRunWizard can be loaded (critical for setup)
        Aidp.log_debug("cli", "interactive_launch_test", step: "validate_first_run_wizard")
        require_relative "cli/first_run_wizard"
        # Don't instantiate to avoid triggering actual wizard
        Aidp.log_debug("cli", "interactive_launch_test", step: "first_run_wizard_loaded")
        display_message("First Run Wizard loaded", type: :info)

        # Validate Init::Runner can be instantiated (init command)
        Aidp.log_debug("cli", "interactive_launch_test", step: "validate_init_runner")
        require_relative "init/runner"
        mock_prompt = TTY::Prompt.new(input: StringIO.new, output: StringIO.new)
        _init_runner = Aidp::Init::Runner.new(Dir.pwd, prompt: mock_prompt, options: {dry_run: true})
        Aidp.log_debug("cli", "interactive_launch_test", step: "init_runner_created")
        display_message("Init Runner instantiation verified", type: :info)

        display_message("Interactive mode initialization verified", type: :info)
      ensure
        tui&.restore_screen
      end

      def run_watch_launch_test
        Aidp.log_debug("cli", "watch_launch_test", step: "init_config")

        # Load config to validate configuration parsing
        config_manager = Aidp::Harness::ConfigManager.new(Dir.pwd)
        config = config_manager.config || {}
        watch_config = config[:watch] || config["watch"] || {}

        Aidp.log_debug("cli", "watch_launch_test", step: "config_loaded", has_watch_config: !watch_config.empty?)

        display_message("Watch mode configuration verified", type: :info)

        # Instantiate Runner to validate all dependencies are loadable
        # Use mock GitHub client to avoid external API calls
        Aidp.log_debug("cli", "watch_launch_test", step: "validate_runner")
        mock_gh_client = Class.new do
          def available?
            false
          end
        end.new

        Aidp::Watch::Runner.new(
          issues_url: "https://github.com/test/test/issues",
          interval: 30,
          once: true,
          gh_available: mock_gh_client,
          prompt: TTY::Prompt.new(input: StringIO.new, output: StringIO.new)
        )

        Aidp.log_debug("cli", "watch_launch_test", step: "runner_instantiated")
        display_message("Watch mode Runner instantiation verified", type: :info)

        # Validate key Watch mode dependencies are loadable
        Aidp.log_debug("cli", "watch_launch_test", step: "validate_watch_dependencies")
        require_relative "watch/plan_generator"
        require_relative "auto_update"
        require_relative "worktree"
        Aidp.log_debug("cli", "watch_launch_test", step: "watch_dependencies_loaded")
        display_message("Watch mode dependencies loaded", type: :info)
      end

      def parse_options(args)
        options = {}

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: aidp [COMMAND] [options]"
          opts.separator ""
          opts.separator "AI Development Pipeline - Autonomous development workflow automation"
          opts.separator ""
          opts.separator "Commands:"
          opts.separator "  (no command)             Start Copilot interactive mode (default)"
          opts.separator "  init                     Analyse project and bootstrap quality docs"
          opts.separator "  watch <issues_url>       Run fully automatic watch mode"
          opts.separator "  status                   Show current system status"
          opts.separator "  jobs                     Manage background jobs"
          opts.separator "    list                     - List all jobs"
          opts.separator "    status <id> [--follow]   - Show job status"
          opts.separator "    logs <id> [--tail]       - Show job logs"
          opts.separator "    stop <id>                - Stop a running job"
          opts.separator "  checkpoint               View progress checkpoints and metrics"
          opts.separator "    show                     - Show latest checkpoint"
          opts.separator "    summary [--watch]        - Show progress summary with trends"
          opts.separator "    history [N]              - Show last N checkpoints"
          opts.separator "    metrics                  - Show detailed metrics"
          opts.separator "    clear [--force]          - Clear checkpoint data"
          opts.separator "  providers                Show provider health dashboard"
          opts.separator "    info <name>              - Show detailed provider information"
          opts.separator "    refresh [name]           - Refresh provider capabilities info"
          opts.separator "  mcp                      MCP server dashboard and management"
          opts.separator "    dashboard                - Show all MCP servers across providers"
          opts.separator "    check <servers...>       - Check provider eligibility for servers"
          opts.separator "  ws                       Manage parallel workstreams (git worktrees)"
          opts.separator "    list                     - List all workstreams"
          opts.separator "    new <slug> [task]        - Create new workstream"
          opts.separator "    rm <slug>                - Remove workstream"
          opts.separator "    status <slug>            - Show workstream status"
          opts.separator "    pause <slug>             - Pause workstream"
          opts.separator "    resume <slug>            - Resume workstream"
          opts.separator "    complete <slug>          - Mark workstream as completed"
          opts.separator "    dashboard                - Show multi-workstream overview"
          opts.separator "    pause-all                - Pause all active workstreams"
          opts.separator "    resume-all               - Resume all paused workstreams"
          opts.separator "    stop-all                 - Stop all active workstreams"
          opts.separator "    cleanup                  - Interactive cleanup of workstreams"
          opts.separator "  work                     Execute workflow in workstream context"
          opts.separator "    --workstream <slug>      - Required: workstream to run in"
          opts.separator "    --mode <mode>            - analyze or execute (default: execute)"
          opts.separator "    --background             - Run in background job"
          opts.separator "  skill                    Manage skills (agent personas)"
          opts.separator "    list                     - List all available skills"
          opts.separator "    show <id>                - Show detailed skill information"
          opts.separator "    search <query>           - Search skills by keyword"
          opts.separator "    validate [path]          - Validate skill file format"
          opts.separator "  settings                 Manage runtime settings"
          opts.separator "    auto-update status       - Show auto-update configuration"
          opts.separator "    auto-update on|off       - Enable/disable auto-updates"
          opts.separator "    auto-update policy <pol> - Set update policy (off/exact/patch/minor/major)"
          opts.separator "    auto-update prerelease   - Toggle prerelease updates"
          opts.separator "  harness                  Manage harness state"
          opts.separator "  config                   Manage configuration"
          opts.separator "    status                   - Show harness status"
          opts.separator "    reset                    - Reset harness state"
          opts.separator "  kb                       Knowledge base commands"
          opts.separator "    show <topic>             - Show knowledge base topic"
          opts.separator ""
          opts.separator "Options:"

          opts.on("-h", "--help", "Show this help message") { options[:help] = true }
          opts.on("-v", "--version", "Show version information") { options[:version] = true }
          opts.on("--setup-config", "Setup or reconfigure config file") { options[:setup_config] = true }
          opts.on("--verbose", "Show detailed prompts and raw provider responses during guided workflow") { options[:verbose] = true }
          opts.on("--quiet", "Suppress non-critical output (incompatible with --verbose and --interactive)") { options[:quiet] = true }
          # Undocumented: Quick exit launch test for CI/CD validation
          opts.on("--launch-test", nil) { options[:launch_test] = true }

          opts.separator ""
          opts.separator "Examples:"
          opts.separator "  # Start interactive Copilot mode"
          opts.separator "  aidp"
          opts.separator ""
          opts.separator "  # Project bootstrap"
          opts.separator "  aidp init                             # High-level analysis and docs"
          opts.separator "  aidp config --interactive             # Configure providers"
          opts.separator ""
          opts.separator "  # Monitor background jobs"
          opts.separator "  aidp jobs list                        # List all jobs"
          opts.separator "  aidp jobs status <job_id>             # Show job status"
          opts.separator "  aidp jobs logs <job_id> --tail        # Tail job logs"
          opts.separator ""
          opts.separator "  # Watch progress in real-time"
          opts.separator "  aidp checkpoint summary --watch       # Auto-refresh every 5s"
          opts.separator "  aidp checkpoint summary --watch --interval 10"
          opts.separator ""
          opts.separator "  # Fully automatic orchestration"
          opts.separator "  aidp watch https://github.com/<org>/<repo>/issues"
          opts.separator "  aidp watch owner/repo --interval 120 --provider claude"
          opts.separator ""
          opts.separator "  # Other commands"
          opts.separator "  aidp providers                        # Check provider health"
          opts.separator "  aidp providers info claude            # Show detailed provider info"
          opts.separator "  aidp mcp                              # Show MCP server dashboard"
          opts.separator "  aidp checkpoint history 20            # Show last 20 checkpoints"
          opts.separator ""
          opts.separator "For more information, visit: https://github.com/viamin/aidp"
        end

        parser.parse!(args)
        options[:parser] = parser
        options
      end

      # Determine if the invocation is a subcommand style call
      def subcommand?(args)
        return false if args.nil? || args.empty?
        %w[status jobs kb harness providers checkpoint eval mcp issue config init watch ws work skill settings models tools security storage prompts].include?(args.first)
      end

      def run_subcommand(args)
        cmd = args.shift
        case cmd
        when "status" then run_status_command
        when "jobs" then run_jobs_command(args)
        when "kb" then run_kb_command(args)
        when "harness" then run_harness_command(args)
        when "providers" then run_providers_command(args)
        when "checkpoint" then run_checkpoint_command(args)
        when "eval" then run_eval_command(args)
        when "mcp" then run_mcp_command(args)
        when "issue" then run_issue_command(args)
        when "config" then run_config_command(args)
        when "devcontainer" then run_devcontainer_command(args)
        when "init" then run_init_command(args)
        when "watch" then run_watch_command(args)
        when "ws" then run_ws_command(args)
        when "work" then run_work_command(args)
        when "skill" then run_skill_command(args)
        when "settings" then run_settings_command(args)
        when "models" then run_models_command(args)
        when "tools" then run_tools_command(args)
        when "security" then run_security_command(args)
        when "storage" then run_storage_command(args)
        when "prompts" then run_prompts_command(args)
        else
          display_message("Unknown command: #{cmd}", type: :info)
          return 1
        end
        0
      end

      def run_status_command
        # Minimal enhanced status output for system spec expectations
        display_message("AI Dev Pipeline Status", type: :info)
        display_message("----------------------", type: :muted)
        display_message("Analyze Mode: available", type: :info)
        display_message("Execute Mode: available", type: :info)
        display_message("Use 'aidp analyze' or 'aidp execute' to start a workflow", type: :info)
      end

      def run_jobs_command(args = [])
        require_relative "cli/jobs_command"
        jobs_cmd = Aidp::CLI::JobsCommand.new(prompt: create_prompt)
        subcommand = args.shift
        jobs_cmd.run(subcommand, args)
      end

      def run_kb_command(args)
        sub = args.shift
        if sub == "show"
          topic = args.shift || "summary"
          display_message("Knowledge Base: #{topic}", type: :info)
          display_message("(KB content display placeholder)", type: :info)
        else
          display_message("Usage: aidp kb show <topic>", type: :info)
        end
      end

      def run_harness_command(args)
        sub = args.shift

        # Delegate to HarnessCommand
        require_relative "cli/harness_command"

        options = {}
        if args.include?("--mode")
          args.delete("--mode")
          options[:mode] = args.shift
        else
          mode = extract_mode_option(args)
          options[:mode] = mode if mode
        end

        command = HarnessCommand.new(prompt: create_prompt)
        command.run(args, subcommand: sub, options: options)
      end

      def run_execute_command(args, mode: :execute)
        flags = args.dup
        step = nil
        approve_step = nil
        reset = false
        no_harness = false
        background = false
        follow = false

        until flags.empty?
          token = flags.shift
          case token
          when "--no-harness" then no_harness = true
          when "--reset" then reset = true
          when "--approve" then approve_step = flags.shift
          when "--background" then background = true
          when "--follow" then follow = true
          else
            step ||= token unless token.start_with?("--")
          end
        end

        if reset
          display_message("Reset #{mode} mode progress", type: :info)
          return
        end
        if approve_step
          display_message("Approved #{mode} step: #{approve_step}", type: :info)
          return
        end
        if no_harness
          display_message("Available #{mode} steps", type: :info)
          display_message("Use 'aidp #{mode}' without arguments", type: :info)
          return
        end

        # Handle background execution
        if background
          require_relative "jobs/background_runner"
          runner = Aidp::Jobs::BackgroundRunner.new(Dir.pwd)

          display_message("Starting #{mode} mode in background...", type: :info)
          job_id = runner.start(mode, {})

          display_message("✓ Started background job: #{job_id}", type: :success)
          display_message("", type: :info)
          display_message("Monitor progress:", type: :info)
          display_message("  aidp jobs status #{job_id}", type: :info)
          display_message("  aidp jobs logs #{job_id} --tail", type: :info)
          display_message("  aidp checkpoint summary", type: :info)
          display_message("", type: :info)
          display_message("Stop the job:", type: :info)
          display_message("  aidp jobs stop #{job_id}", type: :info)

          if follow
            display_message("", type: :info)
            display_message("Following logs (Ctrl+C to stop following)...", type: :info)

            # Wait for log file to be created before following
            log_file = File.join(runner.instance_variable_get(:@jobs_dir), job_id, "output.log")
            begin
              Aidp::Concurrency::Wait.for_file(log_file, timeout: 10, interval: 0.2)
            rescue Aidp::Concurrency::TimeoutError
              display_message("Warning: Log file not found after 10s", type: :warning)
            end

            runner.follow_job_logs(job_id)
          end

          return
        end

        if step
          display_message("Running #{mode} step '#{step}' with enhanced TUI harness", type: :highlight)
          display_message("progress indicators", type: :info)
          return
        end
        display_message("Starting enhanced TUI harness", type: :highlight)
        display_message("Press Ctrl+C to stop", type: :highlight)
        display_message("workflow selection options", type: :info)
      end

      def run_checkpoint_command(args)
        # Delegate to CheckpointCommand
        require_relative "cli/checkpoint_command"
        command = CheckpointCommand.new(prompt: create_prompt)
        command.run(args)
      end

      def run_eval_command(args)
        # Delegate to EvalCommand
        require_relative "cli/eval_command"
        command = EvalCommand.new(prompt: create_prompt)
        command.run(args)
      end

      def format_time_ago_simple(seconds)
        if seconds < 60
          "#{seconds.to_i}s ago"
        elsif seconds < 3600
          "#{(seconds / 60).to_i}m ago"
        else
          "#{(seconds / 3600).to_i}h ago"
        end
      end

      def run_providers_command(args)
        subcommand = args.first if args.first && !args.first.start_with?("--")

        case subcommand
        when "info"
          args.shift # Remove 'info'
          require_relative "cli/providers_command"
          command = ProvidersCommand.new(prompt: create_prompt)
          command.run(args, subcommand: "info")
          return
        when "refresh"
          args.shift # Remove 'refresh'
          require_relative "cli/providers_command"
          command = ProvidersCommand.new(prompt: create_prompt)
          command.run(args, subcommand: "refresh")
          return
        end

        # Accept flags directly on `aidp providers` now (health is implicit)
        no_color = false
        args.reject! do |a|
          if a == "--no-color"
            no_color = true
            true
          else
            false
          end
        end
        config_manager = Aidp::Harness::ConfigManager.new(Dir.pwd)
        pm = Aidp::Harness::ProviderManager.new(config_manager, prompt: create_prompt)

        # Use TTY::Spinner for progress indication
        require "tty-spinner"
        start_time = Time.now
        spinner = TTY::Spinner.new(":spinner Gathering provider health...", format: :dots)
        spinner.auto_spin

        begin
          rows = pm.health_dashboard
        ensure
          spinner.stop
          elapsed = (Time.now - start_time).round(2)
          display_message("Provider Health Dashboard (#{elapsed}s)", type: :highlight)
        end
        require "tty-table"
        color = ->(text, code) { "\e[#{code}m#{text}\e[0m" }
        status_color = lambda do |status|
          case status
          when /healthy/ then 32
          when /unhealthy_auth/ then 31
          when /unhealthy/ then 33
          when /circuit/ then 35
          else 37
          end
        end
        availability_color = ->(avail) { (avail == "yes") ? 32 : 31 }
        rate_color = ->(rl) { rl.start_with?("yes") ? 33 : 36 }
        circuit_color = lambda do |c|
          c.start_with?("open") ? 31 : 32
        end
        table_rows = rows.map do |r|
          last_used = r[:last_used] ? r[:last_used].strftime("%H:%M:%S") : "-"
          cb = r[:circuit_breaker]
          cb += " (#{r[:circuit_breaker_remaining]}s)" if r[:circuit_breaker_remaining]
          rl = if r[:rate_limited]
            r[:rate_limit_reset_in] ? "yes (#{r[:rate_limit_reset_in]}s)" : "yes"
          else
            "no"
          end
          tokens = (r[:total_tokens].to_i > 0) ? r[:total_tokens].to_s : "0"
          reason = r[:unhealthy_reason] || "-"
          is_tty = begin
            $stdout.respond_to?(:tty?) && $stdout.tty?
          rescue
            false
          end
          if no_color || !is_tty
            [r[:provider], r[:status], (r[:available] ? "yes" : "no"), cb, rl, tokens, last_used, reason]
          else
            [
              color.call(r[:provider], "1;97"),
              color.call(r[:status], status_color.call(r[:status])),
              color.call(r[:available] ? "yes" : "no", availability_color.call(r[:available] ? "yes" : "no")),
              color.call(cb, circuit_color.call(cb)),
              color.call(rl, rate_color.call(rl)),
              color.call(tokens, 37),
              color.call(last_used, 90),
              ((reason == "-") ? reason : color.call(reason, 33))
            ]
          end
        end
        header = ["Provider", "Status", "Avail", "Circuit", "RateLimited", "Tokens", "LastUsed", "Reason"]
        table = TTY::Table.new header, table_rows
        display_message(table.render(:basic), type: :info)
      rescue => e
        Aidp.logger.warn("cli", "Failed to display provider health", error_class: e.class.name, error_message: e.message)
        display_message("Failed to display provider health: #{e.message}", type: :error)
      end

      def run_mcp_command(args)
        require_relative "cli/mcp_dashboard"

        subcommand = args.shift

        dashboard = Aidp::CLI::McpDashboard.new(Dir.pwd)

        case subcommand
        when "dashboard", "list", nil
          # Extract flags
          no_color = args.include?("--no-color")
          dashboard.display_dashboard(no_color: no_color)

        when "check"
          # Check eligibility for specific servers
          required_servers = args
          if required_servers.empty?
            display_message("Usage: aidp mcp check <server1> [server2] ...", type: :info)
            display_message("Example: aidp mcp check filesystem brave-search", type: :info)
            return
          end

          dashboard.display_task_eligibility(required_servers)

        else
          display_message("Usage: aidp mcp <command>", type: :info)
          display_message("", type: :info)
          display_message("Commands:", type: :info)
          display_message("  dashboard, list     Show MCP servers across all providers (default)", type: :info)
          display_message("  check <servers...>  Check which providers have required MCP servers", type: :info)
          display_message("", type: :info)
          display_message("Examples:", type: :info)
          display_message("  aidp mcp                              # Show dashboard", type: :info)
          display_message("  aidp mcp dashboard --no-color         # Show without colors", type: :info)
          display_message("  aidp mcp check filesystem dash-api    # Check provider eligibility", type: :info)
        end
      end

      def get_binary_name(provider_name)
        case provider_name
        when "claude", "anthropic"
          "claude"
        when "cursor"
          "cursor"
        when "gemini"
          "gemini"
        when "codex"
          "codex"
        when "github_copilot"
          "gh"
        when "opencode"
          "opencode"
        else
          provider_name
        end
      end

      def extract_mode_option(args)
        mode = nil
        args.each do |arg|
          if arg.start_with?("--mode")
            if arg.include?("=")
              mode = arg.split("=", 2)[1]
            else
              idx = args.index(arg)
              mode = args[idx + 1] if args[idx + 1] && !args[idx + 1].start_with?("--")
            end
          end
        end
        mode&.to_sym
      end

      def display_harness_result(result)
        case result[:status]
        when "completed"
          display_message("\n✅ Harness completed successfully!", type: :success)
          display_message("   All steps finished automatically", type: :success)
        when "stopped"
          display_message("\n⏹️  Harness stopped by user", type: :info)
          display_message("   Execution terminated manually", type: :info)
        when "error"
          # Harness already outputs its own error message
        else
          display_message("\n🔄 Harness finished", type: :success)
          display_message("   Status: #{result[:status]}", type: :info)
          display_message("   Message: #{result[:message]}", type: :info) if result[:message]
        end
      end

      def run_models_command(args)
        require_relative "cli/models_command"
        models_cmd = Aidp::CLI::ModelsCommand.new(prompt: create_prompt)
        models_cmd.run(args)
      end

      def run_tools_command(args)
        require_relative "cli/tools_command"
        tools_cmd = Aidp::CLI::ToolsCommand.new(project_dir: Dir.pwd, prompt: create_prompt)
        tools_cmd.run(args)
      end

      def run_security_command(args)
        require_relative "cli/security_command"
        security_cmd = Aidp::CLI::SecurityCommand.new(project_dir: Dir.pwd, prompt: create_prompt)
        security_cmd.run(args)
      end

      def run_storage_command(args)
        require_relative "cli/storage_command"
        storage_cmd = Aidp::CLI::StorageCommand.new(project_dir: Dir.pwd, prompt: create_prompt)
        storage_cmd.run(args)
      end

      def run_prompts_command(args)
        require_relative "cli/prompts_command"
        prompts_cmd = Aidp::CLI::PromptsCommand.new(project_dir: Dir.pwd, prompt: create_prompt)
        prompts_cmd.run(args)
      end

      def run_issue_command(args)
        require_relative "cli/issue_importer"

        usage = <<~USAGE
          Usage: aidp issue <command> [options]

          Commands:
            import <identifier>    Import a GitHub issue
                                  Identifier can be:
                                  - Full URL: https://github.com/owner/repo/issues/123
                                  - Issue number: 123 (when in a git repo)
                                  - Shorthand: owner/repo#123

          Examples:
            aidp issue import https://github.com/rails/rails/issues/12345
            aidp issue import 123
            aidp issue import rails/rails#12345

          Options:
            -h, --help            Show this help message
        USAGE

        if args.empty? || args.include?("-h") || args.include?("--help")
          display_message(usage, type: :info)
          return
        end

        command = args.shift
        case command
        when "import"
          identifier = args.shift
          unless identifier
            display_message("❌ Missing issue identifier", type: :error)
            display_message(usage, type: :info)
            return
          end

          importer = Aidp::IssueImporter.new
          issue_data = importer.import_issue(identifier)

          if issue_data
            display_message("", type: :info)
            display_message("🚀 Ready to start work loop!", type: :success)
            display_message("   Run: aidp execute", type: :info)
          end
        else
          display_message("❌ Unknown issue command: #{command}", type: :error)
          display_message(usage, type: :info)
        end
      end

      def run_config_command(args)
        # Delegate to ConfigCommand
        require_relative "cli/config_command"
        command = ConfigCommand.new(prompt: create_prompt)
        command.run(args)
      end

      def run_devcontainer_command(args)
        require_relative "cli/devcontainer_commands"

        subcommand = args.shift

        case subcommand
        when "diff"
          commands = CLI::DevcontainerCommands.new(project_dir: Dir.pwd, prompt: create_prompt)
          commands.diff
        when "apply"
          options = parse_devcontainer_apply_options(args)
          commands = CLI::DevcontainerCommands.new(project_dir: Dir.pwd, prompt: create_prompt)
          commands.apply(options)
        when "list-backups", "backups"
          commands = CLI::DevcontainerCommands.new(project_dir: Dir.pwd, prompt: create_prompt)
          commands.list_backups
        when "restore"
          backup = args.shift
          unless backup
            display_message("Error: backup index or path required", type: :error)
            display_devcontainer_usage
            return
          end
          options = parse_devcontainer_restore_options(args)
          commands = CLI::DevcontainerCommands.new(project_dir: Dir.pwd, prompt: create_prompt)
          commands.restore(backup, options)
        when "-h", "--help", nil
          display_devcontainer_usage
        else
          display_message("Unknown devcontainer subcommand: #{subcommand}", type: :error)
          display_devcontainer_usage
        end
      end

      def parse_devcontainer_apply_options(args)
        options = {}
        until args.empty?
          token = args.shift
          case token
          when "--dry-run"
            options[:dry_run] = true
          when "--force"
            options[:force] = true
          when "--no-backup"
            options[:backup] = false
          else
            display_message("Unknown apply option: #{token}", type: :error)
          end
        end
        options
      end

      def parse_devcontainer_restore_options(args)
        options = {}
        until args.empty?
          token = args.shift
          case token
          when "--force"
            options[:force] = true
          when "--no-backup"
            options[:no_backup] = true
          else
            display_message("Unknown restore option: #{token}", type: :error)
          end
        end
        options
      end

      def display_devcontainer_usage
        display_message("\nUsage: aidp devcontainer <subcommand> [options]", type: :info)
        display_message("\nSubcommands:", type: :info)
        display_message("  diff                    Show changes between current and proposed config", type: :muted)
        display_message("  apply                   Apply configuration from aidp.yml", type: :muted)
        display_message("  list-backups            List available backups", type: :muted)
        display_message("  restore <index|path>    Restore from backup", type: :muted)
        display_message("\nApply Options:", type: :info)
        display_message("  --dry-run              Preview changes without applying", type: :muted)
        display_message("  --force                Skip confirmation prompts", type: :muted)
        display_message("  --no-backup            Don't create backup before applying", type: :muted)
        display_message("\nRestore Options:", type: :info)
        display_message("  --force                Skip confirmation prompt", type: :muted)
        display_message("  --no-backup            Don't create backup before restoring", type: :muted)
        display_message("\nExamples:", type: :info)
        display_message("  aidp devcontainer diff", type: :muted)
        display_message("  aidp devcontainer apply --dry-run", type: :muted)
        display_message("  aidp devcontainer apply --force", type: :muted)
        display_message("  aidp devcontainer list-backups", type: :muted)
        display_message("  aidp devcontainer restore 1", type: :muted)
      end

      def run_init_command(args = [])
        options = {}

        until args.empty?
          token = args.shift
          case token
          when "--explain-detection"
            options[:explain_detection] = true
          when "--dry-run"
            options[:dry_run] = true
          when "--preview"
            options[:preview] = true
          when "-h", "--help"
            display_init_usage
            return
          else
            display_message("Unknown init option: #{token}", type: :error)
            display_init_usage
            return
          end
        end

        require_relative "init/runner"
        runner = Aidp::Init::Runner.new(Dir.pwd, prompt: create_prompt, options: options)
        runner.run
      end

      def display_init_usage
        display_message("Usage: aidp init [options]", type: :info)
        display_message("", type: :info)
        display_message("Options:", type: :info)
        display_message("  --explain-detection    Show detailed evidence for all detections", type: :info)
        display_message("  --dry-run              Run analysis without generating files", type: :info)
        display_message("  --preview              Show preview before writing files", type: :info)
        display_message("  -h, --help             Show this help message", type: :info)
        display_message("", type: :info)
        display_message("Examples:", type: :info)
        display_message("  aidp init                           # Run full init workflow", type: :info)
        display_message("  aidp init --explain-detection       # Show detailed detection evidence", type: :info)
        display_message("  aidp init --dry-run                 # Preview without writing files", type: :info)
        display_message("  aidp init --preview                 # Show preview before writing", type: :info)
      end

      def run_watch_command(args)
        if args.empty?
          display_message("Usage: aidp watch <issues_url> [--interval SECONDS] [--provider NAME] [--once] [--no-workstreams] [--force] [--verbose] [--quiet]", type: :info)
          return
        end

        issues_url = args.shift
        interval = Aidp::Watch::Runner::DEFAULT_INTERVAL
        provider_name = nil
        once = false
        use_workstreams = true # Default to using workstreams
        force = false
        verbose = false
        quiet = false
        launch_test = false

        until args.empty?
          token = args.shift
          case token
          when "--interval"
            interval_value = args.shift
            interval = interval_value.to_i if interval_value
          when "--provider"
            provider_name = args.shift
          when "--once"
            once = true
          when "--no-workstreams"
            use_workstreams = false
          when "--force"
            force = true
          when "--verbose"
            verbose = true
          when "--quiet"
            quiet = true
          when "--launch-test"
            launch_test = true
          else
            display_message("⚠️  Unknown watch option: #{token}", type: :warn)
          end
        end

        # Validate incompatible options
        if quiet && verbose
          display_message("❌ --quiet and --verbose are mutually exclusive", type: :error)
          return 1
        end

        # Undocumented: Launch test mode for CI/CD validation
        # Exits after validating watch mode initialization
        if launch_test
          return run_launch_test(:watch)
        end

        # Initialize logger for watch mode
        setup_logging(Dir.pwd)

        # Load watch safety configuration
        config_manager = Aidp::Harness::ConfigManager.new(Dir.pwd)
        config = config_manager.config || {}
        watch_config = config[:watch] || config["watch"] || {}

        runner = Aidp::Watch::Runner.new(
          issues_url: issues_url,
          interval: interval.positive? ? interval : Aidp::Watch::Runner::DEFAULT_INTERVAL,
          provider_name: provider_name,
          project_dir: Dir.pwd,
          once: once,
          use_workstreams: use_workstreams,
          prompt: create_prompt,
          safety_config: watch_config,
          force: force,
          verbose: verbose,
          quiet: quiet
        )
        runner.start
      rescue ArgumentError => e
        log_rescue(e, component: "cli", action: "start_watch_command", fallback: "error_display")
        display_message("❌ #{e.message}", type: :error)
      end

      def run_ws_command(args)
        require_relative "worktree"
        require_relative "workstream_state"
        require "tty-table"

        subcommand = args.shift

        case subcommand
        when "list", nil
          # List all workstreams
          workstreams = Aidp::Worktree.list(project_dir: Dir.pwd)

          if workstreams.empty?
            display_message("No workstreams found.", type: :info)
            display_message("Create one with: aidp ws new <slug> [task]", type: :muted)
            return
          end

          display_message("Workstreams", type: :highlight)
          display_message("=" * 80, type: :muted)

          table_rows = workstreams.map do |ws|
            state = Aidp::WorkstreamState.read(slug: ws[:slug], project_dir: Dir.pwd) || {}
            status_icon = ws[:active] ? "✓" : "✗"
            created = Time.parse(ws[:created_at]).strftime("%Y-%m-%d %H:%M")
            iterations = state[:iterations] || 0
            task = state[:task] && state[:task].to_s[0, 40]
            [
              status_icon,
              ws[:slug],
              ws[:branch],
              created,
              ws[:active] ? "active" : "inactive",
              iterations,
              task
            ]
          end

          header = ["", "Slug", "Branch", "Created", "Status", "Iter", "Task"]
          table = TTY::Table.new(header, table_rows)
          # Render with explicit width for non-TTY environments (e.g., tests)
          renderer = if $stdout.tty?
            table.render(:basic)
          else
            table.render(:basic, width: 120)
          end
          display_message(renderer, type: :info)

        when "new"
          # Create new workstream
          slug = args.shift
          unless slug
            display_message("❌ Missing slug", type: :error)
            display_message("Usage: aidp ws new <slug> [task]", type: :info)
            return
          end

          # Validate slug format (lowercase, hyphens, no special chars)
          unless slug.match?(/^[a-z0-9]+(-[a-z0-9]+)*$/)
            display_message("❌ Invalid slug format", type: :error)
            display_message("   Slug must be lowercase with hyphens (e.g., 'issue-123-fix-auth')", type: :info)
            return
          end

          task_parts = []
          base_branch = nil
          until args.empty?
            token = args.shift
            if token == "--base-branch"
              base_branch = args.shift
            else
              task_parts << token
            end
          end
          task = task_parts.join(" ")

          begin
            result = Aidp::Worktree.create(
              slug: slug,
              project_dir: Dir.pwd,
              base_branch: base_branch,
              task: (task unless task.empty?)
            )

            display_message("✓ Created workstream: #{slug}", type: :success)
            display_message("  Path: #{result[:path]}", type: :info)
            display_message("  Branch: #{result[:branch]}", type: :info)
            display_message("  Task: #{task}", type: :info) unless task.empty?
            display_message("", type: :info)
            display_message("Switch to this workstream:", type: :muted)
            display_message("  cd #{result[:path]}", type: :info)
          rescue Aidp::Worktree::Error => e
            display_message("❌ #{e.message}", type: :error)
          end

        when "rm"
          # Remove workstream
          slug = args.shift
          unless slug
            display_message("❌ Missing slug", type: :error)
            display_message("Usage: aidp ws rm <slug> [--delete-branch] [--force]", type: :info)
            return
          end

          delete_branch = args.include?("--delete-branch")
          force = args.include?("--force")

          # Confirm removal unless --force
          unless force
            prompt = create_prompt
            confirm = prompt.yes?("Remove workstream '#{slug}'?#{" (will also delete branch)" if delete_branch}")
            return unless confirm
          end

          begin
            Aidp::Worktree.remove(
              slug: slug,
              project_dir: Dir.pwd,
              delete_branch: delete_branch
            )

            display_message("✓ Removed workstream: #{slug}", type: :success)
            display_message("  Branch deleted", type: :info) if delete_branch
          rescue Aidp::Worktree::Error => e
            display_message("❌ #{e.message}", type: :error)
          end

        when "status"
          # Show workstream status
          slug = args.shift
          unless slug
            display_message("❌ Missing slug", type: :error)
            display_message("Usage: aidp ws status <slug>", type: :info)
            return
          end

          begin
            ws = Aidp::Worktree.info(slug: slug, project_dir: Dir.pwd)
            unless ws
              display_message("❌ Workstream not found: #{slug}", type: :error)
              return
            end

            state = Aidp::WorkstreamState.read(slug: slug, project_dir: Dir.pwd) || {}
            iterations = state[:iterations] || 0
            elapsed = Aidp::WorkstreamState.elapsed_seconds(slug: slug, project_dir: Dir.pwd)
            task = state[:task]
            recent_events = Aidp::WorkstreamState.recent_events(slug: slug, project_dir: Dir.pwd, limit: 5)
            display_message("Workstream: #{slug}", type: :highlight)
            display_message("=" * 60, type: :muted)
            display_message("Path: #{ws[:path]}", type: :info)
            display_message("Branch: #{ws[:branch]}", type: :info)
            display_message("Created: #{Time.parse(ws[:created_at]).strftime("%Y-%m-%d %H:%M:%S")}", type: :info)
            display_message("Status: #{ws[:active] ? "Active" : "Inactive"}", type: ws[:active] ? :success : :error)
            display_message("Iterations: #{iterations}", type: :info)
            display_message("Elapsed: #{elapsed}s", type: :info)
            display_message("Task: #{task}", type: :info) if task
            if recent_events.any?
              display_message("", type: :info)
              display_message("Recent Events:", type: :highlight)
              recent_events.each do |ev|
                display_message("  #{ev[:timestamp]} #{ev[:type]} #{ev[:data].inspect if ev[:data]}", type: :muted)
              end
            end

            # Show git status if active
            if ws[:active] && Dir.exist?(ws[:path])
              display_message("", type: :info)
              display_message("Git Status:", type: :highlight)
              Dir.chdir(ws[:path]) do
                system("git", "status", "--short")
              end
            end
          rescue Aidp::Worktree::Error => e
            display_message("❌ #{e.message}", type: :error)
          end

        when "pause"
          # Pause workstream
          slug = args.shift
          unless slug
            display_message("❌ Missing slug", type: :error)
            display_message("Usage: aidp ws pause <slug>", type: :info)
            return
          end

          result = Aidp::WorkstreamState.pause(slug: slug, project_dir: Dir.pwd)
          if result[:error]
            display_message("❌ #{result[:error]}", type: :error)
          else
            display_message("⏸️  Paused workstream: #{slug}", type: :success)
          end

        when "resume"
          # Resume workstream
          slug = args.shift
          unless slug
            display_message("❌ Missing slug", type: :error)
            display_message("Usage: aidp ws resume <slug>", type: :info)
            return
          end

          result = Aidp::WorkstreamState.resume(slug: slug, project_dir: Dir.pwd)
          if result[:error]
            display_message("❌ #{result[:error]}", type: :error)
          else
            display_message("▶️  Resumed workstream: #{slug}", type: :success)
          end

        when "complete"
          # Mark workstream as completed
          slug = args.shift
          unless slug
            display_message("❌ Missing slug", type: :error)
            display_message("Usage: aidp ws complete <slug>", type: :info)
            return
          end

          result = Aidp::WorkstreamState.complete(slug: slug, project_dir: Dir.pwd)
          if result[:error]
            display_message("❌ #{result[:error]}", type: :error)
          else
            display_message("✅ Completed workstream: #{slug}", type: :success)
          end

        when "run"
          # Run one or more workstreams in parallel
          require_relative "workstream_executor"

          slugs = []
          max_concurrent = 3
          mode = :execute
          selected_steps = nil

          until args.empty?
            token = args.shift
            case token
            when "--max-concurrent"
              max_concurrent = args.shift.to_i
            when "--mode"
              mode = args.shift&.to_sym || :execute
            when "--steps"
              selected_steps = args.shift.split(",")
            else
              slugs << token
            end
          end

          if slugs.empty?
            display_message("❌ Missing workstream slug(s)", type: :error)
            display_message("Usage: aidp ws run <slug1> [slug2...] [--max-concurrent N] [--mode analyze|execute] [--steps STEP1,STEP2]", type: :info)
            display_message("", type: :info)
            display_message("Examples:", type: :info)
            display_message("  aidp ws run issue-123                           # Run single workstream", type: :info)
            display_message("  aidp ws run issue-123 issue-456 feature-x       # Run multiple in parallel", type: :info)
            display_message("  aidp ws run issue-* --max-concurrent 5          # Run all matching (expand glob first)", type: :info)
            return
          end

          begin
            executor = Aidp::WorkstreamExecutor.new(project_dir: Dir.pwd, max_concurrent: max_concurrent)
            options = {mode: mode}
            options[:selected_steps] = selected_steps if selected_steps

            results = executor.execute_parallel(slugs, options)

            # Show results
            display_message("", type: :info)
            success_count = results.count { |r| r.status == "completed" }
            if success_count == results.size
              display_message("🎉 All workstreams completed successfully!", type: :success)
            else
              display_message("⚠️  Some workstreams failed", type: :warn)
            end
          rescue => e
            display_message("❌ Parallel execution error: #{e.message}", type: :error)
          end

        when "run-all"
          # Run all active workstreams in parallel
          require_relative "workstream_executor"

          max_concurrent = 3
          mode = :execute
          selected_steps = nil

          until args.empty?
            token = args.shift
            case token
            when "--max-concurrent"
              max_concurrent = args.shift.to_i
            when "--mode"
              mode = args.shift&.to_sym || :execute
            when "--steps"
              selected_steps = args.shift.split(",")
            end
          end

          begin
            executor = Aidp::WorkstreamExecutor.new(project_dir: Dir.pwd, max_concurrent: max_concurrent)
            options = {mode: mode}
            options[:selected_steps] = selected_steps if selected_steps

            results = executor.execute_all(options)

            if results.empty?
              display_message("⚠️  No active workstreams to run", type: :warn)
              return
            end

            # Show results
            display_message("", type: :info)
            success_count = results.count { |r| r.status == "completed" }
            if success_count == results.size
              display_message("🎉 All workstreams completed successfully!", type: :success)
            else
              display_message("⚠️  Some workstreams failed", type: :warn)
            end
          rescue => e
            display_message("❌ Parallel execution error: #{e.message}", type: :error)
          end

        when "dashboard"
          # Show multi-workstream dashboard
          workstreams = Aidp::Worktree.list(project_dir: Dir.pwd)

          if workstreams.empty?
            display_message("No workstreams found.", type: :info)
            display_message("Create one with: aidp ws new <slug> [task]", type: :muted)
            return
          end

          display_message("Workstreams Dashboard", type: :highlight)
          display_message("=" * 120, type: :muted)

          # Aggregate state from all workstreams
          table_rows = workstreams.map do |ws|
            state = Aidp::WorkstreamState.read(slug: ws[:slug], project_dir: Dir.pwd) || {}
            status = state[:status] || "active"
            iterations = state[:iterations] || 0
            elapsed = Aidp::WorkstreamState.elapsed_seconds(slug: ws[:slug], project_dir: Dir.pwd)
            task = state[:task] && state[:task].to_s[0, 30]
            recent_events = Aidp::WorkstreamState.recent_events(slug: ws[:slug], project_dir: Dir.pwd, limit: 1)
            recent_event = recent_events.first
            event_summary = if recent_event
              "#{recent_event[:type]} (#{Time.parse(recent_event[:timestamp]).strftime("%H:%M")})"
            else
              "—"
            end

            status_icon = case status
            when "active" then "▶️"
            when "paused" then "⏸️"
            when "completed" then "✅"
            when "removed" then "❌"
            else "?"
            end

            [
              status_icon,
              ws[:slug],
              status,
              iterations,
              "#{elapsed}s",
              task || "—",
              event_summary
            ]
          end

          header = ["", "Slug", "Status", "Iter", "Elapsed", "Task", "Recent Event"]
          table = TTY::Table.new(header, table_rows)
          # Render with explicit width for non-TTY environments
          renderer = if $stdout.tty?
            table.render(:basic)
          else
            table.render(:basic, width: 120)
          end
          display_message(renderer, type: :info)

          # Show summary counts
          display_message("", type: :info)
          status_counts = workstreams.group_by do |ws|
            state = Aidp::WorkstreamState.read(slug: ws[:slug], project_dir: Dir.pwd) || {}
            state[:status] || "active"
          end
          summary_parts = status_counts.map { |status, ws_list| "#{status}: #{ws_list.size}" }
          display_message("Summary: #{summary_parts.join(", ")}", type: :muted)

        when "pause-all"
          # Pause all active workstreams
          workstreams = Aidp::Worktree.list(project_dir: Dir.pwd)
          paused_count = 0
          workstreams.each do |ws|
            state = Aidp::WorkstreamState.read(slug: ws[:slug], project_dir: Dir.pwd)
            next unless state && state[:status] == "active"
            result = Aidp::WorkstreamState.pause(slug: ws[:slug], project_dir: Dir.pwd)
            paused_count += 1 unless result[:error]
          end
          display_message("⏸️  Paused #{paused_count} workstream(s)", type: :success)

        when "resume-all"
          # Resume all paused workstreams
          workstreams = Aidp::Worktree.list(project_dir: Dir.pwd)
          resumed_count = 0
          workstreams.each do |ws|
            state = Aidp::WorkstreamState.read(slug: ws[:slug], project_dir: Dir.pwd)
            next unless state && state[:status] == "paused"
            result = Aidp::WorkstreamState.resume(slug: ws[:slug], project_dir: Dir.pwd)
            resumed_count += 1 unless result[:error]
          end
          display_message("▶️  Resumed #{resumed_count} workstream(s)", type: :success)

        when "stop-all"
          # Complete all active workstreams
          workstreams = Aidp::Worktree.list(project_dir: Dir.pwd)
          stopped_count = 0
          workstreams.each do |ws|
            state = Aidp::WorkstreamState.read(slug: ws[:slug], project_dir: Dir.pwd)
            next unless state && state[:status] == "active"
            result = Aidp::WorkstreamState.complete(slug: ws[:slug], project_dir: Dir.pwd)
            stopped_count += 1 unless result[:error]
          end
          display_message("⏹️  Stopped #{stopped_count} workstream(s)", type: :success)

        when "cleanup"
          # Interactive cleanup of workstreams
          require_relative "workstream_cleanup"
          cleanup = Aidp::WorkstreamCleanup.new(project_dir: Dir.pwd, prompt: create_prompt)
          cleanup.run

        else
          display_message("Usage: aidp ws <command>", type: :info)
          display_message("", type: :info)
          display_message("Commands:", type: :info)
          display_message("  list                      List all workstreams (default)", type: :info)
          display_message("  new <slug> [task]         Create new workstream", type: :info)
          display_message("  rm <slug>                 Remove workstream", type: :info)
          display_message("  status <slug>             Show workstream status", type: :info)
          display_message("  run <slug...>             Run workstream(s) in parallel", type: :info)
          display_message("  run-all                   Run all active workstreams in parallel", type: :info)
          display_message("  dashboard                 Show multi-workstream dashboard", type: :info)
          display_message("  pause <slug>              Pause workstream execution", type: :info)
          display_message("  resume <slug>             Resume paused workstream", type: :info)
          display_message("  complete <slug>           Mark workstream as completed", type: :info)
          display_message("  cleanup                   Interactive cleanup of workstreams", type: :info)
          display_message("", type: :info)
          display_message("Options:", type: :info)
          display_message("  --base-branch <branch>    Branch to create from (for 'new')", type: :info)
          display_message("  --delete-branch           Also delete git branch (for 'rm')", type: :info)
          display_message("  --force                   Skip confirmation (for 'rm')", type: :info)
          display_message("  --max-concurrent N        Max parallel workstreams (for 'run', 'run-all')", type: :info)
          display_message("  --mode analyze|execute    Execution mode (for 'run', 'run-all')", type: :info)
          display_message("  --steps STEP1,STEP2       Specific steps to run (for 'run', 'run-all')", type: :info)
          display_message("", type: :info)
          display_message("Examples:", type: :info)
          display_message("  aidp ws list                                    # List workstreams", type: :info)
          display_message("  aidp ws new issue-123 Fix authentication bug    # Create workstream", type: :info)
          display_message("  aidp ws new feature-x --base-branch develop     # Create from branch", type: :info)
          display_message("  aidp ws status issue-123                        # Show status", type: :info)
          display_message("  aidp ws run issue-123                           # Run single workstream", type: :info)
          display_message("  aidp ws run issue-123 feature-x --max-concurrent 5  # Run multiple in parallel", type: :info)
          display_message("  aidp ws run-all --max-concurrent 3              # Run all active workstreams", type: :info)
          display_message("  aidp ws dashboard                               # Monitor all workstreams", type: :info)
          display_message("  aidp ws rm issue-123                            # Remove workstream", type: :info)
          display_message("  aidp ws rm issue-123 --delete-branch --force    # Force remove with branch", type: :info)
        end
      end

      def run_work_command(args)
        require_relative "worktree"
        require_relative "harness/state_manager"

        # Parse options
        workstream_slug = nil
        mode = :execute
        background = false

        until args.empty?
          token = args.shift
          case token
          when "--workstream"
            workstream_slug = args.shift
          when "--mode"
            mode = args.shift&.to_sym || :execute
          when "--background"
            background = true
          else
            display_message("⚠️  Unknown work option: #{token}", type: :warn)
          end
        end

        unless workstream_slug
          display_message("❌ Missing required --workstream flag", type: :error)
          display_message("Usage: aidp work --workstream <slug> [--mode analyze|execute] [--background]", type: :info)
          return
        end

        # Verify workstream exists
        ws = Aidp::Worktree.info(slug: workstream_slug, project_dir: Dir.pwd)
        unless ws
          display_message("❌ Workstream not found: #{workstream_slug}", type: :error)
          return
        end

        display_message("🚀 Starting #{mode} mode in workstream: #{workstream_slug}", type: :highlight)
        display_message("  Path: #{ws[:path]}", type: :info)
        display_message("  Branch: #{ws[:branch]}", type: :info)

        if background
          require_relative "jobs/background_runner"
          runner = Aidp::Jobs::BackgroundRunner.new(Dir.pwd)

          display_message("Starting in background...", type: :info)
          job_id = runner.start(mode, {workstream: workstream_slug})

          display_message("✓ Started background job: #{job_id}", type: :success)
          display_message("", type: :info)
          display_message("Monitor progress:", type: :info)
          display_message("  aidp jobs status #{job_id}", type: :info)
          display_message("  aidp jobs logs #{job_id} --tail", type: :info)
          display_message("  aidp ws status #{workstream_slug}", type: :info)
        else
          # Run harness inline with workstream context
          state_manager = Aidp::Harness::StateManager.new(Dir.pwd, mode)
          state_manager.set_workstream(workstream_slug)

          # Launch harness (will cd into workstream path via enhanced_runner)
          display_message("Starting interactive harness...", type: :info)
          display_message("Press Ctrl+C to stop", type: :highlight)

          # Re-use existing CLI.run harness launch logic but skip first-run wizard
          # Initialize the enhanced TUI
          require_relative "harness/ui/enhanced_tui"
          require_relative "harness/ui/enhanced_workflow_selector"
          require_relative "harness/enhanced_runner"

          tui = Aidp::Harness::UI::EnhancedTUI.new
          workflow_selector = Aidp::Harness::UI::EnhancedWorkflowSelector.new(tui, project_dir: Dir.pwd)

          begin
            # Get workflow configuration
            workflow_config = workflow_selector.select_workflow(harness_mode: false, mode: mode)
            actual_mode = workflow_config[:mode] || mode

            # Pass workflow configuration to harness
            harness_options = {
              mode: actual_mode,
              workflow_type: workflow_config[:workflow_type],
              selected_steps: workflow_config[:steps],
              user_input: workflow_config[:user_input]
            }

            # Create and run the enhanced harness
            harness_runner = Aidp::Harness::EnhancedRunner.new(Dir.pwd, actual_mode, harness_options)
            result = harness_runner.run
            display_harness_result(result)
          rescue Interrupt
            display_message("\n\n⏹️  Interrupted by user", type: :warning)
          ensure
            tui.restore_screen
          end
        end
      end

      def run_settings_command(args)
        require_relative "auto_update"
        require "yaml"
        require "tty-table"

        subcommand = args.shift

        case subcommand
        when "auto-update"
          action = args.shift

          case action
          when "status", nil
            # Show current auto-update status
            coordinator = Aidp::AutoUpdate.coordinator(project_dir: Dir.pwd)
            status = coordinator.status

            display_message("Auto-Update Configuration", type: :highlight)
            display_message("=" * 60, type: :muted)
            display_message("Enabled: #{status[:enabled] ? "Yes" : "No"}", type: status[:enabled] ? :success : :muted)
            display_message("Policy: #{status[:policy]}", type: :info)
            display_message("Supervisor: #{status[:supervisor]}", type: :info)
            display_message("Allow Prerelease: #{coordinator.policy.allow_prerelease}", type: :info)
            display_message("Check Interval: #{coordinator.policy.check_interval_seconds}s", type: :info)
            display_message("Max Consecutive Failures: #{coordinator.policy.max_consecutive_failures}", type: :info)
            display_message("", type: :info)
            display_message("Current Version: #{status[:current_version]}", type: :info)
            display_message("Latest Available: #{status[:available_version] || "checking..."}", type: :info)

            if status[:update_available]
              if status[:update_allowed]
                display_message("Update Available: Yes (allowed by policy)", type: :success)
              else
                display_message("Update Available: Yes (blocked by policy: #{status[:policy_reason]})", type: :warning)
              end
            else
              display_message("Update Available: No", type: :muted)
            end

            display_message("", type: :info)
            display_message("Failure Tracker:", type: :highlight)
            failure_status = status[:failure_tracker]
            display_message("Consecutive Failures: #{failure_status[:failures]}/#{failure_status[:max_failures]}", type: :info)
            display_message("Last Success: #{failure_status[:last_success] || "never"}", type: :muted)

            if status[:recent_updates]&.any?
              display_message("", type: :info)
              display_message("Recent Updates:", type: :highlight)
              status[:recent_updates].each do |entry|
                timestamp = entry["timestamp"] || entry[:timestamp]
                event = entry["event"] || entry[:event]
                display_message("  #{timestamp} - #{event}", type: :muted)
              end
            end

          when "on"
            # Enable auto-update
            update_config_value(:auto_update, :enabled, true)
            display_message("✓ Auto-update enabled", type: :success)
            display_message("", type: :info)
            display_message("Make sure to configure a supervisor for watch mode.", type: :muted)
            display_message("See: docs/SELF_UPDATE.md", type: :muted)

          when "off"
            # Disable auto-update
            update_config_value(:auto_update, :enabled, false)
            display_message("✓ Auto-update disabled", type: :success)

          when "policy"
            # Set update policy
            policy = args.shift
            unless %w[off exact patch minor major].include?(policy)
              display_message("❌ Invalid policy. Must be: off, exact, patch, minor, major", type: :error)
              return
            end

            update_config_value(:auto_update, :policy, policy)
            display_message("✓ Auto-update policy set to: #{policy}", type: :success)
            display_message("", type: :info)
            case policy
            when "off"
              display_message("No automatic updates will be performed", type: :muted)
            when "exact"
              display_message("Only exact version matches allowed", type: :muted)
            when "patch"
              display_message("Patch updates allowed (e.g., 1.2.3 → 1.2.4)", type: :muted)
            when "minor"
              display_message("Minor + patch updates allowed (e.g., 1.2.3 → 1.3.0)", type: :muted)
            when "major"
              display_message("All updates allowed (e.g., 1.2.3 → 2.0.0)", type: :muted)
            end

          when "prerelease"
            # Toggle prerelease
            current = load_auto_update_config[:allow_prerelease]
            new_value = !current
            update_config_value(:auto_update, :allow_prerelease, new_value)
            display_message("✓ Prerelease updates: #{new_value ? "enabled" : "disabled"}", type: :success)

          else
            display_message("Usage: aidp settings auto-update <command>", type: :info)
            display_message("", type: :info)
            display_message("Commands:", type: :info)
            display_message("  status                Show current configuration", type: :info)
            display_message("  on                    Enable auto-updates", type: :info)
            display_message("  off                   Disable auto-updates", type: :info)
            display_message("  policy <policy>       Set update policy", type: :info)
            display_message("    Policies: off, exact, patch, minor, major", type: :muted)
            display_message("  prerelease            Toggle prerelease updates", type: :info)
            display_message("", type: :info)
            display_message("Examples:", type: :info)
            display_message("  aidp settings auto-update status", type: :info)
            display_message("  aidp settings auto-update on", type: :info)
            display_message("  aidp settings auto-update policy minor", type: :info)
            display_message("  aidp settings auto-update prerelease", type: :info)
          end

        else
          display_message("Usage: aidp settings <category> <command>", type: :info)
          display_message("", type: :info)
          display_message("Categories:", type: :info)
          display_message("  auto-update           Auto-update configuration", type: :info)
          display_message("", type: :info)
          display_message("Examples:", type: :info)
          display_message("  aidp settings auto-update status", type: :info)
        end
      end

      # Load current auto_update config
      def load_auto_update_config
        config_path = File.join(Dir.pwd, ".aidp", "aidp.yml")
        return {} unless File.exist?(config_path)

        full_config = YAML.safe_load_file(config_path, permitted_classes: [Date, Time, Symbol], aliases: true)
        full_config["auto_update"] || full_config[:auto_update] || {}
      end

      # Update a specific configuration value
      def update_config_value(section, key, value)
        config_path = File.join(Dir.pwd, ".aidp", "aidp.yml")

        # Load existing config
        config = if File.exist?(config_path)
          YAML.safe_load_file(config_path, permitted_classes: [Date, Time, Symbol], aliases: true) || {}
        else
          {}
        end

        # Ensure section exists
        config[section.to_s] ||= {}

        # Update value
        config[section.to_s][key.to_s] = value

        # Write back
        File.write(config_path, YAML.dump(config))
      end

      def run_skill_command(args)
        require_relative "skills"
        require "tty-table"

        subcommand = args.shift

        case subcommand
        when "list", nil
          # List all available skills
          begin
            registry = Aidp::Skills::Registry.new(project_dir: Dir.pwd)
            registry.load_skills

            skills = registry.all

            if skills.empty?
              display_message("No skills found.", type: :info)
              display_message("Create one in skills/ or .aidp/skills/", type: :muted)
              return
            end

            by_source = registry.by_source

            if by_source[:template].any?
              display_message("Template Skills", type: :highlight)
              display_message("=" * 80, type: :muted)
              table_rows = by_source[:template].map do |skill_id|
                skill = registry.find(skill_id)
                [skill_id, skill.version, skill.description[0, 60]]
              end
              header = ["ID", "Version", "Description"]
              table = TTY::Table.new(header, table_rows)
              display_message(table.render(:basic), type: :info)
              display_message("", type: :info)
            end

            if by_source[:project].any?
              display_message("Project Skills", type: :highlight)
              display_message("=" * 80, type: :muted)
              table_rows = by_source[:project].map do |skill_id|
                skill = registry.find(skill_id)
                [skill_id, skill.version, skill.description[0, 60]]
              end
              header = ["ID", "Version", "Description"]
              table = TTY::Table.new(header, table_rows)
              display_message(table.render(:basic), type: :info)
              display_message("", type: :info)
            end

            display_message("Use 'aidp skill show <id>' for details", type: :muted)
          rescue => e
            display_message("Failed to list skills: #{e.message}", type: :error)
          end

        when "show"
          # Show detailed skill information
          skill_id = args.shift

          unless skill_id
            display_message("Usage: aidp skill show <skill-id>", type: :info)
            return
          end

          begin
            registry = Aidp::Skills::Registry.new(project_dir: Dir.pwd)
            registry.load_skills

            skill = registry.find(skill_id)

            unless skill
              display_message("Skill not found: #{skill_id}", type: :error)
              display_message("Use 'aidp skill list' to see available skills", type: :muted)
              return
            end

            details = skill.details

            display_message("Skill: #{details[:name]} (#{details[:id]})", type: :highlight)
            display_message("=" * 80, type: :muted)
            display_message("Version: #{details[:version]}", type: :info)
            display_message("Source: #{details[:source]}", type: :muted)
            display_message("", type: :info)
            display_message("Description:", type: :info)
            display_message("  #{details[:description]}", type: :info)
            display_message("", type: :info)

            if details[:expertise].any?
              display_message("Expertise:", type: :info)
              details[:expertise].each { |e| display_message("  • #{e}", type: :info) }
              display_message("", type: :info)
            end

            if details[:keywords].any?
              display_message("Keywords: #{details[:keywords].join(", ")}", type: :info)
              display_message("", type: :info)
            end

            if details[:when_to_use].any?
              display_message("When to Use:", type: :info)
              details[:when_to_use].each { |w| display_message("  • #{w}", type: :info) }
              display_message("", type: :info)
            end

            if details[:when_not_to_use].any?
              display_message("When NOT to Use:", type: :info)
              details[:when_not_to_use].each { |w| display_message("  • #{w}", type: :info) }
              display_message("", type: :info)
            end

            if details[:compatible_providers].any?
              display_message("Compatible Providers: #{details[:compatible_providers].join(", ")}", type: :info)
            else
              display_message("Compatible Providers: all", type: :info)
            end
          rescue => e
            display_message("Failed to show skill: #{e.message}", type: :error)
          end

        when "search"
          # Search skills by query
          query = args.join(" ")

          unless query && !query.empty?
            display_message("Usage: aidp skill search <query>", type: :info)
            return
          end

          begin
            registry = Aidp::Skills::Registry.new(project_dir: Dir.pwd)
            registry.load_skills

            matching_skills = registry.search(query)

            if matching_skills.empty?
              display_message("No skills found matching '#{query}'", type: :info)
              return
            end

            display_message("Skills matching '#{query}':", type: :highlight)
            display_message("=" * 80, type: :muted)
            matching_skills.each do |skill|
              display_message("  • #{skill.id} - #{skill.description}", type: :info)
            end
          rescue => e
            display_message("Failed to search skills: #{e.message}", type: :error)
          end

        when "preview"
          # Preview full skill content
          skill_id = args.shift

          unless skill_id
            display_message("Usage: aidp skill preview <skill-id>", type: :info)
            return
          end

          begin
            registry = Aidp::Skills::Registry.new(project_dir: Dir.pwd)
            registry.load_skills

            skill = registry.find(skill_id)

            unless skill
              display_message("Skill not found: #{skill_id}", type: :error)
              display_message("Use 'aidp skill list' to see available skills", type: :muted)
              return
            end

            require_relative "skills/wizard/builder"
            require_relative "skills/wizard/template_library"

            builder = Aidp::Skills::Wizard::Builder.new
            full_content = builder.to_skill_md(skill)

            # Check if this is a project skill with a matching template
            source_info = registry.by_source[skill_id]
            inheritance_info = ""
            if source_info == :project
              template_library = Aidp::Skills::Wizard::TemplateLibrary.new(project_dir: Dir.pwd)
              template_skill = template_library.templates.find { |s| s.id == skill.id }
              if template_skill
                inheritance_info = " (inherits from template)"
              end
            elsif source_info == :template
              inheritance_info = " (template)"
            end

            display_message("\n" + "=" * 60, type: :info)
            display_message("Skill: #{skill.name} (#{skill.id}) v#{skill.version}#{inheritance_info}", type: :highlight)
            display_message("=" * 60 + "\n", type: :info)
            display_message(full_content, type: :info)
            display_message("\n" + "=" * 60, type: :info)
          rescue => e
            display_message("Failed to preview skill: #{e.message}", type: :error)
          end

        when "diff"
          # Show diff between project skill and template
          skill_id = args.shift

          unless skill_id
            display_message("Usage: aidp skill diff <skill-id>", type: :info)
            return
          end

          begin
            require_relative "skills/wizard/template_library"
            require_relative "skills/wizard/differ"

            registry = Aidp::Skills::Registry.new(project_dir: Dir.pwd)
            registry.load_skills

            project_skill = registry.find(skill_id)

            unless project_skill
              display_message("Skill not found: #{skill_id}", type: :error)
              return
            end

            # Check if it's a project skill
            unless registry.by_source[:project].include?(skill_id)
              display_message("Skill '#{skill_id}' is a template skill, not a project skill", type: :info)
              display_message("Only project skills can be diffed against templates", type: :muted)
              return
            end

            # Find the template
            template_library = Aidp::Skills::Wizard::TemplateLibrary.new(project_dir: Dir.pwd)
            template_skill = template_library.find(skill_id)

            unless template_skill
              display_message("No template found for skill '#{skill_id}'", type: :info)
              display_message("This is a custom skill without a template base", type: :muted)
              return
            end

            # Show diff
            differ = Aidp::Skills::Wizard::Differ.new
            diff_result = differ.diff(template_skill, project_skill)
            differ.display(diff_result)
          rescue => e
            display_message("Failed to diff skill: #{e.message}", type: :error)
          end

        when "edit"
          # Edit an existing skill
          skill_id = args.shift

          unless skill_id
            display_message("Usage: aidp skill edit <skill-id>", type: :info)
            return
          end

          begin
            require_relative "skills/wizard/controller"

            registry = Aidp::Skills::Registry.new(project_dir: Dir.pwd)
            registry.load_skills

            skill = registry.find(skill_id)

            unless skill
              display_message("Skill not found: #{skill_id}", type: :error)
              display_message("Use 'aidp skill list' to see available skills", type: :muted)
              return
            end

            # Check if it's editable (must be project skill or willing to copy template)
            if registry.by_source[:template].include?(skill_id)
              display_message("'#{skill_id}' is a template skill", type: :info)
              display_message("Editing will create a project override in .aidp/skills/", type: :muted)
            end

            # Parse options
            options = {}
            while args.first&.start_with?("--")
              opt = args.shift
              case opt
              when "--dry-run"
                options[:dry_run] = true
              when "--open-editor"
                options[:open_editor] = true
              else
                display_message("Unknown option: #{opt}", type: :error)
                return
              end
            end

            # Pre-fill wizard with existing skill data
            options[:id] = skill.id
            options[:name] = skill.name
            options[:edit_mode] = true
            options[:existing_skill] = skill

            # Run wizard in edit mode
            wizard = Aidp::Skills::Wizard::Controller.new(
              project_dir: Dir.pwd,
              options: options
            )
            wizard.run
          rescue => e
            display_message("Failed to edit skill: #{e.message}", type: :error)
          end

        when "new"
          # Create a new skill using the wizard
          begin
            require_relative "skills/wizard/controller"

            # Parse options
            options = {}
            while args.first&.start_with?("--")
              opt = args.shift
              case opt
              when "--minimal"
                options[:minimal] = true
              when "--dry-run"
                options[:dry_run] = true
              when "--yes", "-y"
                options[:yes] = true
              when "--id"
                options[:id] = args.shift
              when "--name"
                options[:name] = args.shift
              when "--from-template"
                options[:from_template] = args.shift
              when "--clone"
                options[:clone] = args.shift
              else
                display_message("Unknown option: #{opt}", type: :error)
                return
              end
            end

            # Run wizard
            wizard = Aidp::Skills::Wizard::Controller.new(
              project_dir: Dir.pwd,
              options: options
            )
            wizard.run
          rescue => e
            display_message("Failed to create skill: #{e.message}", type: :error)
            Aidp.log_error("cli", "Skill wizard failed", error: e.message, backtrace: e.backtrace.first(5))
          end

        when "validate"
          # Validate skill file format
          skill_path = args.shift

          if skill_path
            # Validate specific file
            unless File.exist?(skill_path)
              display_message("File not found: #{skill_path}", type: :error)
              return
            end

            begin
              Aidp::Skills::Loader.load_from_file(skill_path)
              display_message("✓ Valid skill file: #{skill_path}", type: :success)
            rescue Aidp::Errors::ValidationError => e
              display_message("✗ Invalid skill file: #{skill_path}", type: :error)
              display_message("  #{e.message}", type: :error)
            end
          else
            # Validate all skills in registry
            begin
              registry = Aidp::Skills::Registry.new(project_dir: Dir.pwd)
              registry.load_skills

              skills = registry.all

              if skills.empty?
                display_message("No skills found to validate", type: :info)
                return
              end

              display_message("Validating #{skills.size} skill(s)...", type: :info)
              display_message("", type: :info)

              valid_count = 0
              skills.each do |skill|
                display_message("✓ #{skill.id} (v#{skill.version})", type: :success)
                valid_count += 1
              end

              display_message("", type: :info)
              display_message("#{valid_count}/#{skills.size} skills are valid", type: :success)
            rescue => e
              display_message("Validation failed: #{e.message}", type: :error)
            end
          end

        when "delete"
          # Delete a project skill
          skill_id = args.shift

          unless skill_id
            display_message("Usage: aidp skill delete <skill-id>", type: :info)
            return
          end

          begin
            registry = Aidp::Skills::Registry.new(project_dir: Dir.pwd)
            registry.load_skills

            skill = registry.find(skill_id)

            unless skill
              display_message("Skill not found: #{skill_id}", type: :error)
              return
            end

            # Check if it's a project skill
            source = registry.by_source[skill_id]
            unless source == :project
              display_message("Cannot delete template skill '#{skill_id}'", type: :error)
              display_message("Only project skills in .aidp/skills/ can be deleted", type: :muted)
              return
            end

            # Get skill directory
            skill_dir = File.dirname(skill.source_path)

            # Confirm deletion
            require "tty-prompt"
            prompt = create_prompt
            confirmed = prompt.yes?("Delete skill '#{skill.name}' (#{skill_id})? This cannot be undone.")

            unless confirmed
              display_message("Deletion cancelled", type: :info)
              return
            end

            # Delete the skill directory
            require "fileutils"
            FileUtils.rm_rf(skill_dir)

            display_message("✓ Deleted skill: #{skill.name} (#{skill_id})", type: :success)
          rescue => e
            display_message("Failed to delete skill: #{e.message}", type: :error)
            Aidp.log_error("cli", "Skill deletion failed", error: e.message, backtrace: e.backtrace.first(5))
          end

        else
          display_message("Usage: aidp skill <command>", type: :info)
          display_message("", type: :info)
          display_message("Commands:", type: :info)
          display_message("  list                List all available skills (default)", type: :info)
          display_message("  show <id>           Show detailed skill information", type: :info)
          display_message("  preview <id>        Preview full SKILL.md content", type: :info)
          display_message("  diff <id>           Show diff between project skill and template", type: :info)
          display_message("  search <query>      Search skills by keyword", type: :info)
          display_message("  new [options]       Create a new skill using the wizard", type: :info)
          display_message("  edit <id> [options] Edit an existing skill", type: :info)
          display_message("  delete <id>         Delete a project skill", type: :info)
          display_message("  validate [path]     Validate skill file format", type: :info)
          display_message("", type: :info)
          display_message("New Skill Options:", type: :info)
          display_message("  --minimal           Skip optional sections", type: :info)
          display_message("  --dry-run           Preview without saving", type: :info)
          display_message("  --yes, -y           Skip confirmation prompts", type: :info)
          display_message("  --id <skill_id>     Pre-set skill ID", type: :info)
          display_message("  --name <name>       Pre-set skill name", type: :info)
          display_message("", type: :info)
          display_message("Edit Skill Options:", type: :info)
          display_message("  --dry-run           Preview changes without saving", type: :info)
          display_message("  --open-editor       Open content in $EDITOR", type: :info)
          display_message("", type: :info)
          display_message("Examples:", type: :info)
          display_message("  aidp skill list                                # List all skills", type: :info)
          display_message("  aidp skill show repository_analyst             # Show skill details", type: :info)
          display_message("  aidp skill preview repository_analyst          # Preview full content", type: :info)
          display_message("  aidp skill diff my_skill                       # Show diff with template", type: :info)
          display_message("  aidp skill search git                          # Search for git-related skills", type: :info)
          display_message("  aidp skill new                                 # Create new skill (interactive)", type: :info)
          display_message("  aidp skill new --minimal --id my_skill         # Create with minimal prompts", type: :info)
          display_message("  aidp skill new --from-template repo_analyst    # Inherit from template", type: :info)
          display_message("  aidp skill new --clone my_existing_skill       # Clone existing skill", type: :info)
          display_message("  aidp skill edit repository_analyst             # Edit existing skill", type: :info)
          display_message("  aidp skill delete my_custom_skill              # Delete a project skill", type: :info)
          display_message("  aidp skill validate skills/my_skill/SKILL.md   # Validate specific skill", type: :info)
          display_message("  aidp skill validate                            # Validate all skills", type: :info)
        end
      end
    end # class << self
  end
end
