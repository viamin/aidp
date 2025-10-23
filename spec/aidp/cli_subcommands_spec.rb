# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "time"

RSpec.describe Aidp::CLI, "additional subcommand and helper coverage" do
  # Simple stdout capture helper (avoid interfering with existing helpers)
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  describe "providers command" do
    let(:config_manager_double) { instance_double(Aidp::Harness::ConfigManager) }
    let(:provider_manager_double) { instance_double(Aidp::Harness::ProviderManager) }
    let(:spinner_double) { instance_double(TTY::Spinner, auto_spin: nil, stop: nil) }
    let(:table_double) { instance_double(TTY::Table, render: "Provider  Status\nclaude    healthy") }

    before do
      allow(Aidp::Harness::ConfigManager).to receive(:new).and_return(config_manager_double)
      allow(TTY::Spinner).to receive(:new).and_return(spinner_double)
      allow(TTY::Table).to receive(:new).and_return(table_double)
    end

    it "displays provider health dashboard (success path)" do
      now = Time.now
      rows = [
        {
          provider: "claude",
          status: "healthy",
          available: true,
          circuit_breaker: "closed",
          circuit_breaker_remaining: nil,
          rate_limited: false,
          rate_limit_reset_in: nil,
          total_tokens: 123,
          last_used: now,
          unhealthy_reason: nil
        }
      ]
      allow(Aidp::Harness::ProviderManager).to receive(:new).and_return(provider_manager_double)
      allow(provider_manager_double).to receive(:health_dashboard).and_return(rows)

      output = capture_stdout { Aidp::CLI.run(["providers"]) }

      expect(output).to include("Provider Health Dashboard")
      expect(output).to include("claude")
      expect(output).to include("healthy")
    end

    it "handles error while displaying provider health" do
      allow(Aidp::Harness::ProviderManager).to receive(:new).and_return(provider_manager_double)
      allow(provider_manager_double).to receive(:health_dashboard).and_raise(StandardError, "boom")
      # Stub log_rescue since class-level mixin may not expose it in specs
      allow(described_class).to receive(:log_rescue)

      output = capture_stdout { Aidp::CLI.run(["providers"]) }

      expect(output).to include("Failed to display provider health: boom")
    end
  end

  describe "kb command" do
    it "shows default summary topic when no topic provided" do
      output = capture_stdout { Aidp::CLI.run(["kb", "show"]) }
      expect(output).to include("Knowledge Base: summary")
    end

    it "shows specified topic" do
      output = capture_stdout { Aidp::CLI.run(["kb", "show", "architecture"]) }
      expect(output).to include("Knowledge Base: architecture")
    end

    it "shows usage on unknown subcommand" do
      output = capture_stdout { Aidp::CLI.run(["kb", "unknown"]) }
      expect(output).to include("Usage: aidp kb show <topic>")
    end
  end

  describe "harness command" do
    it "displays status output" do
      output = capture_stdout { Aidp::CLI.run(["harness", "status"]) }
      expect(output).to include("Harness Status")
      expect(output).to include("Mode: (unknown)")
    end

    it "resets harness with explicit mode" do
      output = capture_stdout { Aidp::CLI.run(["harness", "reset", "--mode", "analyze"]) }
      expect(output).to include("Harness state reset for mode: analyze")
    end

    it "shows usage for unknown harness subcommand" do
      output = capture_stdout { Aidp::CLI.run(["harness", "other"]) }
      expect(output).to include("Usage: aidp harness <status|reset>")
    end
  end

  describe "helper extraction methods" do
    it "extracts mode via separate token" do
      args = ["--mode", "execute"]
      mode = described_class.send(:extract_mode_option, args)
      expect(mode).to eq(:execute)
    end

    it "extracts mode via equals form" do
      args = ["--mode=analyze"]
      mode = described_class.send(:extract_mode_option, args)
      expect(mode).to eq(:analyze)
    end

    it "returns nil when mode not present" do
      args = ["--other", "value"]
      expect(described_class.send(:extract_mode_option, args)).to be_nil
    end

    it "extracts interval via token and numeric argument" do
      args = ["--interval", "10"]
      expect(described_class.send(:extract_interval_option, args)).to eq(10)
    end

    it "extracts interval via equals form" do
      args = ["--interval=15"]
      expect(described_class.send(:extract_interval_option, args)).to eq(15)
    end

    it "returns nil when interval not present" do
      args = ["--mode", "execute"]
      expect(described_class.send(:extract_interval_option, args)).to be_nil
    end

    it "formats relative time under a minute" do
      expect(described_class.send(:format_time_ago_simple, 30)).to eq("30s ago")
    end

    it "formats relative time under an hour" do
      expect(described_class.send(:format_time_ago_simple, 90)).to eq("1m ago")
    end

    it "formats relative time over an hour" do
      expect(described_class.send(:format_time_ago_simple, 3700)).to eq("1h ago")
    end
  end

  describe "class-level display_harness_result" do
    it "prints completed harness result" do
      output = capture_stdout do
        described_class.send(:display_harness_result, {status: "completed"})
      end
      expect(output).to include("Harness completed successfully")
    end

    it "prints stopped harness result" do
      output = capture_stdout do
        described_class.send(:display_harness_result, {status: "stopped"})
      end
      expect(output).to include("Harness stopped by user")
    end

    it "prints generic harness result" do
      output = capture_stdout do
        described_class.send(:display_harness_result, {status: "custom", message: "Hi"})
      end
      expect(output).to include("Harness finished")
      expect(output).to include("Status: custom")
      expect(output).to include("Message: Hi")
    end
  end
end
