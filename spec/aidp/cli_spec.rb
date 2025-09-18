# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "stringio"

RSpec.describe Aidp::CLI do
  let(:temp_dir) { Dir.mktmpdir }
  let(:cli) { described_class.new }

  # Mock TUI components to prevent interactive prompts
  let(:mock_tui) { instance_double(Aidp::Harness::UI::EnhancedTUI) }
  let(:mock_workflow_selector) { instance_double(Aidp::Harness::UI::EnhancedWorkflowSelector) }
  let(:mock_harness_runner) { instance_double(Aidp::Harness::EnhancedRunner) }

  before do
    # Mock TUI components to prevent interactive prompts
    allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(mock_tui)
    allow(Aidp::Harness::UI::EnhancedWorkflowSelector).to receive(:new).and_return(mock_workflow_selector)
    allow(Aidp::Harness::EnhancedRunner).to receive(:new).and_return(mock_harness_runner)

    # Mock TUI methods
    allow(mock_tui).to receive(:start_display_loop)
    allow(mock_tui).to receive(:stop_display_loop)
    allow(mock_tui).to receive(:show_message)
    allow(mock_tui).to receive(:single_select).and_return("🔬 Analyze Mode - Analyze your codebase for insights and recommendations")

    # Mock workflow selector
    allow(mock_workflow_selector).to receive(:select_workflow).and_return({
      workflow_type: :simple,
      steps: ["01_REPOSITORY_ANALYSIS"],
      user_input: {}
    })

    # Mock harness runner
    allow(mock_harness_runner).to receive(:run).and_return({
      status: "completed",
      message: "Test completed"
    })
  end

  # Helper method to capture stdout
  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#display_harness_result" do
    it "displays completed status" do
      result = {status: "completed", message: "All done"}

      output = capture_stdout do
        cli.send(:display_harness_result, result)
      end

      expect(output).to include("✅ Harness completed successfully!")
    end

    it "displays stopped status" do
      result = {status: "stopped", message: "User stopped"}

      output = capture_stdout do
        cli.send(:display_harness_result, result)
      end

      expect(output).to include("⏹️  Harness stopped by user")
    end

    it "displays error status" do
      result = {status: "error", message: "Something went wrong"}

      output = capture_stdout do
        cli.send(:display_harness_result, result)
      end

      # Error message is now handled by the harness, not the CLI
      expect(output).to eq("")
    end

    it "displays unknown status" do
      result = {status: "unknown", message: "Unknown state"}

      output = capture_stdout do
        cli.send(:display_harness_result, result)
      end

      expect(output).to include("🔄 Harness finished")
    end
  end

  describe "#format_duration" do
    it "formats seconds correctly" do
      expect(cli.send(:format_duration, 30)).to eq("30s")
    end

    it "formats minutes and seconds" do
      expect(cli.send(:format_duration, 90)).to eq("1m 30s")
    end

    it "formats hours, minutes and seconds" do
      expect(cli.send(:format_duration, 3661)).to eq("1h 1m 1s")
    end

    it "handles zero duration" do
      expect(cli.send(:format_duration, 0)).to eq("0s")
    end

    it "handles negative duration" do
      expect(cli.send(:format_duration, -10)).to eq("0s")
    end
  end

  describe "harness status command" do
    let(:mock_harness_runner) { double("harness_runner") }
    let(:mock_state_manager) { double("state_manager") }

    before do
      allow(Aidp::Harness::Runner).to receive(:new).and_return(mock_harness_runner)
      allow(mock_harness_runner).to receive(:detailed_status).and_return({
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
      })
    end

    it "displays harness status for both modes" do
      output = capture_stdout do
        cli.harness_status
      end

      expect(output).to include("🔧 Harness Status")
    end

    it "displays harness status for specific mode" do
      output = capture_stdout do
        cli.harness_status
      end

      expect(output).to include("📋 Analyze Mode:")
    end
  end

  describe "harness reset command" do
    let(:mock_harness_runner) { double("harness_runner") }
    let(:mock_state_manager) { double("state_manager") }

    before do
      allow(Aidp::Harness::Runner).to receive(:new).and_return(mock_harness_runner)
      allow(mock_harness_runner).to receive(:instance_variable_get).with(:@state_manager).and_return(mock_state_manager)
      allow(mock_state_manager).to receive(:reset_all)
    end

    it "resets harness state for analyze mode" do
      allow(cli).to receive(:options).and_return({mode: "analyze"})
      expect(mock_state_manager).to receive(:reset_all)

      output = capture_stdout do
        cli.harness_reset
      end

      expect(output).to include("✅ Reset harness state for analyze mode")
    end

    it "resets harness state for execute mode" do
      allow(cli).to receive(:options).and_return({mode: "execute"})
      expect(mock_state_manager).to receive(:reset_all)

      output = capture_stdout do
        cli.harness_reset
      end

      expect(output).to include("✅ Reset harness state for execute mode")
    end

    it "shows error for invalid mode" do
      allow(cli).to receive(:options).and_return({mode: "invalid"})

      output = capture_stdout do
        cli.harness_reset
      end

      expect(output).to include("❌ Invalid mode. Use 'analyze' or 'execute'")
    end
  end
end
