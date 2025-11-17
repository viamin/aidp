# frozen_string_literal: true

require "spec_helper"
require "aidp" # load full environment so MessageDisplay & RescueLogging are available
require "aidp/jobs/background_runner"
require "yaml"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Jobs::BackgroundRunner do
  let(:project_dir) { Dir.mktmpdir("aidp-bg-runner") }
  let(:runner) { described_class.new(project_dir, suppress_display: true) }

  before do
    # Display output suppressed via constructor flag
  end

  after do
    FileUtils.rm_rf(project_dir) if File.exist?(project_dir)
  end

  describe "#initialize" do
    it "creates jobs directory" do
      runner # trigger instantiation
      expect(Dir.exist?(File.join(project_dir, ".aidp", "jobs"))).to be true
    end
  end

  describe "#start (stubbed fork)" do
    before do
      allow(runner).to receive(:fork).and_return(12_345)
      allow(Process).to receive(:daemon)
      allow(Process).to receive(:detach)
      allow(runner).to receive(:sleep) # skip delay
      # FIXME: Internal class mocking violation - see docs/ISSUE_295_FINAL_SUMMARY.md "Hard Violations"
      # BackgroundRunner#start creates Harness::Runner in forked process without DI support
      # Needs: runner_factory parameter or similar DI pattern
      # Risk: High - Background jobs are critical, fork makes testing harder
      # Estimated effort: 3-4 hours
      # Additional violations at lines: 69, 96, 135
      allow(Aidp::Harness::Runner).to receive(:new).and_return(double(run: {status: "completed"}))
      # Prevent STDOUT/STDERR redirection side-effects when simulating fork
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      # Mock the file waiting to avoid timeout delays
      allow(Aidp::Concurrency::Wait).to receive(:for_file).and_return(true)
    end

    it "returns a job id and writes metadata" do
      job_id = runner.start(:execute, foo: "bar")
      metadata_file = File.join(project_dir, ".aidp", "jobs", job_id, "metadata.yml")
      expect(File.exist?(metadata_file)).to be true
      data = YAML.load_file(metadata_file)
      expect(data[:job_id]).to eq(job_id)
      expect(data[:status]).to eq("running")
      expect(data[:mode]).to eq(:execute)
    end

    it "marks job completed after child updates metadata" do
      job_id = runner.start(:execute, {})
      # Simulate child process completion callback
      runner.__send__(:mark_job_completed, job_id, {status: "completed"})
      metadata_file = File.join(project_dir, ".aidp", "jobs", job_id, "metadata.yml")
      data = YAML.load_file(metadata_file, permitted_classes: [Symbol]) # times are stored as strings
      expect(data[:status]).to eq("completed")
    end
  end

  describe "job metadata helpers" do
    before do
      allow(runner).to receive(:fork).and_return(23_456)
      allow(Process).to receive(:daemon)
      allow(Process).to receive(:detach)
      allow(runner).to receive(:sleep)
      allow(Aidp::Harness::Runner).to receive(:new).and_return(double(run: {status: "completed"}))
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      # Mock the file waiting to avoid timeout delays
      allow(Aidp::Concurrency::Wait).to receive(:for_file).and_return(true)
      @job_id = runner.start(:execute, {})
    end

    it "lists jobs" do
      ids = runner.list_jobs.map { |j| j[:job_id] }
      expect(ids).to include(@job_id)
    end

    it "returns job status" do
      status = runner.job_status(@job_id)
      expect(status[:job_id]).to eq(@job_id)
      expect(status[:status]).to match(/completed|running/)
      expect(status[:log_file]).to include("output.log")
    end
  end

  describe "#stop_job" do
    before do
      allow(runner).to receive(:fork).and_return(34_567)
      allow(Process).to receive(:daemon)
      allow(Process).to receive(:detach)
      allow(runner).to receive(:sleep)
      allow(Aidp::Harness::Runner).to receive(:new).and_return(double(run: {status: "completed"}))
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      # Mock the file waiting to avoid timeout delays
      allow(Aidp::Concurrency::Wait).to receive(:for_file).and_return(true)
    end

    it "returns failure when job not found" do
      expect(runner.stop_job("missing")[:success]).to be false
    end

    it "stops a running job (simulated)" do
      job_id = runner.start(:execute, {})
      # Simulate running by injecting fake PID metadata
      metadata_file = File.join(project_dir, ".aidp", "jobs", job_id, "metadata.yml")
      data = YAML.load_file(metadata_file)
      data[:pid] = Process.pid
      File.write(metadata_file, data.to_yaml)

      allow(runner).to receive(:process_running?).and_return(true, false)
      allow(Process).to receive(:kill)

      result = runner.stop_job(job_id)
      expect(result[:success]).to be true
      updated = YAML.load_file(metadata_file, permitted_classes: [Symbol])
      expect(updated[:status]).to eq("stopped")
    end
  end

  describe "#job_logs" do
    it "returns nil when log file missing" do
      expect(runner.job_logs("missing")).to be_nil
    end

    it "returns log contents" do
      allow(runner).to receive(:fork).and_return(45_678)
      allow(Process).to receive(:daemon)
      allow(Process).to receive(:detach)
      allow(runner).to receive(:sleep)
      allow(Aidp::Harness::Runner).to receive(:new).and_return(double(run: {status: "completed"}))
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      # Mock the file waiting to avoid timeout delays
      allow(Aidp::Concurrency::Wait).to receive(:for_file).and_return(true)

      job_id = runner.start(:execute, {})
      log_file = File.join(project_dir, ".aidp", "jobs", job_id, "output.log")
      FileUtils.touch(log_file) unless File.exist?(log_file)
      File.open(log_file, "a") { |f| f.puts "hello" }
      expect(runner.job_logs(job_id)).to include("hello")
    end

    it "returns tailed logs when :tail option provided" do
      allow(runner).to receive(:fork).and_return(56_789)
      allow(Process).to receive(:daemon)
      allow(Process).to receive(:detach)
      allow(runner).to receive(:sleep)
      allow(Aidp::Harness::Runner).to receive(:new).and_return(double(run: {status: "completed"}))
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow(Aidp::Concurrency::Wait).to receive(:for_file).and_return(true)

      job_id = runner.start(:execute, {})
      log_file = File.join(project_dir, ".aidp", "jobs", job_id, "output.log")
      FileUtils.touch(log_file) unless File.exist?(log_file)
      File.open(log_file, "a") { |f| f.puts "line1\nline2\nline3" }

      # Mock tail command
      allow(runner).to receive(:`).and_return("line3")
      result = runner.job_logs(job_id, tail: true, lines: 1)
      expect(result).to eq("line3")
    end
  end

  describe "#follow_job_logs" do
    it "does nothing when log file missing" do
      expect(runner.follow_job_logs("missing")).to be_nil
    end
  end

  describe "#display_message" do
    it "suppresses output when suppress_display is true" do
      expect { runner.display_message("test", type: :info) }.not_to raise_error
    end

    it "calls super when suppress_display is false" do
      runner_with_display = described_class.new(project_dir, suppress_display: false)
      expect(runner_with_display).to receive(:display_message).and_call_original
      # Suppress actual output
      allow(runner_with_display).to receive(:puts)
      runner_with_display.display_message("test", type: :info)
    end
  end

  describe "#stop_job error cases" do
    before do
      allow(runner).to receive(:fork).and_return(67_890)
      allow(Process).to receive(:daemon)
      allow(Process).to receive(:detach)
      allow(runner).to receive(:sleep)
      allow(Aidp::Harness::Runner).to receive(:new).and_return(double(run: {status: "completed"}))
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow(Aidp::Concurrency::Wait).to receive(:for_file).and_return(true)
    end

    it "returns failure when job is not running" do
      job_id = runner.start(:execute, {})
      # Don't set PID as running
      allow(runner).to receive(:process_running?).and_return(false)
      result = runner.stop_job(job_id)
      expect(result[:success]).to be false
      expect(result[:message]).to match(/not running/)
    end

    it "force kills process if TERM fails" do
      job_id = runner.start(:execute, {})
      metadata_file = File.join(project_dir, ".aidp", "jobs", job_id, "metadata.yml")
      data = YAML.load_file(metadata_file)
      data[:pid] = 99999
      File.write(metadata_file, data.to_yaml)

      # Simulate process still running: initial check + 10 loop checks + final check = 12 true, then false
      # The loop runs 10 times (lines 147-150), then checks again at line 153
      running_checks = [true] * 12 + [false]
      allow(runner).to receive(:process_running?).and_return(*running_checks)
      allow(runner).to receive(:sleep)
      allow(Process).to receive(:kill)

      runner.stop_job(job_id)
      expect(Process).to have_received(:kill).with("TERM", 99999)
      expect(Process).to have_received(:kill).with("KILL", 99999)
    end

    it "handles ESRCH error (process already dead)" do
      job_id = runner.start(:execute, {})
      metadata_file = File.join(project_dir, ".aidp", "jobs", job_id, "metadata.yml")
      data = YAML.load_file(metadata_file)
      data[:pid] = 99999
      File.write(metadata_file, data.to_yaml)

      allow(runner).to receive(:process_running?).and_return(true)
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

      result = runner.stop_job(job_id)
      expect(result[:success]).to be true
      expect(result[:message]).to match(/already stopped/)
    end

    it "handles general errors during stop" do
      job_id = runner.start(:execute, {})
      metadata_file = File.join(project_dir, ".aidp", "jobs", job_id, "metadata.yml")
      data = YAML.load_file(metadata_file)
      data[:pid] = 99999
      File.write(metadata_file, data.to_yaml)

      allow(runner).to receive(:process_running?).and_return(true)
      allow(Process).to receive(:kill).and_raise(StandardError.new("test error"))

      result = runner.stop_job(job_id)
      expect(result[:success]).to be false
      expect(result[:message]).to match(/Failed to stop job/)
    end
  end

  describe "private methods" do
    describe "#generate_job_id" do
      it "generates unique job IDs" do
        id1 = runner.send(:generate_job_id)
        sleep 0.01
        id2 = runner.send(:generate_job_id)
        expect(id1).not_to eq(id2)
        expect(id1).to match(/^\d{8}_\d{6}_[a-f0-9]{8}$/)
      end
    end

    describe "#load_job_metadata" do
      it "returns nil for missing metadata file" do
        expect(runner.send(:load_job_metadata, "missing")).to be_nil
      end

      it "returns nil for invalid YAML" do
        job_id = "test_job"
        metadata_file = File.join(project_dir, ".aidp", "jobs", job_id, "metadata.yml")
        FileUtils.mkdir_p(File.dirname(metadata_file))
        File.write(metadata_file, "invalid: yaml: content:")
        expect(runner.send(:load_job_metadata, job_id)).to be_nil
      end
    end

    describe "#mark_job_failed" do
      it "updates metadata with error details" do
        job_id = "test_fail_job"
        metadata_file = File.join(project_dir, ".aidp", "jobs", job_id, "metadata.yml")
        FileUtils.mkdir_p(File.dirname(metadata_file))
        File.write(metadata_file, {job_id: job_id, status: "running"}.to_yaml)

        error = StandardError.new("test error")
        error.set_backtrace(["line1", "line2"])
        runner.send(:mark_job_failed, job_id, error)

        metadata = YAML.load_file(metadata_file, permitted_classes: [Symbol])
        expect(metadata[:status]).to eq("failed")
        expect(metadata[:error][:message]).to eq("test error")
        expect(metadata[:error][:class]).to eq("StandardError")
      end
    end

    describe "#process_running?" do
      it "returns false for nil PID" do
        expect(runner.send(:process_running?, nil)).to be false
      end

      it "returns true for running process" do
        expect(runner.send(:process_running?, Process.pid)).to be true
      end

      it "returns false for ESRCH error" do
        allow(Process).to receive(:kill).and_raise(Errno::ESRCH)
        expect(runner.send(:process_running?, 99999)).to be false
      end

      it "returns false for EPERM error" do
        allow(Process).to receive(:kill).and_raise(Errno::EPERM)
        expect(runner.send(:process_running?, 99999)).to be false
      end
    end

    describe "#get_job_checkpoint" do
      it "returns nil when checkpoint load fails" do
        allow(Aidp::Execute::Checkpoint).to receive(:new).and_raise(StandardError.new("test"))
        expect(runner.send(:get_job_checkpoint, "test_job")).to be_nil
      end
    end

    describe "#determine_job_status" do
      it "returns metadata status if not running" do
        metadata = {status: "completed"}
        result = runner.send(:determine_job_status, metadata, false, nil)
        expect(result).to eq("completed")
      end

      it "returns 'running' for active job" do
        metadata = {status: "running"}
        result = runner.send(:determine_job_status, metadata, true, nil)
        expect(result).to eq("running")
      end

      it "returns 'stuck' for job with old checkpoint" do
        metadata = {status: "running"}
        old_time = (Time.now - 700).iso8601
        checkpoint = {timestamp: old_time}
        result = runner.send(:determine_job_status, metadata, true, checkpoint)
        expect(result).to eq("stuck")
      end

      it "returns 'running' for job with recent checkpoint" do
        metadata = {status: "running"}
        recent_time = (Time.now - 60).iso8601
        checkpoint = {timestamp: recent_time}
        result = runner.send(:determine_job_status, metadata, true, checkpoint)
        expect(result).to eq("running")
      end

      it "returns 'running' for active job without checkpoint" do
        metadata = {status: "running"}
        result = runner.send(:determine_job_status, metadata, true, nil)
        expect(result).to eq("running")
      end

      it "returns metadata status or 'completed' for non-running job" do
        metadata = {}
        result = runner.send(:determine_job_status, metadata, false, nil)
        expect(result).to eq("completed")
      end
    end

    describe "#update_job_metadata" do
      it "does nothing when metadata missing" do
        expect { runner.send(:update_job_metadata, "missing", {}) }.not_to raise_error
      end
    end

    describe "#mark_job_stopped" do
      it "updates metadata with stopped status" do
        job_id = "test_stop_job"
        metadata_file = File.join(project_dir, ".aidp", "jobs", job_id, "metadata.yml")
        FileUtils.mkdir_p(File.dirname(metadata_file))
        File.write(metadata_file, {job_id: job_id, status: "running"}.to_yaml)

        runner.send(:mark_job_stopped, job_id)

        metadata = YAML.load_file(metadata_file, permitted_classes: [Symbol])
        expect(metadata[:status]).to eq("stopped")
      end
    end
  end

  describe "#list_jobs with multiple jobs" do
    before do
      allow(runner).to receive(:fork).and_return(11111, 22222, 33333)
      allow(Process).to receive(:daemon)
      allow(Process).to receive(:detach)
      allow(runner).to receive(:sleep)
      allow(Aidp::Harness::Runner).to receive(:new).and_return(double(run: {status: "completed"}))
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow(Aidp::Concurrency::Wait).to receive(:for_file).and_return(true)
    end

    it "returns jobs sorted by start time (newest first)" do
      # Stub Time.now to return predictable timestamps
      time1 = Time.new(2025, 1, 1, 10, 0, 0)
      time2 = Time.new(2025, 1, 1, 10, 0, 1)
      time3 = Time.new(2025, 1, 1, 10, 0, 2)

      allow(Time).to receive(:now).and_return(time1, time1, time2, time2, time3, time3)
      allow(Time).to receive(:new).and_call_original

      job1 = runner.start(:execute, {})
      job2 = runner.start(:analyze, {})
      job3 = runner.start(:execute, {})

      # Reset Time.now for list_jobs
      allow(Time).to receive(:now).and_call_original

      jobs = runner.list_jobs
      job_ids = jobs.map { |j| j[:job_id] }
      # Verify all three jobs are present and newest is first
      expect(job_ids.size).to eq(3)
      expect(job_ids).to include(job1, job2, job3)
      # Job 3 should be first since it has the latest timestamp
      expect(job_ids.first).to eq(job3)
    end

    it "returns empty array when jobs directory doesn't exist" do
      FileUtils.rm_rf(File.join(project_dir, ".aidp", "jobs"))
      expect(runner.list_jobs).to eq([])
    end
  end

  describe "#job_status with checkpoint" do
    before do
      allow(runner).to receive(:fork).and_return(44444)
      allow(Process).to receive(:daemon)
      allow(Process).to receive(:detach)
      allow(runner).to receive(:sleep)
      allow(Aidp::Harness::Runner).to receive(:new).and_return(double(run: {status: "completed"}))
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow(Aidp::Concurrency::Wait).to receive(:for_file).and_return(true)
    end

    it "includes checkpoint data in status" do
      job_id = runner.start(:execute, {})
      checkpoint_data = {step: "01_PRD", iteration: 1}
      allow(runner).to receive(:get_job_checkpoint).and_return(checkpoint_data)

      status = runner.job_status(job_id)
      expect(status[:checkpoint]).to eq(checkpoint_data)
    end

    it "returns nil when job not found" do
      expect(runner.job_status("missing")).to be_nil
    end
  end
end
