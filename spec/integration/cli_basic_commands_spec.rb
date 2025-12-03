# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../lib/aidp/cli/harness_command"
require_relative "../../lib/aidp/cli/checkpoint_command"
require_relative "../../lib/aidp/cli/providers_command"
require_relative "../../lib/aidp/cli/mcp_dashboard"
require_relative "../../lib/aidp/skills/wizard/controller"

RSpec.describe "CLI Basic Commands Integration", type: :integration do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    allow(Dir).to receive(:pwd).and_return(tmpdir)
    allow(Aidp::CLI).to receive(:display_message)
  end

  after do
    FileUtils.rm_rf(tmpdir) if tmpdir && Dir.exist?(tmpdir)
  end

  describe "status command" do
    it "displays system status" do
      Aidp::CLI.send(:run_status_command)

      expect(Aidp::CLI).to have_received(:display_message).with(/AI Dev Pipeline Status/, type: :info)
      expect(Aidp::CLI).to have_received(:display_message).with(/Analyze Mode/, type: :info)
      expect(Aidp::CLI).to have_received(:display_message).with(/Execute Mode/, type: :info)
    end
  end

  describe "kb command" do
    it "shows knowledge base topic" do
      Aidp::CLI.send(:run_kb_command, ["show", "testing"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Knowledge Base: testing/, type: :info)
    end

    it "defaults to summary topic when no topic provided" do
      Aidp::CLI.send(:run_kb_command, ["show"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Knowledge Base: summary/, type: :info)
    end

    it "shows usage for unknown subcommand" do
      Aidp::CLI.send(:run_kb_command, ["unknown"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage: aidp kb show/, type: :info)
    end

    it "shows usage when no subcommand provided" do
      Aidp::CLI.send(:run_kb_command, [])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage: aidp kb show/, type: :info)
    end
  end

  describe "models command" do
    it "delegates to ModelsCommand" do
      # Create minimal config file
      config_dir = File.join(tmpdir, ".aidp")
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, "aidp.yml"), {
        providers: {
          claude: {
            type: "api",
            api_key: "test-key",
            models: ["claude-3-5-sonnet-20241022"]
          }
        }
      }.to_yaml)

      # Load the ModelsCommand class
      require_relative "../../lib/aidp/cli/models_command"

      # Mock ModelsCommand
      models_cmd = instance_double(Aidp::CLI::ModelsCommand, run: nil)
      allow(Aidp::CLI::ModelsCommand).to receive(:new).and_return(models_cmd)

      Aidp::CLI.send(:run_models_command, [])

      expect(Aidp::CLI::ModelsCommand).to have_received(:new)
      expect(models_cmd).to have_received(:run).with([])
    end
  end

  describe "config command" do
    it "shows usage when no args provided" do
      # ConfigCommand uses MessageDisplay instance methods, not class methods
      # So we can't stub display_message on Aidp::CLI for this
      # Just verify the command runs without error
      expect { Aidp::CLI.send(:run_config_command, []) }.not_to raise_error
    end

    it "shows usage with --help flag" do
      expect { Aidp::CLI.send(:run_config_command, ["--help"]) }.not_to raise_error
    end
  end

  describe "settings command" do
    it "shows usage when called with no args" do
      Aidp::CLI.send(:run_settings_command, [])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage: aidp settings <category>/, type: :info)
    end
  end

  describe "devcontainer command" do
    it "shows usage when no args provided" do
      Aidp::CLI.send(:run_devcontainer_command, [])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage: aidp devcontainer/, type: :info)
    end

    it "shows usage with --help flag" do
      Aidp::CLI.send(:run_devcontainer_command, ["--help"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage: aidp devcontainer/, type: :info)
    end
  end

  describe "harness command" do
    it "delegates to HarnessCommand" do
      harness_cmd = instance_double(Aidp::CLI::HarnessCommand, run: nil)
      allow(Aidp::CLI::HarnessCommand).to receive(:new).and_return(harness_cmd)

      Aidp::CLI.send(:run_harness_command, ["status"])

      expect(Aidp::CLI::HarnessCommand).to have_received(:new)
      expect(harness_cmd).to have_received(:run)
    end
  end

  describe "checkpoint command" do
    it "delegates to CheckpointCommand" do
      checkpoint_cmd = instance_double(Aidp::CLI::CheckpointCommand, run: nil)
      allow(Aidp::CLI::CheckpointCommand).to receive(:new).and_return(checkpoint_cmd)

      Aidp::CLI.send(:run_checkpoint_command, ["show"])

      expect(Aidp::CLI::CheckpointCommand).to have_received(:new)
      expect(checkpoint_cmd).to have_received(:run).with(["show"])
    end
  end

  describe "providers command" do
    let(:config_manager) { instance_double(Aidp::Harness::ConfigManager) }
    let(:provider_manager) { instance_double(Aidp::Harness::ProviderManager, health_dashboard: []) }

    before do
      allow(Aidp::Harness::ConfigManager).to receive(:new).and_return(config_manager)
      allow(Aidp::Harness::ProviderManager).to receive(:new).and_return(provider_manager)
    end

    it "displays health dashboard by default" do
      allow(TTY::Spinner).to receive(:new).and_return(double(auto_spin: nil, stop: nil))

      Aidp::CLI.send(:run_providers_command, [])

      expect(provider_manager).to have_received(:health_dashboard)
    end

    it "delegates to ProvidersCommand for info subcommand" do
      providers_cmd = instance_double(Aidp::CLI::ProvidersCommand, run: nil)
      allow(Aidp::CLI::ProvidersCommand).to receive(:new).and_return(providers_cmd)

      Aidp::CLI.send(:run_providers_command, ["info", "claude"])

      expect(Aidp::CLI::ProvidersCommand).to have_received(:new)
      expect(providers_cmd).to have_received(:run).with(["claude"], subcommand: "info")
    end

    it "delegates to ProvidersCommand for refresh subcommand" do
      providers_cmd = instance_double(Aidp::CLI::ProvidersCommand, run: nil)
      allow(Aidp::CLI::ProvidersCommand).to receive(:new).and_return(providers_cmd)

      Aidp::CLI.send(:run_providers_command, ["refresh"])

      expect(Aidp::CLI::ProvidersCommand).to have_received(:new)
      expect(providers_cmd).to have_received(:run).with([], subcommand: "refresh")
    end
  end

  describe "mcp command" do
    let(:dashboard) { instance_double(Aidp::CLI::McpDashboard, display_dashboard: nil, display_task_eligibility: nil) }

    before do
      allow(Aidp::CLI::McpDashboard).to receive(:new).and_return(dashboard)
    end

    it "displays dashboard by default" do
      Aidp::CLI.send(:run_mcp_command, [])

      expect(dashboard).to have_received(:display_dashboard)
    end

    it "displays dashboard for 'dashboard' subcommand" do
      Aidp::CLI.send(:run_mcp_command, ["dashboard"])

      expect(dashboard).to have_received(:display_dashboard)
    end

    it "checks task eligibility for 'check' subcommand" do
      Aidp::CLI.send(:run_mcp_command, ["check", "filesystem", "brave-search"])

      expect(dashboard).to have_received(:display_task_eligibility).with(["filesystem", "brave-search"])
    end

    it "shows usage when check has no servers" do
      Aidp::CLI.send(:run_mcp_command, ["check"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage: aidp mcp check/, type: :info)
    end
  end

  describe "issue command" do
    it "shows usage when no args provided" do
      Aidp::CLI.send(:run_issue_command, [])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage: aidp issue/, type: :info)
    end

    it "shows usage for help flag" do
      Aidp::CLI.send(:run_issue_command, ["--help"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage: aidp issue/, type: :info)
    end

    it "shows error when import has no identifier" do
      Aidp::CLI.send(:run_issue_command, ["import"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Missing issue identifier/, type: :error)
    end

    it "shows error for unknown command" do
      Aidp::CLI.send(:run_issue_command, ["unknown"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Unknown issue command/, type: :error)
    end
  end

  describe "init command" do
    let(:init_runner) { instance_double(Aidp::Init::Runner, run: nil) }

    before do
      allow(Aidp::Init::Runner).to receive(:new).and_return(init_runner)
    end

    it "runs init workflow" do
      Aidp::CLI.send(:run_init_command, [])

      expect(Aidp::Init::Runner).to have_received(:new)
      expect(init_runner).to have_received(:run)
    end

    it "shows usage for help flag" do
      Aidp::CLI.send(:run_init_command, ["--help"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage: aidp init/, type: :info)
    end

    it "passes options to runner" do
      Aidp::CLI.send(:run_init_command, ["--dry-run"])

      expect(Aidp::Init::Runner).to have_received(:new).with(tmpdir, prompt: anything, options: {dry_run: true})
    end
  end

  describe "ws command" do
    before do
      allow(Aidp::Worktree).to receive(:list).and_return([])
    end

    it "lists workstreams by default" do
      Aidp::CLI.send(:run_ws_command, [])

      expect(Aidp::CLI).to have_received(:display_message).with(/No workstreams found/, type: :info)
    end

    it "lists workstreams for 'list' subcommand" do
      Aidp::CLI.send(:run_ws_command, ["list"])

      expect(Aidp::CLI).to have_received(:display_message).with(/No workstreams found/, type: :info)
    end

    it "shows error when new has no slug" do
      Aidp::CLI.send(:run_ws_command, ["new"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Missing slug/, type: :error)
    end

    it "shows error for invalid slug format" do
      Aidp::CLI.send(:run_ws_command, ["new", "Invalid_Slug"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Invalid slug format/, type: :error)
    end

    it "shows usage for unknown subcommand" do
      Aidp::CLI.send(:run_ws_command, ["unknown"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage: aidp ws/, type: :info)
    end
  end

  describe "skill command" do
    it "delegates to skill list by default" do
      registry = instance_double(Aidp::Skills::Registry, load_skills: nil, all: [])
      allow(Aidp::Skills::Registry).to receive(:new).and_return(registry)

      Aidp::CLI.send(:run_skill_command, [])

      expect(Aidp::CLI).to have_received(:display_message).with(/No skills found/, type: :info)
    end

    it "shows usage when show has no skill id" do
      Aidp::CLI.send(:run_skill_command, ["show"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage: aidp skill show/, type: :info)
    end

    it "shows usage when search has no query" do
      Aidp::CLI.send(:run_skill_command, ["search"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage: aidp skill search/, type: :info)
    end

    it "runs skill wizard for 'new' subcommand" do
      wizard = instance_double(Aidp::Skills::Wizard::Controller, run: nil)
      allow(Aidp::Skills::Wizard::Controller).to receive(:new).and_return(wizard)

      Aidp::CLI.send(:run_skill_command, ["new"])

      expect(Aidp::Skills::Wizard::Controller).to have_received(:new)
      expect(wizard).to have_received(:run)
    end
  end

  describe "watch command" do
    let(:watch_runner) { instance_double(Aidp::Watch::Runner, start: nil) }
    let(:config_manager) { instance_double(Aidp::Harness::ConfigManager, config: {}) }

    before do
      allow(Aidp::Watch::Runner).to receive(:new).and_return(watch_runner)
      allow(Aidp::Harness::ConfigManager).to receive(:new).and_return(config_manager)
      allow(Aidp::CLI).to receive(:setup_logging)
    end

    it "shows usage when no URL provided" do
      Aidp::CLI.send(:run_watch_command, [])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage: aidp watch/, type: :info)
    end

    it "starts watch runner with URL" do
      Aidp::CLI.send(:run_watch_command, ["https://github.com/owner/repo/issues"])

      expect(Aidp::Watch::Runner).to have_received(:new)
      expect(watch_runner).to have_received(:start)
    end

    it "passes interval option to runner" do
      Aidp::CLI.send(:run_watch_command, ["https://github.com/owner/repo/issues", "--interval", "120"])

      expect(Aidp::Watch::Runner).to have_received(:new).with(hash_including(interval: 120))
    end

    it "passes provider option to runner" do
      Aidp::CLI.send(:run_watch_command, ["https://github.com/owner/repo/issues", "--provider", "claude"])

      expect(Aidp::Watch::Runner).to have_received(:new).with(hash_including(provider_name: "claude"))
    end

    describe "--launch-test flag" do
      before do
        allow(Aidp).to receive(:log_debug)
        allow(Aidp).to receive(:log_info)
      end

      it "returns 0 when launch test succeeds" do
        result = Aidp::CLI.send(:run_watch_command, ["https://github.com/owner/repo/issues", "--launch-test"])

        expect(result).to eq(0)
      end

      it "instantiates Runner to validate dependencies but does not start it" do
        Aidp::CLI.send(:run_watch_command, ["https://github.com/owner/repo/issues", "--launch-test"])

        expect(Aidp::Watch::Runner).to have_received(:new)
        expect(watch_runner).not_to have_received(:start)
      end

      it "loads and validates configuration during launch test" do
        Aidp::CLI.send(:run_watch_command, ["https://github.com/owner/repo/issues", "--launch-test"])

        expect(Aidp::Harness::ConfigManager).to have_received(:new)
      end

      it "displays success message after launch test" do
        Aidp::CLI.send(:run_watch_command, ["https://github.com/owner/repo/issues", "--launch-test"])

        expect(Aidp::CLI).to have_received(:display_message).with(/Launch test completed successfully/, type: :success)
      end
    end
  end

  describe "work command" do
    let(:worktree_info) { {path: "/path/to/ws", branch: "ws-branch"} }

    before do
      allow(Aidp::Worktree).to receive(:info).and_return(worktree_info)
    end

    it "shows error when no workstream specified" do
      Aidp::CLI.send(:run_work_command, [])

      expect(Aidp::CLI).to have_received(:display_message).with(/Missing required --workstream flag/, type: :error)
    end

    it "shows error when workstream not found" do
      allow(Aidp::Worktree).to receive(:info).and_return(nil)

      Aidp::CLI.send(:run_work_command, ["--workstream", "nonexistent"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Workstream not found/, type: :error)
    end

    it "starts background job when --background flag provided" do
      bg_runner = instance_double(Aidp::Jobs::BackgroundRunner, start: "job-123")
      allow(Aidp::Jobs::BackgroundRunner).to receive(:new).and_return(bg_runner)

      Aidp::CLI.send(:run_work_command, ["--workstream", "test-ws", "--background"])

      expect(bg_runner).to have_received(:start)
    end
  end
end
