# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "stringio"

RSpec.describe Aidp::CLI do
  let(:temp_dir) { Dir.mktmpdir }
  let(:cli) { described_class.new }

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

      expect(output).to include("❌ Harness encountered an error")
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

  describe "harness integration" do
    let(:mock_harness_runner) { double("harness_runner") }

    before do
      allow(Aidp::Harness::Runner).to receive(:new).and_return(mock_harness_runner)
      allow(mock_harness_runner).to receive(:run).and_return({status: "completed"})
    end

    describe "execute command with harness" do
      it "uses harness when no step specified" do
        options = {harness: true}

        # Mock WorkflowSelector to avoid user interaction
        mock_workflow_selector = instance_double(Aidp::Execute::WorkflowSelector)
        allow(Aidp::Execute::WorkflowSelector).to receive(:new).and_return(mock_workflow_selector)
        allow(mock_workflow_selector).to receive(:select_workflow).and_return({
          workflow_type: :exploration,
          steps: ["00_PRD", "IMPLEMENTATION"],
          user_input: {project_description: "Test project"}
        })

        # Expect the harness to be called with workflow configuration
        expect(Aidp::Harness::Runner).to receive(:new).with(temp_dir, :execute, hash_including(options))
        expect(mock_harness_runner).to receive(:run)

        cli.execute(temp_dir, nil, options)
      end

      it "uses harness for specific step when requested" do
        options = {harness: true}

        expect(Aidp::Harness::Runner).to receive(:new).with(temp_dir, :execute, options)
        expect(mock_harness_runner).to receive(:run)

        cli.execute(temp_dir, "test_step", options)
      end

      it "uses traditional runner when no_harness is specified" do
        options = {no_harness: true}
        mock_runner = double("runner")

        allow(Aidp::Execute::Runner).to receive(:new).and_return(mock_runner)
        allow(mock_runner).to receive(:run_step)

        expect(Aidp::Execute::Runner).to receive(:new).with(temp_dir)
        expect(mock_runner).to receive(:run_step).with("test_step", options)

        cli.execute(temp_dir, "test_step", options)
      end
    end

    describe "analyze command with harness" do
      it "uses harness when no step specified" do
        options = {harness: true}

        expect(Aidp::Harness::Runner).to receive(:new).with(temp_dir, :analyze, options)
        expect(mock_harness_runner).to receive(:run)

        cli.analyze(temp_dir, nil, options)
      end

      it "uses harness for specific step when requested" do
        options = {harness: true}

        # Mock the step resolution to return a valid step
        allow(cli).to receive(:resolve_analyze_step).with("test_step", anything).and_return("01_REPOSITORY_ANALYSIS")

        expect(Aidp::Harness::Runner).to receive(:new).with(temp_dir, :analyze, hash_including(options))
        expect(mock_harness_runner).to receive(:run)

        cli.analyze(temp_dir, "test_step", options)
      end

      it "uses traditional runner when no_harness is specified" do
        options = {no_harness: true}
        mock_runner = double("runner")

        # Mock the step resolution to return a valid step
        allow(cli).to receive(:resolve_analyze_step).with("test_step", anything).and_return("01_REPOSITORY_ANALYSIS")

        allow(Aidp::Analyze::Runner).to receive(:new).and_return(mock_runner)
        allow(mock_runner).to receive(:run_step).and_return({status: "completed", provider: "test"})

        expect(Aidp::Analyze::Runner).to receive(:new).with(temp_dir)
        expect(mock_runner).to receive(:run_step).with("01_REPOSITORY_ANALYSIS", options)

        cli.analyze(temp_dir, "test_step", options)
      end
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
