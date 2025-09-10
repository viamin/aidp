# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/harness/job_manager"

RSpec.describe Aidp::Harness::JobManager do
  let(:project_dir) { "/tmp/test_project" }
  let(:harness_runner) { double("harness_runner") }
  let(:job_manager) { described_class.new(project_dir, harness_runner) }

  before do
    allow(harness_runner).to receive(:record_job_created)
    allow(harness_runner).to receive(:record_job_status_change)
    allow(harness_runner).to receive(:record_job_retry)
    allow(harness_runner).to receive(:record_job_cancelled)
    allow(harness_runner).to receive(:log_job_message)
  end

  describe "initialization" do
    it "creates job manager successfully" do
      expect(job_manager).to be_a(described_class)
      expect(job_manager.instance_variable_get(:@project_dir)).to eq(project_dir)
      expect(job_manager.instance_variable_get(:@harness_runner)).to eq(harness_runner)
    end

    it "initializes with empty job collections" do
      expect(job_manager.get_harness_jobs).to be_empty
      expect(job_manager.get_job_metrics).to include(
        total_jobs: 0,
        successful_jobs: 0,
        failed_jobs: 0,
        running_jobs: 0,
        queued_jobs: 0
      )
    end
  end

  describe "job creation" do
    let(:job_class) { double("job_class", name: "TestJob") }
    let(:args) { { step_name: "test_step", provider_type: "claude" } }

    it "creates a harness job successfully" do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")

      job_id = job_manager.create_harness_job(job_class, args)

      expect(job_id).to be_a(String)
      expect(job_id).to start_with("harness_")

      job = job_manager.get_harness_job(job_id)
      expect(job).to include(
        :id,
        :que_job_id,
        :job_class,
        :args,
        :status,
        :created_at,
        :harness_context,
        :metrics
      )
      expect(job[:status]).to eq(:queued)
      expect(job[:job_class]).to eq("TestJob")
      expect(job[:args][:step_name]).to eq("test_step")
      expect(job[:harness_context][:project_dir]).to eq(project_dir)
    end

    it "notifies harness runner when job is created" do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")

      job_id = job_manager.create_harness_job(job_class, args)

      expect(harness_runner).to have_received(:record_job_created).with(
        job_id,
        "TestJob",
        hash_including(:step_name, :provider_type, :harness_context)
      )
    end

    it "updates job metrics when job is created" do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")

      job_manager.create_harness_job(job_class, args)

      metrics = job_manager.get_job_metrics
      expect(metrics[:total_jobs]).to eq(1)
      expect(metrics[:queued_jobs]).to eq(1)
    end
  end

  describe "job status updates" do
    let(:job_class) { double("job_class", name: "TestJob") }
    let(:args) { { step_name: "test_step", provider_type: "claude" } }
    let(:job_id) do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")
      job_manager.create_harness_job(job_class, args)
    end

    it "updates job status to running" do
      job_manager.update_job_status(job_id, :running)

      job = job_manager.get_harness_job(job_id)
      expect(job[:status]).to eq(:running)
      expect(job[:metrics][:start_time]).to be_a(Time)

      metrics = job_manager.get_job_metrics
      expect(metrics[:running_jobs]).to eq(1)
      expect(metrics[:queued_jobs]).to eq(0)
    end

    it "updates job status to completed" do
      job_manager.update_job_status(job_id, :running)
      job_manager.update_job_status(job_id, :completed, result: "test result")

      job = job_manager.get_harness_job(job_id)
      expect(job[:status]).to eq(:completed)
      expect(job[:metrics][:end_time]).to be_a(Time)
      expect(job[:metrics][:duration]).to be_a(Numeric)
      expect(job[:result]).to eq("test result")

      metrics = job_manager.get_job_metrics
      expect(metrics[:successful_jobs]).to eq(1)
      expect(metrics[:running_jobs]).to eq(0)
    end

    it "updates job status to failed" do
      job_manager.update_job_status(job_id, :running)
      job_manager.update_job_status(job_id, :failed, error: "test error")

      job = job_manager.get_harness_job(job_id)
      expect(job[:status]).to eq(:failed)
      expect(job[:metrics][:end_time]).to be_a(Time)
      expect(job[:metrics][:duration]).to be_a(Numeric)
      expect(job[:metrics][:error_messages]).to include("test error")
      expect(job[:metrics][:retry_count]).to eq(1)

      metrics = job_manager.get_job_metrics
      expect(metrics[:failed_jobs]).to eq(1)
      expect(metrics[:running_jobs]).to eq(0)
    end

    it "notifies harness runner of status changes" do
      job_manager.update_job_status(job_id, :running)

      expect(harness_runner).to have_received(:record_job_status_change).with(
        job_id,
        :queued,
        :running,
        nil,
        nil
      )
    end
  end

  describe "job queries" do
    let(:job_class) { double("job_class", name: "TestJob") }
    let(:args) { { step_name: "test_step", provider_type: "claude" } }

    before do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")

      # Create jobs with different statuses
      job1 = job_manager.create_harness_job(job_class, args.merge(step_name: "step1"))
      job2 = job_manager.create_harness_job(job_class, args.merge(step_name: "step2"))
      job3 = job_manager.create_harness_job(job_class, args.merge(step_name: "step3"))

      job_manager.update_job_status(job1, :running)
      job_manager.update_job_status(job2, :completed)
      job_manager.update_job_status(job3, :failed)
    end

    it "gets jobs by status" do
      running_jobs = job_manager.get_jobs_by_status(:running)
      completed_jobs = job_manager.get_jobs_by_status(:completed)
      failed_jobs = job_manager.get_jobs_by_status(:failed)

      expect(running_jobs.size).to eq(1)
      expect(completed_jobs.size).to eq(1)
      expect(failed_jobs.size).to eq(1)
    end

    it "gets running jobs" do
      running_jobs = job_manager.get_running_jobs
      expect(running_jobs.size).to eq(1)
      expect(running_jobs.first[:status]).to eq(:running)
    end

    it "gets failed jobs" do
      failed_jobs = job_manager.get_failed_jobs
      expect(failed_jobs.size).to eq(1)
      expect(failed_jobs.first[:status]).to eq(:failed)
    end

    it "gets completed jobs" do
      completed_jobs = job_manager.get_completed_jobs
      expect(completed_jobs.size).to eq(1)
      expect(completed_jobs.first[:status]).to eq(:completed)
    end

    it "gets jobs for specific step" do
      step1_jobs = job_manager.get_jobs_for_step("step1")
      step2_jobs = job_manager.get_jobs_for_step("step2")

      expect(step1_jobs.size).to eq(1)
      expect(step2_jobs.size).to eq(1)
      expect(step1_jobs.first[:args][:step_name]).to eq("step1")
      expect(step2_jobs.first[:args][:step_name]).to eq("step2")
    end

    it "checks if step has running jobs" do
      expect(job_manager.step_has_running_jobs?("step1")).to be true
      expect(job_manager.step_has_running_jobs?("step2")).to be false
      expect(job_manager.step_has_running_jobs?("step3")).to be false
    end
  end

  describe "job retry" do
    let(:job_class) { double("job_class", name: "TestJob") }
    let(:args) { { step_name: "test_step", provider_type: "claude" } }

    it "retries a failed job successfully" do
      allow(job_class).to receive(:enqueue).and_return("que_job_123", "que_job_456")

      job_id = job_manager.create_harness_job(job_class, args)
      job_manager.update_job_status(job_id, :running)
      job_manager.update_job_status(job_id, :failed, error: "test error")

      # Mock Object.const_get to return the job class
      allow(Object).to receive(:const_get).with("TestJob").and_return(job_class)
      allow(job_class).to receive(:enqueue).and_return("que_job_456")

      result = job_manager.retry_job(job_id)

      expect(result).to be true

      job = job_manager.get_harness_job(job_id)
      expect(job[:status]).to eq(:queued)
      expect(job[:metrics][:retry_count]).to eq(1)
      expect(job[:metrics][:start_time]).to be_nil
      expect(job[:metrics][:end_time]).to be_nil

      expect(harness_runner).to have_received(:record_job_retry).with(job_id, 1)
    end

    it "fails to retry non-failed job" do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")

      job_id = job_manager.create_harness_job(job_class, args)

      result = job_manager.retry_job(job_id)

      expect(result).to be false
    end
  end

  describe "job cancellation" do
    let(:job_class) { double("job_class", name: "TestJob") }
    let(:args) { { step_name: "test_step", provider_type: "claude" } }

    it "cancels a queued job successfully" do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")

      job_id = job_manager.create_harness_job(job_class, args)

      result = job_manager.cancel_job(job_id)

      expect(result).to be true

      job = job_manager.get_harness_job(job_id)
      expect(job[:status]).to eq(:cancelled)
      expect(job[:metrics][:end_time]).to be_a(Time)

      expect(harness_runner).to have_received(:record_job_cancelled).with(job_id, :queued)
    end

    it "cancels a running job successfully" do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")

      job_id = job_manager.create_harness_job(job_class, args)
      job_manager.update_job_status(job_id, :running)

      result = job_manager.cancel_job(job_id)

      expect(result).to be true

      job = job_manager.get_harness_job(job_id)
      expect(job[:status]).to eq(:cancelled)

      expect(harness_runner).to have_received(:record_job_cancelled).with(job_id, :running)
    end

    it "fails to cancel completed job" do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")

      job_id = job_manager.create_harness_job(job_class, args)
      job_manager.update_job_status(job_id, :running)
      job_manager.update_job_status(job_id, :completed)

      result = job_manager.cancel_job(job_id)

      expect(result).to be false
    end
  end

  describe "job summary" do
    let(:job_class) { double("job_class", name: "TestJob") }
    let(:args) { { step_name: "test_step", provider_type: "claude" } }

    before do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")

      # Create jobs with different statuses
      job1 = job_manager.create_harness_job(job_class, args.merge(step_name: "step1"))
      job2 = job_manager.create_harness_job(job_class, args.merge(step_name: "step2"))
      job3 = job_manager.create_harness_job(job_class, args.merge(step_name: "step3"))

      job_manager.update_job_status(job1, :running)
      job_manager.update_job_status(job2, :completed)
      job_manager.update_job_status(job3, :failed)
    end

    it "provides comprehensive job summary" do
      summary = job_manager.get_harness_job_summary

      expect(summary).to include(
        :total_jobs,
        :by_status,
        :metrics,
        :recent_jobs
      )

      expect(summary[:total_jobs]).to eq(3)
      expect(summary[:by_status]).to include(
        queued: 0,
        running: 1,
        completed: 1,
        failed: 1,
        cancelled: 0,
        retrying: 0
      )
      expect(summary[:recent_jobs].size).to eq(3)
    end
  end

  describe "job output" do
    let(:job_class) { double("job_class", name: "TestJob") }
    let(:args) { { step_name: "test_step", provider_type: "claude" } }

    it "provides job output information" do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")

      job_id = job_manager.create_harness_job(job_class, args)
      job_manager.update_job_status(job_id, :running)
      job_manager.update_job_status(job_id, :completed, result: "test result")

      output = job_manager.get_job_output(job_id)

      expect(output).to include("Job ID: #{job_id}")
      expect(output).to include("Class: TestJob")
      expect(output).to include("Status: completed")
      expect(output).to include("Result: test result")
    end
  end

  describe "job logging" do
    let(:job_class) { double("job_class", name: "TestJob") }
    let(:args) { { step_name: "test_step", provider_type: "claude" } }

    it "logs job messages" do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")

      job_id = job_manager.create_harness_job(job_class, args)

      job_manager.log_job_message(job_id, "Test message", "info", { key: "value" })

      job = job_manager.get_harness_job(job_id)
      expect(job[:logs]).to be_an(Array)
      expect(job[:logs].size).to eq(1)
      expect(job[:logs].first[:message]).to eq("Test message")
      expect(job[:logs].first[:level]).to eq("info")
      expect(job[:logs].first[:metadata]).to eq({ key: "value" })

      expect(harness_runner).to have_received(:log_job_message).with(
        job_id,
        "Test message",
        "info",
        { key: "value" }
      )
    end
  end

  describe "cleanup" do
    let(:job_class) { double("job_class", name: "TestJob") }
    let(:args) { { step_name: "test_step", provider_type: "claude" } }

    it "cleans up old completed jobs" do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")

      job_id = job_manager.create_harness_job(job_class, args)
      job_manager.update_job_status(job_id, :completed)

      # Move time forward
      allow(Time).to receive(:now).and_return(Time.now + 25 * 3600) # 25 hours later

      cleaned_count = job_manager.cleanup_old_jobs(24) # 24 hours max age

      expect(cleaned_count).to eq(1)
      expect(job_manager.get_harness_job(job_id)).to be_nil
    end
  end

  describe "wait for completion" do
    let(:job_class) { double("job_class", name: "TestJob") }
    let(:args) { { step_name: "test_step", provider_type: "claude" } }

    it "waits for jobs to complete" do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")

      job_id = job_manager.create_harness_job(job_class, args)
      job_manager.update_job_status(job_id, :running)

      # Start waiting in a thread
      wait_thread = Thread.new do
        job_manager.wait_for_jobs_completion(2) # 2 second timeout
      end

      # Complete the job after a short delay
      sleep(0.2)
      job_manager.update_job_status(job_id, :completed)

      result = wait_thread.value
      expect(result).to be true
    end

    it "times out when jobs don't complete" do
      allow(job_class).to receive(:enqueue).and_return("que_job_123")

      job_id = job_manager.create_harness_job(job_class, args)
      job_manager.update_job_status(job_id, :running)

      result = job_manager.wait_for_jobs_completion(0.1) # Very short timeout

      expect(result).to be false
    end
  end
end
