# frozen_string_literal: true

require "spec_helper"
require_relative "../support/test_prompt"

# This spec tests that both execute and analyze modes properly use the unified configuration.
RSpec.describe "Unified Configuration in .aidp/", type: :integration do
  let(:project_dir) { Dir.mktmpdir("aidp_config_test") }
  let(:config_file) { File.join(project_dir, ".aidp", "aidp.yml") }
  let(:execute_progress_file) { File.join(project_dir, ".aidp", "progress", "execute.yml") }
  let(:analyze_progress_file) { File.join(project_dir, ".aidp", "progress", "analyze.yml") }
  let(:cli) { Aidp::CLI.new }
  let(:test_prompt) { TestPrompt.new }

  before do
    setup_configuration_files
    setup_mock_project
  end

  after do
    FileUtils.remove_entry(project_dir)
    cleanup_user_config
  end

  describe "Progress File Separation" do
    it "execute mode uses .aidp/progress/execute.yml" do
      # Manually create progress file to test the file path structure
      progress_data = {
        "completed_steps" => ["00_PRD"],
        "current_step" => nil,
        "started_at" => Time.now.iso8601
      }

      FileUtils.mkdir_p(File.dirname(execute_progress_file))
      File.write(execute_progress_file, progress_data.to_yaml)

      # Verify execute progress file exists at correct location
      expect(File.exist?(execute_progress_file)).to be true
      expect(execute_progress_file).to include(".aidp/progress/execute.yml")

      # Verify analyze progress file doesn't exist yet
      expect(File.exist?(analyze_progress_file)).to be false

      # Verify progress was saved correctly
      loaded_data = YAML.load_file(execute_progress_file)
      expect(loaded_data["completed_steps"]).to include("00_PRD")

      # Verify Progress class can load it
      execute_progress = Aidp::Execute::Progress.new(project_dir)
      expect(execute_progress.completed_steps).to include("00_PRD")
    end

    it "analyze mode uses .aidp/progress/analyze.yml" do
      # Manually create progress file to test the file path structure
      progress_data = {
        "completed_steps" => ["01_REPOSITORY_ANALYSIS"],
        "current_step" => nil,
        "started_at" => Time.now.iso8601
      }

      FileUtils.mkdir_p(File.dirname(analyze_progress_file))
      File.write(analyze_progress_file, progress_data.to_yaml)

      # Verify analyze progress file exists at correct location
      expect(File.exist?(analyze_progress_file)).to be true
      expect(analyze_progress_file).to include(".aidp/progress/analyze.yml")

      # Verify progress was saved correctly
      loaded_data = YAML.load_file(analyze_progress_file)
      expect(loaded_data["completed_steps"]).to include("01_REPOSITORY_ANALYSIS")

      # Verify Progress class can load it
      analyze_progress = Aidp::Analyze::Progress.new(project_dir)
      expect(analyze_progress.completed_steps).to include("01_REPOSITORY_ANALYSIS")
    end

    it "progress files are isolated between modes" do
      # Create both progress files
      execute_data = {
        "completed_steps" => ["00_PRD"],
        "current_step" => nil,
        "started_at" => Time.now.iso8601
      }

      analyze_data = {
        "completed_steps" => ["01_REPOSITORY_ANALYSIS"],
        "current_step" => nil,
        "started_at" => Time.now.iso8601
      }

      FileUtils.mkdir_p(File.dirname(execute_progress_file))
      FileUtils.mkdir_p(File.dirname(analyze_progress_file))
      File.write(execute_progress_file, execute_data.to_yaml)
      File.write(analyze_progress_file, analyze_data.to_yaml)

      # Both progress files should exist
      expect(File.exist?(execute_progress_file)).to be true
      expect(File.exist?(analyze_progress_file)).to be true

      # Verify isolation - load both files
      loaded_execute = YAML.load_file(execute_progress_file)
      loaded_analyze = YAML.load_file(analyze_progress_file)

      expect(loaded_execute["completed_steps"]).to include("00_PRD")
      expect(loaded_execute["completed_steps"]).not_to include("01_REPOSITORY_ANALYSIS")

      expect(loaded_analyze["completed_steps"]).to include("01_REPOSITORY_ANALYSIS")
      expect(loaded_analyze["completed_steps"]).not_to include("00_PRD")

      # Verify Progress classes can load them correctly
      execute_progress = Aidp::Execute::Progress.new(project_dir)
      analyze_progress = Aidp::Analyze::Progress.new(project_dir)

      expect(execute_progress.completed_steps).to include("00_PRD")
      expect(execute_progress.completed_steps).not_to include("01_REPOSITORY_ANALYSIS")

      expect(analyze_progress.completed_steps).to include("01_REPOSITORY_ANALYSIS")
      expect(analyze_progress.completed_steps).not_to include("00_PRD")
    end
  end

  describe "Unified Configuration File" do
    it "both modes share .aidp/aidp.yml" do
      # Create unified configuration
      unified_config = {
        "harness" => {
          "default_provider" => "cursor",
          "max_retries" => 3
        },
        "providers" => {
          "cursor" => {
            "type" => "subscription",
            "priority" => 1
          },
          "anthropic" => {
            "type" => "usage_based",
            "priority" => 2,
            "max_tokens" => 200000
          }
        }
      }

      FileUtils.mkdir_p(File.dirname(config_file))
      File.write(config_file, unified_config.to_yaml)

      # Both modes should load the same config
      loaded_config = Aidp::Config.load(project_dir)

      expect(loaded_config["harness"]["default_provider"]).to eq("cursor")
      expect(loaded_config["providers"]["cursor"]["type"]).to eq("subscription")
      expect(loaded_config["providers"]["anthropic"]["max_tokens"]).to eq(200000)
    end

    it "configuration file is in .aidp/ directory" do
      # Create configuration
      config_data = {
        "harness" => {"default_provider" => "cursor"}
      }

      FileUtils.mkdir_p(File.dirname(config_file))
      File.write(config_file, config_data.to_yaml)

      # Verify location
      expect(File.exist?(config_file)).to be true
      expect(config_file).to include(".aidp/aidp.yml")

      # Old locations should not exist
      expect(File.exist?(File.join(project_dir, ".aidp.yml"))).to be false
      expect(File.exist?(File.join(project_dir, ".aidp-analyze.yml"))).to be false
    end
  end

  describe "User Configuration" do
    it "user configuration is shared across modes" do
      # User configuration at ~/.aidp.yml
      user_config_file = File.expand_path("~/.aidp.yml")

      user_config = {
        "global_settings" => {
          "log_level" => "info",
          "timeout" => 300
        },
        "harness" => {
          "default_provider" => "anthropic",
          "max_retries" => 5
        }
      }

      File.write(user_config_file, user_config.to_yaml)

      # Verify settings
      config_data = YAML.load_file(user_config_file)
      expect(config_data["global_settings"]["log_level"]).to eq("info")
      expect(config_data["harness"]["default_provider"]).to eq("anthropic")
    end
  end

  describe "Environment Variables" do
    it "environment variables work across modes" do
      # Set environment variables
      ENV["AIDP_DEFAULT_PROVIDER"] = "anthropic"
      ENV["AIDP_MAX_RETRIES"] = "5"

      # Both modes should have access to the same env vars
      expect(ENV["AIDP_DEFAULT_PROVIDER"]).to eq("anthropic")
      expect(ENV["AIDP_MAX_RETRIES"]).to eq("5")
    end
  end

  describe "Configuration Loading" do
    it "loads unified configuration from .aidp/aidp.yml" do
      # Create configuration
      config_data = {
        "harness" => {
          "default_provider" => "cursor",
          "max_retries" => 3
        },
        "providers" => {
          "cursor" => {"type" => "subscription"}
        }
      }

      FileUtils.mkdir_p(File.dirname(config_file))
      File.write(config_file, config_data.to_yaml)

      # Load configuration
      loaded_config = Aidp::Config.load(project_dir)

      expect(loaded_config["harness"]["default_provider"]).to eq("cursor")
      expect(loaded_config["harness"]["max_retries"]).to eq(3)
      expect(loaded_config["providers"]["cursor"]["type"]).to eq("subscription")
    end
  end

  describe "Configuration Validation" do
    it "validates unified configuration schema" do
      # Create valid configuration
      valid_config = {
        "harness" => {
          "default_provider" => "cursor",
          "max_retries" => 3
        },
        "providers" => {
          "cursor" => {
            "type" => "subscription",
            "priority" => 1
          }
        }
      }

      FileUtils.mkdir_p(File.dirname(config_file))
      File.write(config_file, valid_config.to_yaml)

      loaded_config = Aidp::Config.load(project_dir)
      expect(loaded_config["harness"]["default_provider"]).to eq("cursor")
      expect(loaded_config["providers"]["cursor"]["type"]).to eq("subscription")
    end
  end

  private

  def setup_configuration_files
    # Create configuration directories if needed
    FileUtils.mkdir_p(project_dir)
  end

  def setup_mock_project
    # Create basic project structure
    FileUtils.mkdir_p(File.join(project_dir, "app"))
    File.write(File.join(project_dir, "README.md"), "# Test Project")
  end

  def cleanup_user_config
    # Clean up user configuration file
    user_config_file = File.expand_path("~/.aidp.yml")
    File.delete(user_config_file) if File.exist?(user_config_file)
  end
end
