# frozen_string_literal: true

require "spec_helper"

RSpec.describe "TUI Dashboard", type: :aruba do
  before do
    # Create basic project structure
    create_directory("templates/EXECUTE")
    create_directory("templates/ANALYZE")
    create_directory(".aidp")
  end

  describe "kb show command" do
    it "shows knowledge base contents" do
      run_command("aidp kb show summary")

      expect(last_command_started).to be_successfully_executed
      # The command should run without error
    end
  end

  describe "status command" do
    it "shows enhanced status" do
      run_command("aidp status")

      expect(last_command_started).to be_successfully_executed
      expect(last_command_started.stdout).to include("AI Dev Pipeline Status")
      expect(last_command_started.stdout).to include("Execute Mode")
      expect(last_command_started.stdout).to include("Analyze Mode")
    end
  end

  describe "jobs command" do
    it "shows job management interface" do
      run_command("aidp jobs")

      expect(last_command_started).to be_successfully_executed
      # The jobs command should run without error
    end
  end

  describe "harness commands" do
    it "shows harness status" do
      run_command("aidp harness status")

      expect(last_command_started).to be_successfully_executed
      # The command should run without error
    end

    it "resets harness with confirmation" do
      run_command("aidp harness reset --mode analyze")

      expect(last_command_started).to be_successfully_executed
      # The command should run without error
    end
  end
end
