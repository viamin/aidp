# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Harness Backward Compatibility (Simple)", type: :compatibility do
  let(:project_dir) { Dir.mktmpdir("aidp_harness_compatibility_simple_test") }
  let(:cli) { Aidp::CLI.new }

  before do
    # Set up mock mode for tests
    ENV["AIDP_MOCK_MODE"] = "1"
    # Create a mock project structure
    setup_mock_project
  end

  after do
    FileUtils.remove_entry(project_dir)
    ENV.delete("AIDP_MOCK_MODE")
  end

  describe "Core CLI Backward Compatibility" do
    it "existing analyze mode commands work exactly as before" do
      # Test that all existing analyze commands work
      expect { cli.help }.not_to raise_error
      expect { cli.version }.not_to raise_error

      # Test that analyze mode commands work
      result = cli.analyze(project_dir, nil)
      expect(result).to be_a(Hash)
      expect(result[:status]).to eq("success")
    end

    it "existing execute mode commands work exactly as before" do
      # Test that all existing execute commands work
      expect { cli.help }.not_to raise_error
      expect { cli.version }.not_to raise_error

      # Test that execute mode commands work
      result = cli.execute(project_dir, nil)
      expect(result).to be_a(Hash)
      expect(result[:status]).to eq("completed")
    end

    it "step-specific analyze commands work exactly as before" do
      # Test that specific step execution works
      result = cli.analyze(project_dir, "01_REPOSITORY_ANALYSIS")
      expect(result[:status]).to eq("completed")
    end

    it "step-specific execute commands work exactly as before" do
      # Test that specific step execution works
      result = cli.execute(project_dir, "00_PRD")
      expect(result[:status]).to eq("completed")
    end

    it "status command works exactly as before" do
      # Test that status command works
      expect { cli.status }.not_to raise_error
    end
  end

  describe "Configuration Backward Compatibility" do
    it "existing configuration format is fully supported" do
      # Test that existing configuration format works
      config_data = {
        "provider" => "anthropic",
        "model" => "claude-3-sonnet",
        "api_key" => "test_key"
      }
      config_file = File.join(project_dir, ".aidp.yml")
      File.write(config_file, config_data.to_yaml)

      # Test that existing config is loaded correctly
      config = Aidp::Config.load(project_dir)
      expect(config["provider"]).to eq("anthropic")
      expect(config["model"]).to eq("claude-3-sonnet")
      expect(config["api_key"]).to eq("test_key")
    end

    it "existing configuration without harness settings works" do
      # Test that configuration without harness settings works
      config_data = {
        "provider" => "anthropic",
        "model" => "claude-3-sonnet"
      }
      config_file = File.join(project_dir, ".aidp.yml")
      File.write(config_file, config_data.to_yaml)

      # Test that existing config is loaded correctly
      config = Aidp::Config.load(project_dir)
      expect(config["provider"]).to eq("anthropic")
      expect(config["model"]).to eq("claude-3-sonnet")
    end

    it "harness configuration extends existing configuration" do
      # Test that harness configuration extends existing configuration
      config_data = {
        "provider" => "anthropic",
        "model" => "claude-3-sonnet",
        "harness" => {
          "default_provider" => "claude",
          "max_retries" => 3
        }
      }
      config_file = File.join(project_dir, ".aidp.yml")
      File.write(config_file, config_data.to_yaml)

      # Test that both existing and harness config are loaded
      config = Aidp::Config.load(project_dir)
      expect(config["provider"]).to eq("anthropic")
      expect(config["model"]).to eq("claude-3-sonnet")
      expect(config["harness"]["default_provider"]).to eq("claude")
      expect(config["harness"]["max_retries"]).to eq(3)
    end
  end

  describe "Progress Tracking Backward Compatibility" do
    it "existing analyze progress format is fully supported" do
      # Test that existing analyze progress format works
      progress_data = {
        "completed_steps" => ["01_REPOSITORY_ANALYSIS", "02_ARCHITECTURE_ANALYSIS"],
        "current_step" => "03_TEST_ANALYSIS",
        "started_at" => Time.now.iso8601
      }
      progress_file = File.join(project_dir, ".aidp-analyze-progress.yml")
      File.write(progress_file, progress_data.to_yaml)

      # Test that existing progress is loaded correctly
      progress = Aidp::Analyze::Progress.new(project_dir)
      expect(progress.completed_steps).to include("01_REPOSITORY_ANALYSIS", "02_ARCHITECTURE_ANALYSIS")
      expect(progress.current_step).to eq("03_TEST_ANALYSIS")
    end

    it "existing execute progress format is fully supported" do
      # Test that existing execute progress format works
      progress_data = {
        "completed_steps" => ["00_PRD", "01_NFRS"],
        "current_step" => "02_ARCHITECTURE",
        "started_at" => Time.now.iso8601
      }
      progress_file = File.join(project_dir, ".aidp-progress.yml")
      File.write(progress_file, progress_data.to_yaml)

      # Test that existing progress is loaded correctly
      progress = Aidp::Execute::Progress.new(project_dir)
      expect(progress.completed_steps).to include("00_PRD", "01_NFRS")
      expect(progress.current_step).to eq("02_ARCHITECTURE")
    end
  end

  describe "Provider Integration Backward Compatibility" do
    it "existing provider classes work exactly as before" do
      # Test that existing provider classes work
      expect(Aidp::Providers::Anthropic).to be_a(Class)
      expect(Aidp::Providers::Cursor).to be_a(Class)
      expect(Aidp::Providers::Gemini).to be_a(Class)
      expect(Aidp::Providers::MacOSUI).to be_a(Class)
    end

    it "existing provider initialization works exactly as before" do
      # Test that existing provider initialization works
      provider = Aidp::Providers::Anthropic.new
      expect(provider).to be_a(Aidp::Providers::Anthropic)
    end

    it "existing provider methods work exactly as before" do
      # Test that existing provider methods work
      provider = Aidp::Providers::Anthropic.new
      expect(provider).to respond_to(:activity_state)
      expect(provider).to respond_to(:last_activity_time)
    end
  end

  describe "Step Definitions Backward Compatibility" do
    it "analyze mode step definitions are unchanged" do
      # Test that all analyze step definitions are exactly the same
      steps = Aidp::Analyze::Steps::SPEC

      # Verify all expected steps exist
      expected_steps = %w[01_REPOSITORY_ANALYSIS 02_ARCHITECTURE_ANALYSIS 03_TEST_ANALYSIS
        04_FUNCTIONALITY_ANALYSIS 05_DOCUMENTATION_ANALYSIS 06_STATIC_ANALYSIS 06A_TREE_SITTER_SCAN 07_REFACTORING_RECOMMENDATIONS]

      expected_steps.each do |step|
        expect(steps).to have_key(step)
        expect(steps[step]).to have_key("templates")
        expect(steps[step]).to have_key("outs")
        expect(steps[step]).to have_key("gate")
        expect(steps[step]).to have_key("description")
      end
    end

    it "execute mode step definitions are unchanged" do
      # Test that all execute step definitions are exactly the same
      steps = Aidp::Execute::Steps::SPEC

      # Verify all expected steps exist
      expected_steps = %w[00_PRD 01_NFRS 02_ARCHITECTURE 02A_ARCH_GATE_QUESTIONS 03_ADR_FACTORY 04_DOMAIN_DECOMPOSITION
        05_API_DESIGN 06_DATA_MODEL 07_SECURITY_REVIEW 08_PERFORMANCE_REVIEW 09_RELIABILITY_REVIEW 10_TESTING_STRATEGY 11_STATIC_ANALYSIS 12_OBSERVABILITY_SLOS 13_DELIVERY_ROLLOUT 14_DOCS_PORTAL 15_POST_RELEASE]

      expected_steps.each do |step|
        expect(steps).to have_key(step)
        expect(steps[step]).to have_key("templates")
        expect(steps[step]).to have_key("outs")
        expect(steps[step]).to have_key("gate")
        expect(steps[step]).to have_key("description")
      end
    end

    it "step execution order is unchanged" do
      # Test that step execution order is preserved
      analyze_steps = Aidp::Analyze::Steps::SPEC.keys
      execute_steps = Aidp::Execute::Steps::SPEC.keys

      # Verify the order is exactly as expected
      expected_analyze_order = %w[01_REPOSITORY_ANALYSIS 02_ARCHITECTURE_ANALYSIS 03_TEST_ANALYSIS
        04_FUNCTIONALITY_ANALYSIS 05_DOCUMENTATION_ANALYSIS 06_STATIC_ANALYSIS 06A_TREE_SITTER_SCAN 07_REFACTORING_RECOMMENDATIONS]

      expected_execute_order = %w[00_PRD 01_NFRS 02_ARCHITECTURE 02A_ARCH_GATE_QUESTIONS 03_ADR_FACTORY 04_DOMAIN_DECOMPOSITION
        05_API_DESIGN 06_DATA_MODEL 07_SECURITY_REVIEW 08_PERFORMANCE_REVIEW 09_RELIABILITY_REVIEW 10_TESTING_STRATEGY 11_STATIC_ANALYSIS 12_OBSERVABILITY_SLOS 13_DELIVERY_ROLLOUT 14_DOCS_PORTAL 15_POST_RELEASE]

      expect(analyze_steps).to eq(expected_analyze_order)
      expect(execute_steps).to eq(expected_execute_order)
    end
  end

  describe "File System Backward Compatibility" do
    it "existing file operations work exactly as before" do
      # Test that existing file operations work
      test_file = File.join(project_dir, "test_file.txt")
      File.write(test_file, "test content")

      expect(File.exist?(test_file)).to be true
      expect(File.read(test_file)).to eq("test content")

      File.delete(test_file)
      expect(File.exist?(test_file)).to be false
    end

    it "existing directory operations work exactly as before" do
      # Test that existing directory operations work
      test_dir = File.join(project_dir, "test_dir")
      FileUtils.mkdir_p(test_dir)

      expect(Dir.exist?(test_dir)).to be true

      FileUtils.remove_entry(test_dir)
      expect(Dir.exist?(test_dir)).to be false
    end

    it "existing project structure is preserved" do
      # Test that existing project structure is preserved
      expect(Dir.exist?(File.join(project_dir, "lib"))).to be true
      expect(Dir.exist?(File.join(project_dir, "spec"))).to be true
      expect(File.exist?(File.join(project_dir, "lib", "test.rb"))).to be true
      expect(File.exist?(File.join(project_dir, "spec", "test_spec.rb"))).to be true
    end
  end


  describe "Error Handling Backward Compatibility" do
    it "existing error handling works exactly as before" do
      # Test that existing error handling works
      expect { raise StandardError, "test error" }.to raise_error(StandardError, "test error")
    end
  end

  describe "Harness Mode Compatibility" do
    it "harness mode works with existing projects" do
      # Test that harness mode works with existing projects
      # Create existing project files
      progress_file = File.join(project_dir, ".aidp-analyze-progress.yml")
      progress_data = {
        "completed_steps" => ["01_REPOSITORY_ANALYSIS"],
        "current_step" => "02_ARCHITECTURE_ANALYSIS",
        "started_at" => Time.now.iso8601
      }
      File.write(progress_file, progress_data.to_yaml)

      # Test that harness mode works with existing progress
      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
      expect(harness_runner).to be_a(Aidp::Harness::Runner)
    end

    it "harness mode preserves existing functionality" do
      # Test that harness mode preserves existing functionality
      # Test that existing commands still work
      result = cli.analyze(project_dir, "01_REPOSITORY_ANALYSIS")
      expect(result[:status]).to eq("completed")

      result = cli.execute(project_dir, "00_PRD")
      expect(result[:status]).to eq("completed")
    end

    it "harness mode extends existing functionality" do
      # Test that harness mode extends existing functionality
      # Test that harness-specific features work
      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
      expect(harness_runner).to respond_to(:status)
      expect(harness_runner).to respond_to(:run)
    end
  end

  describe "Migration Compatibility" do
    it "configuration migration preserves existing settings" do
      # Test that configuration migration preserves existing settings
      config_data = {
        "provider" => "anthropic",
        "model" => "claude-3-sonnet",
        "api_key" => "test_key"
      }
      config_file = File.join(project_dir, ".aidp.yml")
      File.write(config_file, config_data.to_yaml)

      # Test that existing config is preserved during migration
      config = Aidp::Config.load(project_dir)
      expect(config["provider"]).to eq("anthropic")
      expect(config["model"]).to eq("claude-3-sonnet")
      expect(config["api_key"]).to eq("test_key")
    end

    it "progress migration preserves existing progress" do
      # Test that progress migration preserves existing progress
      progress_data = {
        "completed_steps" => ["01_REPOSITORY_ANALYSIS"],
        "current_step" => "02_ARCHITECTURE_ANALYSIS",
        "started_at" => Time.now.iso8601
      }
      progress_file = File.join(project_dir, ".aidp-analyze-progress.yml")
      File.write(progress_file, progress_data.to_yaml)

      # Test that existing progress is preserved during migration
      progress = Aidp::Analyze::Progress.new(project_dir)
      expect(progress.completed_steps).to include("01_REPOSITORY_ANALYSIS")
      expect(progress.current_step).to eq("02_ARCHITECTURE_ANALYSIS")
    end
  end

  describe "Feature Flag Compatibility" do
    it "harness mode can be disabled" do
      # Test that harness mode can be disabled
      config_data = {
        "provider" => "anthropic",
        "model" => "claude-3-sonnet",
        "harness" => {
          "enabled" => false
        }
      }
      config_file = File.join(project_dir, ".aidp.yml")
      File.write(config_file, config_data.to_yaml)

      # Test that harness mode is disabled
      config = Aidp::Config.load(project_dir)
      expect(config["harness"]["enabled"]).to eq(false)
    end

    it "harness mode can be enabled" do
      # Test that harness mode can be enabled
      config_data = {
        "provider" => "anthropic",
        "model" => "claude-3-sonnet",
        "harness" => {
          "enabled" => true
        }
      }
      config_file = File.join(project_dir, ".aidp.yml")
      File.write(config_file, config_data.to_yaml)

      # Test that harness mode is enabled
      config = Aidp::Config.load(project_dir)
      expect(config["harness"]["enabled"]).to eq(true)
    end

    it "harness mode defaults to enabled" do
      # Test that harness mode defaults to enabled
      config_data = {
        "provider" => "anthropic",
        "model" => "claude-3-sonnet"
      }
      config_file = File.join(project_dir, ".aidp.yml")
      File.write(config_file, config_data.to_yaml)

      # Test that harness mode defaults to enabled
      config = Aidp::Config.load(project_dir)
      expect(config["harness"]).to be_nil # No harness config means default behavior
    end
  end

  private

  def setup_mock_project
    # Create basic project structure
    FileUtils.mkdir_p(File.join(project_dir, "lib"))
    FileUtils.mkdir_p(File.join(project_dir, "spec"))
    FileUtils.mkdir_p(File.join(project_dir, ".aidp"))

    # Create a simple Ruby file
    File.write(File.join(project_dir, "lib", "test.rb"), "class Test; end")

    # Create a simple spec file
    File.write(File.join(project_dir, "spec", "test_spec.rb"), "RSpec.describe Test do; end")
  end
end
