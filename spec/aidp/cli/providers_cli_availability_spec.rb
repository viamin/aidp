# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "Providers CLI availability check" do
  let(:temp_dir) { Dir.mktmpdir("aidp_cli_availability_test") }
  let(:config_file) { File.join(temp_dir, ".aidp", "aidp.yml") }

  # Global cleanup to ensure test isolation
  before(:all) do
    # Clear any environment variables that might interfere with tests
    @original_env = {}
    %w[AIDP_FORCE_CLAUDE_MISSING AIDP_FORCE_CLAUDE_AVAILABLE AIDP_DEFAULT_PROVIDER AIDP_MAX_RETRIES AIDP_ENV AIDP_STREAMING AIDP_QUICK_MODE].each do |var|
      @original_env[var] = ENV[var]
      ENV.delete(var)
    end
  end

  after(:all) do
    # Restore original environment variables
    @original_env.each do |var, value|
      if value
        ENV[var] = value
      else
        ENV.delete(var)
      end
    end
  end

  before do
    # Create test configuration file
    create_test_configuration
    # Clear any environment variables that might interfere
    ENV.delete("AIDP_FORCE_CLAUDE_MISSING")
    ENV.delete("AIDP_FORCE_CLAUDE_AVAILABLE")
    ENV.delete("AIDP_DEFAULT_PROVIDER")
    ENV.delete("AIDP_MAX_RETRIES")
    ENV.delete("AIDP_ENV")
    ENV.delete("AIDP_STREAMING")
    ENV.delete("AIDP_QUICK_MODE")
  end

  after do
    FileUtils.rm_rf(temp_dir)
    # Clean up environment variables
    ENV.delete("AIDP_FORCE_CLAUDE_MISSING")
    ENV.delete("AIDP_FORCE_CLAUDE_AVAILABLE")
    # Clean up any other AIDP environment variables that might interfere
    ENV.delete("AIDP_DEFAULT_PROVIDER")
    ENV.delete("AIDP_MAX_RETRIES")
    ENV.delete("AIDP_ENV")
    ENV.delete("AIDP_STREAMING")
    ENV.delete("AIDP_QUICK_MODE")
  end

  def run_cli(*args)
    cmd = ["bundle", "exec", "aidp", "providers", *args]
    env = {
      "RSPEC_RUNNING" => "true",
      "AIDP_FORCE_CLAUDE_MISSING" => ENV["AIDP_FORCE_CLAUDE_MISSING"],
      "AIDP_FORCE_CLAUDE_AVAILABLE" => ENV["AIDP_FORCE_CLAUDE_AVAILABLE"]
    }.compact
    Open3.capture3(env, *cmd, chdir: temp_dir)
  end

  let(:ansi_regex) { /\e\[[0-9;]*m/ }

  context "when claude binary is missing" do
    before do
      ENV["AIDP_FORCE_CLAUDE_MISSING"] = "1"
      ENV.delete("AIDP_FORCE_CLAUDE_AVAILABLE")
    end
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
    it "shows claude as available" do
      ENV.delete("AIDP_FORCE_CLAUDE_MISSING")
      ENV["AIDP_FORCE_CLAUDE_AVAILABLE"] = "1"

      stdout, _stderr, status = run_cli("--no-color")
      expect(status.exitstatus).to eq(0)
      claude_line = stdout.lines.find { |l| l.strip.start_with?("claude") }
      expect(claude_line).not_to be_nil
      columns = claude_line.strip.split(/\s+/)
      expect(columns[0]).to eq("claude")
      expect(columns[2]).to eq("yes")
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
