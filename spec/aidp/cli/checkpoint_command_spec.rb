# frozen_string_literal: true

require "spec_helper"
require "aidp/cli/checkpoint_command"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::CLI::CheckpointCommand do
  let(:temp_dir) { Dir.mktmpdir("aidp_checkpoint_command_test") }
  let(:prompt) { instance_double(TTY::Prompt) }

  # Mock classes for dependency injection
  let(:checkpoint_double) { instance_double(Aidp::Execute::Checkpoint) }
  let(:checkpoint_class) do
    class_double(Aidp::Execute::Checkpoint).tap do |klass|
      allow(klass).to receive(:new).and_return(checkpoint_double)
    end
  end

  let(:display_double) { instance_double(Aidp::Execute::CheckpointDisplay) }
  let(:display_class) do
    class_double(Aidp::Execute::CheckpointDisplay).tap do |klass|
      allow(klass).to receive(:new).and_return(display_double)
    end
  end

  let(:command) do
    described_class.new(
      prompt: prompt,
      checkpoint_class: checkpoint_class,
      display_class: display_class,
      project_dir: temp_dir
    )
  end

  before do
    allow(prompt).to receive(:say)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#run with show subcommand" do
    it "displays latest checkpoint when data exists" do
      checkpoint_data = {iteration: 5, status: "healthy", metrics: {}}
      allow(checkpoint_double).to receive(:latest_checkpoint).and_return(checkpoint_data)
      allow(display_double).to receive(:display_checkpoint)

      command.run(["show"])
      expect(display_double).to have_received(:display_checkpoint).with(checkpoint_data, show_details: true)
    end

    it "shows message when no checkpoint data found" do
      allow(checkpoint_double).to receive(:latest_checkpoint).and_return(nil)
      expect(prompt).to receive(:say).with("No checkpoint data found.", color: :blue)

      command.run(["show"])
    end
  end

  describe "#run with summary subcommand" do
    it "displays progress summary when data exists" do
      summary = {iteration: 3, metrics: {loc: 150}}
      allow(checkpoint_double).to receive(:progress_summary).and_return(summary)
      allow(display_double).to receive(:display_progress_summary)

      command.run(["summary"])
      expect(display_double).to have_received(:display_progress_summary).with(summary)
    end

    it "shows message when no summary data found" do
      allow(checkpoint_double).to receive(:progress_summary).and_return(nil)
      expect(prompt).to receive(:say).with("No checkpoint data found.", color: :blue)

      command.run(["summary"])
    end

    it "defaults to summary when no subcommand provided" do
      summary = {iteration: 3, metrics: {loc: 150}}
      allow(checkpoint_double).to receive(:progress_summary).and_return(summary)
      allow(display_double).to receive(:display_progress_summary)

      command.run([])
      expect(display_double).to have_received(:display_progress_summary).with(summary)
    end
  end

  describe "#run with history subcommand" do
    it "displays checkpoint history when data exists" do
      history = [
        {iteration: 1, timestamp: Time.now, metrics: {loc: 100}},
        {iteration: 2, timestamp: Time.now + 60, metrics: {loc: 120}}
      ]
      allow(checkpoint_double).to receive(:checkpoint_history).with(limit: 2).and_return(history)
      allow(display_double).to receive(:display_checkpoint_history)

      command.run(["history", "2"])
      expect(display_double).to have_received(:display_checkpoint_history).with(history, limit: 2)
    end

    it "defaults to 10 when no limit specified" do
      allow(checkpoint_double).to receive(:checkpoint_history).with(limit: 10).and_return([])
      expect(prompt).to receive(:say).with("No checkpoint history found.", color: :blue)

      command.run(["history"])
    end

    it "shows message when no history found" do
      allow(checkpoint_double).to receive(:checkpoint_history).with(limit: 5).and_return([])
      expect(prompt).to receive(:say).with("No checkpoint history found.", color: :blue)

      command.run(["history", "5"])
    end
  end

  describe "#run with metrics subcommand" do
    it "displays detailed metrics when data exists" do
      checkpoint_data = {
        iteration: 5,
        metrics: {
          lines_of_code: 1000,
          file_count: 50,
          test_coverage: 85,
          code_quality: 90,
          prd_task_progress: 75,
          tests_passing: true,
          linters_passing: false
        }
      }
      allow(checkpoint_double).to receive(:latest_checkpoint).and_return(checkpoint_data)
      allow(prompt).to receive(:say)

      command.run(["metrics"])

      expect(prompt).to have_received(:say).with("📊 Detailed Metrics", color: :blue)
      expect(prompt).to have_received(:say).with("Lines of Code: 1000", color: :blue)
      expect(prompt).to have_received(:say).with("Tests: ✓ Passing", color: :blue)
      expect(prompt).to have_received(:say).with("Linters: ✗ Failing", color: :blue)
    end

    it "shows message when no metrics data found" do
      allow(checkpoint_double).to receive(:latest_checkpoint).and_return(nil)
      expect(prompt).to receive(:say).with("No checkpoint data found.", color: :blue)

      command.run(["metrics"])
    end
  end

  describe "#run with clear subcommand" do
    it "clears checkpoint data after confirmation when --force provided" do
      allow(checkpoint_double).to receive(:clear)
      expect(prompt).to receive(:say).with("✓ Checkpoint data cleared.", color: :green)

      command.run(["clear", "--force"])
      expect(checkpoint_double).to have_received(:clear)
    end

    it "prompts for confirmation when --force not provided" do
      allow(prompt).to receive(:yes?).with("Are you sure you want to clear all checkpoint data?").and_return(true)
      allow(checkpoint_double).to receive(:clear)
      allow(prompt).to receive(:say)

      command.run(["clear"])
      expect(checkpoint_double).to have_received(:clear)
    end

    it "does not clear when user declines confirmation" do
      allow(prompt).to receive(:yes?).with("Are you sure you want to clear all checkpoint data?").and_return(false)
      expect(checkpoint_double).not_to receive(:clear)

      command.run(["clear"])
    end
  end

  describe "#run with unknown subcommand" do
    it "displays usage message" do
      expect(prompt).to receive(:say).with(/Usage: aidp checkpoint/, color: :blue)
      allow(prompt).to receive(:say) # Allow other usage lines

      command.run(["unknown"])
    end
  end

  describe "usage message content" do
    it "includes all required information" do
      messages = []
      allow(prompt).to receive(:say) { |msg, **_opts| messages << msg }

      command.run(["unknown"])

      usage_text = messages.join("\n")
      expect(usage_text).to include("Usage: aidp checkpoint")
      expect(usage_text).to include("show")
      expect(usage_text).to include("summary")
      expect(usage_text).to include("history")
      expect(usage_text).to include("metrics")
      expect(usage_text).to include("clear")
    end
  end
end
