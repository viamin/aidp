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
  end
end
