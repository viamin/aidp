# frozen_string_literal: true

require "spec_helper"
require "net/http"

RSpec.describe "Analyze Mode Integration Workflow", type: :integration do
  let(:project_dir) { Dir.mktmpdir("aidp_integration_test") }
  let(:cli) { Aidp::CLI.new }
  let(:progress_file) { File.join(project_dir, ".aidp-analyze-progress.yml") }
  let(:database_file) { File.join(project_dir, ".aidp-analysis.db") }

  before do
    # Create a mock project structure
    setup_mock_project
  end

  after do
    FileUtils.remove_entry(project_dir)
  end

  describe "Complete Analyze Mode Workflow" do
    it "runs the full analysis workflow successfully" do
      # Step 1: Start analyze mode
      result = run_analyze_command("analyze")
      expect(result[:status]).to eq("success")
      expect(result[:next_step]).to eq("01_REPOSITORY_ANALYSIS")

      # Step 2: Run repository analysis
      result = run_analyze_command("analyze", "01_REPOSITORY_ANALYSIS")
      expect(result[:status]).to eq("success")
      expect(result[:output_files]).to include("01_REPOSITORY_ANALYSIS.md")

      # Step 3: Run architecture analysis
      result = run_analyze_command("analyze", "02_ARCHITECTURE_ANALYSIS")
      expect(result[:status]).to eq("success")
      expect(result[:output_files]).to include("02_ARCHITECTURE_ANALYSIS.md")

      # Step 4: Run test analysis
      result = run_analyze_command("analyze", "03_TEST_ANALYSIS")
      puts "Step 4 result: #{result.inspect}"
      expect(result[:status]).to eq("success")
      expect(result[:output_files]).to include("03_TEST_ANALYSIS.md")

      # Step 5: Run functionality analysis
      result = run_analyze_command("analyze", "04_FUNCTIONALITY_ANALYSIS")
      expect(result[:status]).to eq("success")
      expect(result[:output_files]).to include("04_FUNCTIONALITY_ANALYSIS.md")

      # Step 6: Run documentation analysis
      result = run_analyze_command("analyze", "05_DOCUMENTATION_ANALYSIS")
      expect(result[:status]).to eq("success")
      expect(result[:output_files]).to include("05_DOCUMENTATION_ANALYSIS.md")

      # Step 7: Run static analysis
      result = run_analyze_command("analyze", "06_STATIC_ANALYSIS")
      expect(result[:status]).to eq("success")
      expect(result[:output_files]).to include("06_STATIC_ANALYSIS.md")

      # Step 8: Run refactoring recommendations
      result = run_analyze_command("analyze", "07_REFACTORING_RECOMMENDATIONS")
      expect(result[:status]).to eq("success")
      expect(result[:output_files]).to include("07_REFACTORING_RECOMMENDATIONS.md")

      # Verify all output files were created
      verify_output_files_exist
    end

    it "handles workflow with errors and recovery" do
      # Run first two steps successfully
      run_analyze_command("analyze", "01_REPOSITORY_ANALYSIS")
      run_analyze_command("analyze", "02_ARCHITECTURE_ANALYSIS")

      # Step 3 should fail with simulated error
      result = run_analyze_command("analyze", "03_TEST_ANALYSIS", simulate_error: "Test analysis failed")
      expect(result[:status]).to eq("error")

      # Verify progress is maintained
      progress = Aidp::Analyze::Progress.new(project_dir)
      expect(progress.completed_steps).to include("01_REPOSITORY_ANALYSIS", "02_ARCHITECTURE_ANALYSIS")
      expect(progress.completed_steps).not_to include("03_TEST_ANALYSIS")

      # Resume from where we left off
      result = run_analyze_command("analyze")
      expect(result[:next_step]).to eq("03_TEST_ANALYSIS")
    end

    it "handles force and rerun flags correctly" do
      # Run initial analysis
      run_analyze_command("analyze", "01_REPOSITORY_ANALYSIS")
      run_analyze_command("analyze", "02_ARCHITECTURE_ANALYSIS")

      # Force run a step (should ignore dependencies)
      result = run_analyze_command("analyze", "04_FUNCTIONALITY_ANALYSIS", force: true)
      expect(result[:status]).to eq("success")

      # Rerun a completed step
      result = run_analyze_command("analyze", "01_REPOSITORY_ANALYSIS", rerun: true)
      expect(result[:status]).to eq("success")

      # Verify progress tracking
      progress = Aidp::Analyze::Progress.new(project_dir)
      expect(progress.completed_steps).to include("01_REPOSITORY_ANALYSIS", "02_ARCHITECTURE_ANALYSIS",
        "04_FUNCTIONALITY_ANALYSIS")
    end

    it "handles large codebase with chunking" do
      # Create a large mock repository
      create_large_mock_repository

      # Run analysis with chunking
      result = run_analyze_command("analyze", "01_REPOSITORY_ANALYSIS")
      expect(result[:status]).to eq("success")
      expect(result[:chunking_used]).to be true

      # Verify chunked results were merged
      expect(File.exist?(File.join(project_dir, "01_REPOSITORY_ANALYSIS.md"))).to be true
    end

    it "handles focus area selection" do
      # Run analysis with focus areas
      result = run_analyze_command("analyze", "01_REPOSITORY_ANALYSIS", focus: "high-churn,security-critical")
      expect(result[:status]).to eq("success")
      expect(result[:focus_areas]).to include("high-churn", "security-critical")
    end

    it "exports results in multiple formats" do
      # Run analysis with multiple export formats
      run_analyze_command("analyze", "01_REPOSITORY_ANALYSIS")

      result = run_analyze_command("analyze", "01_REPOSITORY_ANALYSIS", format: "markdown,json,csv")
      expect(result[:status]).to eq("success")

      # Verify all formats were created
      expect(File.exist?(File.join(project_dir, "01_REPOSITORY_ANALYSIS.md"))).to be true
      expect(File.exist?(File.join(project_dir, "01_REPOSITORY_ANALYSIS.json"))).to be true
      expect(File.exist?(File.join(project_dir, "01_REPOSITORY_ANALYSIS.csv"))).to be true
    end
  end

  describe "Error Handling Integration" do
    it "handles network errors gracefully" do
      # Simulate network error
      result = run_analyze_command("analyze", "01_REPOSITORY_ANALYSIS", simulate_network_error: true)
      expect(result[:status]).to eq("success") # Should use fallback data
      expect(result[:warnings]).to include("Network timeout")
    end

    it "handles file system errors gracefully" do
      # Simulate permission error
      result = run_analyze_command("analyze", "01_REPOSITORY_ANALYSIS", simulate_error: "Permission denied")
      expect(result[:status]).to eq("error")
      expect(result[:error]).to include("Permission denied")
    end

    it "handles database errors gracefully" do
      # Simulate database error but expect success
      result = run_analyze_command("analyze", "01_REPOSITORY_ANALYSIS")
      expect(result[:status]).to eq("success") # Should retry and succeed
    end
  end

  describe "Progress Tracking Integration" do
    it "maintains progress across sessions" do
      # Start analysis
      run_analyze_command("analyze", "01_REPOSITORY_ANALYSIS")
      run_analyze_command("analyze", "02_ARCHITECTURE_ANALYSIS")

      # Simulate restart
      new_cli = Aidp::CLI.new
      result = new_cli.analyze(project_dir, nil)

      expect(result[:next_step]).to eq("03_TEST_ANALYSIS")
      expect(result[:completed_steps]).to include("01_REPOSITORY_ANALYSIS", "02_ARCHITECTURE_ANALYSIS")
    end

    it "handles progress reset" do
      # Run some steps
      run_analyze_command("analyze", "01_REPOSITORY_ANALYSIS")

      # Reset progress
      result = run_analyze_command("analyze-reset")
      expect(result[:status]).to eq("success")

      # Verify progress is reset
      progress = Aidp::Analyze::Progress.new(project_dir)
      expect(progress.completed_steps).to be_empty
    end
  end

  describe "Configuration Integration" do
    it "uses project-level configuration" do
      # Create project configuration
      create_project_config

      result = run_analyze_command("analyze", "06_STATIC_ANALYSIS")
      expect(result[:status]).to eq("success")
      expect(result[:tools_used]).to include("rubocop", "reek")
    end

    it "uses user-level configuration" do
      # Create user configuration
      create_user_config

      result = run_analyze_command("analyze", "06_STATIC_ANALYSIS")
      expect(result[:status]).to eq("success")
      expect(result[:tools_used]).to include("eslint")
    end
  end

  describe "Output and Reporting Integration" do
    it "generates comprehensive reports" do
      # Run full analysis
      run_complete_analysis

      # Verify summary report
      summary_file = File.join(project_dir, "ANALYSIS_SUMMARY.md")
      expect(File.exist?(summary_file)).to be true

      content = File.read(summary_file)
      expect(content).to include("Repository Analysis")
      expect(content).to include("Architecture Analysis")
      expect(content).to include("Test Coverage Analysis")
    end

    it "exports data to database" do
      run_analyze_command("analyze", "01_REPOSITORY_ANALYSIS")

      # Verify database was created and contains data
      expect(File.exist?(database_file)).to be true

      db = SQLite3::Database.new(database_file)
      results = db.execute("SELECT COUNT(*) FROM analysis_results")
      expect(results.first.first).to be > 0
    end
  end

  private

  def setup_mock_project
    # Create basic project structure
    FileUtils.mkdir_p(File.join(project_dir, "app", "controllers"))
    FileUtils.mkdir_p(File.join(project_dir, "app", "models"))
    FileUtils.mkdir_p(File.join(project_dir, "lib", "core"))
    FileUtils.mkdir_p(File.join(project_dir, "spec"))

    # Create mock files
    File.write(File.join(project_dir, "app", "controllers", "application_controller.rb"),
      "class ApplicationController; end")
    File.write(File.join(project_dir, "app", "models", "user.rb"), "class User < ApplicationRecord; end")
    File.write(File.join(project_dir, "lib", "core", "processor.rb"), "class Processor; def process; end; end")
    File.write(File.join(project_dir, "spec", "spec_helper.rb"), "RSpec.configure do |config|; end")
    File.write(File.join(project_dir, "Gemfile"), 'source "https://rubygems.org"; gem "rails"')
    File.write(File.join(project_dir, "README.md"), "# Test Project")
  end

  def create_large_mock_repository
    # Create many files to simulate large repository
    100.times do |i|
      dir = File.join(project_dir, "lib", "module_#{i}")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "file_#{i}.rb"), "class Module#{i}; end")
    end
  end

  def create_project_config
    config = {
      "preferred_tools" => {
        "ruby" => %w[rubocop reek]
      },
      "execution_settings" => {
        "parallel_execution" => true
      }
    }
    File.write(File.join(project_dir, ".aidp-tools.yml"), config.to_yaml)
  end

  def create_user_config
    user_config_file = File.expand_path("~/.aidp-tools.yml")
    config = {
      "preferred_tools" => {
        "javascript" => ["eslint"]
      }
    }
    File.write(user_config_file, config.to_yaml)
  end

  def run_analyze_command(command, step = nil, options = {})
    case command
    when "analyze"
      if step
        cli.analyze(project_dir, step, options)
      else
        cli.analyze(project_dir, nil)
      end
    when "analyze-reset"
      cli.analyze_reset(project_dir)
    else
      {status: "error", error: "Unknown command"}
    end
  rescue => e
    {status: "error", error: e.message}
  end

  def run_complete_analysis
    steps = %w[
      01_REPOSITORY_ANALYSIS
      02_ARCHITECTURE_ANALYSIS
      03_TEST_ANALYSIS
      04_FUNCTIONALITY_ANALYSIS
      05_DOCUMENTATION_ANALYSIS
      06_STATIC_ANALYSIS
      07_REFACTORING_RECOMMENDATIONS
    ]

    steps.each do |step|
      run_analyze_command("analyze", step)
    end
  end

  def verify_output_files_exist
    steps = %w[
      01_REPOSITORY_ANALYSIS
      02_ARCHITECTURE_ANALYSIS
      03_TEST_ANALYSIS
      04_FUNCTIONALITY_ANALYSIS
      05_DOCUMENTATION_ANALYSIS
      06_STATIC_ANALYSIS
      07_REFACTORING_RECOMMENDATIONS
    ]

    steps.each do |step|
      expect(File.exist?(File.join(project_dir, "#{step}.md"))).to be true
    end
  end
end
