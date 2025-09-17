# frozen_string_literal: true
# encoding: utf-8

require "spec_helper"

RSpec.describe "Current CLI Commands", type: :aruba do
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

  describe "current CLI commands" do
    it "shows help information" do
      run_command("aidp --help")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("Usage: aidp [options]")
      expect(last_command_started.stdout).to include("Start the interactive TUI (default)")
      expect(last_command_started.stdout).to include("--help")
      expect(last_command_started.stdout).to include("--version")
    end

    it "shows version information" do
      run_command("aidp --version")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to match(/\d+\.\d+\.\d+/)
    end

    it "starts TUI by default" do
      run_command("aidp") do |cmd|
        # Send Ctrl-C after 1 second to exit TUI
        sleep 1
        Process.kill("INT", cmd.pid)
      end

      expect(last_command_started.stdout).to include("Press Ctrl+C to stop")
      expect(last_command_started.stdout).to include("Choose your mode")
    end
  end
end
