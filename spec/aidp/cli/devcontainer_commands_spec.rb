# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"
require "yaml"
require_relative "../../../lib/aidp/cli/devcontainer_commands"

RSpec.describe Aidp::CLI::DevcontainerCommands do
  let(:project_dir) { Dir.mktmpdir }
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:commands) { described_class.new(project_dir: project_dir, prompt: prompt) }
  let(:devcontainer_path) { File.join(project_dir, ".devcontainer", "devcontainer.json") }
  let(:aidp_yml_path) { File.join(project_dir, ".aidp", "aidp.yml") }

  after do
    FileUtils.rm_rf(project_dir)
  end

  def create_devcontainer(config)
    FileUtils.mkdir_p(File.dirname(devcontainer_path))
    File.write(devcontainer_path, JSON.pretty_generate(config))
  end

  def create_aidp_yml(config)
    FileUtils.mkdir_p(File.dirname(aidp_yml_path))
    File.write(aidp_yml_path, YAML.dump(config))
  end

  describe "#diff" do
    context "when no devcontainer exists" do
      it "displays warning and returns false" do
        expect(commands).to receive(:display_message).with(
          "No existing devcontainer.json found",
          type: :warning
        )
        expect(commands).to receive(:display_message).with(
          "Run 'aidp config --interactive' to create one",
          type: :muted
        )

        result = commands.diff

        expect(result).to be false
      end
    end

    context "when devcontainer exists but no proposed config" do
      before do
        create_devcontainer({"name" => "Test"})
      end

      it "displays warning about no proposed config" do
        expect(commands).to receive(:display_message).with(
          "No proposed configuration found",
          type: :warning
        )
        expect(commands).to receive(:display_message).with(
          "Update your aidp.yml or use --generate",
          type: :muted
        )

        result = commands.diff

        expect(result).to be false
      end
    end

    context "when both current and proposed exist" do
      before do
        create_devcontainer({
          "name" => "Old Name",
          "features" => {
            "ghcr.io/devcontainers/features/ruby:1" => {}
          },
          "forwardPorts" => [3000]
        })

        create_aidp_yml({
          "devcontainer" => {
            "manage" => true,
            "custom_ports" => [
              {"number" => 3000, "label" => "App"},
              {"number" => 5432, "label" => "Database"}
            ]
          },
          "providers" => {
            "openai" => {"models" => ["gpt-4"]}
          }
        })
      end

      it "displays the diff and returns true" do
        expect(commands).to receive(:display_message).with(
          "📄 Devcontainer Changes Preview",
          type: :highlight
        )
        allow(commands).to receive(:display_message) # Allow other messages

        result = commands.diff

        expect(result).to be true
      end
    end
  end

  describe "#apply" do
    context "when no configuration found" do
      it "displays error and returns false" do
        expect(commands).to receive(:display_message).with(
          "❌ No configuration found in aidp.yml",
          type: :error
        )
        expect(commands).to receive(:display_message).with(
          "Run 'aidp config --interactive' first",
          type: :muted
        )

        result = commands.apply

        expect(result).to be false
      end
    end

    context "with dry run" do
      before do
        create_aidp_yml({
          "devcontainer" => {
            "manage" => true,
            "custom_ports" => [{"number" => 3000, "label" => "App"}]
          },
          "providers" => {
            "anthropic" => {"enabled" => true}
          }
        })
      end

      it "shows preview without making changes" do
        allow(commands).to receive(:display_message)
        expect(commands).to receive(:display_message).with(
          "🔍 Dry Run - Changes Preview",
          type: :highlight
        )
        expect(commands).to receive(:display_message).with(
          "\nNo changes made (dry run)",
          type: :muted
        )

        result = commands.apply(dry_run: true)

        expect(result).to be true
        expect(File.exist?(devcontainer_path)).to be false
      end
    end

    context "when creating new devcontainer" do
      before do
        create_aidp_yml({
          "devcontainer" => {
            "manage" => true,
            "custom_ports" => [{"number" => 3000, "label" => "App"}]
          },
          "providers" => {
            "anthropic" => {"enabled" => true}
          }
        })
      end

      it "creates devcontainer without confirmation when forced" do
        allow(commands).to receive(:display_message)

        result = commands.apply(force: true)

        expect(result).to be true
        expect(File.exist?(devcontainer_path)).to be true

        config = JSON.parse(File.read(devcontainer_path))
        expect(config["forwardPorts"]).to include(3000)
      end

      it "prompts for confirmation when not forced" do
        allow(commands).to receive(:display_message)
        expect(prompt).to receive(:yes?).with("Apply these changes?").and_return(true)

        result = commands.apply

        expect(result).to be true
        expect(File.exist?(devcontainer_path)).to be true
      end

      it "cancels when user declines confirmation" do
        allow(commands).to receive(:display_message)
        expect(prompt).to receive(:yes?).with("Apply these changes?").and_return(false)
        expect(commands).to receive(:display_message).with("Cancelled", type: :warning)

        result = commands.apply

        expect(result).to be false
        expect(File.exist?(devcontainer_path)).to be false
      end
    end

    context "when updating existing devcontainer" do
      before do
        create_devcontainer({
          "name" => "Old Name",
          "features" => {
            "ghcr.io/devcontainers/features/ruby:1" => {}
          }
        })

        create_aidp_yml({
          "devcontainer" => {
            "manage" => true,
            "custom_ports" => [{"number" => 8080, "label" => "API"}]
          },
          "providers" => {
            "anthropic" => {"enabled" => true}
          },
          "work_loop" => {
            "test_commands" => [
              {"framework" => "rspec"}
            ]
          }
        })
      end

      it "creates backup by default" do
        allow(commands).to receive(:display_message)
        allow(prompt).to receive(:yes?).and_return(true)

        commands.apply

        backup_dir = File.join(project_dir, ".aidp", "backups", "devcontainer")
        expect(Dir.exist?(backup_dir)).to be true

        # Backups are named devcontainer-TIMESTAMP.json, not devcontainer.json.TIMESTAMP
        expect(Dir.glob(File.join(backup_dir, "devcontainer-*.json")).size).to eq(1)
      end

      it "skips backup when backup: false" do
        allow(commands).to receive(:display_message)
        allow(prompt).to receive(:yes?).and_return(true)

        commands.apply(backup: false)

        backup_dir = File.join(project_dir, ".aidp", "backups", "devcontainer")
        expect(Dir.exist?(backup_dir)).to be false
      end

      it "merges with existing configuration" do
        allow(commands).to receive(:display_message)

        commands.apply(force: true)

        config = JSON.parse(File.read(devcontainer_path))
        # Should preserve old name
        expect(config["name"]).to eq("Old Name")
        # Should add GitHub CLI feature based on provider
        expect(config["features"].keys).to include(
          "ghcr.io/devcontainers/features/github-cli:1"
        )
        # Should add custom port
        expect(config["forwardPorts"]).to include(8080)
      end
    end

    context "with invalid aidp.yml" do
      before do
        FileUtils.mkdir_p(File.dirname(aidp_yml_path))
        File.write(aidp_yml_path, "invalid: yaml: content: [")
      end

      it "handles parsing errors gracefully" do
        expect(commands).to receive(:display_message).with(
          "❌ No configuration found in aidp.yml",
          type: :error
        )
        expect(commands).to receive(:display_message).with(
          "Run 'aidp config --interactive' first",
          type: :muted
        )

        result = commands.apply

        expect(result).to be false
      end
    end
  end

  describe "#list_backups" do
    let(:backup_dir) { File.join(project_dir, ".aidp", "backups", "devcontainer") }

    context "when no backups exist" do
      it "displays message and returns true" do
        expect(commands).to receive(:display_message).with(
          "No backups found",
          type: :muted
        )

        result = commands.list_backups

        expect(result).to be true
      end
    end

    context "when backups exist" do
      before do
        FileUtils.mkdir_p(backup_dir)

        # Create test backups
        3.times do |i|
          backup_file = File.join(backup_dir, "devcontainer-2025010#{i}_120000.json")
          File.write(backup_file, '{"name": "test"}')

          if i == 0
            metadata_file = "#{backup_file}.meta"
            File.write(metadata_file, JSON.generate({"reason" => "wizard_update"}))
          end

          sleep 0.01 # Ensure different mtimes
        end
      end

      it "lists all backups with details" do
        expect(commands).to receive(:display_message).with(
          "📦 Available Backups",
          type: :highlight
        )
        allow(commands).to receive(:display_message) # Allow other messages

        result = commands.list_backups

        expect(result).to be true
      end

      it "displays backup metadata when available" do
        output_received = []
        allow(commands).to receive(:display_message) do |msg, options|
          output_received << msg
        end

        commands.list_backups

        expect(output_received.join("\n")).to include("Reason: wizard_update")
      end

      it "shows total size" do
        output_received = []
        allow(commands).to receive(:display_message) do |msg, options|
          output_received << msg
        end

        commands.list_backups

        expect(output_received.join("\n")).to match(/Total: \d+ backups/)
      end
    end
  end

  describe "#restore" do
    let(:backup_dir) { File.join(project_dir, ".aidp", "backups", "devcontainer") }
    let(:backup_file) { File.join(backup_dir, "devcontainer-20250103_120000.json") }

    before do
      FileUtils.mkdir_p(backup_dir)
      File.write(backup_file, JSON.generate({"name" => "Backup Config"}))

      create_devcontainer({"name" => "Current Config"})
    end

    context "with index-based selection" do
      it "restores backup by index" do
        allow(commands).to receive(:display_message)
        expect(prompt).to receive(:yes?).with("Restore this backup?").and_return(true)

        result = commands.restore("1")

        expect(result).to be true

        config = JSON.parse(File.read(devcontainer_path))
        expect(config["name"]).to eq("Backup Config")
      end

      it "handles invalid index" do
        expect(commands).to receive(:display_message).with(
          /❌ Invalid backup index/,
          type: :error
        )

        result = commands.restore("999")

        expect(result).to be false
      end
    end

    context "with direct path" do
      it "restores backup from path" do
        allow(commands).to receive(:display_message)
        expect(prompt).to receive(:yes?).with("Restore this backup?").and_return(true)

        result = commands.restore(backup_file)

        expect(result).to be true
      end
    end

    context "with non-existent backup" do
      it "displays error" do
        expect(commands).to receive(:display_message).with(
          /❌ Backup not found/,
          type: :error
        )

        result = commands.restore("/nonexistent/backup.json")

        expect(result).to be false
      end
    end

    context "with user confirmation" do
      it "cancels when user declines" do
        allow(commands).to receive(:display_message)
        expect(prompt).to receive(:yes?).with("Restore this backup?").and_return(false)
        expect(commands).to receive(:display_message).with("Cancelled", type: :warning)

        result = commands.restore("1")

        expect(result).to be false

        # Current config unchanged
        config = JSON.parse(File.read(devcontainer_path))
        expect(config["name"]).to eq("Current Config")
      end

      it "proceeds when forced" do
        allow(commands).to receive(:display_message)

        result = commands.restore("1", force: true)

        expect(result).to be true
      end
    end

    context "with backup creation" do
      it "creates backup before restoring by default" do
        allow(commands).to receive(:display_message)
        allow(prompt).to receive(:yes?).and_return(true)

        initial_backups = Dir.glob(File.join(backup_dir, "*.json")).size

        commands.restore("1")

        final_backups = Dir.glob(File.join(backup_dir, "*.json")).size
        expect(final_backups).to eq(initial_backups + 1)
      end

      it "skips backup when no_backup option set" do
        allow(commands).to receive(:display_message)
        allow(prompt).to receive(:yes?).and_return(true)

        initial_backups = Dir.glob(File.join(backup_dir, "*.json")).size

        commands.restore("1", no_backup: true)

        final_backups = Dir.glob(File.join(backup_dir, "*.json")).size
        expect(final_backups).to eq(initial_backups)
      end
    end
  end

  describe "private methods" do
    describe "#format_size" do
      it "formats bytes correctly" do
        size_formatter = commands.send(:method, :format_size)

        expect(size_formatter.call(0)).to eq("0 B")
        expect(size_formatter.call(500)).to eq("500.0 B")
        expect(size_formatter.call(1024)).to eq("1.0 KB")
        expect(size_formatter.call(1024 * 1024)).to eq("1.0 MB")
        expect(size_formatter.call(1024 * 1024 * 1024)).to eq("1.0 GB")
      end
    end

    describe "#normalize_features" do
      it "normalizes hash format" do
        features = {
          "ghcr.io/devcontainers/features/ruby:1" => {},
          "ghcr.io/devcontainers/features/node:1" => {}
        }

        result = commands.send(:normalize_features, features)

        expect(result).to eq(features)
      end

      it "normalizes array format" do
        features = [
          "ghcr.io/devcontainers/features/ruby:1",
          "ghcr.io/devcontainers/features/node:1"
        ]

        result = commands.send(:normalize_features, features)

        expect(result).to eq({
          "ghcr.io/devcontainers/features/ruby:1" => {},
          "ghcr.io/devcontainers/features/node:1" => {}
        })
      end

      it "handles nil" do
        result = commands.send(:normalize_features, nil)

        expect(result).to eq({})
      end
    end

    describe "#default_devcontainer_path" do
      it "returns standard path" do
        path = commands.send(:default_devcontainer_path)

        expect(path).to eq(File.join(project_dir, ".devcontainer", "devcontainer.json"))
      end
    end
  end

  describe "integration scenarios" do
    context "full workflow: create, backup, modify, restore" do
      it "handles complete lifecycle" do
        # Create initial config via aidp.yml
        create_aidp_yml({
          "devcontainer" => {
            "manage" => true,
            "custom_ports" => [{"number" => 3000, "label" => "App V1"}]
          },
          "providers" => {
            "anthropic" => {"enabled" => true}
          }
        })

        allow(commands).to receive(:display_message)

        # Apply initial
        commands.apply(force: true)
        expect(File.exist?(devcontainer_path)).to be true

        v1_config = JSON.parse(File.read(devcontainer_path))
        expect(v1_config["forwardPorts"]).to include(3000)

        # Modify config
        sleep 1.1  # Ensure unique backup timestamp
        create_aidp_yml({
          "devcontainer" => {
            "manage" => true,
            "custom_ports" => [
              {"number" => 3000, "label" => "App V2"},
              {"number" => 8080, "label" => "API"}
            ]
          },
          "providers" => {
            "anthropic" => {"enabled" => true}
          }
        })

        # Apply update (creates backup)
        commands.apply(force: true)

        v2_config = JSON.parse(File.read(devcontainer_path))
        # Should have both ports now
        expect(v2_config["forwardPorts"]).to include(3000, 8080)

        # Verify backup exists
        backup_dir = File.join(project_dir, ".aidp", "backups", "devcontainer")
        backups = Dir.glob(File.join(backup_dir, "devcontainer-*.json"))
        expect(backups.size).to eq(1)

        # Restore to version 1
        allow(prompt).to receive(:yes?).with("Restore this backup?").and_return(true)
        commands.restore("1", no_backup: true)

        restored_config = JSON.parse(File.read(devcontainer_path))
        # Restored should be the V1 config (only port 3000)
        expect(restored_config["forwardPorts"]).to include(3000)
        expect(restored_config["forwardPorts"]).not_to include(8080)
      end
    end
  end
end
