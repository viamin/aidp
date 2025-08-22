# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Analyze::Runner do
  let(:project_dir) { Dir.mktmpdir }
  let(:runner) { described_class.new(project_dir) }
  let(:provider_manager) { class_double(Aidp::ProviderManager).as_stubbed_const }
  let(:mock_provider) { instance_double("Aidp::Providers::Base") }
  let(:mock_job) { double("Que::Job", job_id: 1) }

  before do
    # Set up test environment
    ENV["AIDP_MOCK_MODE"] = "1"

    # Create templates directory
    FileUtils.mkdir_p(File.join(project_dir, "templates", "ANALYZE"))
    FileUtils.mkdir_p(File.join(project_dir, "templates", "COMMON"))

    # Create test template
    File.write(
      File.join(project_dir, "templates", "ANALYZE", "test_template.md"),
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
        "agent" => "test_agent",
        "outs" => ["test_output.md"]
      }
    end

    before do
      # Mock step specification
      stub_const(
        "Aidp::Analyze::Steps::SPEC",
        { step_name => step_spec }
      )

      # Mock progress tracking
      allow(runner.progress).to receive(:mark_step_completed)
    end

    context "when in mock mode" do
      it "returns mock execution result" do
        result = runner.run_step(step_name)

        expect(result[:status]).to eq("success")
        expect(result[:provider]).to eq("mock")
        expect(result[:message]).to eq("Mock execution")
      end
    end

    context "when using real provider" do
      before do
        ENV.delete("AIDP_MOCK_MODE")

        # Create a completed job in the database
        create_mock_job(id: 1)
      end

      it "submits job and waits for completion" do
        result = runner.run_step(step_name)

        expect(result[:status]).to eq("success")
        expect(result[:provider]).to eq("test_provider")
        expect(result[:message]).to eq("Analysis completed successfully")
      end

      it "handles job failures" do
        create_mock_job(id: 1, error: "Test error")

        result = runner.run_step(step_name)

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("Test error")
      end

      it "generates output files" do
        runner.run_step(step_name)

        output_file = File.join(project_dir, "test_output.md")
        expect(File.exist?(output_file)).to be true
      end

      it "marks step as completed on success" do
        expect(runner.progress).to receive(:mark_step_completed).with(step_name)
        runner.run_step(step_name)
      end

      it "stores execution metrics" do
        result = runner.run_step(step_name)

        # Check metrics in database
        metrics = Que.execute(<<~SQL, [step_name])
          SELECT * FROM analysis_metrics
          WHERE step_name = $1
          ORDER BY recorded_at DESC
          LIMIT 1
        SQL

        expect(metrics).not_to be_empty
        metric = metrics.first
        expect(metric["metric_name"]).to include("duration")
        expect(metric["value"]).not_to be_nil
      end
    end

    context "with error simulation" do
      it "returns error result" do
        result = runner.run_step(step_name, simulate_error: "Test error")

        expect(result[:status]).to eq("error")
        expect(result[:error]).to eq("Test error")
      end
    end

    context "with focus areas" do
      it "includes focus areas in result" do
        result = runner.run_step(step_name, focus: "area1,area2")

        expect(result[:focus_areas]).to eq(["area1", "area2"])
      end
    end

    context "with export formats" do
      it "includes export formats in result" do
        result = runner.run_step(step_name, format: "json,md")

        expect(result[:export_formats]).to eq(["json", "md"])
      end
    end
  end

  describe "#wait_for_job_completion" do
    let(:job_id) { 1 }

    it "returns completed status when job succeeds" do
      create_mock_job(id: job_id)

      result = runner.send(:wait_for_job_completion, job_id)
      expect(result[:status]).to eq("completed")
    end

    it "returns failed status with error when job fails" do
      create_mock_job(id: job_id, error: "Test error")

      result = runner.send(:wait_for_job_completion, job_id)
      expect(result[:status]).to eq("failed")
      expect(result[:error]).to eq("Test error")
    end
  end

  describe "#store_execution_metrics" do
    let(:step_name) { "TEST_STEP" }
    let(:result) { { status: "success", provider: "test_provider" } }
    let(:duration) { 10.0 }

    it "stores metrics in the database" do
      runner.send(:store_execution_metrics, step_name, result, duration)

      metrics = Que.execute(<<~SQL, [step_name])
        SELECT * FROM analysis_metrics
        WHERE step_name = $1
        ORDER BY recorded_at DESC
        LIMIT 1
      SQL

      expect(metrics).not_to be_empty
      metric = metrics.first
      expect(metric["metric_name"]).to include("duration")
      expect(metric["value"]).to include(duration.to_s)
    end

    it "handles failure metrics" do
      result = { status: "error", error: "Test error" }
      runner.send(:store_execution_metrics, step_name, result, duration)

      metrics = Que.execute(<<~SQL, [step_name])
        SELECT * FROM analysis_metrics
        WHERE step_name = $1
        AND metric_name LIKE '%failure%'
        ORDER BY recorded_at DESC
        LIMIT 1
      SQL

      expect(metrics).not_to be_empty
      expect(metrics.first["value"]).to include("Test error")
    end
  end
end
