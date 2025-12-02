# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "stringio"
require "time"
require "aidp/cli"
require "aidp/harness/provider_info"
require "aidp/worktree"
require "tty-prompt"
require "tty-table"

RSpec.describe Aidp::CLI do
  let(:temp_dir) { Dir.mktmpdir }
  let(:test_prompt) { TestPrompt.new }
  let(:cli) { described_class.new(prompt: test_prompt) }

  after do
    FileUtils.rm_rf(temp_dir)
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

    describe "logging setup" do
      let(:test_project_dir) { temp_dir }

      before do
        # Change to temp directory for tests
        @original_pwd = Dir.pwd
        Dir.chdir(test_project_dir)
        FileUtils.mkdir_p(File.join(test_project_dir, ".aidp"))

        # Stub all the TUI components to avoid interactive flow
        allow(Aidp::CLI::FirstRunWizard).to receive(:ensure_config).and_return(true)

        tui_double = double("EnhancedTUI", restore_screen: nil)
        allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(tui_double)

        workflow_selector_double = double("EnhancedWorkflowSelector")
        allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(workflow_selector_double)
        allow(workflow_selector_double).to receive(:select_workflow).and_return({mode: :execute, steps: []})

        runner_double = double("EnhancedRunner", run: {status: "completed"})
        allow(Aidp::Harness::EnhancedRunner).to receive(:new).and_return(runner_double)
      end

      after do
        Dir.chdir(@original_pwd)
      end

      it "sets up logging from aidp.yml config when file exists" do
        config_path = File.join(test_project_dir, ".aidp", "aidp.yml")
        File.write(config_path, {"logging" => {"level" => "debug"}}.to_yaml)

        expect(Aidp).to receive(:setup_logger).with(test_project_dir, {"level" => "debug"})
        allow(Aidp.logger).to receive(:info)

        # Pass empty args (no subcommand) to trigger main flow
        described_class.run([])
      end

      it "handles missing aidp.yml gracefully" do
        # No config file exists
        expect(Aidp).to receive(:setup_logger).with(test_project_dir, {})
        allow(Aidp.logger).to receive(:info)

        described_class.run([])
      end

      it "handles logging setup errors and falls back to default config" do
        config_path = File.join(test_project_dir, ".aidp", "aidp.yml")
        File.write(config_path, "invalid: yaml: content:")

        # YAML parse error happens before setup_logger is called
        # So it only gets called once in the rescue block with empty config
        expect(Aidp).to receive(:setup_logger).once.with(test_project_dir, {})
        allow(Aidp.logger).to receive(:warn)
        allow(described_class).to receive(:log_rescue)

        described_class.run([])
      end
    end

    describe "--setup-config flag" do
      let(:test_project_dir) { temp_dir }

      before do
        @original_pwd = Dir.pwd
        Dir.chdir(test_project_dir)
        FileUtils.mkdir_p(File.join(test_project_dir, ".aidp"))

        # Stub dependencies to avoid interactive flow
        allow(Aidp).to receive(:setup_logger)
        allow(Aidp.logger).to receive(:info)
        allow(Aidp.logger).to receive(:warn)
      end

      after do
        Dir.chdir(@original_pwd)
      end

      it "runs first run wizard when --setup-config flag is provided" do
        # Stub wizard to return success
        allow(Aidp::CLI::FirstRunWizard).to receive(:setup_config).and_return(true)

        # Stub TUI components to avoid hanging
        tui_double = double("EnhancedTUI", restore_screen: nil)
        allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(tui_double)

        workflow_selector_double = double("EnhancedWorkflowSelector")
        allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(workflow_selector_double)
        allow(workflow_selector_double).to receive(:select_workflow).and_return({mode: :execute, steps: []})

        runner_double = double("EnhancedRunner", run: {status: "completed"})
        allow(Aidp::Harness::EnhancedRunner).to receive(:new).and_return(runner_double)

        expect(Aidp::CLI::FirstRunWizard).to receive(:setup_config)

        described_class.run(["--setup-config"])
      end

      it "returns 1 when setup wizard is cancelled" do
        # Stub wizard to return false (cancelled)
        allow(Aidp::CLI::FirstRunWizard).to receive(:setup_config).and_return(false)

        result = described_class.run(["--setup-config"])

        expect(result).to eq(1)
      end

      it "ensures config exists before starting TUI when flag not provided" do
        # Stub ensure_config to return success
        allow(Aidp::CLI::FirstRunWizard).to receive(:ensure_config).and_return(true)

        # Stub TUI components
        tui_double = double("EnhancedTUI", restore_screen: nil)
        allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(tui_double)

        workflow_selector_double = double("EnhancedWorkflowSelector")
        allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(workflow_selector_double)
        allow(workflow_selector_double).to receive(:select_workflow).and_return({mode: :execute, steps: []})

        runner_double = double("EnhancedRunner", run: {status: "completed"})
        allow(Aidp::Harness::EnhancedRunner).to receive(:new).and_return(runner_double)

        expect(Aidp::CLI::FirstRunWizard).to receive(:ensure_config)

        described_class.run([])
      end

      it "returns 1 when ensure_config fails" do
        # Stub ensure_config to return false
        allow(Aidp::CLI::FirstRunWizard).to receive(:ensure_config).and_return(false)

        result = described_class.run([])

        expect(result).to eq(1)
      end
    end

    describe "error handling" do
      let(:test_project_dir) { temp_dir }

      before do
        @original_pwd = Dir.pwd
        Dir.chdir(test_project_dir)
        FileUtils.mkdir_p(File.join(test_project_dir, ".aidp"))

        # Stub dependencies
        allow(Aidp).to receive(:setup_logger)
        allow(Aidp.logger).to receive(:info)
        allow(Aidp.logger).to receive(:warn)
        allow(Aidp::CLI::FirstRunWizard).to receive(:ensure_config).and_return(true)
      end

      after do
        Dir.chdir(@original_pwd)
      end

      it "handles Interrupt (Ctrl+C) and returns 1" do
        tui_double = double("EnhancedTUI", restore_screen: nil)
        allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(tui_double)

        workflow_selector_double = double("EnhancedWorkflowSelector")
        allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(workflow_selector_double)
        allow(workflow_selector_double).to receive(:select_workflow).and_raise(Interrupt)

        result = described_class.run([])

        expect(result).to eq(1)
      end

      it "handles general errors and returns 1" do
        tui_double = double("EnhancedTUI", restore_screen: nil)
        allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(tui_double)

        workflow_selector_double = double("EnhancedWorkflowSelector")
        allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(workflow_selector_double)
        allow(workflow_selector_double).to receive(:select_workflow).and_raise(StandardError.new("test error"))

        # Stub log_rescue to avoid actual logging
        allow(described_class).to receive(:log_rescue)

        result = described_class.run([])

        expect(result).to eq(1)
      end

      it "restores screen in ensure block even when error occurs" do
        tui_double = double("EnhancedTUI", restore_screen: nil)
        allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(tui_double)

        workflow_selector_double = double("EnhancedWorkflowSelector")
        allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(workflow_selector_double)
        allow(workflow_selector_double).to receive(:select_workflow).and_raise(StandardError.new("test error"))

        allow(described_class).to receive(:log_rescue)

        expect(tui_double).to receive(:restore_screen)

        described_class.run([])
      end
    end

    describe "--launch-test flag (interactive mode)" do
      let(:test_project_dir) { temp_dir }

      before do
        @original_pwd = Dir.pwd
        Dir.chdir(test_project_dir)
        FileUtils.mkdir_p(File.join(test_project_dir, ".aidp"))

        # Stub dependencies
        allow(Aidp).to receive(:setup_logger)
        allow(Aidp).to receive(:log_debug)
        allow(Aidp).to receive(:log_info)
        allow(Aidp.logger).to receive(:info)
        allow(Aidp.logger).to receive(:warn)
      end

      after do
        Dir.chdir(@original_pwd)
      end

      it "returns 0 when launch test succeeds" do
        tui_double = double("EnhancedTUI", restore_screen: nil)
        allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(tui_double)

        workflow_selector_double = double("EnhancedWorkflowSelector")
        allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(workflow_selector_double)

        config_manager_double = double("ConfigManager", config: {})
        allow(Aidp::Harness::ConfigManager).to receive(:new).and_return(config_manager_double)

        result = described_class.run(["--launch-test"])

        expect(result).to eq(0)
      end

      it "initializes TUI components during launch test" do
        tui_double = double("EnhancedTUI", restore_screen: nil)
        expect(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(tui_double)

        workflow_selector_double = double("EnhancedWorkflowSelector")
        expect(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(workflow_selector_double)

        config_manager_double = double("ConfigManager", config: {})
        expect(Aidp::Harness::ConfigManager).to receive(:new).and_return(config_manager_double)

        described_class.run(["--launch-test"])
      end

      it "restores screen after launch test" do
        tui_double = double("EnhancedTUI")
        allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(tui_double)
        expect(tui_double).to receive(:restore_screen)

        workflow_selector_double = double("EnhancedWorkflowSelector")
        allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(workflow_selector_double)

        config_manager_double = double("ConfigManager", config: {})
        allow(Aidp::Harness::ConfigManager).to receive(:new).and_return(config_manager_double)

        described_class.run(["--launch-test"])
      end

      it "returns 1 and logs error when launch test fails" do
        allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_raise(StandardError.new("TUI initialization failed"))
        allow(described_class).to receive(:log_rescue)

        result = described_class.run(["--launch-test"])

        expect(result).to eq(1)
      end

      it "does not start interactive workflow during launch test" do
        tui_double = double("EnhancedTUI", restore_screen: nil)
        allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(tui_double)

        workflow_selector_double = double("EnhancedWorkflowSelector")
        allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(workflow_selector_double)
        # Should NOT be called during launch test
        expect(workflow_selector_double).not_to receive(:select_workflow)

        config_manager_double = double("ConfigManager", config: {})
        allow(Aidp::Harness::ConfigManager).to receive(:new).and_return(config_manager_double)

        described_class.run(["--launch-test"])
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

    it "parses launch-test flag (undocumented)" do
      options = described_class.send(:parse_options, ["--launch-test"])
      expect(options[:launch_test]).to be true
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

    it "raises OptionParser::InvalidOption for unknown flag" do
      expect {
        described_class.send(:parse_options, ["--bogus-flag"])
      }.to raise_error(OptionParser::InvalidOption)
    end

    it "raises on mixed valid and invalid flags and does not set partial options" do
      expect {
        described_class.send(:parse_options, ["--help", "--unknown123"])
      }.to raise_error(OptionParser::InvalidOption)
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

    it "routes to run_jobs_command for jobs" do
      expect(described_class).to receive(:run_jobs_command).with(["list"])
      described_class.send(:run_subcommand, ["jobs", "list"])
    end

    it "routes to run_kb_command for kb" do
      expect(described_class).to receive(:run_kb_command).with(["show", "topic"])
      described_class.send(:run_subcommand, ["kb", "show", "topic"])
    end

    it "routes to run_harness_command for harness" do
      expect(described_class).to receive(:run_harness_command).with(["status"])
      described_class.send(:run_subcommand, ["harness", "status"])
    end

    it "routes to run_providers_command for providers" do
      expect(described_class).to receive(:run_providers_command).with(["info", "claude"])
      described_class.send(:run_subcommand, ["providers", "info", "claude"])
    end

    it "routes to run_checkpoint_command for checkpoint" do
      expect(described_class).to receive(:run_checkpoint_command).with(["summary"])
      described_class.send(:run_subcommand, ["checkpoint", "summary"])
    end

    it "routes to run_mcp_command for mcp" do
      expect(described_class).to receive(:run_mcp_command).with(["dashboard"])
      described_class.send(:run_subcommand, ["mcp", "dashboard"])
    end

    it "routes to run_issue_command for issue" do
      expect(described_class).to receive(:run_issue_command).with(["import", "123"])
      described_class.send(:run_subcommand, ["issue", "import", "123"])
    end

    it "routes to run_config_command for config" do
      expect(described_class).to receive(:run_config_command).with(["--interactive"])
      described_class.send(:run_subcommand, ["config", "--interactive"])
    end

    it "routes to run_init_command for init" do
      expect(described_class).to receive(:run_init_command).with(["--dry-run"])
      described_class.send(:run_subcommand, ["init", "--dry-run"])
    end

    it "routes to run_watch_command for watch" do
      expect(described_class).to receive(:run_watch_command).with(["https://example.com/issues"])
      described_class.send(:run_subcommand, ["watch", "https://example.com/issues"])
    end

    it "routes to run_ws_command for ws" do
      expect(described_class).to receive(:run_ws_command).with(["list"])
      described_class.send(:run_subcommand, ["ws", "list"])
    end

    it "routes to run_work_command for work" do
      expect(described_class).to receive(:run_work_command).with(["--workstream", "slug"])
      described_class.send(:run_subcommand, ["work", "--workstream", "slug"])
    end

    it "routes to run_skill_command for skill" do
      expect(described_class).to receive(:run_skill_command).with(["list"])
      described_class.send(:run_subcommand, ["skill", "list"])
    end

    it "returns 0 for successful subcommand" do
      allow(described_class).to receive(:run_status_command)
      result = described_class.send(:run_subcommand, ["status"])
      expect(result).to eq(0)
    end

    it "displays message for unknown subcommand" do
      allow(described_class).to receive(:display_message)
      described_class.send(:run_subcommand, ["unknown"])
      expect(described_class).to have_received(:display_message).with("Unknown command: unknown", type: :info)
    end

    it "returns 1 for unknown subcommand" do
      result = described_class.send(:run_subcommand, ["unknown"])
      expect(result).to eq(1)
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

    it "runs specific step and announces execution without PRD simulation" do
      messages = []
      allow(described_class).to receive(:display_message) do |msg, type:|
        messages << {msg: msg, type: type}
      end
      described_class.send(:run_execute_command, ["00_PRD_TEST"], mode: :execute)
      expect(messages.any? { |m| m[:msg].include?("Running execute step '00_PRD_TEST' with enhanced TUI harness") }).to be true
      # Legacy test-only PRD completion + question emission removed; ensure not present
      expect(messages.any? { |m| m[:msg].include?("PRD completed") }).to be false
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

  describe ".run_init_command" do
    before do
      allow(described_class).to receive(:display_message)
    end

    it "shows usage for unknown option" do
      described_class.send(:run_init_command, ["--badopt"])
      expect(described_class).to have_received(:display_message).with(/Unknown init option/, type: :error)
    end

    it "displays init usage output" do
      messages = []
      allow(described_class).to receive(:display_message) do |msg, type:|
        messages << {msg: msg, type: type}
      end
      described_class.send(:display_init_usage)
      expect(messages.first[:msg]).to match(/Usage: aidp init/)
    end
  end

  describe ".run_watch_command" do
    before do
      allow(described_class).to receive(:display_message)
    end

    it "shows usage when no args" do
      described_class.send(:run_watch_command, [])
      expect(described_class).to have_received(:display_message).with(/Usage: aidp watch/, type: :info)
    end

    it "handles unknown option with warning message" do
      described_class.send(:run_watch_command, ["https://example.com/issues", "--weird"])
      expect(described_class).to have_received(:display_message).with(/Unknown watch option: --weird/, type: :warn)
    end
  end

  describe "issue import command" do
    before do
      allow(described_class).to receive(:display_message)
      require_relative "../../lib/aidp/cli/issue_importer"
    end

    it "shows usage when no args" do
      described_class.send(:run_issue_command, [])
      expect(described_class).to have_received(:display_message).with(/Usage: aidp issue <command>/, type: :info)
    end

    it "shows usage with help flag" do
      allow(described_class).to receive(:display_message)
      described_class.send(:run_issue_command, ["--help"])
      expect(described_class).to have_received(:display_message).with(/Usage: aidp issue <command>/, type: :info)
    end

    it "shows missing identifier error" do
      described_class.send(:run_issue_command, ["import"])
      expect(described_class).to have_received(:display_message).with(/Missing issue identifier/, type: :error)
    end

    it "shows unknown issue subcommand usage" do
      described_class.send(:run_issue_command, ["bogus"])
      expect(described_class).to have_received(:display_message).with(/Unknown issue command: bogus/, type: :error)
    end
  end

  describe "execute command edge precedence" do
    before { allow(described_class).to receive(:display_message) }

    it "prioritizes reset over approve when both provided" do
      described_class.send(:run_execute_command, ["--reset", "--approve", "STEP_02"], mode: :execute)
      expect(described_class).to have_received(:display_message).with(/Reset execute mode progress/, type: :info)
      expect(described_class).not_to have_received(:display_message).with(/Approved execute step:/, type: :info)
    end

    it "non PRD step does not show PRD completion" do
      messages = []
      allow(described_class).to receive(:display_message) { |m, type:| messages << {m: m, type: type} }
      described_class.send(:run_execute_command, ["01_OTHER_STEP"], mode: :execute)
      expect(messages.any? { |x| x[:m].include?("PRD completed") }).to be false
      expect(messages.any? { |x| x[:m].include?("Running execute step '01_OTHER_STEP'") }).to be true
    end

    it "analyze mode PRD step runs with generic step message only" do
      messages = []
      allow(described_class).to receive(:display_message) { |m, type:| messages << {m: m, type: type} }
      described_class.send(:run_execute_command, ["00_PRD_ANALYZE"], mode: :analyze)
      expect(messages.any? { |x| x[:m].include?("Running analyze step '00_PRD_ANALYZE' with enhanced TUI harness") }).to be true
      expect(messages.any? { |x| x[:m].include?("PRD completed") }).to be false
    end
  end

  describe "helper extraction methods" do
    it "extracts mode from separate token" do
      expect(described_class.send(:extract_mode_option, ["--mode", "analyze"])).to eq(:analyze)
    end
    it "extracts mode from equals form" do
      expect(described_class.send(:extract_mode_option, ["--mode=execute"])).to eq(:execute)
    end
  end

  describe "get_binary_name mappings" do
    it { expect(described_class.send(:get_binary_name, "claude")).to eq("claude") }
    it { expect(described_class.send(:get_binary_name, "anthropic")).to eq("claude") }
    it { expect(described_class.send(:get_binary_name, "cursor")).to eq("cursor") }
    it { expect(described_class.send(:get_binary_name, "gemini")).to eq("gemini") }
    it { expect(described_class.send(:get_binary_name, "codex")).to eq("codex") }
    it { expect(described_class.send(:get_binary_name, "github_copilot")).to eq("gh") }
    it { expect(described_class.send(:get_binary_name, "opencode")).to eq("opencode") }
    it { expect(described_class.send(:get_binary_name, "unknown_provider")).to eq("unknown_provider") }
  end

  describe "class-level display_harness_result" do
    before do
      @messages = []
      allow(described_class).to receive(:display_message) do |m, type:|
        @messages << {m: m, type: type}
      end
    end

    it "shows completed messages" do
      described_class.send(:display_harness_result, {status: "completed", message: "done"})
      expect(@messages.any? { |x| x[:m].include?("Harness completed successfully") }).to be true
    end

    it "shows stopped messages" do
      described_class.send(:display_harness_result, {status: "stopped"})
      expect(@messages.any? { |x| x[:m].include?("Harness stopped by user") }).to be true
    end

    it "skips error messaging for error status" do
      described_class.send(:display_harness_result, {status: "error", message: "boom"})
      expect(@messages.any? { |x| x[:m].include?("boom") }).to be false
    end

    it "shows generic finished messages for other status" do
      described_class.send(:display_harness_result, {status: "partial", message: "hello"})
      expect(@messages.any? { |x| x[:m].include?("Harness finished") }).to be true
      expect(@messages.any? { |x| x[:m].include?("Message: hello") }).to be true
    end

    it "shows generic status without message when message absent" do
      described_class.send(:display_harness_result, {status: "unknown"})
      expect(@messages.any? { |x| x[:m].include?("Harness finished") }).to be true
      expect(@messages.any? { |x| x[:m].include?("Status: unknown") }).to be true
    end
  end

  describe "kb command" do
    before do
      allow(described_class).to receive(:display_message)
    end

    it "shows topic when show subcommand provided" do
      described_class.send(:run_kb_command, ["show", "testing"])
      expect(described_class).to have_received(:display_message).with(/Knowledge Base: testing/, type: :info)
    end

    it "defaults to summary topic when show has no topic" do
      described_class.send(:run_kb_command, ["show"])
      expect(described_class).to have_received(:display_message).with(/Knowledge Base: summary/, type: :info)
    end

    it "shows usage for unknown subcommand" do
      described_class.send(:run_kb_command, ["unknown"])
      expect(described_class).to have_received(:display_message).with(/Usage: aidp kb show/, type: :info)
    end

    it "shows usage for no subcommand" do
      described_class.send(:run_kb_command, [])
      expect(described_class).to have_received(:display_message).with(/Usage: aidp kb show/, type: :info)
    end
  end

  describe "extract_mode_option helper" do
    it "extracts mode from equals form" do
      expect(described_class.send(:extract_mode_option, ["--mode=analyze"])).to eq(:analyze)
    end

    it "extracts mode from separate token" do
      expect(described_class.send(:extract_mode_option, ["--mode", "execute"])).to eq(:execute)
    end

    it "returns nil when no mode flag present" do
      expect(described_class.send(:extract_mode_option, ["--other"])).to be_nil
    end

    it "handles mode flag followed by another flag" do
      expect(described_class.send(:extract_mode_option, ["--mode", "--other"])).to be_nil
    end
  end
end

RSpec.describe Aidp::CLI, "additional subcommand and helper coverage" do
  # Simple stdout capture helper (avoid interfering with existing helpers)
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  describe "kb command" do
    it "shows default summary topic when no topic provided" do
      output = capture_stdout { Aidp::CLI.run(["kb", "show"]) }
      expect(output).to include("Knowledge Base: summary")
    end

    it "shows specified topic" do
      output = capture_stdout { Aidp::CLI.run(["kb", "show", "architecture"]) }
      expect(output).to include("Knowledge Base: architecture")
    end

    it "shows usage on unknown subcommand" do
      output = capture_stdout { Aidp::CLI.run(["kb", "unknown"]) }
      expect(output).to include("Usage: aidp kb show <topic>")
    end
  end

  describe "helper extraction methods" do
    it "extracts mode via separate token" do
      args = ["--mode", "execute"]
      mode = described_class.send(:extract_mode_option, args)
      expect(mode).to eq(:execute)
    end

    it "extracts mode via equals form" do
      args = ["--mode=analyze"]
      mode = described_class.send(:extract_mode_option, args)
      expect(mode).to eq(:analyze)
    end

    it "returns nil when mode not present" do
      args = ["--other", "value"]
      expect(described_class.send(:extract_mode_option, args)).to be_nil
    end
  end

  describe "class-level display_harness_result" do
    it "handles completed harness result" do
      # Test that the method runs without error for completed status
      expect do
        described_class.send(:display_harness_result, {status: "completed"})
      end.not_to raise_error
    end

    it "handles stopped harness result" do
      # Test that the method runs without error for stopped status
      expect do
        described_class.send(:display_harness_result, {status: "stopped"})
      end.not_to raise_error
    end

    it "prints generic harness result" do
      output = capture_stdout do
        described_class.send(:display_harness_result, {status: "custom", message: "Hi"})
      end
      expect(output).to include("Harness finished")
      expect(output).to include("Status: custom")
      expect(output).to include("Message: Hi")
    end
  end
end

RSpec.describe Aidp::CLI, "workstream commands" do
  let(:project_dir) { Dir.mktmpdir }
  let(:worktree_module) { Aidp::Worktree }
  let(:test_prompt) { TestPrompt.new(responses: {yes?: true}) }

  before do
    # Initialize a git repository
    Dir.chdir(project_dir) do
      system("git", "init", "-q")
      system("git", "config", "user.name", "Test User")
      system("git", "config", "user.email", "test@example.com")
      system("git", "config", "commit.gpgsign", "false")
      File.write("README.md", "# Test Project")
      system("git", "add", ".")
      system("git", "commit", "-q", "-m", "Initial commit")
    end
  end

  after do
    # Clean up git worktrees before removing directory
    Dir.chdir(project_dir) do
      worktrees = worktree_module.list(project_dir: project_dir)
      worktrees.each do |ws|
        worktree_module.remove(slug: ws[:slug], project_dir: project_dir)
      rescue
        nil
      end
    end
    FileUtils.rm_rf(project_dir)
  end

  describe "aidp ws list" do
    it "shows message when no workstreams exist" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "list"])
        end
      end

      expect(output).to include("No workstreams found")
      expect(output).to include("Create one with: aidp ws new")
    end

    it "lists existing workstreams in table format" do
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "test-123", project_dir: project_dir)
        worktree_module.create(slug: "test-456", project_dir: project_dir)
      end

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "list"])
        end
      end

      expect(output).to include("Workstreams")
      expect(output).to include("test-123")
      expect(output).to include("test-456")
      expect(output).to include("aidp/test-123")
      expect(output).to include("aidp/test-456")
    end

    it "shows active status for existing worktrees" do
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "active-ws", project_dir: project_dir)
      end

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "list"])
        end
      end

      expect(output).to include("active-ws")
      expect(output).to include("active")
    end
  end

  describe "aidp ws new" do
    it "creates a new workstream with valid slug" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "new", "issue-123"])
        end
      end

      expect(output).to include("✓ Created workstream: issue-123")
      expect(output).to include("Path:")
      expect(output).to include("Branch: aidp/issue-123")
      expect(output).to include("Switch to this workstream:")

      # Verify worktree was created
      ws = worktree_module.info(slug: "issue-123", project_dir: project_dir)
      expect(ws).not_to be_nil
      expect(ws[:slug]).to eq("issue-123")
      expect(ws[:branch]).to eq("aidp/issue-123")
    end

    it "rejects invalid slug format (uppercase)" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "new", "Issue-123"])
        end
      end

      expect(output).to include("❌ Invalid slug format")
      expect(output).to include("must be lowercase")

      # Verify worktree was not created
      ws = worktree_module.info(slug: "Issue-123", project_dir: project_dir)
      expect(ws).to be_nil
    end

    it "rejects invalid slug format (special characters)" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "new", "issue_123"])
        end
      end

      expect(output).to include("❌ Invalid slug format")

      # Verify worktree was not created
      ws = worktree_module.info(slug: "issue_123", project_dir: project_dir)
      expect(ws).to be_nil
    end

    it "requires slug argument" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "new"])
        end
      end

      expect(output).to include("❌ Missing slug")
      expect(output).to include("Usage: aidp ws new <slug>")
    end

    it "handles worktree creation errors gracefully" do
      # Create a workstream first
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "duplicate", project_dir: project_dir)
      end

      # Try to create it again
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "new", "duplicate"])
        end
      end

      expect(output).to include("❌")
      expect(output).to include("already exists")
    end

    it "supports --base-branch option" do
      # Create a feature branch
      Dir.chdir(project_dir) do
        # Get the current branch (the initial branch created by git init)
        initial_branch = `git branch --show-current`.strip
        system("git", "checkout", "-q", "-b", "feature")
        File.write("feature.txt", "feature content")
        system("git", "add", ".")
        system("git", "commit", "-q", "-m", "Add feature")
        # Go back to initial branch
        system("git", "checkout", "-q", initial_branch)
      end

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "new", "from-feature", "--base-branch", "feature"])
        end
      end

      expect(output).to include("✓ Created workstream: from-feature")

      # Verify it was created from the feature branch
      ws = worktree_module.info(slug: "from-feature", project_dir: project_dir)
      expect(ws).not_to be_nil
      expect(File.exist?(File.join(ws[:path], "feature.txt"))).to be true
    end
  end

  describe "aidp ws rm" do
    it "removes an existing workstream" do
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "to-remove", project_dir: project_dir)
      end

      # Mock prompt to auto-confirm
      allow(Aidp::CLI).to receive(:create_prompt).and_return(test_prompt)

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "rm", "to-remove"])
        end
      end

      expect(output).to include("✓ Removed workstream: to-remove")

      # Verify worktree was removed
      ws = worktree_module.info(slug: "to-remove", project_dir: project_dir)
      expect(ws).to be_nil
    end

    it "requires slug argument" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "rm"])
        end
      end

      expect(output).to include("❌ Missing slug")
      expect(output).to include("Usage: aidp ws rm <slug>")
    end

    it "handles non-existent workstream gracefully" do
      allow(Aidp::CLI).to receive(:create_prompt).and_return(test_prompt)

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "rm", "nonexistent"])
        end
      end

      expect(output).to include("❌")
      expect(output).to include("not found")
    end

    it "skips confirmation with --force" do
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "force-remove", project_dir: project_dir)
      end

      # Should not call prompt
      allow(Aidp::CLI).to receive(:create_prompt).and_return(test_prompt)
      expect(test_prompt).not_to receive(:yes?)

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "rm", "force-remove", "--force"])
        end
      end

      expect(output).to include("✓ Removed workstream: force-remove")

      # Verify worktree was removed
      ws = worktree_module.info(slug: "force-remove", project_dir: project_dir)
      expect(ws).to be_nil
    end

    it "supports --delete-branch option" do
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "with-branch", project_dir: project_dir)
      end

      allow(Aidp::CLI).to receive(:create_prompt).and_return(test_prompt)

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "rm", "with-branch", "--delete-branch", "--force"])
        end
      end

      expect(output).to include("✓ Removed workstream: with-branch")
      expect(output).to include("Branch deleted")

      # Verify branch was deleted
      Dir.chdir(project_dir) do
        branches = `git branch --list aidp/with-branch`.strip
        expect(branches).to be_empty
      end
    end

    it "does not remove if user declines confirmation" do
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "keep-me", project_dir: project_dir)
      end

      # Mock prompt to decline
      test_prompt_decline = TestPrompt.new(responses: {yes?: false})
      allow(Aidp::CLI).to receive(:create_prompt).and_return(test_prompt_decline)

      capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "rm", "keep-me"])
        end
      end

      # Verify worktree still exists
      ws = worktree_module.info(slug: "keep-me", project_dir: project_dir)
      expect(ws).not_to be_nil
    end
  end

  describe "aidp ws status" do
    it "shows detailed workstream status" do
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "status-test", project_dir: project_dir)
      end

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "status", "status-test"])
        end
      end

      expect(output).to include("Workstream: status-test")
      expect(output).to include("Path:")
      expect(output).to include("Branch: aidp/status-test")
      expect(output).to include("Created:")
      expect(output).to include("Status: Active")
      expect(output).to include("Git Status:")
    end

    it "requires slug argument" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "status"])
        end
      end

      expect(output).to include("❌ Missing slug")
      expect(output).to include("Usage: aidp ws status <slug>")
    end

    it "handles non-existent workstream gracefully" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "status", "nonexistent"])
        end
      end

      expect(output).to include("❌ Workstream not found: nonexistent")
    end
  end

  describe "aidp ws help" do
    it "shows usage when no subcommand provided or unknown subcommand" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "help"])
        end
      end

      expect(output).to include("Usage: aidp ws <command>")
      expect(output).to include("list")
      expect(output).to include("new <slug>")
      expect(output).to include("rm <slug>")
      expect(output).to include("status <slug>")
      expect(output).to include("aidp ws list")
    end
  end

  # Helper method to capture stdout output
  def capture_output
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
