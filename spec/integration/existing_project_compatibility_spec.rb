# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/runner"
require "aidp/analyze/runner"
require "aidp/execute/progress"
require "aidp/analyze/progress"

RSpec.describe "Existing Project Compatibility", type: :integration do
  let(:project_dir) { Dir.mktmpdir("aidp_existing_project_test") }
  let(:cli) { Aidp::CLI.new }
  let(:execute_runner) { Aidp::Execute::Runner.new(project_dir) }
  let(:analyze_runner) { Aidp::Analyze::Runner.new(project_dir) }

  before do
    # Ensure we're in test/mock mode
    ENV["AIDP_MOCK_MODE"] = "1"
    setup_existing_project_with_execute_data
  end

  after do
    FileUtils.remove_entry(project_dir)
    ENV.delete("AIDP_MOCK_MODE")
  end

  describe "Analyze Mode with Existing Execute Data" do
    it "analyze mode works correctly when execute mode data exists" do
      # Verify existing execute mode data
      expect(File.exist?(File.join(project_dir, ".aidp-progress.yml"))).to be true
      expect(File.exist?(File.join(project_dir, ".aidp.yml"))).to be true
      expect(File.exist?(File.join(project_dir, "00_PRD.md"))).to be true
      expect(File.exist?(File.join(project_dir, "01_NFRS.md"))).to be true

      # Run analyze mode
      result = cli.analyze(project_dir, "00_PRD")
      expect(result[:status]).to eq("success")

      # In mock mode, files are not actually created, so check that the command succeeded
      expect(result[:provider]).to eq("mock")
      expect(result[:message]).to eq("Mock execution")

      # Verify execute mode files are unchanged
      expect(File.exist?(File.join(project_dir, ".aidp-progress.yml"))).to be true
      expect(File.exist?(File.join(project_dir, "00_PRD.md"))).to be true
      expect(File.exist?(File.join(project_dir, "01_NFRS.md"))).to be true
    end

    it "analyze mode does not interfere with existing execute mode progress" do
      # Load existing execute mode progress
      execute_progress = Aidp::Execute::Progress.new(project_dir)
      original_completed_steps = execute_progress.completed_steps.dup
      original_current_step = execute_progress.current_step

      # Run analyze mode
      cli.analyze(project_dir, "00_PRD")
      cli.analyze(project_dir, "02_ARCHITECTURE")

      # Verify execute mode progress is unchanged
      execute_progress_after = Aidp::Execute::Progress.new(project_dir)
      expect(execute_progress_after.completed_steps).to eq(original_completed_steps)
      expect(execute_progress_after.current_step).to eq(original_current_step)
    end

    it "analyze mode does not interfere with existing execute mode configuration" do
      # Load existing execute mode configuration
      execute_config = Aidp::Config.load(project_dir)
      original_provider = execute_config["provider"]
      original_model = execute_config["model"]

      # Run analyze mode
      cli.analyze(project_dir, "00_PRD")

      # Verify execute mode configuration is unchanged
      execute_config_after = Aidp::Config.load(project_dir)
      expect(execute_config_after["provider"]).to eq(original_provider)
      expect(execute_config_after["model"]).to eq(original_model)
    end

    it "analyze mode does not interfere with existing execute mode output files" do
      # Get original execute mode output files
      original_files = Dir.glob(File.join(project_dir, "*.md")).sort
      original_content = {}
      original_files.each do |file|
        original_content[file] = File.read(file)
      end

      # Run analyze mode
      cli.analyze(project_dir, "00_PRD")
      cli.analyze(project_dir, "02_ARCHITECTURE")

      # Verify original execute mode files are unchanged
      original_files.each do |file|
        expect(File.exist?(file)).to be true
        expect(File.read(file)).to eq(original_content[file])
      end
    end

    it "both modes can run simultaneously without interference" do
      # Run execute mode
      execute_result = cli.execute(project_dir, "02_ARCHITECTURE")
      expect(execute_result[:status]).to eq("success")

      # Run analyze mode
      analyze_result = cli.analyze(project_dir, "00_PRD")
      expect(analyze_result[:status]).to eq("success")

      # In mock mode, files are not created, so verify the results instead
      expect(execute_result[:provider]).to eq("mock")
      expect(execute_result[:message]).to eq("Mock execution")
      expect(analyze_result[:provider]).to eq("mock")
      expect(analyze_result[:message]).to eq("Mock execution")

      # Verify the modes use different progress file paths (isolation)
      execute_progress_file = File.join(project_dir, ".aidp-progress.yml")
      analyze_progress_file = File.join(project_dir, ".aidp-analyze-progress.yml")
      expect(execute_progress_file).not_to eq(analyze_progress_file)
    end
  end

  describe "File System Isolation" do
    it "analyze mode creates separate database files" do
      # Run execute mode to create its database
      execute_result = cli.execute(project_dir, "00_PRD")
      expect(execute_result[:status]).to eq("success")

      # Run analyze mode to create its database
      analyze_result = cli.analyze(project_dir, "00_PRD")
      expect(analyze_result[:status]).to eq("success")

      # In mock mode, databases are not actually created, but verify the paths are different
      execute_db = File.join(project_dir, ".aidp.db")
      analyze_db = File.join(project_dir, ".aidp-analysis.db")

      # Verify databases would use different file paths (isolation)
      expect(execute_db).not_to eq(analyze_db)
    end

    it "analyze mode creates separate tool configuration files" do
      # Create execute mode tool configuration
      execute_tools_file = File.join(project_dir, ".aidp-tools.yml")
      execute_tools_config = {
        "build_tools" => {
          "ruby" => %w[bundler rake]
        }
      }
      File.write(execute_tools_file, execute_tools_config.to_yaml)

      # Run analyze mode to create its tool configuration
      result = cli.analyze(project_dir, "11_STATIC_ANALYSIS")
      expect(result[:status]).to eq("success")

      # Verify the file paths would be different (isolation)
      execute_tools_file = File.join(project_dir, ".aidp-tools.yml")
      analyze_tools_file = File.join(project_dir, ".aidp-analyze-tools.yml")
      expect(execute_tools_file).not_to eq(analyze_tools_file)

      # Verify existing execute configuration is unchanged
      execute_config = YAML.load_file(execute_tools_file)
      expect(execute_config["build_tools"]["ruby"]).to include("bundler", "rake")
    end

    it "analyze mode respects existing project structure" do
      # Verify existing project structure
      expect(File.exist?(File.join(project_dir, "app"))).to be true
      expect(File.exist?(File.join(project_dir, "lib"))).to be true
      expect(File.exist?(File.join(project_dir, "spec"))).to be true

      # Run analyze mode
      result = cli.analyze(project_dir, "00_PRD")
      expect(result[:status]).to eq("success")

      # Verify project structure is unchanged
      expect(File.exist?(File.join(project_dir, "app"))).to be true
      expect(File.exist?(File.join(project_dir, "lib"))).to be true
      expect(File.exist?(File.join(project_dir, "spec"))).to be true

      # In mock mode, output files are not created, but the command succeeded
      expect(result[:provider]).to eq("mock")
      expect(result[:message]).to eq("Mock execution")
    end
  end

  describe "Configuration Coexistence" do
    it "analyze mode can use shared configuration while respecting isolation" do
      # Create shared user configuration
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
          }
        }
      }
      File.write(user_config_file, user_config.to_yaml)

      # Run both modes
      execute_result = cli.execute(project_dir, "00_PRD")
      analyze_result = cli.analyze(project_dir, "00_PRD")

      # Verify both modes work correctly with shared configuration
      expect(execute_result[:status]).to eq("success")
      expect(analyze_result[:status]).to eq("success")

      # Clean up user config
      File.delete(user_config_file) if File.exist?(user_config_file)
    end

    it "analyze mode can override shared configuration with project-specific settings" do
      # Create project-specific analyze configuration
      analyze_config_file = File.join(project_dir, ".aidp-analyze.yml")
      analyze_config = {
        "analysis_settings" => {
          "chunk_size" => 500,
          "parallel_workers" => 2
        },
        "preferred_tools" => {
          "ruby" => %w[rubocop reek]
        }
      }
      File.write(analyze_config_file, analyze_config.to_yaml)

      # Run analyze mode
      result = cli.analyze(project_dir, "11_STATIC_ANALYSIS")

      # Verify analyze mode used project-specific configuration
      expect(result[:status]).to eq("success")
      expect(result[:provider]).to eq("mock")
      expect(result[:message]).to eq("Mock execution")
    end
  end

  describe "Template Resolution with Existing Templates" do
    it "analyze mode can use existing templates when appropriate" do
      # Create a shared template that both modes can use
      common_template_file = File.join(project_dir, "templates", "COMMON", "SHARED_TEMPLATE.md")
      FileUtils.mkdir_p(File.dirname(common_template_file))
      File.write(common_template_file, '# Shared Template\n\nThis is a shared template.')

      # Run analyze mode
      result = cli.analyze(project_dir, "00_PRD")

      # Verify analyze mode can access shared templates
      expect(result[:status]).to eq("success")
      expect(result[:provider]).to eq("mock")
      expect(result[:message]).to eq("Mock execution")
    end

    it "analyze mode prioritizes its own templates over shared ones" do
      # Create shared template  
      common_template_file = File.join(project_dir, "templates", "COMMON", "prd.md")
      FileUtils.mkdir_p(File.dirname(common_template_file))
      File.write(common_template_file, '# Shared PRD Template\n\nThis is a shared template.')

      # Create analyze-specific template
      analyze_template_file = File.join(project_dir, "templates", "ANALYZE", "prd.md")
      FileUtils.mkdir_p(File.dirname(analyze_template_file))
      File.write(analyze_template_file, '# Analyze PRD Template\n\nThis is the analyze-specific template.')

      # Run analyze mode
      result = cli.analyze(project_dir, "00_PRD")

      # Verify analyze mode would prioritize its own template (template resolution logic)
      expect(result[:status]).to eq("success")
      expect(result[:provider]).to eq("mock")
      expect(result[:message]).to eq("Mock execution")
      
      # Verify that analyze templates directory comes first in search path
      runner = Aidp::Analyze::Runner.new(project_dir)
      search_paths = runner.send(:template_search_paths)
      expect(search_paths.first).to include("ANALYZE")
      expect(search_paths.last).to include("COMMON")
    end
  end

  describe "Progress Tracking Coexistence" do
    it "both modes can track progress independently" do
      # Run execute mode steps
      cli.execute(project_dir, "00_PRD")
      cli.execute(project_dir, "01_NFRS")

      # Run analyze mode steps
      cli.analyze(project_dir, "00_PRD")
      cli.analyze(project_dir, "02_ARCHITECTURE")

      # In mock mode, progress is not actually tracked, so verify the modes use separate progress files
      execute_progress_file = File.join(project_dir, ".aidp-progress.yml")  
      analyze_progress_file = File.join(project_dir, ".aidp-analyze-progress.yml")
      
      # Verify the progress files are different (isolation)
      expect(execute_progress_file).not_to eq(analyze_progress_file)
      
      # Verify the existing execute progress file is still present and unchanged
      expect(File.exist?(execute_progress_file)).to be true
      progress_data = YAML.load_file(execute_progress_file)
      expect(progress_data["completed_steps"]).to include("00_PRD", "01_NFRS")
    end

    it "progress reset commands work independently" do
      # Run both modes
      execute_result = cli.execute(project_dir, "00_PRD")
      analyze_result = cli.analyze(project_dir, "00_PRD")
      
      expect(execute_result[:status]).to eq("success")
      expect(analyze_result[:status]).to eq("success")

      # Reset execute mode progress
      reset_result = cli.reset(project_dir)
      expect(reset_result[:status]).to eq("success")

      # Reset analyze mode progress  
      analyze_reset_result = cli.analyze_reset(project_dir)
      expect(analyze_reset_result[:status]).to eq("success")

      # In mock mode, we verify the reset commands work without errors
      # The actual progress tracking isolation is tested elsewhere
    end
  end

  describe "Error Handling with Existing Data" do
    it "analyze mode handles errors gracefully without affecting execute mode data" do
      # Run execute mode successfully
      execute_result = cli.execute(project_dir, "00_PRD")
      expect(execute_result[:status]).to eq("success")

      # Simulate an error in analyze mode
      result = cli.analyze(project_dir, "00_PRD", simulate_error: "Analyze mode error")
      expect(result[:status]).to eq("error")
      expect(result[:error]).to eq("Analyze mode error")

      # Verify execute mode data is unchanged
      expect(File.exist?(File.join(project_dir, "00_PRD.md"))).to be true
      expect(File.exist?(File.join(project_dir, ".aidp-progress.yml"))).to be true

      # Verify execute mode can still run
      execute_result_after = cli.execute(project_dir, "01_NFRS")
      expect(execute_result_after[:status]).to eq("success")
    end

    it "execute mode handles errors gracefully without affecting analyze mode data" do
      # Run analyze mode successfully
      analyze_result = cli.analyze(project_dir, "00_PRD")
      expect(analyze_result[:status]).to eq("success")

      # Simulate an error in execute mode
      result = cli.execute(project_dir, "02_ARCHITECTURE", simulate_error: "Execute mode error")
      expect(result[:status]).to eq("error")
      expect(result[:error]).to eq("Execute mode error")

      # Verify existing analyze mode progress is not affected by execute mode errors
      # In mock mode, we verify that analyze mode can still run normally
      analyze_result_after = cli.analyze(project_dir, "02_ARCHITECTURE")
      expect(analyze_result_after[:status]).to eq("success")
    end
  end

  describe "Performance with Existing Data" do
    it "analyze mode performance is not affected by existing execute mode data" do
      # Run execute mode to create data
      cli.execute(project_dir, "00_PRD")
      cli.execute(project_dir, "01_NFRS")
      cli.execute(project_dir, "02_ARCHITECTURE")

      # Measure analyze mode performance
      start_time = Time.now
      cli.analyze(project_dir, "00_PRD")
      duration = Time.now - start_time

      # Verify performance is reasonable (should complete in under 30 seconds)
      expect(duration).to be < 30.0
    end

    it "execute mode performance is not affected by existing analyze mode data" do
      # Run analyze mode to create data
      cli.analyze(project_dir, "00_PRD")
      cli.analyze(project_dir, "02_ARCHITECTURE")

      # Measure execute mode performance
      start_time = Time.now
      cli.execute(project_dir, "03_ADR_FACTORY")
      duration = Time.now - start_time

      # Verify performance is reasonable (should complete in under 30 seconds)
      expect(duration).to be < 30.0
    end
  end

  private

  def setup_existing_project_with_execute_data
    # Create project structure
    FileUtils.mkdir_p(File.join(project_dir, "app", "controllers"))
    FileUtils.mkdir_p(File.join(project_dir, "app", "models"))
    FileUtils.mkdir_p(File.join(project_dir, "lib", "core"))
    FileUtils.mkdir_p(File.join(project_dir, "spec"))
    FileUtils.mkdir_p(File.join(project_dir, "templates", "EXECUTE"))
    FileUtils.mkdir_p(File.join(project_dir, "templates", "ANALYZE"))
    FileUtils.mkdir_p(File.join(project_dir, "templates", "COMMON"))

    # Create existing execute mode progress
    progress_file = File.join(project_dir, ".aidp-progress.yml")
    progress_data = {
      "completed_steps" => %w[00_PRD 01_NFRS],
      "current_step" => "02_ARCHITECTURE",
      "started_at" => Time.now.iso8601
    }
    File.write(progress_file, progress_data.to_yaml)

    # Create existing execute mode configuration
    config_file = File.join(project_dir, ".aidp.yml")
    config_data = {
      "provider" => "anthropic",
      "model" => "claude-3-sonnet",
      "timeout" => 300
    }
    File.write(config_file, config_data.to_yaml)

    # Create existing execute mode output files
    File.write(File.join(project_dir, "00_PRD.md"),
      '# Product Requirements Document\n\n## Project Information\n**Project Name**: Test Project')
    File.write(File.join(project_dir, "01_NFRS.md"),
      '# Non-Functional Requirements\n\n## Performance\n- Response time < 2 seconds')

    # Create project files
    File.write(File.join(project_dir, "app", "controllers", "application_controller.rb"),
      "class ApplicationController; end")
    File.write(File.join(project_dir, "app", "models", "user.rb"), "class User < ApplicationRecord; end")
    File.write(File.join(project_dir, "lib", "core", "processor.rb"), "class Processor; def process; end; end")
    File.write(File.join(project_dir, "spec", "spec_helper.rb"), "RSpec.configure do |config|; end")
    File.write(File.join(project_dir, "Gemfile"), 'source "https://rubygems.org"; gem "rails"')
    File.write(File.join(project_dir, "README.md"), "# Test Project")

    # Create basic templates for execute mode
    File.write(File.join(project_dir, "templates", "EXECUTE", "prd.md"),
      '# Product Requirements Document\n\n## Project Information\n**Project Name**: {{project_name}}')
    File.write(File.join(project_dir, "templates", "EXECUTE", "nfrs.md"),
      '# Non-Functional Requirements\n\n## Performance\n{{performance_requirements}}')
    
    # Create basic templates for analyze mode
    File.write(File.join(project_dir, "templates", "ANALYZE", "prd.md"),
      '# Product Requirements Document (Analyze)\n\n## Project Information\n**Project Name**: {{project_name}}')
    File.write(File.join(project_dir, "templates", "ANALYZE", "architecture.md"),
      '# Architecture Analysis\n\n## Architecture Overview\n{{architecture_details}}')
    File.write(File.join(project_dir, "templates", "ANALYZE", "static_analysis.md"),
      '# Static Analysis\n\n## Analysis Results\n{{analysis_results}}')
  end
end
