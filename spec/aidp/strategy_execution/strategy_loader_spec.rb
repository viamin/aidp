# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::StrategyExecution::StrategyLoader do
  let(:project_dir) { Dir.mktmpdir("aidp_strategy_loader") }
  let(:loader) { described_class.new(project_dir: project_dir) }

  after do
    FileUtils.remove_entry(project_dir) if Dir.exist?(project_dir)
  end

  it "loads strategies when the YAML contains Date values" do
    path = File.join(project_dir, "strategy.yml")
    File.write(path, YAML.dump({
      "name" => "dated",
      "agents" => {"coder" => "bin/coder"},
      "evaluators" => [{"name" => "tests", "command" => "bin/tests"}],
      "captured_on" => Date.new(2026, 7, 29)
    }))

    strategy = loader.load_file(path)

    expect(strategy.name).to eq("dated")
    expect(strategy.agents).to include(coder: include(command: "bin/coder"))
  end

  it "loads a relative path from the project directory instead of the current working directory" do
    File.write(File.join(project_dir, "strategy.yml"), YAML.dump({
      "name" => "relative",
      "agents" => {"coder" => "bin/coder"}
    }))

    Dir.mktmpdir("aidp_strategy_loader_cwd") do |cwd|
      Dir.chdir(cwd) do
        strategy = loader.load_file("strategy.yml")

        expect(strategy.name).to eq("relative")
      end
    end
  end
end
