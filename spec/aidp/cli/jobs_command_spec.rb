# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Aidp::CLI::JobsCommand do
  let(:command) { described_class.new }
  let(:mock_stdin) { StringIO.new }
  let(:mock_stdout) { StringIO.new }

  before do
    # Stub stdin/stdout to prevent actual terminal interaction
    allow($stdin).to receive(:ready?).and_return(false)
    allow($stdout).to receive(:write) { |msg| mock_stdout.write(msg) }
    allow($stdout).to receive(:flush)

    # Prevent actual job processor from starting
    ENV["QUE_WORKER_COUNT"] = "0"

    # Set up test database config
    allow(Que).to receive(:connection=)
    allow(Que).to receive(:migrate!)
  end

  after do
    ENV.delete("QUE_WORKER_COUNT")
  end



  describe "#run" do
    context "with no jobs" do
      it "displays empty state message" do
        # Simulate Ctrl-C after first render
        expect(command).to receive(:sleep).and_raise(Interrupt)

        command.run

        expect(mock_stdout.string).to include("No Background Jobs")
        expect(mock_stdout.string).to include("No jobs are currently running")
      end
    end

    context "with active jobs" do
      before do
        # Create some test jobs
        create_mock_job(id: 1)
        create_mock_job(id: 2, error: "Test error")
        create_mock_job(id: 3, status: "running")
      end

      it "displays job list with current status" do
        expect(command).to receive(:sleep).and_raise(Interrupt)

        command.run

        output = mock_stdout.string
        expect(output).to include("Background Jobs")
        expect(output).to include("ProviderExecutionJob")
        expect(output).to include("completed")
        expect(output).to include("failed")
        expect(output).to include("Test error")
      end

      it "updates job status in real-time" do
        # First render
        expect(command).to receive(:sleep) do
          # Update a job status
          create_mock_job(id: 3, status: "completed")
          raise Interrupt
        end

        command.run

        expect(mock_stdout.string).to include("completed")
      end
    end

    context "when viewing job details" do
      before do
        create_mock_job(id: 1)
      end

      it "displays detailed job information" do
        # Simulate: press 'd', enter job ID, then Ctrl-C
        allow($stdin).to receive(:ready?).and_return(true)
        allow($stdin).to receive(:getch).and_return("d")
        allow(command).to receive(:gets).and_return("1\n")
        expect(command).to receive(:sleep).and_raise(Interrupt)

        command.run

        output = mock_stdout.string
        expect(output).to include("Job Details - ID: 1")
        expect(output).to include("ProviderExecutionJob")
        expect(output).to include("test_queue")
      end

      it "handles invalid job IDs gracefully" do
        allow($stdin).to receive(:ready?).and_return(true)
        allow($stdin).to receive(:getch).and_return("d")
        allow(command).to receive(:gets).and_return("999\n")
        expect(command).to receive(:sleep).and_raise(Interrupt)

        command.run

        # Should fall back to job list
        expect(mock_stdout.string).to include("Background Jobs")
      end
    end

    context "when retrying jobs" do
      before do
        create_mock_job(id: 1, error: "Test error")
      end

      it "retries failed jobs" do
        allow($stdin).to receive(:ready?).and_return(true)
        allow($stdin).to receive(:getch).and_return("r")
        allow(command).to receive(:gets).and_return("1\n")
        expect(command).to receive(:sleep).and_raise(Interrupt)

        command.run

        # Check job was reset for retry
        job = Que.execute("SELECT * FROM que_jobs WHERE job_id = $1", [1]).first
        expect(job["error_count"]).to eq(0)
        expect(job["last_error_message"]).to be_nil
      end

      it "only retries failed jobs" do
        create_mock_job(id: 2) # Completed job

        allow($stdin).to receive(:ready?).and_return(true)
        allow($stdin).to receive(:getch).and_return("r")
        allow(command).to receive(:gets).and_return("2\n")
        expect(command).to receive(:sleep).and_raise(Interrupt)

        command.run

        # Check job was not changed
        job = Que.execute("SELECT * FROM que_jobs WHERE job_id = $1", [2]).first
        expect(job["finished_at"]).not_to be_nil
      end
    end

    context "when handling keyboard input" do
      before do
        create_mock_job(id: 1)
      end

      it "exits on 'q'" do
        allow($stdin).to receive(:ready?).and_return(true)
        allow($stdin).to receive(:getch).and_return("q")

        command.run

        expect(mock_stdout.string).to include("Background Jobs")
      end

      it "toggles details view on 'd' and 'b'" do
        # Simulate: press 'd', enter job ID, press 'b', then Ctrl-C
        allow($stdin).to receive(:ready?).and_return(true)
        allow($stdin).to receive(:getch).and_return("d", "b")
        allow(command).to receive(:gets).and_return("1\n")
        expect(command).to receive(:sleep).and_raise(Interrupt)

        command.run

        output = mock_stdout.string
        expect(output).to include("Job Details")
        expect(output).to include("Background Jobs") # Back to list
      end
    end
  end
end
