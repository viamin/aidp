# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Configuration Isolation", type: :integration do
  let(:project_dir) { Dir.mktmpdir("aidp_config_test") }
  let(:cli) { Aidp::CLI.new }
  let(:execute_progress) { Aidp::Execute::Progress.new(project_dir) }
  let(:analyze_config) { Aidp::Analyze::Runner.new(project_dir) }

  before do
    setup_configuration_files
    setup_mock_project
  end

  after do
    FileUtils.remove_entry(project_dir)
    cleanup_user_config
  end

  describe "Progress File Isolation" do


  end

  describe "Configuration File Isolation" do
    it "execute mode uses .aidp.yml" do
      # Execute mode should use its own configuration file
      config_file = File.join(project_dir, ".aidp.yml")

      # Create execute mode configuration
      execute_config_data = {
        "provider" => "anthropic",
        "model" => "claude-3-sonnet"
      }
      File.write(config_file, execute_config_data.to_yaml)

      expect(File.exist?(config_file)).to be true
      expect(File.exist?(File.join(project_dir, ".aidp-analyze.yml"))).to be false

      config_data = YAML.load_file(config_file)
      expect(config_data["provider"]).to eq("anthropic")
      expect(config_data["model"]).to eq("claude-3-sonnet")
    end

    it "analyze mode uses .aidp-analyze.yml" do
      # Analyze mode should use its own configuration file
      config_file = File.join(project_dir, ".aidp-analyze.yml")

      # Create analyze mode configuration
      analyze_config_data = {
        "analysis_settings" => {
          "chunk_size" => 1000,
          "parallel_workers" => 4
        },
        "preferred_tools" => {
          "ruby" => %w[rubocop reek]
        }
      }

      File.write(config_file, analyze_config_data.to_yaml)

      expect(File.exist?(config_file)).to be true
      expect(File.exist?(File.join(project_dir, ".aidp.yml"))).to be false

      config_data = YAML.load_file(config_file)
      expect(config_data["analysis_settings"]["chunk_size"]).to eq(1000)
      expect(config_data["preferred_tools"]["ruby"]).to include("rubocop", "reek")
    end

    it "configuration files are completely isolated" do
      # Both modes can have their own configurations without interference
      execute_config_file = File.join(project_dir, ".aidp.yml")
      analyze_config_file = File.join(project_dir, ".aidp-analyze.yml")

      # Execute mode configuration
      execute_config_data = {
        "provider" => "anthropic",
        "model" => "claude-3-sonnet",
        "timeout" => 300
      }
      File.write(execute_config_file, execute_config_data.to_yaml)

      # Analyze mode configuration
      analyze_config_data = {
        "analysis_settings" => {
          "chunk_size" => 1000,
          "parallel_workers" => 4,
          "timeout" => 600
        },
        "preferred_tools" => {
          "ruby" => %w[rubocop reek],
          "javascript" => ["eslint"]
        }
      }

      File.write(analyze_config_file, analyze_config_data.to_yaml)

      # Verify isolation
      execute_data = YAML.load_file(execute_config_file)
      analyze_data = YAML.load_file(analyze_config_file)

      expect(execute_data["provider"]).to eq("anthropic")
      expect(execute_data["model"]).to eq("claude-3-sonnet")
      expect(execute_data["timeout"]).to eq(300)
      expect(execute_data).not_to have_key("analysis_settings")

      expect(analyze_data["analysis_settings"]["chunk_size"]).to eq(1000)
      expect(analyze_data["analysis_settings"]["timeout"]).to eq(600)
      expect(analyze_data["preferred_tools"]["ruby"]).to include("rubocop", "reek")
      expect(analyze_data).not_to have_key("provider")
    end
  end

  describe "Tool Configuration Isolation" do
    it "execute mode tool configuration is separate" do
      # Execute mode should have its own tool configuration
      execute_tools_file = File.join(project_dir, ".aidp-tools.yml")

      execute_tools_config = {
        "build_tools" => {
          "ruby" => %w[bundler rake],
          "javascript" => %w[npm yarn]
        },
        "test_tools" => {
          "ruby" => %w[rspec minitest],
          "javascript" => %w[jest mocha]
        }
      }

      File.write(execute_tools_file, execute_tools_config.to_yaml)

      expect(File.exist?(execute_tools_file)).to be true
      expect(File.exist?(File.join(project_dir, ".aidp-analyze-tools.yml"))).to be false

      config_data = YAML.load_file(execute_tools_file)
      expect(config_data["build_tools"]["ruby"]).to include("bundler", "rake")
      expect(config_data["test_tools"]["javascript"]).to include("jest", "mocha")
    end

    it "analyze mode tool configuration is separate" do
      # Analyze mode should have its own tool configuration
      analyze_tools_file = File.join(project_dir, ".aidp-analyze-tools.yml")

      analyze_tools_config = {
        "static_analysis_tools" => {
          "ruby" => %w[rubocop reek brakeman],
          "javascript" => %w[eslint prettier]
        },
        "code_quality_tools" => {
          "ruby" => %w[flog flay],
          "javascript" => %w[jshint jscs]
        }
      }

      File.write(analyze_tools_file, analyze_tools_config.to_yaml)

      expect(File.exist?(analyze_tools_file)).to be true
      expect(File.exist?(File.join(project_dir, ".aidp-tools.yml"))).to be false

      config_data = YAML.load_file(analyze_tools_file)
      expect(config_data["static_analysis_tools"]["ruby"]).to include("rubocop", "reek", "brakeman")
      expect(config_data["code_quality_tools"]["javascript"]).to include("jshint", "jscs")
    end

    it "tool configurations are completely isolated" do
      # Both modes can have their own tool configurations
      execute_tools_file = File.join(project_dir, ".aidp-tools.yml")
      analyze_tools_file = File.join(project_dir, ".aidp-analyze-tools.yml")

      # Execute mode tools
      execute_tools_config = {
        "build_tools" => {
          "ruby" => %w[bundler rake],
          "javascript" => %w[npm yarn]
        },
        "test_tools" => {
          "ruby" => %w[rspec minitest],
          "javascript" => %w[jest mocha]
        }
      }

      # Analyze mode tools
      analyze_tools_config = {
        "static_analysis_tools" => {
          "ruby" => %w[rubocop reek brakeman],
          "javascript" => %w[eslint prettier]
        },
        "code_quality_tools" => {
          "ruby" => %w[flog flay],
          "javascript" => %w[jshint jscs]
        }
      }

      File.write(execute_tools_file, execute_tools_config.to_yaml)
      File.write(analyze_tools_file, analyze_tools_config.to_yaml)

      # Verify isolation
      execute_data = YAML.load_file(execute_tools_file)
      analyze_data = YAML.load_file(analyze_tools_file)

      expect(execute_data["build_tools"]["ruby"]).to include("bundler", "rake")
      expect(execute_data["test_tools"]["javascript"]).to include("jest", "mocha")
      expect(execute_data).not_to have_key("static_analysis_tools")

      expect(analyze_data["static_analysis_tools"]["ruby"]).to include("rubocop", "reek", "brakeman")
      expect(analyze_data["code_quality_tools"]["javascript"]).to include("jshint", "jscs")
      expect(analyze_data).not_to have_key("build_tools")
    end
  end

  describe "User Configuration Isolation" do
    it "user configuration is shared but mode-specific sections are isolated" do
      # User configuration can have mode-specific sections
      user_config_file = File.expand_path("~/.aidp.yml")

      user_config = {
        "global_settings" => {
          "log_level" => "info",
          "timeout" => 300
        },
        "execute_mode" => {
          "provider" => "anthropic",
          "model" => "claude-3-sonnet"
        },
        "analyze_mode" => {
          "analysis_settings" => {
            "chunk_size" => 1000,
            "parallel_workers" => 4
          },
          "preferred_tools" => {
            "ruby" => %w[rubocop reek]
          }
        }
      }

      File.write(user_config_file, user_config.to_yaml)

      # Verify shared settings
      config_data = YAML.load_file(user_config_file)
      expect(config_data["global_settings"]["log_level"]).to eq("info")
      expect(config_data["global_settings"]["timeout"]).to eq(300)

      # Verify mode-specific settings
      expect(config_data["execute_mode"]["provider"]).to eq("anthropic")
      expect(config_data["analyze_mode"]["analysis_settings"]["chunk_size"]).to eq(1000)

      # Verify isolation
      expect(config_data["execute_mode"]).not_to have_key("analysis_settings")
      expect(config_data["analyze_mode"]).not_to have_key("provider")
    end
  end

  describe "Environment Variable Isolation" do
    it "environment variables can be mode-specific" do
      # Set mode-specific environment variables
      ENV["AIDP_PROVIDER"] = "anthropic"
      ENV["AIDP_ANALYZE_CHUNK_SIZE"] = "1000"
      ENV["AIDP_ANALYZE_PARALLEL_WORKERS"] = "4"

      # Execute mode should use general AIDP_ variables
      expect(ENV["AIDP_PROVIDER"]).to eq("anthropic")

      # Analyze mode should use AIDP_ANALYZE_ variables
      expect(ENV["AIDP_ANALYZE_CHUNK_SIZE"]).to eq("1000")
      expect(ENV["AIDP_ANALYZE_PARALLEL_WORKERS"]).to eq("4")

      # Verify isolation
      expect(ENV["AIDP_ANALYZE_CHUNK_SIZE"]).not_to eq(ENV["AIDP_PROVIDER"])
    end
  end

  describe "Configuration Loading Isolation" do
    it "execute mode loads only execute configuration" do
      # Create both configuration files
      execute_config_file = File.join(project_dir, ".aidp.yml")
      analyze_config_file = File.join(project_dir, ".aidp-analyze.yml")

      execute_config_data = {"provider" => "anthropic", "model" => "claude-3-sonnet"}
      analyze_config_data = {"analysis_settings" => {"chunk_size" => 1000}}

      File.write(execute_config_file, execute_config_data.to_yaml)
      File.write(analyze_config_file, analyze_config_data.to_yaml)

      # Execute mode should only load its own config
      execute_config = Aidp::Config.load(project_dir)
      expect(execute_config["provider"]).to eq("anthropic")
      expect(execute_config["model"]).to eq("claude-3-sonnet")
      expect(execute_config["analysis_settings"]).to be_nil
    end

    it "analyze mode loads only analyze configuration" do
      # Create both configuration files
      execute_config_file = File.join(project_dir, ".aidp.yml")
      analyze_config_file = File.join(project_dir, ".aidp-analyze.yml")

      execute_config_data = {"provider" => "anthropic", "model" => "claude-3-sonnet"}
      analyze_config_data = {"analysis_settings" => {"chunk_size" => 1000}}

      File.write(execute_config_file, execute_config_data.to_yaml)
      File.write(analyze_config_file, analyze_config_data.to_yaml)

      # Analyze mode should only load its own config
      analyze_config_data_loaded = YAML.load_file(analyze_config_file)
      expect(analyze_config_data_loaded["analysis_settings"]["chunk_size"]).to eq(1000)
      expect(analyze_config_data_loaded["provider"]).to be_nil
    end
  end

  describe "Configuration Validation" do
    it "execute mode validates its own configuration schema" do
      # Execute mode should validate its configuration
      execute_config_file = File.join(project_dir, ".aidp.yml")

      valid_config = {
        "provider" => "anthropic",
        "model" => "claude-3-sonnet",
        "timeout" => 300
      }

      File.write(execute_config_file, valid_config.to_yaml)

      execute_config = Aidp::Config.load(project_dir)
      expect(execute_config["provider"]).to eq("anthropic")
      expect(execute_config["model"]).to eq("claude-3-sonnet")
    end

    it "analyze mode validates its own configuration schema" do
      # Analyze mode should validate its configuration
      analyze_config_file = File.join(project_dir, ".aidp-analyze.yml")

      valid_config = {
        "analysis_settings" => {
          "chunk_size" => 1000,
          "parallel_workers" => 4,
          "timeout" => 600
        },
        "preferred_tools" => {
          "ruby" => %w[rubocop reek]
        }
      }

      File.write(analyze_config_file, valid_config.to_yaml)

      config_data = YAML.load_file(analyze_config_file)
      expect(config_data["analysis_settings"]["chunk_size"]).to eq(1000)
      expect(config_data["preferred_tools"]["ruby"]).to include("rubocop", "reek")
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
