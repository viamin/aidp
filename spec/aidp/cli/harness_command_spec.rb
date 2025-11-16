# frozen_string_literal: true

require "spec_helper"
require "aidp/cli/harness_command"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::CLI::HarnessCommand do
  let(:temp_dir) { Dir.mktmpdir("aidp_harness_command_test") }
  let(:prompt) { instance_double(TTY::Prompt) }

  # Mock classes for dependency injection
  let(:runner_double) { instance_double(Aidp::Harness::Runner) }
  let(:runner_class) do
    class_double(Aidp::Harness::Runner).tap do |klass|
      allow(klass).to receive(:new).and_return(runner_double)
    end
  end

  let(:state_manager_double) { double("state_manager", reset_all: nil) }

  let(:command) do
    described_class.new(
      prompt: prompt,
      runner_class: runner_class,
      project_dir: temp_dir
    )
  end

  before do
    allow(prompt).to receive(:say)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#run with status subcommand" do
    let(:mock_status) do
      {
        harness: {
          state: "running",
          current_step: "test_step",
          current_provider: "cursor",
          duration: 120,
          user_input_count: 2,
          progress: {
            completed_steps: 3,
            total_steps: 5,
            next_step: "next_step"
          }
        },
        configuration: {
          default_provider: "cursor",
          fallback_providers: ["claude", "gemini"],
          max_retries: 2
        },
        provider_manager: {
          current_provider: "cursor",
          available_providers: ["cursor", "claude"],
          rate_limited_providers: [],
          total_switches: 0
        }
      }
    end

    before do
      allow(runner_double).to receive(:respond_to?).with(:detailed_status).and_return(true)
      allow(runner_double).to receive(:detailed_status).and_return(mock_status)
    end

    it "displays harness status for both modes" do
      expect(prompt).to receive(:say).with("🔧 Harness Status", color: :cyan)
      expect(runner_class).to receive(:new).with(temp_dir, :analyze, {}).and_return(runner_double)
      expect(runner_class).to receive(:new).with(temp_dir, :execute, {}).and_return(runner_double)
      allow(prompt).to receive(:say) # Allow other calls

      command.run([], subcommand: "status")
    end

    it "displays mode information" do
      expect(prompt).to receive(:say).with(/📋 Analyze Mode:/, color: :blue)
      expect(prompt).to receive(:say).with(/📋 Execute Mode:/, color: :blue)
      allow(prompt).to receive(:say) # Allow other calls

      command.run([], subcommand: "status")
    end

    it "displays progress information" do
      expect(prompt).to receive(:say).with(/Progress: 3\/5/, color: :green)
      allow(prompt).to receive(:say) # Allow other calls

      command.run([], subcommand: "status")
    end
  end

  describe "#run with reset subcommand" do
    before do
      allow(runner_double).to receive(:instance_variable_get).with(:@state_manager).and_return(state_manager_double)
    end

    context "with analyze mode" do
      it "resets harness state for analyze mode" do
        expect(runner_class).to receive(:new).with(temp_dir, :analyze, {}).and_return(runner_double)
        expect(state_manager_double).to receive(:reset_all)
        expect(prompt).to receive(:say).with("✅ Reset harness state for analyze mode", color: :green)
        allow(prompt).to receive(:say)

        command.run([], subcommand: "reset", options: {mode: "analyze"})
      end
    end

    context "with execute mode" do
      it "resets harness state for execute mode" do
        expect(runner_class).to receive(:new).with(temp_dir, :execute, {}).and_return(runner_double)
        expect(state_manager_double).to receive(:reset_all)
        expect(prompt).to receive(:say).with("✅ Reset harness state for execute mode", color: :green)
        allow(prompt).to receive(:say)

        command.run([], subcommand: "reset", options: {mode: "execute"})
      end
    end

    context "with default mode (analyze)" do
      it "uses analyze mode when no mode specified" do
        expect(runner_class).to receive(:new).with(temp_dir, :analyze, {}).and_return(runner_double)
        expect(state_manager_double).to receive(:reset_all)
        allow(prompt).to receive(:say)

        command.run([], subcommand: "reset", options: {})
      end
    end

    context "with invalid mode" do
      it "shows error for invalid mode" do
        expect(prompt).to receive(:say).with("❌ Invalid mode. Use 'analyze' or 'execute'", color: :red)
        allow(prompt).to receive(:say)

        command.run([], subcommand: "reset", options: {mode: "invalid"})
      end

      it "does not create a runner for invalid mode" do
        expect(runner_class).not_to receive(:new)
        allow(prompt).to receive(:say)

        command.run([], subcommand: "reset", options: {mode: "invalid"})
      end
    end
  end

  describe "#run with unknown subcommand" do
    it "displays error message" do
      expect(prompt).to receive(:say).with("Unknown harness subcommand: unknown", color: :red)
      allow(prompt).to receive(:say) # Allow help display

      result = command.run([], subcommand: "unknown")
      expect(result).to eq(1)
    end
  end

  describe "error handling" do
    context "when runner raises an error" do
      before do
        allow(runner_class).to receive(:new).and_raise(StandardError, "Connection failed")
      end

      it "handles errors gracefully in status command" do
        expect(prompt).to receive(:say).with("🔧 Harness Status", color: :cyan)
        allow(prompt).to receive(:say) # Allow other calls

        # Should not raise, should log and continue
        expect { command.run([], subcommand: "status") }.not_to raise_error
      end
    end

    context "when detailed_status is not available" do
      before do
        allow(runner_double).to receive(:respond_to?).with(:detailed_status).and_return(false)
      end

      it "shows unknown state" do
        expect(prompt).to receive(:say).with(/State: unknown/, color: :blue)
        allow(prompt).to receive(:say)

        command.run([], subcommand: "status")
      end
    end
  end
end
