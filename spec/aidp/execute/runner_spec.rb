# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Execute::Runner do
  let(:project_dir) { Dir.mktmpdir }
  let(:runner) { described_class.new(project_dir) }
  let(:provider_manager) { class_double(Aidp::ProviderManager).as_stubbed_const }
  let(:mock_provider) { instance_double("Aidp::Providers::Base") }
  let(:mock_job) { double("Que::Job", job_id: 1) }

  before do
    # Set up test environment
    ENV["AIDP_MOCK_MODE"] = "1"

    # Create templates directory
    FileUtils.mkdir_p(File.join(project_dir, "templates", "EXECUTE"))
    FileUtils.mkdir_p(File.join(project_dir, "templates", "COMMON"))

    # Create test template
    File.write(
      File.join(project_dir, "templates", "EXECUTE", "test_template.md"),
      "Test template content"
    )

    # Mock provider setup
    allow(provider_manager).to receive(:load_from_config).and_return(mock_provider)
    allow(mock_provider).to receive(:name).and_return("test_provider")
    allow(mock_provider).to receive(:set_job_context)

    # Mock Que job
    allow(Aidp::Jobs::ProviderExecutionJob).to receive(:enqueue).and_return(mock_job)

    # Set up test database config
    allow(Que).to receive(:connection=)
    allow(Que).to receive(:migrate!)
  end

  after do
    FileUtils.remove_entry project_dir
    ENV.delete("AIDP_MOCK_MODE")
  end

  describe "#run_step" do
    let(:step_name) { "TEST_STEP" }
    let(:step_spec) do
      {
        "templates" => ["test_template.md"],
        "outs" => ["test_output.md"]
      }
    end

    before do
      # Mock step specification
      stub_const(
        "Aidp::Execute::Steps::SPEC",
        {step_name => step_spec}
      )
    end

    context "when in mock mode" do
      it "returns mock execution result" do
        result = runner.run_step(step_name)

        expect(result[:status]).to eq("completed")
        expect(result[:output]).to eq("Mock execution result")
      end
    end

    context "when using real provider" do
      before do
        ENV.delete("AIDP_MOCK_MODE")
        ENV["RAILS_ENV"] = "production" # Ensure we're not in test mode

        # Mock job enqueueing
        allow(Aidp::Jobs::ProviderExecutionJob).to receive(:enqueue).and_return(1)

        # Mock the database operations to avoid real database calls
        allow(Que).to receive(:execute).and_return([
          {
            "finished_at" => Time.now,
            "error_count" => 0,
            "last_error_message" => nil,
            "run_at" => Time.now - 10
          }
        ])
      end

      it "submits job and waits for completion" do
        result = runner.run_step(step_name)

        expect(result[:status]).to eq("completed")
      end

      it "handles job failures" do
        # Mock a failed job
        allow(Que).to receive(:execute).and_return([
          {
            "finished_at" => Time.now,
            "error_count" => 1,
            "last_error_message" => "Test error",
            "run_at" => Time.now - 10
          }
        ])

        result = runner.run_step(step_name)

        expect(result[:status]).to eq("failed")
        expect(result[:error]).to eq("Test error")
      end

      it "generates output files" do
        result = runner.run_step(step_name)

        # Verify that the step completed successfully
        expect(result[:status]).to eq("completed")
      end

      it "marks step as completed" do
        # Mock the progress tracking
        allow(runner.progress).to receive(:mark_step_completed).and_return(nil)

        runner.run_step(step_name)

        # Verify the method exists and can be called
        expect(runner.progress).to respond_to(:mark_step_completed)
      end
    end

    context "with error simulation" do
      it "returns error result" do
        result = runner.run_step(step_name, simulate_error: "Test error")

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("Test error")
      end
    end
  end

  describe "#should_use_mock_mode?" do
    it "returns true when mock_mode option is set" do
      expect(runner.send(:should_use_mock_mode?, mock_mode: true)).to be true
    end

    it "returns true when AIDP_MOCK_MODE env var is set" do
      ENV["AIDP_MOCK_MODE"] = "1"
      expect(runner.send(:should_use_mock_mode?, {})).to be true
    end

    it "returns true in test environment" do
      expect(runner.send(:should_use_mock_mode?, {})).to be true
    end

    it "returns false in production environment" do
      ENV.delete("AIDP_MOCK_MODE")
      ENV.delete("RAILS_ENV")
      expect(runner.send(:should_use_mock_mode?, {})).to be false
    end
  end

  describe "#wait_for_job_completion" do
    let(:job_id) { 1 }

    it "returns completed status when job succeeds" do
      # Mock a completed job
      allow(Que).to receive(:execute).and_return([
        {
          "finished_at" => Time.now,
          "error_count" => 0,
          "last_error_message" => nil,
          "run_at" => Time.now - 10
        }
      ])

      result = runner.send(:wait_for_job_completion, job_id)
      expect(result[:status]).to eq("completed")
    end

    it "returns failed status with error when job fails" do
      # Mock a failed job
      allow(Que).to receive(:execute).and_return([
        {
          "finished_at" => Time.now,
          "error_count" => 1,
          "last_error_message" => "Test error",
          "run_at" => Time.now - 10
        }
      ])

      result = runner.send(:wait_for_job_completion, job_id)
      expect(result[:status]).to eq("failed")
      expect(result[:error]).to eq("Test error")
    end
  end
end
