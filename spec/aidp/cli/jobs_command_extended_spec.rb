# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/aidp/cli/jobs_command"

RSpec.describe Aidp::CLI::JobsCommand do
  let(:input) { StringIO.new }
  let(:output) { StringIO.new }
  let(:prompt) { TestPrompt.new }
  let(:instance) { described_class.new(input: input, output: output, prompt: prompt) }

  describe "private utility methods" do
    describe "#format_time" do
      it "formats Time objects" do
        t = Time.new(2024, 1, 1, 12, 0, 0, "+00:00")
        expect(instance.send(:format_time, t)).to match(/2024-01-01 12:00:00/)
      end

      it "formats ISO8601 strings" do
        expect(instance.send(:format_time, "2024-01-01T12:00:00Z")).to match(/2024-01-01 12:00:00/)
      end

      it "returns N/A for nil" do
        expect(instance.send(:format_time, nil)).to eq("N/A")
      end

      it "falls back to to_s on parse error" do
        expect(instance.send(:format_time, "not-a-time")).to eq("not-a-time")
      end
    end

    describe "#format_duration_from_start" do
      it "returns N/A when start missing" do
        expect(instance.send(:format_duration_from_start, nil, Time.now)).to eq("N/A")
      end

      it "shows seconds only for short durations" do
        started = Time.now - 5
        expect(instance.send(:format_duration_from_start, started, Time.now)).to eq("5s")
      end

      it "shows minutes and seconds" do
        started = Time.now - 125 # 2m5s
        formatted = instance.send(:format_duration_from_start, started, Time.now)
        expect(formatted).to include("2m")
        expect(formatted).to include("5s")
      end

      it "shows hours component" do
        started = Time.now - 3665 # 1h1m5s
        formatted = instance.send(:format_duration_from_start, started, Time.now)
        expect(formatted).to include("1h")
        expect(formatted).to include("1m")
        expect(formatted).to include("5s")
      end
    end

    describe "#format_checkpoint_age" do
      it "returns seconds for age < 60" do
        ts = (Time.now - 10).iso8601
        expect(instance.send(:format_checkpoint_age, ts)).to match(/10s ago/)
      end

      it "returns minutes for age < 3600" do
        ts = (Time.now - 120).iso8601
        expect(instance.send(:format_checkpoint_age, ts)).to match(/2m ago/)
      end

      it "returns hours for age >= 3600" do
        ts = (Time.now - 7200).iso8601
        expect(instance.send(:format_checkpoint_age, ts)).to match(/2h ago/)
      end

      it "returns N/A for nil" do
        expect(instance.send(:format_checkpoint_age, nil)).to eq("N/A")
      end
    end

    describe "#determine_job_status" do
      it "maps error level to failed" do
        log_data = {"level" => "error", "message" => "boom"}
        expect(instance.send(:determine_job_status, log_data)).to eq("failed")
      end

      it "maps info with completed to completed" do
        log_data = {"level" => "info", "message" => "Job completed successfully"}
        expect(instance.send(:determine_job_status, log_data)).to eq("completed")
      end

      it "maps info with retrying to retrying" do
        log_data = {"level" => "info", "message" => "retrying due to network"}
        expect(instance.send(:determine_job_status, log_data)).to eq("retrying")
      end

      it "maps info without keywords to running" do
        log_data = {"level" => "info", "message" => "Working..."}
        expect(instance.send(:determine_job_status, log_data)).to eq("running")
      end

      it "returns unknown for other levels" do
        log_data = {"level" => "debug", "message" => "details"}
        expect(instance.send(:determine_job_status, log_data)).to eq("unknown")
      end
    end

    describe "#truncate_message" do
      it "returns N/A for nil" do
        expect(instance.send(:truncate_message, nil)).to eq("N/A")
      end

      it "returns original when short" do
        msg = "short message"
        expect(instance.send(:truncate_message, msg)).to eq(msg)
      end

      it "truncates long messages" do
        long = "a" * 200
        truncated = instance.send(:truncate_message, long)
        expect(truncated.length).to be < long.length
        expect(truncated).to end_with("...")
      end
    end
  end

  describe "harness jobs integration" do
    let(:temp_dir) { Dir.mktmpdir("harness_jobs") }
    let(:harness_dir) { File.join(temp_dir, ".aidp", "harness_logs") }
    before do
      FileUtils.mkdir_p(harness_dir)
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it "fetches and sorts harness jobs" do
      # Create sample logs
      File.write(File.join(harness_dir, "job1.json"), {created_at: (Time.now - 60).iso8601, level: "info", message: "Job completed"}.to_json)
      File.write(File.join(harness_dir, "job2.json"), {created_at: (Time.now - 10).iso8601, level: "error", message: "Failure"}.to_json)

      Dir.chdir(temp_dir) do
        jobs = instance.send(:fetch_harness_jobs)
        expect(jobs.size).to eq(2)
        expect(jobs.first[:id]).to eq("job2") # newest first
        expect(jobs.map { |j| j[:status] }).to include("failed", "completed")
      end
    end

    it "skips malformed JSON without raising" do
      File.write(File.join(harness_dir, "bad.json"), "{invalid")
      Dir.chdir(temp_dir) do
        expect { instance.send(:fetch_harness_jobs) }.not_to raise_error
      end
    end

    it "renders harness jobs box" do
      File.write(File.join(harness_dir, "job3.json"), {created_at: Time.now.iso8601, level: "info", message: "Working..."}.to_json)
      Dir.chdir(temp_dir) do
        jobs = instance.send(:fetch_harness_jobs)
        allow(instance).to receive(:display_message)
        instance.send(:render_harness_jobs, jobs)
        expect(instance).to have_received(:display_message).at_least(:once)
      end
    end
  end
end
