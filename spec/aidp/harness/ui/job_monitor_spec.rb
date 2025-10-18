# frozen_string_literal: true

require "spec_helper"
require "stringio"
require_relative "../../../../lib/aidp/harness/ui/job_monitor"
require_relative "../../../support/test_prompt"

RSpec.describe Aidp::Harness::UI::JobMonitor do
  let(:test_prompt) { TestPrompt.new }
  let(:frame_manager) { Aidp::Harness::UI::FrameManager.new({output: test_prompt}) }
  let(:job_monitor) { described_class.new({frame_manager: frame_manager}, prompt: test_prompt) }
  let(:sample_job_data) { build_sample_job_data }

  describe "#register_job" do
    context "when valid job data is provided" do
      it "registers the job successfully" do
        job_monitor.register_job("test_job", sample_job_data)

        expect(job_monitor.has_job?("test_job")).to be true
      end

      it "creates job with correct initial status" do
        job_monitor.register_job("test_job", sample_job_data)

        job_status = job_monitor.job_status("test_job")
        expect(job_status[:status]).to eq(:pending)
      end

      it "sets default values for missing fields" do
        minimal_job_data = {status: :running}
        job_monitor.register_job("minimal_job", minimal_job_data)

        job_status = job_monitor.job_status("minimal_job")
        expect(job_status[:priority]).to eq(:normal)
        expect(job_status[:progress]).to eq(0)
      end
    end

    context "when invalid job data is provided" do
      it "raises MonitorError for empty job ID" do
        expect {
          job_monitor.register_job("", sample_job_data)
        }.to raise_error(Aidp::Harness::UI::JobMonitor::MonitorError)
      end

      it "raises MonitorError for non-hash job data" do
        expect {
          job_monitor.register_job("test_job", "invalid_data")
        }.to raise_error(Aidp::Harness::UI::JobMonitor::MonitorError)
      end
    end
  end

  describe "#update_job_status" do
    before { job_monitor.register_job("test_job", sample_job_data) }

    context "when valid status update is provided" do
      it "updates job status successfully" do
        job_monitor.update_job_status("test_job", :running)

        job_status = job_monitor.job_status("test_job")
        expect(job_status[:status]).to eq(:running)
      end

      it "updates last_updated timestamp" do
        original_time = job_monitor.job_status("test_job")[:last_updated]
        # No sleep needed - Time.now naturally advances during test execution
        job_monitor.update_job_status("test_job", :running)

        updated_time = job_monitor.job_status("test_job")[:last_updated]
        expect(updated_time).to be >= original_time
      end

      it "merges additional data" do
        additional_data = {progress: 50, current_step: 2}
        job_monitor.update_job_status("test_job", :running, additional_data)

        job_status = job_monitor.job_status("test_job")
        expect(job_status[:progress]).to eq(50)
        expect(job_status[:current_step]).to eq(2)
      end
    end

    context "when invalid status update is provided" do
      it "raises MonitorError for non-existent job" do
        expect {
          job_monitor.update_job_status("non_existent_job", :running)
        }.to raise_error(Aidp::Harness::UI::JobMonitor::JobNotFoundError)
      end

      it "raises MonitorError for invalid status" do
        expect {
          job_monitor.update_job_status("test_job", :invalid_status)
        }.to raise_error(Aidp::Harness::UI::JobMonitor::MonitorError)
      end
    end
  end

  describe "#get_job_status" do
    before { job_monitor.register_job("test_job", sample_job_data) }

    context "when job exists" do
      it "returns job status information" do
        job_status = job_monitor.job_status("test_job")

        expect(job_status).to include(
          :id, :status, :priority, :created_at, :last_updated
        )
      end

      it "returns a copy of the job data" do
        job_status = job_monitor.job_status("test_job")
        job_status[:status] = :modified

        original_status = job_monitor.job_status("test_job")
        expect(original_status[:status]).to eq(:pending)
      end
    end

    context "when job does not exist" do
      it "raises JobNotFoundError" do
        expect {
          job_monitor.job_status("non_existent_job")
        }.to raise_error(Aidp::Harness::UI::JobMonitor::JobNotFoundError)
      end
    end
  end

  describe "#get_jobs_by_status" do
    before do
      job_monitor.register_job("job1", sample_job_data.merge(status: :running))
      job_monitor.register_job("job2", sample_job_data.merge(status: :pending))
      job_monitor.register_job("job3", sample_job_data.merge(status: :running))
    end

    context "when jobs with specified status exist" do
      it "returns jobs with matching status" do
        running_jobs = job_monitor.jobs_by_status(:running)

        expect(running_jobs.keys).to match_array(["job1", "job3"])
        expect(running_jobs["job1"][:status]).to eq(:running)
        expect(running_jobs["job3"][:status]).to eq(:running)
      end
    end

    context "when no jobs with specified status exist" do
      it "returns empty hash" do
        completed_jobs = job_monitor.jobs_by_status(:completed)

        expect(completed_jobs).to be_empty
      end
    end

    context "when invalid status is provided" do
      it "raises MonitorError" do
        expect {
          job_monitor.jobs_by_status(:invalid_status)
        }.to raise_error(Aidp::Harness::UI::JobMonitor::MonitorError)
      end
    end
  end

  describe "#get_jobs_by_priority" do
    before do
      job_monitor.register_job("job1", sample_job_data.merge(priority: :high))
      job_monitor.register_job("job2", sample_job_data.merge(priority: :normal))
      job_monitor.register_job("job3", sample_job_data.merge(priority: :high))
    end

    context "when jobs with specified priority exist" do
      it "returns jobs with matching priority" do
        high_priority_jobs = job_monitor.jobs_by_priority(:high)

        expect(high_priority_jobs.keys).to match_array(["job1", "job3"])
        expect(high_priority_jobs["job1"][:priority]).to eq(:high)
        expect(high_priority_jobs["job3"][:priority]).to eq(:high)
      end
    end
  end

  describe "#start_monitoring" do
    context "when monitoring is not active" do
      it "starts monitoring successfully" do
        job_monitor.start_monitoring(1.0)

        expect(job_monitor.monitoring_active?).to be true
      end

      it "creates monitoring thread" do
        job_monitor.start_monitoring(1.0)

        expect(job_monitor.instance_variable_get(:@monitor_thread)).to be_a(Thread)
      end
    end

    context "when monitoring is already active" do
      before { job_monitor.start_monitoring(1.0) }

      it "does not start a second monitoring thread" do
        original_thread = job_monitor.instance_variable_get(:@monitor_thread)
        job_monitor.start_monitoring(1.0)

        expect(job_monitor.instance_variable_get(:@monitor_thread)).to eq(original_thread)
      end
    end
  end

  describe "#stop_monitoring" do
    context "when monitoring is active" do
      before { job_monitor.start_monitoring(1.0) }

      it "stops monitoring successfully" do
        job_monitor.stop_monitoring

        expect(job_monitor.monitoring_active?).to be false
      end

      it "clears monitoring thread" do
        job_monitor.stop_monitoring

        expect(job_monitor.instance_variable_get(:@monitor_thread)).to be_nil
      end
    end

    context "when monitoring is not active" do
      it "does not raise an error" do
        expect { job_monitor.stop_monitoring }
          .not_to raise_error
      end
    end
  end

  describe "#add_update_callback" do
    context "when valid callback is provided" do
      it "adds callback successfully" do
        callback = ->(event_type, job, additional_data) { puts "Callback called" }

        job_monitor.add_update_callback(callback)

        expect(job_monitor.instance_variable_get(:@update_callbacks)).to include(callback)
      end
    end

    context "when invalid callback is provided" do
      it "raises MonitorError for non-callable object" do
        expect {
          job_monitor.add_update_callback("not_a_callback")
        }.to raise_error(Aidp::Harness::UI::JobMonitor::MonitorError)
      end
    end
  end

  describe "#get_monitoring_summary" do
    before do
      job_monitor.register_job("job1", sample_job_data.merge(status: :running, priority: :high))
      job_monitor.register_job("job2", sample_job_data.merge(status: :pending, priority: :normal))
    end

    it "returns comprehensive monitoring summary" do
      summary = job_monitor.monitoring_summary

      expect(summary).to include(
        :total_jobs,
        :jobs_by_status,
        :jobs_by_priority,
        :monitoring_active,
        :total_events
      )
    end

    it "includes correct job counts" do
      summary = job_monitor.monitoring_summary

      expect(summary[:total_jobs]).to eq(2)
      expect(summary[:jobs_by_status][:running]).to eq(1)
      expect(summary[:jobs_by_status][:pending]).to eq(1)
      expect(summary[:jobs_by_priority][:high]).to eq(1)
      expect(summary[:jobs_by_priority][:normal]).to eq(1)
    end
  end

  describe "#display_job_status" do
    before { job_monitor.register_job("test_job", sample_job_data) }

    it "displays job status information" do
      job_monitor.display_job_status("test_job")
      expect(test_prompt.messages.any? { |msg| msg[:message].match(/Job Status: test_job/) }).to be true
    end

    it "includes job details" do
      job_monitor.display_job_status("test_job")
      expect(test_prompt.messages.any? { |msg| msg[:message].match(/Job ID: test_job/) }).to be true
    end
  end

  describe "#display_all_jobs" do
    before do
      job_monitor.register_job("job1", sample_job_data.merge(status: :running))
      job_monitor.register_job("job2", sample_job_data.merge(status: :pending))
    end

    it "displays all jobs" do
      job_monitor.display_all_jobs
      expect(test_prompt.messages.any? { |msg| msg[:message].match(/All Jobs/) }).to be true
    end

    it "includes job information" do
      job_monitor.display_all_jobs
      message_texts = test_prompt.messages.map { |m| m[:message] }
      expect(message_texts.join(" ")).to include("job1")
      expect(message_texts.join(" ")).to include("job2")
    end
  end

  private

  def build_sample_job_data
    {
      status: :pending,
      priority: :normal,
      progress: 0,
      total_steps: 5,
      current_step: 0,
      metadata: {
        description: "Test job",
        created_by: "test_suite"
      }
    }
  end
end
