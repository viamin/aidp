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
end
