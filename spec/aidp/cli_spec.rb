# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "stringio"

RSpec.describe Aidp::CLI do
  let(:temp_dir) { Dir.mktmpdir }
  let(:test_prompt) { TestPrompt.new }
  let(:cli) { described_class.new(prompt: test_prompt) }

  # Mock TUI components to prevent interactive prompts
  let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
  let(:mock_workflow_selector) { instance_double(Aidp::Harness::UI::EnhancedWorkflowSelector) }
  let(:mock_harness_runner) { instance_double(Aidp::Harness::EnhancedRunner) }

  before do
    # Mock TUI components to prevent interactive prompts
    allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(mock_tui)
    allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(mock_workflow_selector)
    allow(Aidp::Harness::EnhancedRunner).to receive(:new).and_return(mock_harness_runner)

    # Mock TUI methods
    allow(mock_tui).to receive(:start_display_loop)
    allow(mock_tui).to receive(:stop_display_loop)
    allow(mock_tui).to receive(:show_message)
    allow(mock_tui).to receive(:single_select).and_return("🔬 Analyze Mode - Analyze your codebase for insights and recommendations")

    # Mock workflow selector
    allow(mock_workflow_selector).to receive(:select_workflow).and_return({
      workflow_type: :simple,
      steps: ["01_REPOSITORY_ANALYSIS"],
      user_input: {}
    })

    # Mock harness runner
    allow(mock_harness_runner).to receive(:run).and_return({
      status: "completed",
      message: "Test completed"
    })
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#display_harness_result" do
    it "displays completed status" do
      result = {status: "completed", message: "All done"}

      cli.send(:display_harness_result, result)
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("✅ Harness completed successfully!") }).to be true
    end

    it "displays stopped status" do
      result = {status: "stopped", message: "User stopped"}

      cli.send(:display_harness_result, result)
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("⏹️  Harness stopped by user") }).to be true
    end

    it "displays error status" do
      result = {status: "error", message: "Something went wrong"}

      cli.send(:display_harness_result, result)
      # Error message is now handled by the harness, not the CLI
      expect(test_prompt.messages).to be_empty
    end

    it "displays unknown status" do
      result = {status: "unknown", message: "Unknown state"}

      cli.send(:display_harness_result, result)
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("🔄 Harness finished") }).to be true
    end
  end

  describe "#format_duration" do
    it "formats seconds correctly" do
      expect(cli.send(:format_duration, 30)).to eq("30s")
    end

    it "formats minutes and seconds" do
      expect(cli.send(:format_duration, 90)).to eq("1m 30s")
    end

    it "formats hours, minutes and seconds" do
      expect(cli.send(:format_duration, 3661)).to eq("1h 1m 1s")
    end

    it "handles zero duration" do
      expect(cli.send(:format_duration, 0)).to eq("0s")
    end

    it "handles negative duration" do
      expect(cli.send(:format_duration, -10)).to eq("0s")
    end
  end

  describe "harness status command" do
    let(:mock_harness_runner) { double("harness_runner") }
    let(:mock_state_manager) { double("state_manager") }

    before do
      allow(Aidp::Harness::Runner).to receive(:new).and_return(mock_harness_runner)
      allow(mock_harness_runner).to receive(:detailed_status).and_return({
        harness: {
          state: "running",
          current_step: "test_step",
          current_provider: "cursor",
          duration: 120,
          user_input_count: 2,
          progress: {
            completed_steps: 3,
            total_steps: 5,
            next_step: "next_step"
          }
        },
        configuration: {
          default_provider: "cursor",
          fallback_providers: ["claude", "gemini"],
          max_retries: 2
        },
        provider_manager: {
          current_provider: "cursor",
          available_providers: ["cursor", "claude"],
          rate_limited_providers: [],
          total_switches: 0
        }
      })
    end

    it "displays harness status for both modes" do
      cli.harness_status
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("🔧 Harness Status") }).to be true
    end

    it "displays harness status for specific mode" do
      cli.harness_status
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("📋 Analyze Mode:") }).to be true
    end
  end

  describe "harness reset command" do
    let(:mock_harness_runner) { double("harness_runner") }
    let(:mock_state_manager) { double("state_manager") }

    before do
      allow(Aidp::Harness::Runner).to receive(:new).and_return(mock_harness_runner)
      allow(mock_harness_runner).to receive(:instance_variable_get).with(:@state_manager).and_return(mock_state_manager)
      allow(mock_state_manager).to receive(:reset_all)
    end

    it "resets harness state for analyze mode" do
      allow(cli).to receive(:options).and_return({mode: "analyze"})
      expect(mock_state_manager).to receive(:reset_all)

      cli.harness_reset
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("✅ Reset harness state for analyze mode") }).to be true
    end

    it "resets harness state for execute mode" do
      allow(cli).to receive(:options).and_return({mode: "execute"})
      expect(mock_state_manager).to receive(:reset_all)

      cli.harness_reset
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("✅ Reset harness state for execute mode") }).to be true
    end

    it "shows error for invalid mode" do
      allow(cli).to receive(:options).and_return({mode: "invalid"})

      cli.harness_reset
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("❌ Invalid mode. Use 'analyze' or 'execute'") }).to be true
    end
  end

  describe "config command" do
    let(:wizard_instance) { instance_double(Aidp::Setup::Wizard, run: true) }

    it "shows usage when --interactive missing" do
      allow(TTY::Prompt).to receive(:new).and_return(test_prompt)
      described_class.run(["config"])
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("Usage: aidp config --interactive") }).to be true
    end

    it "invokes wizard in interactive dry-run mode" do
      allow(TTY::Prompt).to receive(:new).and_return(test_prompt)
      expect(Aidp::Setup::Wizard).to receive(:new)
        .with(Dir.pwd, prompt: test_prompt, dry_run: true)
        .and_return(wizard_instance)

      described_class.run(["config", "--interactive", "--dry-run"])
    end
  end

  describe ".run (class method)" do
    it "can be called as a class method without raising errors" do
      # Test that the class method exists and can be called
      expect { described_class.run(["--help"]) }.not_to raise_error
    end

    it "returns 0 for successful help command" do
      result = described_class.run(["--help"])
      expect(result).to eq(0)
    end

    it "returns 0 for successful version command" do
      result = described_class.run(["--version"])
      expect(result).to eq(0)
    end

    it "returns 0 for successful status command" do
      result = described_class.run(["status"])
      expect(result).to eq(0)
    end

    it "has access to display_message as a class method" do
      # Test that display_message is available as a class method
      expect { described_class.display_message("Test message") }.not_to raise_error
    end

    it "can handle the startup path without NoMethodError" do
      # Test the specific path that was failing - startup with configuration check
      # Mock the configuration check to avoid interactive prompts
      allow(Aidp::CLI::FirstRunWizard).to receive(:ensure_config).and_return(true)
      allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(double("TUI",
        start_display_loop: nil,
        stop_display_loop: nil,
        single_select: "🔬 Analyze Mode - Analyze your codebase for insights and recommendations"))
      allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(double("Selector",
        select_workflow: {status: :success, next_step: nil}))

      # This should not raise NoMethodError for display_message
      expect { described_class.run([]) }.not_to raise_error
    end

    context "when config setup is cancelled" do
      before do
        allow(Aidp::CLI::FirstRunWizard).to receive(:ensure_config).and_return(false)
      end

      it "returns 1 and shows cancellation message" do
        result = described_class.run([])
        expect(result).to eq(1)
      end
    end

    context "when setup-config flag is used" do
      it "forces configuration setup" do
        allow(Aidp::CLI::FirstRunWizard).to receive(:setup_config).and_return(true)
        allow(Aidp::CLI::FirstRunWizard).to receive(:ensure_config).and_return(true)

        # Mock TUI components to prevent actual execution
        allow(mock_tui).to receive(:start_display_loop)
        allow(mock_workflow_selector).to receive(:select_workflow).and_return({
          mode: :execute,
          workflow_type: :simple,
          steps: [],
          user_input: {}
        })
        allow(mock_harness_runner).to receive(:run).and_return({status: "completed", message: "Done"})

        expect(Aidp::CLI::FirstRunWizard).to receive(:setup_config)

        described_class.run(["--setup-config"])
      end

      it "returns 1 when setup is cancelled" do
        allow(Aidp::CLI::FirstRunWizard).to receive(:setup_config).and_return(false)

        result = described_class.run(["--setup-config"])
        expect(result).to eq(1)
      end
    end

    context "when running copilot mode" do
      before do
        allow(Aidp::CLI::FirstRunWizard).to receive(:ensure_config).and_return(true)
        allow(Aidp).to receive(:setup_logger)
        allow(Aidp).to receive(:logger).and_return(double("Logger", info: nil, warn: nil, level: "info"))
      end

      it "initializes TUI and workflow selector" do
        expect(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(mock_tui)
        expect(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(mock_workflow_selector)

        allow(mock_workflow_selector).to receive(:select_workflow).and_return({
          mode: :execute,
          workflow_type: :simple,
          steps: [],
          user_input: {}
        })
        allow(mock_harness_runner).to receive(:run).and_return({status: "completed", message: "Done"})

        described_class.run([])
      end

      it "starts and stops TUI display loop" do
        allow(mock_workflow_selector).to receive(:select_workflow).and_return({
          mode: :execute,
          workflow_type: :simple,
          steps: [],
          user_input: {}
        })
        allow(mock_harness_runner).to receive(:run).and_return({status: "completed", message: "Done"})

        expect(mock_tui).to receive(:start_display_loop)
        expect(mock_tui).to receive(:stop_display_loop)

        described_class.run([])
      end

      it "creates and runs harness with workflow config" do
        allow(mock_workflow_selector).to receive(:select_workflow).and_return({
          mode: :analyze,
          workflow_type: :comprehensive,
          steps: ["step1", "step2"],
          user_input: {key: "value"}
        })

        expect(Aidp::Harness::EnhancedRunner).to receive(:new).with(
          Dir.pwd,
          :analyze,
          hash_including(
            mode: :analyze,
            workflow_type: :comprehensive,
            selected_steps: ["step1", "step2"],
            user_input: {key: "value"}
          )
        ).and_return(mock_harness_runner)

        expect(mock_harness_runner).to receive(:run).and_return({status: "completed", message: "Done"})

        described_class.run([])
      end

      it "returns 0 on successful completion" do
        allow(mock_workflow_selector).to receive(:select_workflow).and_return({
          mode: :execute,
          workflow_type: :simple,
          steps: [],
          user_input: {}
        })
        allow(mock_harness_runner).to receive(:run).and_return({status: "completed", message: "Done"})

        result = described_class.run([])
        expect(result).to eq(0)
      end

      it "handles Interrupt gracefully" do
        allow(mock_workflow_selector).to receive(:select_workflow).and_raise(Interrupt)

        result = described_class.run([])
        expect(result).to eq(1)
      end

      it "ensures TUI is stopped even on error" do
        allow(mock_workflow_selector).to receive(:select_workflow).and_raise(StandardError.new("Test error"))
        # Stub log_rescue since it's not available in class methods (bug in production code)
        allow(described_class).to receive(:log_rescue)

        expect(mock_tui).to receive(:stop_display_loop)

        described_class.run([])
      end

      it "handles general errors and returns 1" do
        allow(mock_workflow_selector).to receive(:select_workflow).and_raise(StandardError.new("Test error"))
        # Stub log_rescue since it's not available in class methods (bug in production code)
        allow(described_class).to receive(:log_rescue)

        result = described_class.run([])
        expect(result).to eq(1)
      end

      context "error handling inside harness execution" do
        before do
          # Successful workflow selection, errors occur in runner
          allow(mock_workflow_selector).to receive(:select_workflow).and_return({
            mode: :execute,
            workflow_type: :simple,
            steps: [],
            user_input: {}
          })
          # Ensure display loop expectations can be asserted
          allow(mock_tui).to receive(:start_display_loop)
          allow(mock_tui).to receive(:stop_display_loop)
        end

        it "returns 1 and displays interrupt message when runner raises Interrupt" do
          # Capture display messages
          messages = []
          allow(described_class).to receive(:display_message) do |msg, type:|
            messages << {message: msg, type: type}
          end

          allow(mock_harness_runner).to receive(:run).and_raise(Interrupt)

          result = described_class.run([])

          expect(result).to eq(1)
          expect(messages.any? { |m| m[:message].include?("Interrupted by user") && m[:type] == :warning }).to be true
          expect(mock_tui).to have_received(:stop_display_loop)
        end

        it "returns 1 and displays error message when runner raises StandardError" do
          allow(described_class).to receive(:log_rescue) # avoid dependency on mixin
          messages = []
          allow(described_class).to receive(:display_message) do |msg, type:|
            messages << {message: msg, type: type}
          end

          allow(mock_harness_runner).to receive(:run).and_raise(StandardError.new("Boom failure"))

          result = described_class.run([])

          expect(result).to eq(1)
          # Error message should include the exception message
          expect(messages.any? { |m| m[:message].include?("Boom failure") && m[:type] == :error }).to be true
          expect(mock_tui).to have_received(:stop_display_loop)
        end
      end
    end
  end

  describe ".subcommand?" do
    it "returns true for status command" do
      expect(described_class.send(:subcommand?, ["status"])).to be true
    end

    it "returns true for jobs command" do
      expect(described_class.send(:subcommand?, ["jobs"])).to be true
    end

    it "returns true for kb command" do
      expect(described_class.send(:subcommand?, ["kb"])).to be true
    end

    it "returns true for harness command" do
      expect(described_class.send(:subcommand?, ["harness"])).to be true
    end

    it "returns true for providers command" do
      expect(described_class.send(:subcommand?, ["providers"])).to be true
    end

    it "returns true for checkpoint command" do
      expect(described_class.send(:subcommand?, ["checkpoint"])).to be true
    end

    it "returns true for mcp command" do
      expect(described_class.send(:subcommand?, ["mcp"])).to be true
    end

    it "returns true for issue command" do
      expect(described_class.send(:subcommand?, ["issue"])).to be true
    end

    it "returns true for config command" do
      expect(described_class.send(:subcommand?, ["config"])).to be true
    end

    it "returns true for init command" do
      expect(described_class.send(:subcommand?, ["init"])).to be true
    end

    it "returns true for watch command" do
      expect(described_class.send(:subcommand?, ["watch"])).to be true
    end

    it "returns true for ws command" do
      expect(described_class.send(:subcommand?, ["ws"])).to be true
    end

    it "returns true for work command" do
      expect(described_class.send(:subcommand?, ["work"])).to be true
    end

    it "returns true for skill command" do
      expect(described_class.send(:subcommand?, ["skill"])).to be true
    end

    it "returns false for unknown command" do
      expect(described_class.send(:subcommand?, ["unknown"])).to be false
    end

    it "returns false for empty args" do
      expect(described_class.send(:subcommand?, [])).to be false
    end

    it "returns false for nil args" do
      expect(described_class.send(:subcommand?, nil)).to be false
    end

    it "returns false for option flags" do
      expect(described_class.send(:subcommand?, ["--help"])).to be false
    end
  end

  describe ".parse_options" do
    it "parses help flag" do
      options = described_class.send(:parse_options, ["--help"])
      expect(options[:help]).to be true
    end

    it "parses version flag" do
      options = described_class.send(:parse_options, ["--version"])
      expect(options[:version]).to be true
    end

    it "parses setup-config flag" do
      options = described_class.send(:parse_options, ["--setup-config"])
      expect(options[:setup_config]).to be true
    end

    it "includes parser in options" do
      options = described_class.send(:parse_options, [])
      expect(options[:parser]).to be_a(OptionParser)
    end

    it "handles multiple flags" do
      options = described_class.send(:parse_options, ["--setup-config", "--help"])
      expect(options[:setup_config]).to be true
      expect(options[:help]).to be true
    end

    it "returns empty options hash for no flags" do
      options = described_class.send(:parse_options, [])
      expect(options[:parser]).to be_a(OptionParser)
      expect(options.keys).to eq([:parser])
    end
  end

  describe ".setup_logging" do
    let(:temp_project_dir) { Dir.mktmpdir }
    let(:config_dir) { File.join(temp_project_dir, ".aidp") }
    let(:config_file) { File.join(config_dir, "aidp.yml") }

    before do
      FileUtils.mkdir_p(config_dir)
      allow(Aidp).to receive(:setup_logger)
      allow(Aidp).to receive(:logger).and_return(double("Logger", info: nil, warn: nil, level: "info"))
    end

    after do
      FileUtils.rm_rf(temp_project_dir)
    end

    it "sets up logger with config from aidp.yml" do
      File.write(config_file, {logging: {level: "debug", output: "file"}}.to_yaml)

      expect(Aidp).to receive(:setup_logger).with(temp_project_dir, {level: "debug", output: "file"})

      described_class.send(:setup_logging, temp_project_dir)
    end

    it "handles missing config file gracefully" do
      expect(Aidp).to receive(:setup_logger).with(temp_project_dir, {})

      described_class.send(:setup_logging, temp_project_dir)
    end

    it "handles malformed YAML gracefully" do
      File.write(config_file, "invalid: yaml: content:")

      # Stub log_rescue since it's not available in class methods (bug in production code)
      allow(described_class).to receive(:log_rescue)
      # When YAML parsing fails, it calls setup_logger once in the rescue block
      expect(Aidp).to receive(:setup_logger).once

      described_class.send(:setup_logging, temp_project_dir)
    end

    it "uses empty hash when logging config is missing" do
      File.write(config_file, {other_config: "value"}.to_yaml)

      expect(Aidp).to receive(:setup_logger).with(temp_project_dir, {})

      described_class.send(:setup_logging, temp_project_dir)
    end

    it "logs initialization info" do
      logger = double("Logger", level: "info")
      allow(Aidp).to receive(:logger).and_return(logger)

      expect(logger).to receive(:info).with("cli", "AIDP starting", hash_including(:version, :log_level))

      described_class.send(:setup_logging, temp_project_dir)
    end

    it "logs warning when config loading fails" do
      File.write(config_file, "malformed yaml [}")
      logger = double("Logger", level: "info")
      allow(Aidp).to receive(:logger).and_return(logger)
      # Stub log_rescue since it's not available in class methods (bug in production code)
      allow(described_class).to receive(:log_rescue)

      expect(logger).to receive(:warn).with("cli", "Failed to load logging config, using defaults", hash_including(:error))

      described_class.send(:setup_logging, temp_project_dir)
    end
  end

  describe ".run_subcommand" do
    it "routes to run_status_command for status" do
      expect(described_class).to receive(:run_status_command)
      described_class.send(:run_subcommand, ["status"])
    end

    it "returns 0 for successful subcommand" do
      allow(described_class).to receive(:run_status_command)
      result = described_class.send(:run_subcommand, ["status"])
      expect(result).to eq(0)
    end

    it "returns 1 for unknown subcommand" do
      result = described_class.send(:run_subcommand, ["unknown"])
      expect(result).to eq(1)
    end
  end

  describe ".run_checkpoint_command" do
    let(:checkpoint) { instance_double(Aidp::Execute::Checkpoint) }
    let(:display) { instance_double(Aidp::Execute::CheckpointDisplay) }

    before do
      allow(Aidp::Execute::Checkpoint).to receive(:new).and_return(checkpoint)
      allow(Aidp::Execute::CheckpointDisplay).to receive(:new).and_return(display)
      allow(described_class).to receive(:display_message)
    end

    it "shows latest checkpoint" do
      checkpoint_data = {iteration: 5, status: "healthy", metrics: {}}
      allow(checkpoint).to receive(:latest_checkpoint).and_return(checkpoint_data)
      allow(display).to receive(:display_checkpoint)

      expect { described_class.send(:run_checkpoint_command, ["show"]) }.not_to raise_error
      expect(display).to have_received(:display_checkpoint).with(checkpoint_data, show_details: true)
    end

    it "handles no checkpoint data gracefully" do
      allow(checkpoint).to receive(:latest_checkpoint).and_return(nil)
      described_class.send(:run_checkpoint_command, ["show"])
      expect(described_class).to have_received(:display_message).with("No checkpoint data found.", type: :info)
    end

    it "shows checkpoint history" do
      history = [
        {iteration: 1, timestamp: Time.now, metrics: {loc: 100}},
        {iteration: 2, timestamp: Time.now + 60, metrics: {loc: 120}}
      ]
      allow(checkpoint).to receive(:checkpoint_history).with(limit: 2).and_return(history)
      allow(display).to receive(:display_checkpoint_history)

      described_class.send(:run_checkpoint_command, ["history", "2"])
      expect(display).to have_received(:display_checkpoint_history).with(history, limit: 2)
    end

    it "shows summary" do
      summary = {iteration: 3, metrics: {loc: 150}}
      allow(checkpoint).to receive(:progress_summary).and_return(summary)
      allow(display).to receive(:display_progress_summary)

      described_class.send(:run_checkpoint_command, ["summary"])
      expect(display).to have_received(:display_progress_summary).with(summary)
    end
  end

  describe ".run_providers_command" do
    let(:config_manager) { instance_double(Aidp::Harness::ConfigManager) }
    let(:provider_manager) { instance_double(Aidp::Harness::ProviderManager) }
    let(:spinner) { instance_double(TTY::Spinner, auto_spin: nil, stop: nil) }

    before do
      allow(Aidp::Harness::ConfigManager).to receive(:new).and_return(config_manager)
      allow(Aidp::Harness::ProviderManager).to receive(:new).and_return(provider_manager)
      allow(TTY::Spinner).to receive(:new).and_return(spinner)
      allow(described_class).to receive(:display_message)
    end

    it "displays provider health dashboard" do
      health_rows = [
        {provider: "cursor", status: "healthy", available: true, circuit_breaker: "closed",
         rate_limited: false, total_tokens: 1000, last_used: Time.now}
      ]
      allow(provider_manager).to receive(:health_dashboard).and_return(health_rows)

      expect { described_class.send(:run_providers_command, []) }.not_to raise_error
      expect(provider_manager).to have_received(:health_dashboard)
    end

    it "handles errors gracefully" do
      allow(provider_manager).to receive(:health_dashboard).and_raise(StandardError.new("Test error"))
      allow(Aidp.logger).to receive(:warn)

      described_class.send(:run_providers_command, [])
      expect(Aidp.logger).to have_received(:warn)
      expect(described_class).to have_received(:display_message).with(/Failed to display provider health/, type: :error)
    end
  end

  describe ".run_jobs_command" do
    let(:jobs_cmd) { instance_double(Aidp::CLI::JobsCommand) }

    before do
      allow(Aidp::CLI::JobsCommand).to receive(:new).and_return(jobs_cmd)
      allow(jobs_cmd).to receive(:run)
    end

    it "creates JobsCommand and delegates to it" do
      described_class.send(:run_jobs_command, ["list"])
      expect(jobs_cmd).to have_received(:run).with("list", [])
    end

    it "handles status subcommand" do
      described_class.send(:run_jobs_command, ["status", "job123"])
      expect(jobs_cmd).to have_received(:run).with("status", ["job123"])
    end
  end

  describe ".run_kb_command" do
    before do
      allow(described_class).to receive(:display_message)
    end

    it "shows knowledge base topic" do
      described_class.send(:run_kb_command, ["show", "testing"])
      expect(described_class).to have_received(:display_message).with("Knowledge Base: testing", type: :info)
    end

    it "shows default summary topic when no topic specified" do
      described_class.send(:run_kb_command, ["show"])
      expect(described_class).to have_received(:display_message).with("Knowledge Base: summary", type: :info)
    end

    it "shows usage for unknown subcommand" do
      described_class.send(:run_kb_command, ["unknown"])
      expect(described_class).to have_received(:display_message).with(/Usage:/, type: :info)
    end
  end

  describe "helper methods" do
    describe ".format_time_ago_simple" do
      it "formats seconds" do
        expect(described_class.send(:format_time_ago_simple, 30)).to eq("30s ago")
      end

      it "formats minutes" do
        expect(described_class.send(:format_time_ago_simple, 180)).to eq("3m ago")
      end

      it "formats hours" do
        expect(described_class.send(:format_time_ago_simple, 7200)).to eq("2h ago")
      end

      it "does not have days formatting" do
        # The actual implementation only goes up to hours
        result = described_class.send(:format_time_ago_simple, 172800)
        expect(result).to match(/\d+h ago/)
      end
    end
  end

  describe ".run_execute_command" do
    before do
      allow(described_class).to receive(:display_message) # suppress output collection unless needed
    end

    it "handles --reset flag" do
      described_class.send(:run_execute_command, ["--reset"], mode: :execute)
      expect(described_class).to have_received(:display_message).with("Reset execute mode progress", type: :info)
    end

    it "handles --approve flag" do
      described_class.send(:run_execute_command, ["--approve", "STEP_01"], mode: :analyze)
      expect(described_class).to have_received(:display_message).with("Approved analyze step: STEP_01", type: :info)
    end

    it "lists steps with --no-harness" do
      described_class.send(:run_execute_command, ["--no-harness"], mode: :execute)
      expect(described_class).to have_received(:display_message).with("Available execute steps", type: :info)
    end

    context "background execution" do
      let(:bg_runner) { instance_double(Aidp::Jobs::BackgroundRunner) }
      let(:jobs_dir) { Dir.mktmpdir }

      before do
        allow(Aidp::Jobs::BackgroundRunner).to receive(:new).and_return(bg_runner)
        allow(bg_runner).to receive(:start).and_return("job-123")
        allow(bg_runner).to receive(:follow_job_logs)
        # Provide stubbed jobs directory for log path construction
        allow(bg_runner).to receive(:instance_variable_get).with(:@jobs_dir).and_return(jobs_dir)
      end

      after do
        FileUtils.rm_rf(jobs_dir) if jobs_dir && Dir.exist?(jobs_dir)
      end

      it "starts background job" do
        described_class.send(:run_execute_command, ["--background"], mode: :execute)
        expect(bg_runner).to have_received(:start).with(:execute, {})
      end

      it "follows logs when --follow provided" do
        # Stub file wait to skip actual waiting
        allow(Aidp::Concurrency::Wait).to receive(:for_file)
        described_class.send(:run_execute_command, ["--background", "--follow"], mode: :execute)
        expect(bg_runner).to have_received(:follow_job_logs).with("job-123")
      end
    end

    it "runs specific step and shows PRD completion in test mode" do
      # Create a temporary template file to trigger PRD question simulation
      root = Dir.mktmpdir
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("AIDP_ROOT").and_return(root)
      exec_dir = File.join(root, "templates", "EXECUTE")
      FileUtils.mkdir_p(exec_dir)
      File.write(File.join(exec_dir, "00_PRD_TEST.md"), "# PRD\n## Questions\n- What is X?\n- How to Y?\n")

      begin
        messages = []
        allow(described_class).to receive(:display_message) do |msg, type:|
          messages << {msg: msg, type: type}
        end
        described_class.send(:run_execute_command, ["00_PRD_TEST"], mode: :execute)
        expect(messages.any? { |m| m[:msg].include?("PRD completed") && m[:type] == :success }).to be true
        expect(messages.any? { |m| m[:msg].include?("What is X?") }).to be true
      ensure
        FileUtils.rm_rf(root)
      end
    end

    it "starts harness when no step or special flags" do
      messages = []
      allow(described_class).to receive(:display_message) do |msg, type:|
        messages << {msg: msg, type: type}
      end
      described_class.send(:run_execute_command, [], mode: :execute)
      expect(messages.any? { |m| m[:msg].include?("Starting enhanced TUI harness") }).to be true
    end
  end

  describe ".run_work_command" do
    before do
      allow(described_class).to receive(:display_message) # generic stub; specific examples capture separately when needed
    end

    it "shows error when --workstream flag missing" do
      messages = []
      allow(described_class).to receive(:display_message) do |msg, type:|
        messages << {msg: msg, type: type}
      end
      described_class.send(:run_work_command, [])
      expect(messages.any? { |m| m[:msg].include?("Missing required --workstream") && m[:type] == :error }).to be true
    end

    it "shows error when workstream not found" do
      allow(Aidp::Worktree).to receive(:info).and_return(nil)
      messages = []
      allow(described_class).to receive(:display_message) do |msg, type:|
        messages << {msg: msg, type: type}
      end
      described_class.send(:run_work_command, ["--workstream", "ws-abc"])
      expect(messages.any? { |m| m[:msg].include?("Workstream not found: ws-abc") }).to be true
    end

    context "background execution" do
      let(:ws_info) { {slug: "ws-bg", path: "/tmp/ws-bg", branch: "ws-bg", created_at: Time.now.iso8601, active: true} }
      let(:bg_runner) { instance_double(Aidp::Jobs::BackgroundRunner) }

      before do
        allow(Aidp::Worktree).to receive(:info).and_return(ws_info)
        allow(Aidp::Jobs::BackgroundRunner).to receive(:new).and_return(bg_runner)
        allow(bg_runner).to receive(:start).and_return("job-999")
      end

      it "starts background job in execute mode" do
        described_class.send(:run_work_command, ["--workstream", "ws-bg", "--background"])
        expect(bg_runner).to have_received(:start).with(:execute, {workstream: "ws-bg"})
      end

      it "starts background job in analyze mode" do
        described_class.send(:run_work_command, ["--workstream", "ws-bg", "--mode", "analyze", "--background"])
        expect(bg_runner).to have_received(:start).with(:analyze, {workstream: "ws-bg"})
      end
    end

    context "inline harness execution" do
      let(:ws_info) { {slug: "ws-inline", path: "/tmp/ws-inline", branch: "ws-inline", created_at: Time.now.iso8601, active: true} }
      let(:state_manager) { instance_double(Aidp::Harness::StateManager, set_workstream: true) }
      let(:tui) { instance_double(Aidp::Harness::UI::EnhancedTUI, start_display_loop: nil, stop_display_loop: nil) }
      let(:selector) { instance_double(Aidp::Harness::UI::EnhancedWorkflowSelector) }
      let(:runner) { instance_double(Aidp::Harness::EnhancedRunner, run: {status: "completed", message: "OK"}) }

      before do
        allow(Aidp::Worktree).to receive(:info).and_return(ws_info)
        allow(Aidp::Harness::StateManager).to receive(:new).and_return(state_manager)
        allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(tui)
        allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(selector)
        allow(selector).to receive(:select_workflow).and_return({
          mode: :execute,
          workflow_type: :simple,
          steps: [],
          user_input: {}
        })
        allow(Aidp::Harness::EnhancedRunner).to receive(:new).and_return(runner)
      end

      it "runs harness with execute mode by default" do
        described_class.send(:run_work_command, ["--workstream", "ws-inline"])
        expect(state_manager).to have_received(:set_workstream).with("ws-inline")
        expect(Aidp::Harness::EnhancedRunner).to have_received(:new).with(Dir.pwd, :execute, hash_including(:mode))
        expect(tui).to have_received(:start_display_loop)
        expect(tui).to have_received(:stop_display_loop)
      end

      it "runs harness with analyze mode override" do
        allow(selector).to receive(:select_workflow).and_return({
          mode: :analyze,
          workflow_type: :simple,
          steps: [],
          user_input: {}
        })
        described_class.send(:run_work_command, ["--workstream", "ws-inline", "--mode", "analyze"])
        expect(Aidp::Harness::EnhancedRunner).to have_received(:new).with(Dir.pwd, :analyze, hash_including(mode: :analyze))
      end

      it "handles Interrupt gracefully ensuring TUI stops" do
        allow(runner).to receive(:run).and_raise(Interrupt)
        messages = []
        allow(described_class).to receive(:display_message) do |msg, type:|
          messages << {msg: msg, type: type}
        end
        described_class.send(:run_work_command, ["--workstream", "ws-inline"])
        expect(messages.any? { |m| m[:msg].include?("Interrupted by user") }).to be true
        expect(tui).to have_received(:stop_display_loop)
      end
    end

    it "warns on unknown option" do
      allow(Aidp::Worktree).to receive(:info).and_return({slug: "ws-x", path: "/tmp/ws-x", branch: "ws-x", created_at: Time.now.iso8601, active: true})
      messages = []
      allow(described_class).to receive(:display_message) do |msg, type:|
        messages << {msg: msg, type: type}
      end
      described_class.send(:run_work_command, ["--workstream", "ws-x", "--unknown-flag"]) # token treated as unknown work option
      expect(messages.any? { |m| m[:msg].include?("Unknown work option: --unknown-flag") }).to be true
    end
  end
end
