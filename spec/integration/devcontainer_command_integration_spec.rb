# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../../lib/aidp/cli/devcontainer_commands"
require_relative "../support/test_prompt"

RSpec.describe "DevcontainerCommand Integration", type: :integration do
  let(:project_dir) { Dir.mktmpdir }
  let(:test_prompt) { TestPrompt.new }
  let(:devcontainer_commands) do
    Aidp::CLI::DevcontainerCommands.new(project_dir: project_dir, prompt: test_prompt)
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "full workflow" do
    it "handles complete devcontainer lifecycle: diff, apply, backup, restore" do
      # 1. Create aidp.yml configuration
      config_dir = File.join(project_dir, ".aidp")
      FileUtils.mkdir_p(config_dir)
      config_data = {
        "devcontainer" => {
          "manage" => true,
          "custom_ports" => [
            {"number" => 8080, "label" => "App Server"}
          ]
        },
        "providers" => {
          "openai" => {
            "models" => ["gpt-4"]
          }
        },
        "work_loop" => {
          "test_commands" => [
            {"command" => "bundle exec rspec", "framework" => "rspec"}
          ]
        }
      }
      File.write(File.join(config_dir, "aidp.yml"), config_data.to_yaml)

      # 2. Test diff with no existing devcontainer (should warn, not error)
      result = devcontainer_commands.diff
      expect(result).to eq(false)  # No existing file to diff

      # 3. Apply configuration (force mode to skip confirmation)
      test_prompt.messages.clear
      result = devcontainer_commands.apply(force: true)
      expect(result).to be true

      # Verify devcontainer.json was created
      devcontainer_path = File.join(project_dir, ".devcontainer", "devcontainer.json")
      expect(File.exist?(devcontainer_path)).to be true

      # Parse and verify content
      devcontainer_config = JSON.parse(File.read(devcontainer_path))
      expect(devcontainer_config["name"]).to be_a(String)
      expect(devcontainer_config["forwardPorts"]).to include(8080)

      # 4. Modify the devcontainer.json manually
      devcontainer_config["customizations"] = {
        "vscode" => {
          "settings" => {
            "custom.setting" => true
          }
        }
      }
      File.write(devcontainer_path, JSON.pretty_generate(devcontainer_config))

      # 5. Create a backup
      backup_manager = Aidp::Setup::Devcontainer::BackupManager.new(project_dir)
      backup_path = backup_manager.create_backup(
        devcontainer_path,  # Use absolute path
        {reason: "manual_test", timestamp: Time.now.utc.iso8601}
      )
      expect(File.exist?(backup_path)).to be true

      # 6. List backups
      test_prompt.messages.clear
      result = devcontainer_commands.list_backups
      expect(result).to be true

      # 7. Apply again (should update, not create)
      File.write(devcontainer_path, JSON.pretty_generate({"name" => "old-config"}))
      test_prompt.messages.clear
      result = devcontainer_commands.apply(force: true, backup: false)
      expect(result).to be true

      # Verify it was updated
      updated_config = JSON.parse(File.read(devcontainer_path))
      expect(updated_config["forwardPorts"]).to include(8080)

      # 8. Restore from backup (restore uses 1-based indexing)
      test_prompt.messages.clear
      result = devcontainer_commands.restore("1", force: true, no_backup: true)
      expect(result).to be true

      # Verify restored content has the custom settings we added
      restored_config = JSON.parse(File.read(devcontainer_path))
      expect(restored_config.dig("customizations", "vscode", "settings", "custom.setting")).to eq(true)
    end

    it "handles dry-run mode without writing files" do
      # Create aidp.yml
      config_dir = File.join(project_dir, ".aidp")
      FileUtils.mkdir_p(config_dir)
      config_data = {
        "devcontainer" => {"manage" => true},
        "providers" => {"openai" => {"models" => ["gpt-4"]}}
      }
      File.write(File.join(config_dir, "aidp.yml"), config_data.to_yaml)

      # Apply with dry-run
      result = devcontainer_commands.apply(dry_run: true)
      expect(result).to be true

      # Verify no file was created
      devcontainer_path = File.join(project_dir, ".devcontainer", "devcontainer.json")
      expect(File.exist?(devcontainer_path)).to be false
    end

    it "validates backup index is numeric" do
      # Create a backup first
      config_dir = File.join(project_dir, ".aidp")
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, "aidp.yml"), {}.to_yaml)

      devcontainer_dir = File.join(project_dir, ".devcontainer")
      FileUtils.mkdir_p(devcontainer_dir)
      devcontainer_path = File.join(devcontainer_dir, "devcontainer.json")
      File.write(devcontainer_path, JSON.pretty_generate({"name" => "test"}))

      backup_manager = Aidp::Setup::Devcontainer::BackupManager.new(project_dir)
      backup_manager.create_backup(
        devcontainer_path,  # Use absolute path
        {reason: "test", timestamp: Time.now.utc.iso8601}
      )

      # Try to restore with invalid index (should handle gracefully)
      result = devcontainer_commands.restore("invalid", force: true)
      expect(result).to eq(false)  # Should fail gracefully
    end
  end

  describe "error handling" do
    it "handles missing aidp.yml gracefully" do
      # Don't create aidp.yml
      result = devcontainer_commands.diff
      expect(result).to eq(false)  # Should fail gracefully when no devcontainer exists
    end

    it "handles empty project directory" do
      # Project dir exists but is empty
      result = devcontainer_commands.list_backups
      expect(result).to be true  # Should still work, just show no backups
    end
  end

  describe "port detection" do
    it "detects ports from configuration and includes them in devcontainer" do
      # Create aidp.yml with custom ports
      config_dir = File.join(project_dir, ".aidp")
      FileUtils.mkdir_p(config_dir)
      config_data = {
        "devcontainer" => {
          "manage" => true,
          "custom_ports" => [
            {"number" => 3000, "label" => "Rails"},
            {"number" => 5432, "label" => "Postgres"}
          ]
        },
        "providers" => {"openai" => {"models" => ["gpt-4"]}}
      }
      File.write(File.join(config_dir, "aidp.yml"), config_data.to_yaml)

      # Apply
      result = devcontainer_commands.apply(force: true)
      expect(result).to be true

      # Verify devcontainer.json was created
      devcontainer_path = File.join(project_dir, ".devcontainer", "devcontainer.json")
      expect(File.exist?(devcontainer_path)).to be true

      # Verify ports are in devcontainer.json
      devcontainer_config = JSON.parse(File.read(devcontainer_path))

      expect(devcontainer_config["forwardPorts"]).to include(3000)
      expect(devcontainer_config["forwardPorts"]).to include(5432)

      expect(devcontainer_config["portsAttributes"]).to have_key("3000")
      expect(devcontainer_config["portsAttributes"]["3000"]["label"]).to eq("Rails")
      expect(devcontainer_config["portsAttributes"]["5432"]["label"]).to eq("Postgres")
    end
  end

  describe "merging behavior" do
    it "preserves user customizations when applying updates" do
      # Create initial devcontainer with custom settings
      devcontainer_dir = File.join(project_dir, ".devcontainer")
      FileUtils.mkdir_p(devcontainer_dir)
      initial_config = {
        "name" => "My Custom Name",
        "customizations" => {
          "vscode" => {
            "extensions" => ["custom.extension"]
          }
        },
        "forwardPorts" => [9000]
      }
      File.write(File.join(devcontainer_dir, "devcontainer.json"), JSON.pretty_generate(initial_config))

      # Create aidp.yml
      config_dir = File.join(project_dir, ".aidp")
      FileUtils.mkdir_p(config_dir)
      config_data = {
        "devcontainer" => {
          "manage" => true,
          "custom_ports" => [
            {"number" => 3000, "label" => "App"}
          ]
        },
        "providers" => {"openai" => {"models" => ["gpt-4"]}},
        "work_loop" => {
          "test_commands" => [
            {"command" => "bundle exec rspec", "framework" => "rspec"}
          ]
        }
      }
      File.write(File.join(config_dir, "aidp.yml"), config_data.to_yaml)

      # Apply (should merge, not replace)
      result = devcontainer_commands.apply(force: true)
      expect(result).to be true

      # Verify merge preserved user customizations
      devcontainer_path = File.join(project_dir, ".devcontainer", "devcontainer.json")
      merged_config = JSON.parse(File.read(devcontainer_path))

      # Custom name should be preserved
      expect(merged_config["name"]).to eq("My Custom Name")

      # Custom extension should be preserved
      expect(merged_config.dig("customizations", "vscode", "extensions")).to include("custom.extension")

      # New port should be added
      expect(merged_config["forwardPorts"]).to include(3000)

      # Old port should still be there
      expect(merged_config["forwardPorts"]).to include(9000)
    end
  end
end
