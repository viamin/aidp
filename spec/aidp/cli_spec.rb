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

    it "defines execute-approve command" do
      expect(Aidp::CLI.commands.keys).to include("execute_approve")
    end

    it "defines execute-reset command" do
      expect(Aidp::CLI.commands.keys).to include("execute_reset")
    end

    it "defines analyze-approve command" do
      expect(Aidp::CLI.commands.keys).to include("analyze_approve")
    end

    it "defines analyze-reset command" do
      expect(Aidp::CLI.commands.keys).to include("analyze_reset")
    end
  end

  describe "#resolve_analyze_step" do
    let(:progress) { instance_double(Aidp::Analyze::Progress) }

    before do
      allow(progress).to receive(:next_step).and_return("01_REPOSITORY_ANALYSIS")
      allow(progress).to receive(:current_step).and_return("02_ARCHITECTURE_ANALYSIS")
    end

    context "with 'next' keyword" do
      it "returns the next step from progress" do
        result = cli.send(:resolve_analyze_step, "next", progress)
        expect(result).to eq("01_REPOSITORY_ANALYSIS")
      end
    end

    context "with 'current' keyword" do
      it "returns the current step from progress" do
        result = cli.send(:resolve_analyze_step, "current", progress)
        expect(result).to eq("02_ARCHITECTURE_ANALYSIS")
      end

      it "falls back to next step when no current step" do
        allow(progress).to receive(:current_step).and_return(nil)
        result = cli.send(:resolve_analyze_step, "current", progress)
        expect(result).to eq("01_REPOSITORY_ANALYSIS")
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
      allow(runner).to receive(:run_step)
    end

    context "when called without arguments" do
      it "lists available steps with status indicators" do
        expect { cli.analyze(temp_dir) }.to output(/Available analyze steps:/).to_stdout
        expect { cli.analyze(temp_dir) }.to output(/⏳ 01: 01_REPOSITORY_ANALYSIS/).to_stdout
      end

      it "shows helpful hint for next step" do
        expect { cli.analyze(temp_dir) }.to output(/💡 Run 'aidp analyze next' or 'aidp analyze 01'/).to_stdout
      end

      it "returns success status with metadata" do
        result = cli.analyze(temp_dir)
        expect(result[:status]).to eq("success")
        expect(result[:message]).to eq("Available steps listed")
        expect(result[:next_step]).to eq("01_REPOSITORY_ANALYSIS")
      end
    end

    context "when called with 'next'" do
      it "runs the next step" do
        expect(runner).to receive(:run_step).with("01_REPOSITORY_ANALYSIS", {})
        cli.analyze(temp_dir, "next")
      end
    end

    context "when called with 'current'" do
      it "runs the current step" do
        allow(progress).to receive(:current_step).and_return("02_ARCHITECTURE_ANALYSIS")
        expect(runner).to receive(:run_step).with("02_ARCHITECTURE_ANALYSIS", {})
        cli.analyze(temp_dir, "current")
      end
    end

    context "when called with step number" do
      it "runs the correct step for '01'" do
        expect(runner).to receive(:run_step).with("01_REPOSITORY_ANALYSIS", {})
        cli.analyze(temp_dir, "01")
      end

      it "runs the correct step for '1'" do
        expect(runner).to receive(:run_step).with("01_REPOSITORY_ANALYSIS", {})
        cli.analyze(temp_dir, "1")
      end
    end

    context "when called with full step name" do
      it "runs the step" do
        expect(runner).to receive(:run_step).with("01_REPOSITORY_ANALYSIS", {})
        cli.analyze(temp_dir, "01_REPOSITORY_ANALYSIS")
      end
    end

    context "when called with invalid step" do
      it "shows error message" do
        expect { cli.analyze(temp_dir, "invalid") }.to output(/❌ Step 'invalid' not found/).to_stdout
      end

      it "shows available steps" do
        expect { cli.analyze(temp_dir, "invalid") }.to output(/Available steps:/).to_stdout
      end

      it "returns error status" do
        result = cli.analyze(temp_dir, "invalid")
        expect(result[:status]).to eq("error")
        expect(result[:message]).to eq("Step not found")
      end
    end

    context "with options" do
      it "passes force option to runner" do
        cli.options = {"force" => true}
        expect(runner).to receive(:run_step).with("01_REPOSITORY_ANALYSIS", {"force" => true})
        cli.analyze(temp_dir, "01")
      end

      it "passes rerun option to runner" do
        cli.options = {"rerun" => true}
        expect(runner).to receive(:run_step).with("01_REPOSITORY_ANALYSIS", {"rerun" => true})
        cli.analyze(temp_dir, "01")
      end
    end
  end
end
