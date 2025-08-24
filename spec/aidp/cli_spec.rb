# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe Aidp::CLI do
  let(:temp_dir) { Dir.mktmpdir("aidp_cli_test") }
  let(:cli) { Aidp::CLI.new }

  after do
    FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  describe "CLI commands" do
    it "defines execute command" do
      expect(Aidp::CLI.commands.keys).to include("execute")
    end

    it "defines analyze command" do
      expect(Aidp::CLI.commands.keys).to include("analyze")
    end

    it "defines status command" do
      expect(Aidp::CLI.commands.keys).to include("status")
    end

    it "defines version command" do
      expect(Aidp::CLI.commands.keys).to include("version")
    end
  end

  describe "#resolve_analyze_step" do
    let(:progress) { instance_double(Aidp::Analyze::Progress) }

    before do
      allow(progress).to receive(:next_step).and_return("00_PRD")
      allow(progress).to receive(:current_step).and_return("02_ARCHITECTURE")
    end

    context "with 'next' keyword" do
      it "returns the next step from progress" do
        result = cli.send(:resolve_analyze_step, "next", progress)
        expect(result).to eq("00_PRD")
      end
    end

    context "with 'current' keyword" do
      it "returns the current step from progress" do
        result = cli.send(:resolve_analyze_step, "current", progress)
        expect(result).to eq("02_ARCHITECTURE")
      end

      it "falls back to next step when no current step" do
        allow(progress).to receive(:current_step).and_return(nil)
        result = cli.send(:resolve_analyze_step, "current", progress)
        expect(result).to eq("00_PRD")
      end
    end

    context "with step numbers" do
      it "resolves single digit numbers" do
        result = cli.send(:resolve_analyze_step, "1", progress)
        expect(result).to eq("01_REPOSITORY_ANALYSIS")
      end

      it "resolves zero-padded numbers" do
        result = cli.send(:resolve_analyze_step, "01", progress)
        expect(result).to eq("01_REPOSITORY_ANALYSIS")
      end

      it "resolves larger step numbers" do
        result = cli.send(:resolve_analyze_step, "3", progress)
        expect(result).to eq("03_TEST_ANALYSIS")
      end

      it "resolves two-digit step numbers" do
        result = cli.send(:resolve_analyze_step, "03", progress)
        expect(result).to eq("03_TEST_ANALYSIS")
      end

      it "returns nil for invalid step numbers" do
        result = cli.send(:resolve_analyze_step, "99", progress)
        expect(result).to be_nil
      end
    end

    context "with full step names" do
      it "resolves exact case matches" do
        result = cli.send(:resolve_analyze_step, "01_REPOSITORY_ANALYSIS", progress)
        expect(result).to eq("01_REPOSITORY_ANALYSIS")
      end

      it "resolves case-insensitive matches" do
        result = cli.send(:resolve_analyze_step, "01_repository_analysis", progress)
        expect(result).to eq("01_REPOSITORY_ANALYSIS")
      end

      it "resolves mixed case matches" do
        result = cli.send(:resolve_analyze_step, "01_Repository_Analysis", progress)
        expect(result).to eq("01_REPOSITORY_ANALYSIS")
      end

      it "returns nil for non-existent step names" do
        result = cli.send(:resolve_analyze_step, "99_INVALID_STEP", progress)
        expect(result).to be_nil
      end
    end

    context "with invalid input" do
      it "returns nil for empty string" do
        result = cli.send(:resolve_analyze_step, "", progress)
        expect(result).to be_nil
      end

      it "returns nil for random text" do
        result = cli.send(:resolve_analyze_step, "invalid", progress)
        expect(result).to be_nil
      end

      it "returns nil for nil input" do
        result = cli.send(:resolve_analyze_step, nil, progress)
        expect(result).to be_nil
      end
    end

    context "with whitespace handling" do
      it "strips whitespace from input" do
        result = cli.send(:resolve_analyze_step, "  01  ", progress)
        expect(result).to eq("01_REPOSITORY_ANALYSIS")
      end

      it "handles tabs and newlines" do
        result = cli.send(:resolve_analyze_step, "\t\n01\t\n", progress)
        expect(result).to eq("01_REPOSITORY_ANALYSIS")
      end
    end
  end

  describe "#analyze command" do
    let(:runner) { instance_double(Aidp::Analyze::Runner) }
    let(:progress) { instance_double(Aidp::Analyze::Progress) }

    before do
      allow(Aidp::Analyze::Runner).to receive(:new).and_return(runner)
      allow(Aidp::Analyze::Progress).to receive(:new).and_return(progress)
      allow(progress).to receive(:next_step).and_return("01_REPOSITORY_ANALYSIS")
      allow(progress).to receive(:current_step).and_return(nil)
      allow(progress).to receive(:step_completed?).and_return(false)
      allow(progress).to receive(:completed_steps).and_return([])
      allow(runner).to receive(:run_step).and_return({status: "completed", provider: "mock", message: "Mock execution"})
    end

    context "when called without arguments" do
      it "lists available steps with status indicators" do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        expect { cli.analyze }.to output(/Available analyze steps:/).to_stdout
        expect { cli.analyze }.to output(/⏳ 01: 01_REPOSITORY_ANALYSIS/).to_stdout
      end

      it "shows helpful hint for next step" do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        expect { cli.analyze }.to output(/💡 Run 'aidp analyze next' or 'aidp analyze 01'/).to_stdout
      end

      it "returns success status with metadata" do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        result = cli.analyze
        expect(result[:status]).to eq("success")
        expect(result[:message]).to eq("Available steps listed")
        expect(result[:next_step]).to eq("01_REPOSITORY_ANALYSIS")
      end
    end

    context "when called with 'next'" do
      it "runs the next step" do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        expect(runner).to receive(:run_step).with("01_REPOSITORY_ANALYSIS", {})
        cli.analyze("next")
      end
    end

    context "when called with 'current'" do
      it "runs the current step" do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        allow(progress).to receive(:current_step).and_return("02_ARCHITECTURE_ANALYSIS")
        expect(runner).to receive(:run_step).with("02_ARCHITECTURE_ANALYSIS", {})
        cli.analyze("current")
      end
    end

    context "when called with step number" do
      it "runs the correct step for '01'" do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        expect(runner).to receive(:run_step).with("01_REPOSITORY_ANALYSIS", {})
        cli.analyze("01")
      end

      it "runs the correct step for '1'" do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        expect(runner).to receive(:run_step).with("01_REPOSITORY_ANALYSIS", {})
        cli.analyze("1")
      end
    end

    context "when called with full step name" do
      it "runs the step" do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        expect(runner).to receive(:run_step).with("01_REPOSITORY_ANALYSIS", {})
        cli.analyze("01_REPOSITORY_ANALYSIS")
      end
    end

    context "when called with invalid step" do
      it "shows error message" do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        expect { cli.analyze("invalid") }.to output(/❌ Step 'invalid' not found/).to_stdout
      end

      it "shows available steps" do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        expect { cli.analyze("invalid") }.to output(/Available steps:/).to_stdout
      end

      it "returns error status" do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        result = cli.analyze("invalid")
        expect(result[:status]).to eq("error")
        expect(result[:message]).to eq("Step not found")
      end
    end

    context "with options" do
      it "passes force option to runner" do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        cli.options = {"force" => true}
        expect(runner).to receive(:run_step).with("01_REPOSITORY_ANALYSIS", {"force" => true})
        cli.analyze("01")
      end

      it "passes rerun option to runner" do
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        cli.options = {"rerun" => true}
        expect(runner).to receive(:run_step).with("01_REPOSITORY_ANALYSIS", {"rerun" => true})
        cli.analyze("01")
      end
    end
  end
end
