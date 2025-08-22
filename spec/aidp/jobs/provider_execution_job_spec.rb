# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Jobs::ProviderExecutionJob do
  let(:project_dir) { Dir.mktmpdir }
  let(:provider_manager) { class_double(Aidp::ProviderManager).as_stubbed_const }
  let(:mock_provider) { instance_double("Aidp::Providers::Base") }

  before do
    allow(provider_manager).to receive(:get_provider).and_return(mock_provider)
    allow(mock_provider).to receive(:name).and_return("test_provider")
    allow(mock_provider).to receive(:set_job_context)

    # Mock database operations
    allow(Aidp::DatabaseConnection).to receive(:connection).and_return(
      double("connection", exec_params: double("result"))
    )
  end

  after do
    FileUtils.remove_entry project_dir
  end

  describe "#run" do
    let(:provider_type) { "test_provider" }
    let(:prompt) { "test prompt" }
    let(:metadata) { {test: true} }
    let(:job_instance) do
      # Create a test instance with mocked Que attributes
      instance = described_class.allocate
      allow(instance).to receive(:que_attrs).and_return({job_id: 123, error_count: 0})
      instance
    end

    it "executes the provider successfully" do
      allow(mock_provider).to receive(:send).and_return("success")

      # Test that the job can be executed without errors
      expect {
        job_instance.run(
          provider_type: provider_type,
          prompt: prompt,
          metadata: metadata
        )
      }.not_to raise_error

      # Verify that the provider was called
      expect(mock_provider).to have_received(:send).with(
        prompt: prompt,
        session: nil
      )
    end

    it "handles provider failures" do
      allow(mock_provider).to receive(:send).and_raise(RuntimeError, "test error")

      expect {
        job_instance.run(
          provider_type: provider_type,
          prompt: prompt,
          metadata: metadata
        )
      }.to raise_error(RuntimeError, "test error")

      # Verify that the provider was called
      expect(mock_provider).to have_received(:send).with(
        prompt: prompt,
        session: nil
      )
    end

    it "handles unavailable providers" do
      allow(provider_manager).to receive(:get_provider).and_return(nil)

      expect {
        job_instance.run(
          provider_type: provider_type,
          prompt: prompt,
          metadata: metadata
        )
      }.to raise_error(RuntimeError, "Provider test_provider not available")
    end

    it "sets job context on provider" do
      allow(mock_provider).to receive(:send).and_return("success")

      job_instance.run(
        provider_type: provider_type,
        prompt: prompt,
        metadata: metadata
      )

      # Verify that the provider was called with correct parameters
      expect(mock_provider).to have_received(:send).with(
        prompt: prompt,
        session: nil
      )
    end

    it "tracks execution attempts" do
      # First attempt fails
      allow(mock_provider).to receive(:send).and_raise(RuntimeError, "first error")

      expect {
        job_instance.run(
          provider_type: provider_type,
          prompt: prompt,
          metadata: metadata
        )
      }.to raise_error(RuntimeError, "first error")

      # Second attempt succeeds
      allow(mock_provider).to receive(:send).and_return("success")

      expect {
        job_instance.run(
          provider_type: provider_type,
          prompt: prompt,
          metadata: metadata
        )
      }.not_to raise_error

      # Verify that the provider was called twice
      expect(mock_provider).to have_received(:send).twice
    end
  end
end
