# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "yaml"
require "aidp/execute/deterministic_unit"

RSpec.describe Aidp::Execute::DeterministicUnits::Definition do
  describe "#initialize" do
    it "normalizes next map aliases" do
      definition = described_class.new(
        name: "run_tests",
        command: "bundle exec rspec",
        next: {
          if_pass: :agentic,
          if_fail: :wait_for_github,
          else: :agentic
        }
      )

      expect(definition.next_for(:success)).to eq(:agentic)
      expect(definition.next_for(:failure)).to eq(:wait_for_github)
      expect(definition.next_for(:unknown)).to eq(:agentic)
    end

    it "defaults to command type when command provided" do
      definition = described_class.new(name: "lint", command: "bundle exec standardrb")
      expect(definition.command?).to be(true)
      expect(definition.wait?).to be(false)
    end
  end
end

RSpec.describe Aidp::Execute::DeterministicUnits::Runner do
  let(:project_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#run" do
    let(:definition) do
      Aidp::Execute::DeterministicUnits::Definition.new(
        name: "run_tests",
        command: "bundle exec rspec",
        output_file: "logs/tests.yml"
      )
    end

    it "executes command units and writes yaml output" do
      command_runner = lambda do |_command, _ctx|
        {exit_status: 0, stdout: "All good", stderr: ""}
      end

      runner = described_class.new(project_dir, command_runner: command_runner, clock: Time)

      result = runner.run(definition)

      expect(result).to be_success
      expect(result.output_path).to eq(File.join(project_dir, "logs/tests.yml"))

      written = YAML.safe_load_file(result.output_path, permitted_classes: [Symbol])
      stdout_value = written[:stdout] || written["stdout"]
      expect(stdout_value).to eq("All good")
    end

    it "captures failures and still writes output" do
      command_runner = lambda do |_command, _ctx|
        raise StandardError, "boom"
      end

      runner = described_class.new(project_dir, command_runner: command_runner, clock: Time)

      result = runner.run(definition)

      expect(result).to be_failure
      expect(result.data[:error]).to eq("boom")
    end

    it "supports wait units with injectable sleep handler" do
      definition = Aidp::Execute::DeterministicUnits::Definition.new(
        name: "wait_for_github",
        type: :wait,
        output_file: "logs/wait.yml",
        metadata: {interval_seconds: 5}
      )

      slept = 0
      sleep_handler = lambda { |seconds| slept += seconds }

      runner = described_class.new(project_dir, clock: Time)

      result = runner.run(definition, sleep_handler: sleep_handler)

      expect(result.status).to eq(:waiting)
      expect(slept).to be_positive
      expect(File).to exist(result.output_path)
    end

    it "marks event when context signals activity" do
      definition = Aidp::Execute::DeterministicUnits::Definition.new(
        name: "wait_for_github",
        type: :wait,
        metadata: {interval_seconds: 1}
      )

      runner = described_class.new(project_dir, clock: Time)
      result = runner.run(definition, event_detected: true, sleep_handler: ->(_seconds) {})

      expect(result.status).to eq(:event)
    end
  end

  describe "default command runner (shell-free execution)" do
    def command_definition(command)
      Aidp::Execute::DeterministicUnits::Definition.new(name: "run_tests", command: command)
    end

    it "executes a plain command without a shell" do
      runner = described_class.new(project_dir, clock: Time)

      result = runner.run(command_definition("true"))

      expect(result).to be_success
    end

    it "rejects shell operators instead of interpreting them" do
      runner = described_class.new(project_dir, clock: Time)

      result = runner.run(command_definition("true && touch #{File.join(project_dir, "pwned.txt")}"))

      expect(result).to be_failure
      expect(result.data[:stderr]).to include("shell operators are not supported")
      expect(File.exist?(File.join(project_dir, "pwned.txt"))).to be(false)
    end

    it "rejects environment variable assignments" do
      runner = described_class.new(project_dir, clock: Time)

      result = runner.run(command_definition("RAILS_ENV=test true"))

      expect(result).to be_failure
      expect(result.data[:stderr]).to include("env VAR=value")
    end

    it "rejects a single-token command containing shell metacharacters" do
      runner = described_class.new(project_dir, clock: Time)

      result = runner.run(command_definition("aidp-missing|aidp-missing"))

      expect(result).to be_failure
      expect(result.data[:stderr]).to include("shell metacharacters")
    end

    it "reports unparseable commands" do
      runner = described_class.new(project_dir, clock: Time)

      result = runner.run(command_definition("echo 'unclosed"))

      expect(result).to be_failure
      expect(result.data[:stderr]).to include("Unmatched quote")
    end

    it "reports missing binaries" do
      runner = described_class.new(project_dir, clock: Time)

      result = runner.run(command_definition("aidp-missing-binary-12345"))

      expect(result).to be_failure
      expect(result.data[:stderr]).to include("aidp-missing-binary-12345")
    end
  end
end
