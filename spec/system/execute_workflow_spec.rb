# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Execute Workflow with TUI", type: :aruba do
  before do
    # Create basic project structure
    create_directory("templates/EXECUTE")
    create_directory("templates/ANALYZE")
    create_directory(".aidp")

    # Create sample execute templates
    write_file("templates/EXECUTE/00_PRD.md", "# PRD Template\n\n## Questions\n- What is the main goal?\n- What are the requirements?")
    write_file("templates/EXECUTE/01_NFRS.md", "# NFRS Template\n\n## Questions\n- What is the priority level?\n- What are the constraints?")
  end

  describe "execute command" do
    it "starts execute workflow with TUI" do
      run_command("aidp execute")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("Starting enhanced TUI harness")
      expect(last_command_started.stdout).to include("Press Ctrl+C to stop")
      expect(last_command_started.stdout).to include("workflow selection options")
    end

    it "starts execute workflow in traditional mode" do
      run_command("aidp execute --no-harness")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("Available execute steps")
      expect(last_command_started.stdout).to include("Use 'aidp execute' without arguments")
    end

    it "runs specific execute step with TUI" do
      run_command("aidp execute 00_PRD")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("Running execute step '00_PRD' with enhanced TUI harness")
      expect(last_command_started.stdout).to include("progress indicators")
    end

    it "resets execute progress" do
      run_command("aidp execute --reset")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("Reset execute mode progress")
    end

    it "approves execute gate step" do
      run_command("aidp execute --approve 00_PRD")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("Approved execute step: 00_PRD")
    end
  end
end
