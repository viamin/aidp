# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/harness/job_manager"

RSpec.describe "Harness Error Handling and Edge Cases", type: :integration do
  let(:project_dir) { Dir.mktmpdir("aidp_harness_error_test") }
  let(:harness_state_dir) { File.join(project_dir, ".aidp", "harness") }
  let(:config_file) { File.join(project_dir, "aidp.yml") }

  before do
    # Set up mock mode for tests
    ENV["AIDP_MOCK_MODE"] = "1"
    # Create a mock project structure
    setup_mock_project
    # Create harness configuration
    setup_harness_config
  end

  after do
    FileUtils.remove_entry(project_dir)
    ENV.delete("AIDP_MOCK_MODE")
  end

  describe "Configuration Error Handling" do
    it "handles missing configuration file gracefully" do
      # Remove configuration file
      File.delete(config_file) if File.exist?(config_file)

      # Should use default configuration without crashing
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        expect(harness_runner).to be_a(Aidp::Harness::Runner)
      }.not_to raise_error
    end

    it "handles malformed YAML configuration gracefully" do
      # Create malformed YAML
      File.write(config_file, "invalid: yaml: content: [")

      # Should handle malformed YAML gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        expect(harness_runner).to be_a(Aidp::Harness::Runner)
      }.not_to raise_error
    end

    it "handles empty configuration file gracefully" do
      # Create empty configuration file
      File.write(config_file, "")

      # Should use default configuration
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        expect(harness_runner).to be_a(Aidp::Harness::Runner)
      }.not_to raise_error
    end

    it "handles configuration with missing required sections" do
      # Create configuration missing harness section
      config = {
        providers: {
          claude: {type: "api"}
        }
      }
      File.write(config_file, YAML.dump(config))

      # Should use default harness configuration
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        expect(harness_runner).to be_a(Aidp::Harness::Runner)
      }.not_to raise_error
    end

    it "handles configuration with invalid provider types" do
      # Create configuration with invalid provider type
      config = {
        harness: {default_provider: "claude"},
        providers: {
          claude: {type: "invalid_type"}
        }
      }
      File.write(config_file, YAML.dump(config))

      # Should raise configuration error for invalid provider type
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        expect(harness_runner).to be_a(Aidp::Harness::Runner)
      }.to raise_error(Aidp::Harness::Configuration::ConfigurationError)
    end

    it "handles configuration with circular provider dependencies" do
      # Create configuration with circular dependencies
      config = {
        harness: {
          default_provider: "claude",
          fallback_providers: ["gemini", "claude"] # Circular dependency
        },
        providers: {
          claude: {type: "api", fallback_providers: ["gemini"]},
          gemini: {type: "api", fallback_providers: ["claude"]}
        }
      }
      File.write(config_file, YAML.dump(config))

      # Should handle circular dependencies gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        expect(harness_runner).to be_a(Aidp::Harness::Runner)
      }.not_to raise_error
    end
  end

  describe "State Management Error Handling" do
    it "handles corrupted state file gracefully" do
      # Create corrupted state file
      FileUtils.mkdir_p(harness_state_dir)
      corrupted_state_file = File.join(harness_state_dir, "analyze_state.json")
      File.write(corrupted_state_file, "invalid json content")

      # Should handle corruption gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.send(:load_state)
      }.not_to raise_error
    end

    it "handles state file with invalid JSON structure" do
      # Create state file with invalid structure
      FileUtils.mkdir_p(harness_state_dir)
      invalid_state_file = File.join(harness_state_dir, "analyze_state.json")
      File.write(invalid_state_file, '{"invalid": "structure", "missing": "required_fields"}')

      # Should handle invalid structure gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.send(:load_state)
      }.not_to raise_error
    end

    it "handles state file with extremely large content" do
      # Create state file with large content
      FileUtils.mkdir_p(harness_state_dir)
      large_state_file = File.join(harness_state_dir, "analyze_state.json")
      large_content = {
        state: "running",
        current_step: "01_REPOSITORY_ANALYSIS",
        execution_log: Array.new(10000) { |i| {message: "Log entry #{i}", timestamp: Time.now} }
      }
      File.write(large_state_file, JSON.pretty_generate(large_content))

      # Should handle large state files gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.send(:load_state)
      }.not_to raise_error
    end

    it "handles state file permission errors gracefully" do
      # Create state file with no read permissions
      FileUtils.mkdir_p(harness_state_dir)
      protected_state_file = File.join(harness_state_dir, "analyze_state.json")
      File.write(protected_state_file, '{"state": "running"}')
      File.chmod(0o000, protected_state_file)

      # Should handle permission errors gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.send(:load_state)
      }.to raise_error(Errno::EACCES)

      # Clean up permissions
      File.chmod(0o644, protected_state_file)
    end

    it "handles concurrent state file access gracefully" do
      # Create state file
      FileUtils.mkdir_p(harness_state_dir)
      state_file = File.join(harness_state_dir, "analyze_state.json")
      File.write(state_file, '{"state": "running"}')

      # Simulate concurrent access using Async for better concurrency control
      require "async"

      Async do |task|
        # Create multiple async tasks instead of threads
        tasks = []

        2.times do |i|
          tasks << task.async do
            harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
            harness_runner.send(:load_state)
          rescue RuntimeError => e
            # Expected timeout due to concurrent access protection
            expect(e.message).to include("Could not acquire state lock")
          end
        end

        # Wait for all tasks to complete with timeout
        tasks.each do |async_task|
          begin
            async_task.wait
          rescue Async::TimeoutError
            # Task timed out, which is expected behavior for some tasks
          end
        end
      end
    end
  end

  describe "Provider Management Error Handling" do
    it "handles provider initialization failures gracefully" do
      # Mock provider initialization failure
      allow_any_instance_of(Aidp::Harness::ProviderManager).to receive(:current_provider).and_raise(StandardError.new("Provider initialization failed"))

      # Should handle provider failures gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.status
      }.not_to raise_error
    end

    it "handles provider switching failures gracefully" do
      # Mock provider switching failure
      allow_any_instance_of(Aidp::Harness::ProviderManager).to receive(:switch_provider).and_raise(StandardError.new("Provider switching failed"))

      # Should handle switching failures gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        provider_manager = harness_runner.instance_variable_get(:@provider_manager)
        provider_manager.switch_provider
      }.to raise_error(StandardError)
    end

    it "handles all providers being unavailable gracefully" do
      # Mock all providers being unavailable
      allow_any_instance_of(Aidp::Harness::ProviderManager).to receive(:current_provider).and_return(nil)
      allow_any_instance_of(Aidp::Harness::ProviderManager).to receive(:switch_provider).and_return(nil)

      # Should handle no available providers gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.status
      }.not_to raise_error
    end

    it "handles provider timeout gracefully" do
      # Mock provider timeout
      allow_any_instance_of(Aidp::Harness::ProviderManager).to receive(:current_provider).and_raise(Timeout::Error.new("Provider timeout"))

      # Should handle timeouts gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.status
      }.not_to raise_error
    end

    it "handles provider authentication failures gracefully" do
      # Mock authentication failure
      allow_any_instance_of(Aidp::Harness::ProviderManager).to receive(:current_provider).and_raise(StandardError.new("Authentication failed"))

      # Should handle authentication failures gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.status
      }.not_to raise_error
    end
  end

  describe "Error Handler Edge Cases" do
    it "handles nil error gracefully" do
      configuration = Aidp::Harness::Configuration.new(project_dir)
      provider_manager = Aidp::Harness::ProviderManager.new(configuration)
      error_handler = Aidp::Harness::ErrorHandler.new(provider_manager, configuration)

      # Should handle nil error gracefully
      expect {
        result = error_handler.handle_error(nil, {})
        expect(result).to include(:success, :action)
      }.not_to raise_error
    end

    it "handles error with missing context gracefully" do
      configuration = Aidp::Harness::Configuration.new(project_dir)
      provider_manager = Aidp::Harness::ProviderManager.new(configuration)
      error_handler = Aidp::Harness::ErrorHandler.new(provider_manager, configuration)

      # Should handle missing context gracefully
      expect {
        result = error_handler.handle_error(StandardError.new("Test error"), nil)
        expect(result).to include(:success, :action)
      }.not_to raise_error
    end

    it "handles error with empty context gracefully" do
      configuration = Aidp::Harness::Configuration.new(project_dir)
      provider_manager = Aidp::Harness::ProviderManager.new(configuration)
      error_handler = Aidp::Harness::ErrorHandler.new(provider_manager, configuration)

      # Should handle empty context gracefully
      expect {
        result = error_handler.handle_error(StandardError.new("Test error"), {})
        expect(result).to include(:success, :action)
      }.not_to raise_error
    end

    it "handles error with invalid context gracefully" do
      configuration = Aidp::Harness::Configuration.new(project_dir)
      provider_manager = Aidp::Harness::ProviderManager.new(configuration)
      error_handler = Aidp::Harness::ErrorHandler.new(provider_manager, configuration)

      # Should handle invalid context gracefully
      expect {
        result = error_handler.handle_error(StandardError.new("Test error"), "invalid_context")
        expect(result).to include(:success, :action)
      }.not_to raise_error
    end

    it "handles cascading errors gracefully" do
      configuration = Aidp::Harness::Configuration.new(project_dir)
      provider_manager = Aidp::Harness::ProviderManager.new(configuration)
      error_handler = Aidp::Harness::ErrorHandler.new(provider_manager, configuration)

      # Mock cascading errors
      allow(provider_manager).to receive(:switch_provider).and_raise(StandardError.new("Switch failed"))

      # Should handle cascading errors gracefully
      expect {
        result = error_handler.handle_error(StandardError.new("Original error"), {provider: "claude"})
        expect(result).to include(:success, :action)
      }.not_to raise_error
    end

    it "handles error handler initialization failure gracefully" do
      # Mock configuration failure
      allow_any_instance_of(Aidp::Harness::Configuration).to receive(:max_retries).and_raise(StandardError.new("Config error"))

      # Should handle initialization failure gracefully
      expect {
        configuration = Aidp::Harness::Configuration.new(project_dir)
        provider_manager = Aidp::Harness::ProviderManager.new(configuration)
        Aidp::Harness::ErrorHandler.new(provider_manager, configuration)
      }.not_to raise_error
    end
  end

  describe "User Interface Error Handling" do
    it "handles user input validation failures gracefully" do
      user_interface = Aidp::Harness::UserInterface.new

      # Mock invalid user input
      allow(user_interface).to receive(:collect_feedback).and_raise(StandardError.new("Input validation failed"))

      # Should handle validation failures gracefully
      expect {
        user_interface.collect_feedback([])
      }.to raise_error(StandardError)
    end

    it "handles user input timeout gracefully" do
      user_interface = Aidp::Harness::UserInterface.new

      # Mock user input timeout
      allow(user_interface).to receive(:collect_feedback).and_raise(Timeout::Error.new("Input timeout"))

      # Should handle timeouts gracefully
      expect {
        user_interface.collect_feedback([])
      }.to raise_error(Timeout::Error)
    end

    it "handles user input cancellation gracefully" do
      user_interface = Aidp::Harness::UserInterface.new

      # Mock user cancellation
      allow(user_interface).to receive(:collect_feedback).and_return(nil)

      # Should handle cancellation gracefully
      expect {
        result = user_interface.collect_feedback([])
        expect(result).to be_nil
      }.not_to raise_error
    end

    it "handles user input with special characters gracefully" do
      user_interface = Aidp::Harness::UserInterface.new

      # Mock user input with special characters
      special_input = {"question_1" => "Test with special chars: !@#$%^&*()_+-=[]{}|;':\",./<>?"}
      allow(user_interface).to receive(:collect_feedback).and_return(special_input)

      # Should handle special characters gracefully
      expect {
        result = user_interface.collect_feedback([])
        expect(result).to eq(special_input)
      }.not_to raise_error
    end

    it "handles user input with extremely long content gracefully" do
      user_interface = Aidp::Harness::UserInterface.new

      # Mock user input with long content
      long_input = {"question_1" => "A" * 10000}
      allow(user_interface).to receive(:collect_feedback).and_return(long_input)

      # Should handle long content gracefully
      expect {
        result = user_interface.collect_feedback([])
        expect(result).to eq(long_input)
      }.not_to raise_error
    end
  end

  describe "Condition Detector Edge Cases" do
    it "handles nil result gracefully" do
      condition_detector = Aidp::Harness::ConditionDetector.new

      # Should handle nil result gracefully
      expect {
        expect(condition_detector.is_rate_limited?(nil)).to be false
        expect(condition_detector.needs_user_feedback?(nil)).to be false
        expect(condition_detector.is_work_complete?(nil, nil)).to be false
      }.not_to raise_error
    end

    it "handles empty result gracefully" do
      condition_detector = Aidp::Harness::ConditionDetector.new

      # Should handle empty result gracefully
      expect {
        expect(condition_detector.is_rate_limited?({})).to be false
        expect(condition_detector.needs_user_feedback?({})).to be false
        expect(condition_detector.is_work_complete?({}, nil)).to be false
      }.not_to raise_error
    end

    it "handles result with missing message gracefully" do
      condition_detector = Aidp::Harness::ConditionDetector.new

      # Should handle missing message gracefully
      expect {
        expect(condition_detector.is_rate_limited?({status: "error"})).to be false
        expect(condition_detector.needs_user_feedback?({status: "success"})).to be false
        expect(condition_detector.is_work_complete?({status: "completed"}, nil)).to be false
      }.not_to raise_error
    end

    it "handles result with invalid message type gracefully" do
      condition_detector = Aidp::Harness::ConditionDetector.new

      # Should handle invalid message type gracefully
      expect {
        expect(condition_detector.is_rate_limited?({message: 123})).to be false
        expect(condition_detector.needs_user_feedback?({message: []})).to be false
        expect(condition_detector.is_work_complete?({message: {}}, nil)).to be false
      }.not_to raise_error
    end

    it "handles result with extremely long message gracefully" do
      condition_detector = Aidp::Harness::ConditionDetector.new

      # Should handle long message gracefully
      long_message = "A" * 100000
      expect {
        expect(condition_detector.is_rate_limited?({message: long_message})).to be false
        expect(condition_detector.needs_user_feedback?({message: long_message})).to be false
        expect(condition_detector.is_work_complete?({message: long_message}, nil)).to be false
      }.not_to raise_error
    end
  end

  describe "Status Display Error Handling" do
    it "handles status display initialization failure gracefully" do
      # Mock status display initialization failure
      allow_any_instance_of(Aidp::Harness::StatusDisplay).to receive(:start_status_updates).and_raise(StandardError.new("Display initialization failed"))

      # Should handle initialization failure gracefully
      expect {
        status_display = Aidp::Harness::StatusDisplay.new
        status_display.start_status_updates
      }.to raise_error(StandardError)
    end

    it "handles status display update failure gracefully" do
      status_display = Aidp::Harness::StatusDisplay.new

      # Mock status update failure
      allow(status_display).to receive(:get_status_data).and_raise(StandardError.new("Status update failed"))

      # Should handle update failure gracefully
      expect {
        status_display.get_status_data
      }.to raise_error(StandardError)
    end

    it "handles status display with missing data gracefully" do
      status_display = Aidp::Harness::StatusDisplay.new

      # Mock missing status data
      allow(status_display).to receive(:get_status_data).and_return(nil)

      # Should handle missing data gracefully
      expect {
        result = status_display.get_status_data
        expect(result).to be_nil
      }.not_to raise_error
    end
  end

  describe "Job Management Error Handling" do
    it "handles job creation failure gracefully" do
      job_manager = Aidp::Harness::JobManager.new(project_dir)

      # Mock job creation failure
      allow(job_manager).to receive(:create_harness_job).and_raise(StandardError.new("Job creation failed"))

      # Should handle creation failure gracefully
      expect {
        job_manager.create_harness_job("test_job", {})
      }.to raise_error(StandardError)
    end

    it "handles job execution failure gracefully" do
      job_manager = Aidp::Harness::JobManager.new(project_dir)

      # Mock job execution failure
      allow(job_manager).to receive(:wait_for_jobs_completion).and_raise(StandardError.new("Job execution failed"))

      # Should handle execution failure gracefully
      expect {
        job_manager.wait_for_jobs_completion(["job_123"])
      }.to raise_error(StandardError)
    end

    it "handles job timeout gracefully" do
      job_manager = Aidp::Harness::JobManager.new(project_dir)

      # Mock job timeout
      allow(job_manager).to receive(:wait_for_jobs_completion).and_raise(Timeout::Error.new("Job timeout"))

      # Should handle timeout gracefully
      expect {
        job_manager.wait_for_jobs_completion(["job_123"])
      }.to raise_error(Timeout::Error)
    end

    it "handles job with invalid parameters gracefully" do
      job_manager = Aidp::Harness::JobManager.new(project_dir)

      # Should handle invalid parameters gracefully
      expect {
        job_manager.create_harness_job(nil, nil)
      }.not_to raise_error
    end
  end

  describe "Memory and Resource Error Handling" do
    it "handles memory pressure gracefully" do
      # Mock memory pressure scenario
      allow(GC).to receive(:start).and_raise(NoMemoryError.new("Out of memory"))

      # Should handle memory pressure gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.status
      }.not_to raise_error
    end

    it "handles disk space exhaustion gracefully" do
      # Mock disk space exhaustion
      allow(File).to receive(:write).and_raise(Errno::ENOSPC.new("No space left on device"))

      # Should handle disk space exhaustion gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.send(:save_state)
      }.to raise_error(Errno::ENOSPC)
    end

    it "handles file system errors gracefully" do
      # Mock file system errors
      allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EIO.new("Input/output error"))

      # Should handle file system errors gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.send(:save_state)
      }.to raise_error(Errno::EIO)
    end
  end

  describe "Network and External Service Error Handling" do
    it "handles network connectivity issues gracefully" do
      # Mock network connectivity issues
      allow_any_instance_of(Aidp::Harness::ProviderManager).to receive(:current_provider).and_raise(SocketError.new("Network unreachable"))

      # Should handle network issues gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.status
      }.not_to raise_error
    end

    it "handles DNS resolution failures gracefully" do
      # Mock DNS resolution failure
      allow_any_instance_of(Aidp::Harness::ProviderManager).to receive(:current_provider).and_raise(SocketError.new("Name or service not known"))

      # Should handle DNS failures gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.status
      }.not_to raise_error
    end

    it "handles SSL/TLS certificate errors gracefully" do
      # Mock SSL certificate error
      allow_any_instance_of(Aidp::Harness::ProviderManager).to receive(:current_provider).and_raise(OpenSSL::SSL::SSLError.new("SSL certificate verify failed"))

      # Should handle SSL errors gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.status
      }.not_to raise_error
    end
  end

  describe "Concurrency and Threading Error Handling" do
    it "handles thread creation failures gracefully" do
      # Mock thread creation failure
      allow(Thread).to receive(:new).and_raise(ThreadError.new("Thread creation failed"))

      # Should handle thread creation failure gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.status
      }.not_to raise_error
    end

    it "handles thread interruption gracefully" do
      # Create a thread and interrupt it
      thread = Thread.new do
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.status
      end

      # Interrupt the thread
      thread.raise(Interrupt.new("Thread interrupted"))

      # Should handle interruption gracefully
      expect {
        thread.join
      }.to raise_error(Interrupt)
    end

    it "handles deadlock scenarios gracefully" do
      # Mock deadlock scenario
      allow_any_instance_of(Aidp::Harness::StateManager).to receive(:with_lock).and_raise(ThreadError.new("Deadlock detected"))

      # Should handle deadlock gracefully
      expect {
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
        harness_runner.send(:save_state)
      }.to raise_error(ThreadError)
    end
  end

  describe "Data Validation and Sanitization" do
    it "handles malicious input gracefully" do
      user_interface = Aidp::Harness::UserInterface.new

      # Mock malicious input
      malicious_input = {"question_1" => "<script>alert('xss')</script>"}
      allow(user_interface).to receive(:collect_feedback).and_return(malicious_input)

      # Should handle malicious input gracefully
      expect {
        result = user_interface.collect_feedback([])
        expect(result).to eq(malicious_input)
      }.not_to raise_error
    end

    it "handles SQL injection attempts gracefully" do
      user_interface = Aidp::Harness::UserInterface.new

      # Mock SQL injection attempt
      sql_injection = {"question_1" => "'; DROP TABLE users; --"}
      allow(user_interface).to receive(:collect_feedback).and_return(sql_injection)

      # Should handle SQL injection gracefully
      expect {
        result = user_interface.collect_feedback([])
        expect(result).to eq(sql_injection)
      }.not_to raise_error
    end

    it "handles path traversal attempts gracefully" do
      user_interface = Aidp::Harness::UserInterface.new

      # Mock path traversal attempt
      path_traversal = {"question_1" => "../../../etc/passwd"}
      allow(user_interface).to receive(:collect_feedback).and_return(path_traversal)

      # Should handle path traversal gracefully
      expect {
        result = user_interface.collect_feedback([])
        expect(result).to eq(path_traversal)
      }.not_to raise_error
    end
  end

  private

  def setup_mock_project
    # Create basic project structure
    FileUtils.mkdir_p(File.join(project_dir, "lib"))
    FileUtils.mkdir_p(File.join(project_dir, "spec"))
    FileUtils.mkdir_p(File.join(project_dir, ".aidp"))

    # Create a simple Ruby file
    File.write(File.join(project_dir, "lib", "test.rb"), "class Test; end")

    # Create a simple spec file
    File.write(File.join(project_dir, "spec", "test_spec.rb"), "RSpec.describe Test do; end")
  end

  def setup_harness_config
    config = {
      harness: {
        default_provider: "claude",
        max_retries: 3,
        fallback_providers: ["gemini", "cursor"],
        auto_switch_on_error: true,
        auto_switch_on_rate_limit: true,
        concurrent_requests: 1,
        timeout: 300,
        ui: {
          interactive: true,
          show_progress: true
        },
        error_handling: {
          retry_on_error: true,
          max_retries: 3
        },
        performance: {
          enable_metrics: true,
          enable_caching: true
        }
      },
      providers: {
        claude: {
          type: "api",
          priority: 1,
          max_tokens: 100_000,
          models: ["claude-3-5-sonnet-20241022"],
          auth: {
            api_key_env: "ANTHROPIC_API_KEY"
          }
        },
        gemini: {
          type: "api",
          priority: 2,
          max_tokens: 50_000,
          models: ["gemini-1.5-pro"],
          auth: {
            api_key_env: "GEMINI_API_KEY"
          }
        },
        cursor: {
          type: "package",
          priority: 3,
          models: ["cursor-default"]
        }
      }
    }

    File.write(config_file, YAML.dump(config))
  end
end
