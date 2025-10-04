# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "Providers CLI availability check" do
  let(:temp_dir) { Dir.mktmpdir("aidp_cli_availability_test") }
  let(:config_file) { File.join(temp_dir, "aidp.yml") }

  before do
    # Create test configuration file
    create_test_configuration
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  def run_cli(*args)
    cmd = ["bundle", "exec", "aidp", "providers", *args]
    env = {"RSPEC_RUNNING" => "true"}
    env["AIDP_FORCE_CLAUDE_MISSING"] = "1" if ENV["AIDP_FORCE_CLAUDE_MISSING"] == "1"
    Open3.capture3(env, *cmd, chdir: temp_dir)
  end

  let(:ansi_regex) { /\e\[[0-9;]*m/ }

  context "when claude binary is missing" do
    before { ENV["AIDP_FORCE_CLAUDE_MISSING"] = "1" }
    after { ENV.delete("AIDP_FORCE_CLAUDE_MISSING") }

    it "marks claude as unavailable with binary_missing reason" do
      stdout, _stderr, status = run_cli("--no-color")
      expect(status.exitstatus).to eq(0)

      # Check if we got the expected data regardless of table orientation
      expect(stdout).to include("claude")
      expect(stdout).to include("unhealthy")
      expect(stdout).to include("binary_missing")

      # For vertical format, we expect these patterns
      if stdout.include?("Provider    claude")
        # Vertical format - check that Avail shows "no"
        claude_section = stdout.split("Provider    claude")[1].split("Provider    ")[0]
        expect(claude_section).to include("Avail       no")
      else
        # Horizontal format - original logic
        claude_line = stdout.lines.find { |l| l.strip.start_with?("claude") }
        expect(claude_line).not_to be_nil
        columns = claude_line.strip.split(/\s+/)
        expect(columns[0]).to eq("claude")
        expect(columns[2]).to eq("no")
      end

      expect(stdout).to match(/claude.*binary_missing/im)
    end
  end

  context "when claude binary is present" do
    before do
      # Ensure which returns some path for claude
      allow(Aidp::Util).to receive(:which).and_call_original
      allow(Aidp::Util).to receive(:which).with("claude").and_return("/usr/local/bin/claude")

      # Short-circuit version execution by stubbing Process.spawn to exit immediately
      allow(Process).to receive(:spawn).and_wrap_original do |orig, *spawn_args|
        if spawn_args.first == "claude"
          # Emulate an immediate successful process with pid
          pid = fork do
            $stdout.write("claude version test")
            exit 0
          end
          pid
        else
          orig.call(*spawn_args)
        end
      end
    end

    it "shows claude as available" do
      ENV.delete("AIDP_FORCE_CLAUDE_MISSING")
      stdout, _stderr, status = run_cli("--no-color")
      expect(status.exitstatus).to eq(0)
      claude_line = stdout.lines.find { |l| l.strip.start_with?("claude") }
      expect(claude_line).not_to be_nil
      columns = claude_line.strip.split(/\s+/)
      expect(columns[0]).to eq("claude")
      expect(columns[2]).to eq("yes")
    end
  end
end

private

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

  File.write(config_file, YAML.dump(config))
end
