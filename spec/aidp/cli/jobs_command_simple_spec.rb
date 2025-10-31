# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe Aidp::CLI::JobsCommand do
  let(:input) { StringIO.new }
  let(:output) { StringIO.new }
  let(:test_prompt) { TestPrompt.new(responses: responses) }
  let(:responses) { {} }
  let(:temp_dir) { Dir.mktmpdir("jobs_command_test") }
  let(:file_manager) { double("FileManager") }
  let(:background_runner) { double("BackgroundRunner") }
  let(:jobs_command) do
    described_class.new(input: input, output: output, prompt: test_prompt).tap do |cmd|
      cmd.instance_variable_set(:@file_manager, file_manager)
      cmd.instance_variable_set(:@background_runner, background_runner)
    end
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "#initialize" do
    it "creates an instance with default settings" do
      expect(jobs_command).to be_a(described_class)
    end

    it "accepts custom input and output streams" do
      custom_input = StringIO.new
      custom_output = StringIO.new
      instance = described_class.new(input: custom_input, output: custom_output)
      expect(instance).to be_a(described_class)
    end

    it "initializes with default prompt" do
      instance = described_class.new
      expect(instance).to be_a(described_class)
    end
  end

  describe "#run" do
    context "with list subcommand" do
      before do
        allow(background_runner).to receive(:list_jobs).and_return([])
      end

      it "calls list_jobs for 'list' subcommand" do
        expect(jobs_command).to receive(:list_jobs)
        jobs_command.run("list")
      end

      it "calls list_jobs for nil subcommand (default)" do
        expect(jobs_command).to receive(:list_jobs)
        jobs_command.run(nil)
      end
    end

    context "with status subcommand" do
      it "shows job status when job_id provided" do
        expect(jobs_command).to receive(:show_job_status).with("job123", follow: false)
        jobs_command.run("status", ["job123"])
      end

      it "shows job status with follow option" do
        expect(jobs_command).to receive(:show_job_status).with("job123", follow: true)
        jobs_command.run("status", ["job123", "--follow"])
      end

      it "calls display_message when no job_id provided" do
        expect(jobs_command).to receive(:display_message).with("Usage: aidp jobs status <job_id> [--follow]",
          type: :error)
        jobs_command.run("status", [])
      end
    end

    context "with stop subcommand" do
      it "stops job when job_id provided" do
        expect(jobs_command).to receive(:stop_job).with("job123")
        jobs_command.run("stop", ["job123"])
      end

      it "calls display_message when no job_id provided" do
        expect(jobs_command).to receive(:display_message).with("Usage: aidp jobs stop <job_id>", type: :error)
        jobs_command.run("stop", [])
      end
    end

    context "with logs subcommand" do
      it "shows job logs when job_id provided" do
        expect(jobs_command).to receive(:show_job_logs).with("job123", tail: false, follow: false)
        jobs_command.run("logs", ["job123"])
      end

      it "shows job logs with tail option" do
        expect(jobs_command).to receive(:show_job_logs).with("job123", tail: true, follow: false)
        jobs_command.run("logs", ["job123", "--tail"])
      end

      it "calls display_message when no job_id provided" do
        expect(jobs_command).to receive(:display_message).with("Usage: aidp jobs logs <job_id> [--tail] [--follow]",
          type: :error)
        jobs_command.run("logs", [])
      end
    end

    context "with unknown subcommand" do
      it "shows error messages" do
        expect(jobs_command).to receive(:display_message).with("Unknown jobs subcommand: unknown", type: :error)
        expect(jobs_command).to receive(:display_message).with("Available: list, status, stop, logs", type: :info)
        jobs_command.run("unknown")
      end
    end
  end

  describe "#list_jobs" do
    context "when no jobs exist" do
      before do
        allow(background_runner).to receive(:list_jobs).and_return([])
        allow(jobs_command).to receive(:display_message)
      end

      it "calls display_message multiple times" do
        expect(jobs_command).to receive(:display_message).at_least(:once)
        jobs_command.send(:list_jobs)
      end
    end

    context "when jobs exist" do
      let(:job_data) do
        [
          {
            job_id: "job123",
            mode: :execute,
            started_at: "2023-01-01T10:00:00Z",
            status: "running"
          }
        ]
      end

      before do
        allow(background_runner).to receive(:list_jobs).and_return(job_data)
        allow(jobs_command).to receive(:render_background_jobs)
        allow(jobs_command).to receive(:display_message)
      end

      it "calls render_background_jobs" do
        expect(jobs_command).to receive(:render_background_jobs).with(job_data)
        jobs_command.send(:list_jobs)
      end
    end
  end

  describe "#show_job_status" do
    let(:job_id) { "job123" }

    context "when job exists" do
      let(:job_status) do
        {
          job_id: job_id,
          mode: :execute,
          started_at: "2023-01-01T10:00:00Z",
          status: "running"
        }
      end

      before do
        allow(background_runner).to receive(:job_status).with(job_id).and_return(job_status)
        allow(jobs_command).to receive(:display_message)
      end

      it "retrieves and displays job status" do
        expect(background_runner).to receive(:job_status).with(job_id)
        expect(jobs_command).to receive(:display_message).at_least(:once)
        jobs_command.send(:show_job_status, job_id, follow: false)
      end
    end

    context "when job does not exist" do
      before do
        allow(background_runner).to receive(:job_status).with(job_id).and_return(nil)
        allow(jobs_command).to receive(:display_message)
      end

      it "displays job not found message" do
        expect(jobs_command).to receive(:display_message).at_least(:once)
        jobs_command.send(:show_job_status, job_id, follow: false)
      end
    end
  end

  describe "#stop_job" do
    let(:job_id) { "job123" }

    before do
      allow(background_runner).to receive(:stop_job).and_return({success: true, message: "Job stopped"})
      allow(jobs_command).to receive(:display_message)
    end

    it "calls background_runner to stop job" do
      expect(background_runner).to receive(:stop_job).with(job_id)
      jobs_command.send(:stop_job, job_id)
    end

    it "displays confirmation message" do
      expect(jobs_command).to receive(:display_message).at_least(:once)
      jobs_command.send(:stop_job, job_id)
    end
  end

  describe "#show_job_logs" do
    let(:job_id) { "job123" }

    context "when log content exists" do
      let(:log_content) { "Sample log content" }

      before do
        allow(background_runner).to receive(:job_logs).with(job_id, tail: false, lines: 50).and_return(log_content)
        allow(jobs_command).to receive(:display_message)
        allow(jobs_command).to receive(:puts)
      end

      it "reads and displays log content" do
        expect(background_runner).to receive(:job_logs).with(job_id, tail: false, lines: 50)
        expect(jobs_command).to receive(:display_message).at_least(:once)
        jobs_command.send(:show_job_logs, job_id, tail: false, follow: false)
      end
    end

    context "when no log content exists" do
      before do
        allow(background_runner).to receive(:job_logs).with(job_id, tail: false, lines: 50).and_return(nil)
        allow(jobs_command).to receive(:display_message)
      end

      it "displays no logs found message" do
        expect(jobs_command).to receive(:display_message).with(/No logs found/, type: :error)
        jobs_command.send(:show_job_logs, job_id, tail: false, follow: false)
      end
    end
  end

  describe "private methods" do
    describe "#format_job_status" do
      it "formats running status" do
        formatted = jobs_command.send(:format_job_status, "running")
        expect(formatted).to include("Running")
      end

      it "formats completed status" do
        formatted = jobs_command.send(:format_job_status, "completed")
        expect(formatted).to include("Completed")
      end

      it "formats failed status" do
        formatted = jobs_command.send(:format_job_status, "failed")
        expect(formatted).to include("Failed")
      end

      it "formats unknown status" do
        formatted = jobs_command.send(:format_job_status, "unknown")
        expect(formatted).to include("unknown")
      end
    end

    describe "#format_time" do
      it "formats ISO8601 string timestamps" do
        result = jobs_command.send(:format_time, "2023-01-01T12:34:56Z")
        expect(result).to eq("2023-01-01 12:34:56")
      end

      it "returns N/A when time is nil" do
        expect(jobs_command.send(:format_time, nil)).to eq("N/A")
      end

      it "falls back to to_s for unparsable input" do
        expect(jobs_command.send(:format_time, "not-a-time")).to eq("not-a-time")
      end
    end

    describe "#format_duration_from_start" do
      it "returns formatted duration between timestamps" do
        duration = jobs_command.send(
          :format_duration_from_start,
          "2023-01-01T10:00:00Z",
          "2023-01-01T10:05:30Z"
        )
        expect(duration).to eq("5m 30s")
      end

      it "uses current time when completed_at is nil" do
        allow(Time).to receive(:now).and_return(Time.parse("2023-01-01T10:02:00Z"))

        duration = jobs_command.send(
          :format_duration_from_start,
          "2023-01-01T10:00:00Z",
          nil
        )
        expect(duration).to eq("2m")
      end

      it "returns N/A when start time missing" do
        expect(jobs_command.send(:format_duration_from_start, nil, nil)).to eq("N/A")
      end
    end

    describe "#format_duration" do
      it "returns 0s for nil or non-positive values" do
        expect(jobs_command.send(:format_duration, nil)).to eq("0s")
        expect(jobs_command.send(:format_duration, 0)).to eq("0s")
      end

      it "formats durations with hours, minutes, and seconds" do
        expect(jobs_command.send(:format_duration, 3725)).to eq("1h 2m 5s")
      end
    end

    describe "#format_checkpoint_age" do
      it "returns seconds when under a minute old" do
        allow(Time).to receive(:now).and_return(Time.parse("2023-01-01T12:00:30Z"))
        expect(jobs_command.send(:format_checkpoint_age, "2023-01-01T12:00:00Z")).to eq("30s ago")
      end

      it "returns minutes when under an hour old" do
        allow(Time).to receive(:now).and_return(Time.parse("2023-01-01T12:05:00Z"))
        expect(jobs_command.send(:format_checkpoint_age, "2023-01-01T12:02:00Z")).to eq("3m ago")
      end

      it "returns hours when over an hour old" do
        allow(Time).to receive(:now).and_return(Time.parse("2023-01-01T15:00:00Z"))
        expect(jobs_command.send(:format_checkpoint_age, "2023-01-01T13:00:00Z")).to eq("2h ago")
      end
    end

    describe "#truncate_message" do
      it "returns original message when under limit" do
        expect(jobs_command.send(:truncate_message, "short message")).to eq("short message")
      end

      it "truncates long messages with ellipsis" do
        long_message = "a" * 80
        truncated = jobs_command.send(:truncate_message, long_message)
        expect(truncated).to end_with("...")
        expect(truncated.length).to be < long_message.length
      end
    end

    describe "#determine_job_status" do
      it "returns failed for error level" do
        expect(jobs_command.send(:determine_job_status, {"level" => "error", "message" => ""})).to eq("failed")
      end

      it "returns completed when message notes completion" do
        expect(jobs_command.send(:determine_job_status, {"level" => "info", "message" => "Job completed"}))
          .to eq("completed")
      end

      it "returns retrying when message includes retrying" do
        expect(jobs_command.send(:determine_job_status, {"level" => "info", "message" => "retrying now"}))
          .to eq("retrying")
      end

      it "returns running for other info messages" do
        expect(jobs_command.send(:determine_job_status, {"level" => "info", "message" => "working"}))
          .to eq("running")
      end

      it "returns unknown for unhandled levels" do
        expect(jobs_command.send(:determine_job_status, {"level" => "debug", "message" => ""})).to eq("unknown")
      end
    end

    describe "#fetch_harness_jobs" do
      let(:logs_dir) { File.join(temp_dir, ".aidp", "harness_logs") }

      before do
        FileUtils.mkdir_p(logs_dir)
        allow(Dir).to receive(:pwd).and_return(temp_dir)
        allow(jobs_command).to receive(:display_message)
      end

      it "loads harness jobs from disk sorted by newest first" do
        File.write(File.join(logs_dir, "old_job.json"), JSON.dump({
          "created_at" => "2023-01-01T10:00:00Z",
          "level" => "info",
          "message" => "Still running"
        }))
        File.write(File.join(logs_dir, "new_job.json"), JSON.dump({
          "created_at" => "2023-01-01T11:00:00Z",
          "level" => "info",
          "message" => "completed successfully"
        }))

        jobs = jobs_command.send(:fetch_harness_jobs)

        expect(jobs.map { |job| job[:id] }).to eq(%w[new_job old_job])
        expect(jobs.first[:status]).to eq("completed")
        expect(jobs.first[:message]).to eq("completed successfully")
      end

      it "skips files with invalid JSON" do
        File.write(File.join(logs_dir, "good_job.json"), JSON.dump({
          "created_at" => "2023-01-01T12:00:00Z",
          "level" => "info",
          "message" => "All good"
        }))
        File.write(File.join(logs_dir, "bad_job.json"), "{invalid")

        jobs = jobs_command.send(:fetch_harness_jobs)

        expect(jobs.size).to eq(1)
        expect(jobs.first[:id]).to eq("good_job")
      end
    end
  end
end
