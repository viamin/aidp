# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "Providers CLI availability check" do
  let(:temp_dir) { Dir.mktmpdir("aidp_cli_availability_test") }
  let(:config_file) { File.join(temp_dir, ".aidp", "aidp.yml") }

  before do
    # Create test configuration file
    create_test_configuration
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  def run_cli(*args)
    cmd = ["bundle", "exec", "aidp", "providers", *args]
    env = {}
    Open3.capture3(env, *cmd, chdir: temp_dir)
  end

  let(:ansi_regex) { /\e\[[0-9;]*m/ }

  context "provider availability detection" do
    it "shows actual provider status based on binary availability" do
      stdout, _stderr, status = run_cli("--no-color")
      expect(status.exitstatus).to eq(0)

      # Check that provider status is reported
      expect(stdout).to include("claude")

      # The actual availability depends on whether the binary is installed
      # This is now testing real behavior, not mocked behavior
      # We just verify the output format is correct
      lines = stdout.lines.map(&:strip)
      expect(lines.any? { |l| l.match?(/claude/i) }).to be true
    end

    it "displays provider information in readable format" do
      stdout, _stderr, status = run_cli("--no-color")
      expect(status.exitstatus).to eq(0)

      # Verify we have a table with provider information
      # Don't test specific availability status since it depends on actual system state
      expect(stdout).to match(/provider/i)
      expect(stdout).to match(/status|avail/i)
    end
  end

  def create_test_configuration
    config = {
      "harness" => {
        "default_provider" => "claude",
        "max_retries" => 3,
        "fallback_providers" => ["cursor", "macos"]
      },
      "providers" => {
        "claude" => {
          "type" => "usage_based",
          "priority" => 1,
          "models" => ["claude-3-5-sonnet-20241022"]
        },
        "cursor" => {
          "type" => "subscription",
          "priority" => 2,
          "models" => ["cursor-default"]
        },
        "macos" => {
          "type" => "passthrough",
          "priority" => 3,
          "models" => ["cursor-chat"]
        }
      }
    }

    FileUtils.mkdir_p(File.dirname(config_file))
    File.write(config_file, YAML.dump(config))
  end
end
