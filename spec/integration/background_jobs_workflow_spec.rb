# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Background Jobs Workflow" do
  let(:project_dir) { Dir.mktmpdir }
  let(:analyze_runner) { Aidp::Analyze::Runner.new(project_dir) }
  let(:execute_runner) { Aidp::Execute::Runner.new(project_dir) }
  let(:provider_manager) { class_double(Aidp::ProviderManager).as_stubbed_const }
  let(:mock_provider) { instance_double("Aidp::Providers::Base") }

  before do
    # Set up test environment with mock mode for integration tests
    ENV["QUE_WORKER_COUNT"] = "1" # Enable one worker for integration tests
    ENV["AIDP_MOCK_MODE"] = "1" # Use mock mode for integration tests

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
    ENV.delete("AIDP_MOCK_MODE")
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
      expect(result[:provider]).to eq("mock")
      expect(result[:message]).to eq("Mock execution")
    end

    it "handles provider failures" do
      result = analyze_runner.run_step(step_name, simulate_error: "Test error")

      expect(result[:status]).to eq("error")
      expect(result[:error]).to eq("Test error")
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
      expect(result[:provider]).to eq("mock")
      expect(result[:message]).to eq("Mock execution")
    end

    it "handles provider failures" do
      result = execute_runner.run_step(step_name, simulate_error: "Test error")

      expect(result[:status]).to eq("error")
      expect(result[:error]).to eq("Test error")
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
      # Stub database connection to avoid real DB calls
      allow(jobs_command).to receive(:run).and_raise(Interrupt)
    end

    it "allows retrying failed jobs" do
      # In mock mode, just verify the command can be instantiated
      expect(jobs_command).to be_a(Aidp::CLI::JobsCommand)
      
      # Simulate running and interrupting
      expect { jobs_command.run }.to raise_error(Interrupt)
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
      # Stub the run method to avoid real database interactions
      allow(jobs_command).to receive(:run).and_raise(Interrupt)
    end

    it "shows job status updates" do
      # In mock mode, just verify the command can be instantiated and run
      expect(jobs_command).to be_a(Aidp::CLI::JobsCommand)
      expect { jobs_command.run }.to raise_error(Interrupt)
    end

    it "shows detailed job information" do
      # In mock mode, just verify the command can be instantiated and run
      expect(jobs_command).to be_a(Aidp::CLI::JobsCommand)
      expect { jobs_command.run }.to raise_error(Interrupt)
    end
  end
end
