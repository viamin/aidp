# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::StrategyExecution::CliProtocol::Runner do
  let(:project_dir) { Dir.mktmpdir }
  let(:runner) { described_class.new(project_dir: project_dir) }

  after do
    FileUtils.rm_rf(project_dir)
  end

  it "executes a command with the protocol payload" do
    command = [
      "ruby",
      "-e",
      'require "json"; input = JSON.parse(STDIN.read); puts JSON.generate(success: true, summary: input["task"]["description"], output: "done", artifacts: [])'
    ]

    result = runner.execute(
      command: command,
      role: "agent",
      request: {task: {description: "ship it"}}
    )

    expect(result[:success]).to be true
    expect(result[:summary]).to eq("ship it")
    expect(result[:artifact_dir]).to include(".aidp")
  end

  it "normalizes relative artifact paths against the artifact directory" do
    command = [
      "ruby",
      "-e",
      'require "json"; input = JSON.parse(STDIN.read); File.write(File.join(input["artifact_dir"], "out.txt"), "artifact"); puts JSON.generate(success: true, artifacts: ["out.txt"])'
    ]

    result = runner.execute(
      command: command,
      role: "agent",
      request: {task: {description: "ship it"}}
    )

    expect(result[:artifacts]).to eq([File.join(result[:artifact_dir], "out.txt")])
  end

  it "raises when evaluator response is incomplete" do
    command = ["ruby", "-e", "puts JSON.generate(success: true)"]

    expect {
      runner.execute(command: command, role: "evaluator", request: {})
    }.to raise_error(Aidp::StrategyExecution::CliProtocol::ProtocolError)
  end
end
