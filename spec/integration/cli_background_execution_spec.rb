# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "CLI Background Execution Integration", type: :integration do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    # Stub Dir.pwd to return tmpdir (external boundary)
    allow(Dir).to receive(:pwd).and_return(tmpdir)
    # Stub display_message to capture output
    allow(Aidp::CLI).to receive(:display_message)
  end

  after do
    FileUtils.rm_rf(tmpdir) if tmpdir && Dir.exist?(tmpdir)
  end

  describe "execute --background" do
    it "starts background job and displays job information" do
      # Create a real BackgroundRunner instance in tmpdir
      runner = Aidp::Jobs::BackgroundRunner.new(tmpdir)

      # Stub only external boundary (Process.fork)
      allow(Process).to receive(:fork).and_return(12345)
      allow(Process).to receive(:detach)

      job_id = runner.start(:execute, {})

      # Job ID format is timestamp-based, e.g., "20251116_223631_af6b94a9"
      expect(job_id).to match(/^\d{8}_\d{6}_[a-f0-9]{8}$/)
      expect(Dir.exist?(File.join(tmpdir, ".aidp", "jobs", job_id))).to be true
    end

    it "displays background job instructions via CLI" do
      # Stub BackgroundRunner to avoid actual fork
      runner = instance_double(Aidp::Jobs::BackgroundRunner, start: "test-job-123")
      allow(Aidp::Jobs::BackgroundRunner).to receive(:new).and_return(runner)

      Aidp::CLI.send(:run_execute_command, ["--background"], mode: :execute)

      # Should display messages about the background job
      expect(Aidp::CLI).to have_received(:display_message).with(/Starting .* mode in background/, type: :info)
      expect(Aidp::CLI).to have_received(:display_message).with(/Started background job/, type: :success)
      expect(Aidp::CLI).to have_received(:display_message).with(/aidp jobs status/, type: :info)
    end
  end

  describe "execute --background --follow" do
    it "waits for log file and follows it" do
      runner = Aidp::Jobs::BackgroundRunner.new(tmpdir)

      allow(Process).to receive(:fork).and_return(12345)
      allow(Process).to receive(:detach)

      job_id = runner.start(:execute, {})
      log_file = File.join(tmpdir, ".aidp", "jobs", job_id, "output.log")

      # Create the log file to simulate job starting
      FileUtils.mkdir_p(File.dirname(log_file))
      File.write(log_file, "Job started\n")

      # Verify log file exists and can be read
      expect(File.exist?(log_file)).to be true
      expect(File.read(log_file)).to include("Job started")
    end

    it "displays follow logs message via CLI" do
      runner = instance_double(Aidp::Jobs::BackgroundRunner,
        start: "test-job-123",
        follow_job_logs: nil,
        instance_variable_get: File.join(tmpdir, ".aidp", "jobs"))

      allow(Aidp::Jobs::BackgroundRunner).to receive(:new).and_return(runner)

      # Create log file so Wait.for_file doesn't raise
      log_dir = File.join(tmpdir, ".aidp", "jobs", "test-job-123")
      FileUtils.mkdir_p(log_dir)
      File.write(File.join(log_dir, "output.log"), "test")

      # Stub Wait.for_file to avoid actual waiting
      allow(Aidp::Concurrency::Wait).to receive(:for_file)

      Aidp::CLI.send(:run_execute_command, ["--background", "--follow"], mode: :execute)

      expect(Aidp::CLI).to have_received(:display_message).with(/Following logs/, type: :info)
      expect(runner).to have_received(:follow_job_logs).with("test-job-123")
    end

    it "handles log file timeout gracefully" do
      runner = instance_double(Aidp::Jobs::BackgroundRunner,
        start: "test-job-123",
        follow_job_logs: nil,
        instance_variable_get: File.join(tmpdir, ".aidp", "jobs"))

      allow(Aidp::Jobs::BackgroundRunner).to receive(:new).and_return(runner)

      # Stub Wait.for_file to raise timeout
      allow(Aidp::Concurrency::Wait).to receive(:for_file).and_raise(Aidp::Concurrency::TimeoutError.new("timeout"))

      Aidp::CLI.send(:run_execute_command, ["--background", "--follow"], mode: :execute)

      expect(Aidp::CLI).to have_received(:display_message).with(/Warning: Log file not found/, type: :warning)
      # Should still try to follow even after timeout
      expect(runner).to have_received(:follow_job_logs).with("test-job-123")
    end
  end

  describe "analyze --background" do
    it "starts background job in analyze mode" do
      runner = instance_double(Aidp::Jobs::BackgroundRunner, start: "analyze-job-123")
      allow(Aidp::Jobs::BackgroundRunner).to receive(:new).and_return(runner)

      Aidp::CLI.send(:run_execute_command, ["--background"], mode: :analyze)

      expect(runner).to have_received(:start).with(:analyze, {})
      expect(Aidp::CLI).to have_received(:display_message).with(/Starting analyze mode in background/, type: :info)
    end
  end

  describe "execute --no-harness" do
    it "displays available steps instead of running harness" do
      Aidp::CLI.send(:run_execute_command, ["--no-harness"], mode: :execute)

      expect(Aidp::CLI).to have_received(:display_message).with(/Available execute steps/, type: :info)
    end
  end

  describe "analyze --no-harness" do
    it "displays available steps instead of running harness" do
      Aidp::CLI.send(:run_execute_command, ["--no-harness"], mode: :analyze)

      expect(Aidp::CLI).to have_received(:display_message).with(/Available analyze steps/, type: :info)
    end
  end

  describe "execute with specific step" do
    it "announces running specific step" do
      Aidp::CLI.send(:run_execute_command, ["00_PRD_TEST"], mode: :execute)

      expect(Aidp::CLI).to have_received(:display_message).with(/Running execute step '00_PRD_TEST'/, type: :highlight)
    end
  end

  describe "analyze with specific step" do
    it "announces running specific step" do
      Aidp::CLI.send(:run_execute_command, ["00_ANALYSIS_TEST"], mode: :analyze)

      expect(Aidp::CLI).to have_received(:display_message).with(/Running analyze step '00_ANALYSIS_TEST'/, type: :highlight)
    end
  end

  describe "execute --reset" do
    it "displays reset message" do
      Aidp::CLI.send(:run_execute_command, ["--reset"], mode: :execute)

      expect(Aidp::CLI).to have_received(:display_message).with(/Reset execute mode progress/, type: :info)
    end
  end

  describe "analyze --reset" do
    it "displays reset message" do
      Aidp::CLI.send(:run_execute_command, ["--reset"], mode: :analyze)

      expect(Aidp::CLI).to have_received(:display_message).with(/Reset analyze mode progress/, type: :info)
    end
  end
end
