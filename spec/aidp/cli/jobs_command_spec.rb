# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Aidp::CLI::JobsCommand do
  before do
    # Prevent actual job processor from starting
    ENV["QUE_WORKER_COUNT"] = "0"
    ENV["MOCK_DATABASE"] = "true"

    # Mock screen dimensions
    allow(TTY::Screen).to receive(:width).and_return(80)
    allow(TTY::Screen).to receive(:height).and_return(24)

    # Mock Que connection to prevent database issues
    allow(Que).to receive(:connection).and_return(nil)
  end

  after do
    ENV.delete("QUE_WORKER_COUNT")
  end

  describe "#run" do
    context "with no active jobs" do
      it "exits cleanly when no jobs are found" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Mock fetch_jobs to return empty array
        allow(command).to receive(:fetch_jobs).and_return([])

        # Test that run method can be called and exits cleanly
        expect { command.run }.not_to raise_error
      end
    end

    context "with active jobs" do
      it "can fetch job data" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Test that fetch_jobs method can be called
        expect { command.send(:fetch_jobs) }.not_to raise_error
      end

      it "can determine job status" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Test job status determination
        completed_job = {finished_at: Time.now, error_count: 0}
        failed_job = {finished_at: Time.now, error_count: 1}
        running_job = {finished_at: nil, error_count: 0}

        expect(command.send(:job_status, completed_job)).to eq("completed")
        expect(command.send(:job_status, failed_job)).to eq("failed")
        expect(command.send(:job_status, running_job)).to eq("running")
      end
    end

    context "when viewing job details" do
      it "can fetch individual job data" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Test that fetch_job method can be called
        expect { command.send(:fetch_job, "1") }.not_to raise_error
      end

      it "can check if job exists" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Test that job_exists? method can be called
        expect { command.send(:job_exists?, "1") }.not_to raise_error
      end

      it "can switch view modes" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Test view mode switching
        expect(command.instance_variable_get(:@view_mode)).to eq(:list)

        command.send(:switch_to_list)
        expect(command.instance_variable_get(:@view_mode)).to eq(:list)
        expect(command.instance_variable_get(:@selected_job_id)).to be_nil
      end
    end

    context "when retrying jobs" do
      it "can handle retry commands" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Mock the input to return a job ID
        allow(command.instance_variable_get(:@io)).to receive(:gets).and_return("1\n")

        # Test that handle_retry_command method can be called
        expect { command.send(:handle_retry_command) }.not_to raise_error
      end

      it "can handle details commands" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Mock the input to return a job ID
        allow(command.instance_variable_get(:@io)).to receive(:gets).and_return("1\n")

        # Test that handle_details_command method can be called
        expect { command.send(:handle_details_command) }.not_to raise_error
      end
    end

    context "when viewing job output" do
      it "can handle output commands" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Mock the input to return a job ID
        allow(command.instance_variable_get(:@io)).to receive(:gets).and_return("1\n")

        # Test that handle_output_command method can be called
        expect { command.send(:handle_output_command) }.not_to raise_error
      end

      it "can get job output" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Test that get_job_output method can be called
        expect { command.send(:get_job_output, "1") }.not_to raise_error
      end

      it "can detect hung jobs" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Mock a job that's been running for more than 5 minutes
        hung_job = {run_at: Time.now - 400, finished_at: nil, error_count: 0}
        allow(command).to receive(:fetch_job).and_return(hung_job)

        output_result = command.send(:get_job_output, "1")
        expect(output_result).to include("WARNING")
        expect(output_result).to include("hung")
      end
    end

    context "when killing jobs" do
      it "can handle kill commands" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Mock the input to return a job ID and confirmation
        allow(command.instance_variable_get(:@io)).to receive(:gets).and_return("1\n", "y\n")

        # Test that handle_kill_command method can be called
        expect { command.send(:handle_kill_command) }.not_to raise_error
      end

      it "can kill a job" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Test that kill_job method can be called
        expect { command.send(:kill_job, "1") }.not_to raise_error
      end

      it "can format duration" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Test duration formatting
        expect(command.send(:format_duration, 3661)).to eq("1h 1m")  # 1 hour 1 minute
        expect(command.send(:format_duration, 125)).to eq("2m")      # 2 minutes
        expect(command.send(:format_duration, 30)).to eq("0m")       # 30 seconds
      end
    end

    context "when handling keyboard input" do
      it "can handle input processing" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Test that handle_input method can be called
        expect { command.send(:handle_input) }.not_to raise_error
      end

      it "can format runtime" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Test runtime formatting with string timestamps
        now = Time.now
        job_with_runtime = {
          finished_at: now.to_s,
          run_at: (now - 60).to_s
        }
        result = command.send(:format_runtime, job_with_runtime)
        expect(result).to include("1m")
      end

      it "can truncate error messages" do
        input = StringIO.new
        output = StringIO.new
        command = described_class.new(input: input, output: output)

        # Test error message truncation
        long_error = "A" * 100
        truncated = command.send(:truncate_error, long_error)
        expect(truncated.length).to be < long_error.length
        expect(truncated).to end_with("...")
      end
    end
  end
end
