# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Background Jobs Workflow" do
  let(:project_dir) { Dir.mktmpdir }
  let(:analyze_runner) { Aidp::Analyze::Runner.new(project_dir) }
  let(:execute_runner) { Aidp::Execute::Runner.new(project_dir) }
  let(:provider_manager) { class_double(Aidp::ProviderManager).as_stubbed_const }
  let(:mock_provider) { instance_double("Aidp::Providers::Base") }

  before do
    # Set up test environment
    ENV["QUE_WORKER_COUNT"] = "1" # Enable one worker for integration tests
    ENV.delete("AIDP_MOCK_MODE") # Use real job processing

    # Create templates directory
    FileUtils.mkdir_p(File.join(project_dir, "templates", "ANALYZE"))
    FileUtils.mkdir_p(File.join(project_dir, "templates", "EXECUTE"))
    FileUtils.mkdir_p(File.join(project_dir, "templates", "COMMON"))

    # Create test templates
    File.write(
      File.join(project_dir, "templates", "ANALYZE", "test_template.md"),
      "Test analyze template"
    )
    File.write(
      File.join(project_dir, "templates", "EXECUTE", "test_template.md"),
      "Test execute template"
    )

    # Mock provider setup
    allow(provider_manager).to receive(:load_from_config).and_return(mock_provider)
    allow(mock_provider).to receive(:name).and_return("test_provider")
    allow(mock_provider).to receive(:set_job_context)
    allow(mock_provider).to receive(:send).and_return("Success")

    # Set up test database config
    allow(Que).to receive(:connection=)
    allow(Que).to receive(:migrate!)
  end

  after do
    FileUtils.remove_entry project_dir
    ENV.delete("QUE_WORKER_COUNT")
  end

  describe "analyze mode workflow" do
    let(:step_name) { "TEST_ANALYZE_STEP" }
    let(:step_spec) do
      {
        "templates" => ["test_template.md"],
        "agent" => "test_agent",
        "outs" => ["test_output.md"]
      }
    end

    before do
      stub_const("Aidp::Analyze::Steps::SPEC", { step_name => step_spec })
    end

    it "executes analyze step with background job" do
      result = analyze_runner.run_step(step_name)

      expect(result[:status]).to eq("success")
      expect(result[:provider]).to eq("test_provider")

      # Check job was created and completed
      jobs = Que.execute("SELECT * FROM que_jobs WHERE job_class = $1", ["Aidp::Jobs::ProviderExecutionJob"])
      expect(jobs).not_to be_empty
      expect(jobs.first["error_count"]).to eq(0)
      expect(jobs.first["finished_at"]).not_to be_nil
    end

    it "handles provider failures" do
      allow(mock_provider).to receive(:send).and_raise("Test error")

      result = analyze_runner.run_step(step_name)

      expect(result[:status]).to eq("error")
      expect(result[:error]).to include("Test error")

      # Check job failure was recorded
      jobs = Que.execute("SELECT * FROM que_jobs WHERE job_class = $1", ["Aidp::Jobs::ProviderExecutionJob"])
      expect(jobs.first["error_count"]).to be > 0
      expect(jobs.first["last_error_message"]).to include("Test error")
    end
  end

  describe "execute mode workflow" do
    let(:step_name) { "TEST_EXECUTE_STEP" }
    let(:step_spec) do
      {
        "templates" => ["test_template.md"],
        "outs" => ["test_output.md"]
      }
    end

    before do
      stub_const("Aidp::Execute::Steps::SPEC", { step_name => step_spec })
    end

    it "executes execute step with background job" do
      result = execute_runner.run_step(step_name)

      expect(result[:status]).to eq("success")
      expect(result[:provider]).to eq("test_provider")

      # Check job was created and completed
      jobs = Que.execute("SELECT * FROM que_jobs WHERE job_class = $1", ["Aidp::Jobs::ProviderExecutionJob"])
      expect(jobs).not_to be_empty
      expect(jobs.first["error_count"]).to eq(0)
      expect(jobs.first["finished_at"]).not_to be_nil
    end

    it "handles provider failures" do
      allow(mock_provider).to receive(:send).and_raise("Test error")

      result = execute_runner.run_step(step_name)

      expect(result[:status]).to eq("error")
      expect(result[:error]).to include("Test error")

      # Check job failure was recorded
      jobs = Que.execute("SELECT * FROM que_jobs WHERE job_class = $1", ["Aidp::Jobs::ProviderExecutionJob"])
      expect(jobs.first["error_count"]).to be > 0
      expect(jobs.first["last_error_message"]).to include("Test error")
    end
  end

  describe "job retry workflow" do
    let(:jobs_command) { Aidp::CLI::JobsCommand.new }
    let(:mock_stdin) { StringIO.new }
    let(:mock_stdout) { StringIO.new }

    before do
      # Stub stdin/stdout
      allow($stdin).to receive(:ready?).and_return(false)
      allow($stdout).to receive(:write) { |msg| mock_stdout.write(msg) }
      allow($stdout).to receive(:flush)
    end

    it "allows retrying failed jobs" do
      # Create a failed job
      create_mock_job(id: 1, error: "Initial failure")

      # Simulate retry command
      allow($stdin).to receive(:ready?).and_return(true)
      allow($stdin).to receive(:getch).and_return("r")
      allow(jobs_command).to receive(:gets).and_return("1\n")
      expect(jobs_command).to receive(:sleep).and_raise(Interrupt)

      jobs_command.run

      # Check job was reset for retry
      job = Que.execute("SELECT * FROM que_jobs WHERE job_id = $1", [1]).first
      expect(job["error_count"]).to eq(0)
      expect(job["last_error_message"]).to be_nil
      expect(job["finished_at"]).to be_nil
    end
  end

  describe "job monitoring workflow" do
    let(:jobs_command) { Aidp::CLI::JobsCommand.new }
    let(:mock_stdin) { StringIO.new }
    let(:mock_stdout) { StringIO.new }

    before do
      # Stub stdin/stdout
      allow($stdin).to receive(:ready?).and_return(false)
      allow($stdout).to receive(:write) { |msg| mock_stdout.write(msg) }
      allow($stdout).to receive(:flush)

      # Create some test jobs
      # Create test jobs
      create_mock_job(id: 1, status: "completed")
      create_mock_job(id: 2, status: "failed", error: "Test error")
      create_mock_job(id: 3, status: "running")
    end

    it "shows job status updates" do
      expect(jobs_command).to receive(:sleep).and_raise(Interrupt)

      jobs_command.run

      output = mock_stdout.string
      expect(output).to include("completed")
      expect(output).to include("failed")
      expect(output).to include("Test error")
      expect(output).to include("running")
    end

    it "shows detailed job information" do
      allow($stdin).to receive(:ready?).and_return(true)
      allow($stdin).to receive(:getch).and_return("d")
      allow(jobs_command).to receive(:gets).and_return("1\n")
      expect(jobs_command).to receive(:sleep).and_raise(Interrupt)

      jobs_command.run

      output = mock_stdout.string
      expect(output).to include("Job Details - ID: 1")
      expect(output).to include("ProviderExecutionJob")
      expect(output).to include("test_queue")
      expect(output).to include("completed")
    end
  end
end
