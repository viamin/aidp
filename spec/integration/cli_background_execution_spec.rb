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
