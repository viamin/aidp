# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "Providers Health CLI" do
  let(:temp_dir) { Dir.mktmpdir("aidp_cli_health_test") }
  let(:config_file) { File.join(temp_dir, "aidp.yml") }
  let(:ansi_regex) { /\e\[[0-9;]*m/ }

  before do
    # Create test configuration file
    create_test_configuration
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  def run_cli(*args)
    cmd = ["bundle", "exec", "aidp", "providers", "health", *args]
    env = {"RSPEC_RUNNING" => "true"}
    stdout, stderr, status = Open3.capture3(env, *cmd, chdir: temp_dir)
    [stdout, stderr, status]
  end

  # Single integration test - process spawning is inherently slow but validates full CLI
  it "displays provider health dashboard with correct output" do
    stdout, _stderr, status = run_cli("--no-color")

    expect(status.exitstatus).to eq(0)
    expect(stdout).to include("Provider Health Dashboard")
    expect(stdout).to match(/Provider\s+Status\s+Avail\s+Circuit/i)
    expect(stdout).not_to match(ansi_regex) # --no-color removes ANSI
    expect(stdout.scan("cursor").length).to be >= 1 # configured provider present
  end
end

private

def create_test_configuration
  config = {
    "harness" => {
      "default_provider" => "cursor",
      "max_retries" => 3,
      "fallback_providers" => ["macos"]
    },
    "providers" => {
      "cursor" => {
        "type" => "subscription",
        "priority" => 1,
        "models" => ["cursor-default"]
      },
      "macos" => {
        "type" => "passthrough",
        "priority" => 2,
        "models" => ["cursor-chat"]
      }
    }
  }

  File.write(config_file, YAML.dump(config))
end
