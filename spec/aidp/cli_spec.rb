# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::CLI do
  let(:temp_dir) { Dir.mktmpdir }
  let(:cli) { described_class.new }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#should_use_harness?" do
    it "returns true by default" do
      result = cli.send(:should_use_harness?, {})
      expect(result).to be true
    end

    it "returns false when no_harness is true" do
      result = cli.send(:should_use_harness?, {no_harness: true})
      expect(result).to be false
    end

    it "returns true when harness is explicitly true" do
      result = cli.send(:should_use_harness?, {harness: true})
      expect(result).to be true
    end

    it "returns false when no_harness overrides harness" do
      result = cli.send(:should_use_harness?, {harness: true, no_harness: true})
      expect(result).to be false
    end
  end

  describe "#display_harness_result" do
    it "displays completed status" do
      result = {status: "completed", message: "All done"}

      expect { cli.send(:display_harness_result, result) }.to output(
        /✅ Harness completed successfully!/
      ).to_stdout
    end

    it "displays stopped status" do
      result = {status: "stopped", message: "User stopped"}

      expect { cli.send(:display_harness_result, result) }.to output(
        /⏹️  Harness stopped by user/
      ).to_stdout
    end

    it "displays error status" do
      result = {status: "error", message: "Something went wrong"}

      expect { cli.send(:display_harness_result, result) }.to output(
        /❌ Harness encountered an error/
      ).to_stdout
    end

    it "displays unknown status" do
      result = {status: "unknown", message: "Unknown state"}

      expect { cli.send(:display_harness_result, result) }.to output(
        /🔄 Harness finished/
      ).to_stdout
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

        expect(Aidp::Harness::Runner).to receive(:new).with(temp_dir, :execute, options)
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

        expect(Aidp::Harness::Runner).to receive(:new).with(temp_dir, :analyze, options)
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
      expect { cli.harness_status }.to output(
        /🔧 Harness Status/
      ).to_stdout
    end

    it "displays harness status for specific mode" do
      expect { cli.harness_status }.to output(
        /📋 Analyze Mode:/
      ).to_stdout
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

      expect { cli.harness_reset }.to output(
        /✅ Reset harness state for analyze mode/
      ).to_stdout
    end

    it "resets harness state for execute mode" do
      allow(cli).to receive(:options).and_return({mode: "execute"})
      expect(mock_state_manager).to receive(:reset_all)

      expect { cli.harness_reset }.to output(
        /✅ Reset harness state for execute mode/
      ).to_stdout
    end

    it "shows error for invalid mode" do
      allow(cli).to receive(:options).and_return({mode: "invalid"})

      expect { cli.harness_reset }.to output(
        /❌ Invalid mode. Use 'analyze' or 'execute'/
      ).to_stdout
    end
  end
end
