# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

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

      # Mock ModelsCommand
      models_cmd = instance_double(Aidp::CLI::ModelsCommand, run: nil)
      allow(Aidp::CLI::ModelsCommand).to receive(:new).and_return(models_cmd)

      Aidp::CLI.send(:run_models_command, [])

      expect(Aidp::CLI::ModelsCommand).to have_received(:new)
      expect(models_cmd).to have_received(:run).with([])
    end
  end

  describe "config command" do
    it "shows config path when no subcommand provided" do
      Aidp::CLI.send(:run_config_command, [])

      expect(Aidp::CLI).to have_received(:display_message).with(/Config file path/, type: :info)
    end

    it "shows config path for 'path' subcommand" do
      Aidp::CLI.send(:run_config_command, ["path"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Config file path/, type: :info)
    end
  end

  describe "settings command" do
    it "delegates to SettingsCommand" do
      # Mock SettingsCommand
      settings_cmd = instance_double(Aidp::CLI::SettingsCommand, run: nil)
      allow(Aidp::CLI::SettingsCommand).to receive(:new).and_return(settings_cmd)

      Aidp::CLI.send(:run_settings_command, [])

      expect(Aidp::CLI::SettingsCommand).to have_received(:new)
      expect(settings_cmd).to have_received(:run)
    end
  end

  describe "devcontainer command" do
    it "delegates to DevcontainerCommand" do
      # Mock DevcontainerCommand
      devcontainer_cmd = instance_double(Aidp::CLI::DevcontainerCommand, run: nil)
      allow(Aidp::CLI::DevcontainerCommand).to receive(:new).and_return(devcontainer_cmd)

      Aidp::CLI.send(:run_devcontainer_command, [])

      expect(Aidp::CLI::DevcontainerCommand).to have_received(:new)
      expect(devcontainer_cmd).to have_received(:run).with([])
    end
  end
end
