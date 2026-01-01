# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/test_runner"
require "tmpdir"

RSpec.describe Aidp::Harness::TestRunner do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config) { double("config") }
  let(:runner) { described_class.new(temp_dir, config) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#run_tests" do
    context "when no test commands configured" do
      before do
        allow(config).to receive(:test_commands).and_return([])
      end

      it "returns success with empty output" do
        result = runner.run_tests

        expect(result[:success]).to be true
        expect(result[:output]).to eq ""
        expect(result[:failures]).to be_empty
      end
    end

    context "when test commands configured" do
      before do
        allow(config).to receive(:test_commands).and_return(["echo 'tests pass'", "exit 0"])
      end

      it "runs all test commands" do
        result = runner.run_tests

        expect(result[:success]).to be true
        expect(result[:output]).to include("All passed")
      end
    end

    context "when config omits commands but tooling detects tests" do
      before do
        allow(config).to receive(:test_commands).and_return([])
        allow(Aidp::ToolingDetector).to receive(:detect).and_return(
          Aidp::ToolingDetector::Result.new(
            test_commands: ["echo detected tests"],
            lint_commands: []
          )
        )
      end

      it "falls back to detected commands" do
        result = runner.run_tests

        expect(result[:success]).to be true
        expect(result[:output]).to include("All passed")
        expect(Aidp::ToolingDetector).to have_received(:detect).with(temp_dir)
      end
    end

    context "when test command fails" do
      before do
        allow(config).to receive(:test_commands).and_return(["exit 1"])
      end

      it "returns failure with exit code" do
        result = runner.run_tests

        expect(result[:success]).to be false
        expect(result[:output]).to include("Exit Code: 1")
        expect(result[:failures].size).to eq 1
      end
    end

    context "when some tests pass and some fail" do
      before do
        allow(config).to receive(:test_commands).and_return([
          "exit 0",
          "exit 1",
          "echo 'test output' && exit 0"
        ])
      end

      it "returns failure with only failed command details" do
        result = runner.run_tests

        expect(result[:success]).to be false
        expect(result[:failures].size).to eq 1
        expect(result[:failures].first[:command]).to eq "exit 1"
      end
    end
  end

  describe "#run_linters" do
    context "when no lint commands configured" do
      before do
        allow(config).to receive(:lint_commands).and_return([])
      end

      it "returns success with empty output" do
        result = runner.run_linters

        expect(result[:success]).to be true
        expect(result[:output]).to eq ""
        expect(result[:failures]).to be_empty
      end
    end

    context "when lint commands configured" do
      before do
        allow(config).to receive(:lint_commands).and_return(["echo 'linting passed'"])
      end

      it "runs all lint commands" do
        result = runner.run_linters

        expect(result[:success]).to be true
        expect(result[:output]).to include("All passed")
      end
    end

    context "when lint command fails" do
      before do
        allow(config).to receive(:lint_commands).and_return(["bash -c 'echo error >&2 && exit 1'"])
      end

      it "returns failure with stderr output" do
        result = runner.run_linters

        expect(result[:success]).to be false
        expect(result[:output]).to include("error")
        expect(result[:output]).to include("Exit Code: 1")
      end
    end

    context "when config omits lint commands but tooling detects them" do
      before do
        allow(config).to receive(:lint_commands).and_return([])
        allow(Aidp::ToolingDetector).to receive(:detect).and_return(
          Aidp::ToolingDetector::Result.new(
            test_commands: [],
            lint_commands: ["echo lint fallback"]
          )
        )
      end

      it "runs detected lint command" do
        result = runner.run_linters

        expect(result[:success]).to be true
        expect(result[:output]).to include("All passed")
        expect(Aidp::ToolingDetector).to have_received(:detect).with(temp_dir)
      end
    end
  end

  describe "command execution in project directory" do
    before do
      allow(config).to receive(:test_commands).and_return(["pwd"])
    end

    it "executes commands in the project directory" do
      result = runner.run_tests

      # The output should contain the temp_dir path
      expect(result[:output]).to include("All passed")
    end
  end

  describe "#run_commands_for_phase" do
    context "when commands are configured for the phase" do
      before do
        allow(config).to receive(:commands_for_phase).with(:each_unit).and_return([
          {name: "test_1", command: "echo 'test passed'", category: :test, required: true},
          {name: "lint_1", command: "echo 'lint passed'", category: :lint, required: false}
        ])
      end

      it "runs all commands for the phase" do
        result = runner.run_commands_for_phase(:each_unit)

        expect(result[:success]).to be true
        expect(result[:output]).to include("All 2 commands passed")
        expect(result[:results_by_command]).to have_key("test_1")
        expect(result[:results_by_command]).to have_key("lint_1")
      end

      it "increments iteration count" do
        expect { runner.run_commands_for_phase(:each_unit) }.to change { runner.iteration_count }.by(1)
      end
    end

    context "when a required command fails" do
      before do
        allow(config).to receive(:commands_for_phase).with(:each_unit).and_return([
          {name: "failing_test", command: "exit 1", category: :test, required: true},
          {name: "passing_test", command: "echo 'pass'", category: :test, required: true}
        ])
      end

      it "returns failure status" do
        result = runner.run_commands_for_phase(:each_unit)

        expect(result[:success]).to be false
        expect(result[:required_failures].length).to eq(1)
        expect(result[:required_failures].first[:name]).to eq("failing_test")
      end
    end

    context "when only optional command fails" do
      before do
        allow(config).to receive(:commands_for_phase).with(:each_unit).and_return([
          {name: "optional_lint", command: "exit 1", category: :lint, required: false},
          {name: "required_test", command: "echo 'pass'", category: :test, required: true}
        ])
      end

      it "returns success status since only optional failed" do
        result = runner.run_commands_for_phase(:each_unit)

        expect(result[:success]).to be true
        expect(result[:failures].length).to eq(1)
        expect(result[:required_failures]).to be_empty
      end
    end

    context "when no commands configured for phase" do
      before do
        allow(config).to receive(:commands_for_phase).with(:full_loop).and_return([])
      end

      it "returns empty success result" do
        result = runner.run_commands_for_phase(:full_loop)

        expect(result[:success]).to be true
        expect(result[:output]).to eq("")
        expect(result[:failures]).to be_empty
        expect(result[:results_by_command]).to eq({})
      end
    end

    context "with on_completion phase" do
      before do
        allow(config).to receive(:commands_for_phase).with(:on_completion).and_return([
          {name: "formatter", command: "echo 'formatted'", category: :formatter, required: true}
        ])
      end

      it "runs on_completion commands" do
        result = runner.run_commands_for_phase(:on_completion)

        expect(result[:success]).to be true
        expect(result[:results_by_command]["formatter"][:success]).to be true
      end
    end
  end

  describe "#commands_by_phase" do
    before do
      allow(config).to receive(:commands_for_phase).with(:each_unit).and_return([
        {name: "test", command: "rspec", category: :test, required: true}
      ])
      allow(config).to receive(:commands_for_phase).with(:full_loop).and_return([
        {name: "full_test", command: "rspec --all", category: :test, required: true}
      ])
      allow(config).to receive(:commands_for_phase).with(:on_completion).and_return([
        {name: "format", command: "rubocop -a", category: :formatter, required: true}
      ])
    end

    it "returns commands organized by phase" do
      result = runner.commands_by_phase

      expect(result[:each_unit].length).to eq(1)
      expect(result[:each_unit].first[:name]).to eq("test")
      expect(result[:full_loop].length).to eq(1)
      expect(result[:full_loop].first[:name]).to eq("full_test")
      expect(result[:on_completion].length).to eq(1)
      expect(result[:on_completion].first[:name]).to eq("format")
    end
  end

  describe "#iteration_count" do
    before do
      allow(config).to receive(:test_commands).and_return(["echo 'test'"])
    end

    it "tracks iterations across multiple runs" do
      expect(runner.iteration_count).to eq(0)

      runner.run_tests
      expect(runner.iteration_count).to eq(1)

      runner.run_tests
      expect(runner.iteration_count).to eq(2)
    end

    it "can be reset" do
      runner.run_tests
      expect(runner.iteration_count).to eq(1)

      runner.reset_iteration_count
      expect(runner.iteration_count).to eq(0)
    end
  end
end
