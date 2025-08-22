# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Jobs::ProviderExecutionJob do
  let(:project_dir) { Dir.mktmpdir }
  let(:job_manager) { Aidp::JobManager.new(project_dir) }
  let(:provider_manager) { class_double(Aidp::ProviderManager).as_stubbed_const }
  let(:mock_provider) { instance_double("Aidp::Providers::Base") }

  before do
    allow(provider_manager).to receive(:get_provider).and_return(mock_provider)
    allow(mock_provider).to receive(:name).and_return("test_provider")
    allow(mock_provider).to receive(:set_job_context)
  end

  after do
    FileUtils.remove_entry project_dir
  end

  describe ".perform" do
    let(:job) do
      job_manager.enqueue_provider_job(
        provider_type: "test_provider",
        prompt: "test prompt",
        metadata: { test: true }
      )
    end

    it "executes the provider successfully" do
      allow(mock_provider).to receive(:send).and_return("success")

      described_class.perform(
        job[:id],
        "test_provider",
        "test prompt",
        nil
      )

      updated_job = job_manager.get_job(job[:id])
      expect(updated_job[:status]).to eq("completed")

      executions = job_manager.get_job_executions(job[:id])
      expect(executions.length).to eq(1)
      expect(executions.first[:status]).to eq("completed")
    end

    it "handles provider failures" do
      allow(mock_provider).to receive(:send).and_raise("test error")

      expect {
        described_class.perform(
          job[:id],
          "test_provider",
          "test prompt",
          nil
        )
      }.to raise_error(RuntimeError, "test error")

      updated_job = job_manager.get_job(job[:id])
      expect(updated_job[:status]).to eq("failed")
      expect(updated_job[:error]).to eq("Provider execution failed: test error")

      executions = job_manager.get_job_executions(job[:id])
      expect(executions.length).to eq(1)
      expect(executions.first[:status]).to eq("failed")
      expect(executions.first[:error]).to eq("Provider execution failed: test error")
    end

    it "handles unavailable providers" do
      allow(provider_manager).to receive(:get_provider).and_return(nil)

      expect {
        described_class.perform(
          job[:id],
          "test_provider",
          "test prompt",
          nil
        )
      }.to raise_error(RuntimeError, "Provider test_provider not available")

      updated_job = job_manager.get_job(job[:id])
      expect(updated_job[:status]).to eq("failed")
      expect(updated_job[:error]).to eq("Provider execution failed: Provider test_provider not available")
    end

    it "sets job context on provider" do
      allow(mock_provider).to receive(:send).and_return("success")

      described_class.perform(
        job[:id],
        "test_provider",
        "test prompt",
        nil
      )

      expect(mock_provider).to have_received(:set_job_context).with(
        hash_including(
          job_id: job[:id],
          execution_id: kind_of(Integer),
          job_manager: job_manager
        )
      )
    end

    it "tracks execution attempts" do
      # First attempt
      allow(mock_provider).to receive(:send).and_raise("first error")

      expect {
        described_class.perform(
          job[:id],
          "test_provider",
          "test prompt",
          nil
        )
      }.to raise_error(RuntimeError, "first error")

      # Retry
      allow(mock_provider).to receive(:send).and_return("success")
      job_manager.retry_job(job[:id])

      described_class.perform(
        job[:id],
        "test_provider",
        "test prompt",
        nil
      )

      executions = job_manager.get_job_executions(job[:id])
      expect(executions.length).to eq(2)
      expect(executions.map { |e| e[:attempt] }).to eq([1, 2])
      expect(executions.map { |e| e[:status] }).to eq(["failed", "completed"])
    end
  end
end
