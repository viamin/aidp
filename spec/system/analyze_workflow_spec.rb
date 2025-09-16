# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Analyze Workflow with TUI", type: :aruba do
  before do
    # Create basic project structure
    create_directory("templates/EXECUTE")
    create_directory("templates/ANALYZE")
    create_directory(".aidp")

    # Create sample analyze templates
    write_file("templates/ANALYZE/01_REPOSITORY_ANALYSIS.md", "# Repository Analysis\n\n## Questions\n- What type of analysis?\n- What files to analyze?")
    write_file("templates/ANALYZE/02_ARCHITECTURE_ANALYSIS.md", "# Architecture Analysis\n\n## Questions\n- Select configuration file\n- What components to analyze?")
    write_file("templates/ANALYZE/03_TEST_ANALYSIS.md", "# Test Analysis\n\n## Questions\n- Test coverage threshold\n- What tests to run?")
  end

  describe "analyze command" do
    it "starts analyze workflow with TUI" do
      run_command("aidp analyze")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("Starting analyze mode with enhanced TUI harness")
      expect(last_command_started.stdout).to include("Press Ctrl+C to stop")
      expect(last_command_started.stdout).to include("progress indicators")
    end

    it "starts analyze workflow in traditional mode" do
      run_command("aidp analyze --no-harness")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("Available analyze steps")
      expect(last_command_started.stdout).to include("Use 'aidp analyze' without arguments")
    end

    it "runs specific analyze step with TUI" do
      run_command("aidp analyze 01_REPOSITORY_ANALYSIS")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("Running analyze step '01_REPOSITORY_ANALYSIS' with enhanced TUI harness")
      expect(last_command_started.stdout).to include("progress indicators")
    end

    it "runs next analyze step" do
      run_command("aidp analyze next")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("Running analyze step")
      expect(last_command_started.stdout).to include("progress indicators")
    end

    it "runs analyze step by number" do
      run_command("aidp analyze 01")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("Running analyze step '01_REPOSITORY_ANALYSIS'")
      expect(last_command_started.stdout).to include("progress indicators")
    end

    it "resets analyze progress" do
      run_command("aidp analyze --reset")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("Reset analyze mode progress")
    end

    it "approves analyze gate step" do
      run_command("aidp analyze --approve 01_REPOSITORY_ANALYSIS")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("Approved analyze step: 01_REPOSITORY_ANALYSIS")
    end

    it "runs analyze with background jobs" do
      run_command("aidp analyze --background")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("Starting analyze mode with enhanced TUI harness")
      expect(last_command_started.stdout).to include("background job indicators")
    end
  end
end
