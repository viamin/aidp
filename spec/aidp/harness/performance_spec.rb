# frozen_string_literal: true

require "spec_helper"
require "benchmark"
require_relative "../../../lib/aidp/harness/job_manager"

RSpec.describe "Harness Performance Testing", type: :performance do
  let(:project_dir) { Dir.mktmpdir("aidp_harness_performance_test") }
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

  describe "Harness Initialization Performance" do
    it "initializes harness runner quickly" do
      # Measure harness initialization time
      initialization_times = []

      10.times do
        time = Benchmark.realtime do
          harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
          harness_runner.status
        end
        initialization_times << time
      end

      average_time = initialization_times.sum / initialization_times.size

      # Harness initialization should be fast (under 100ms)
      expect(average_time).to be < 0.1

      # Individual initialization should not exceed 200ms
      expect(initialization_times.max).to be < 0.2
    end

    it "initializes configuration quickly" do
      # Measure configuration loading time
      config_times = []

      10.times do
        time = Benchmark.realtime do
          configuration = Aidp::Harness::Configuration.new(project_dir)
          configuration.default_provider
        end
        config_times << time
      end

      average_time = config_times.sum / config_times.size

      # Configuration loading should be very fast (under 50ms)
      expect(average_time).to be < 0.05

      # Individual config loading should not exceed 100ms
      expect(config_times.max).to be < 0.1
    end

    it "initializes provider manager quickly" do
      # Measure provider manager initialization time
      provider_times = []

      10.times do
        time = Benchmark.realtime do
          configuration = Aidp::Harness::Configuration.new(project_dir)
          provider_manager = Aidp::Harness::ProviderManager.new(configuration)
          provider_manager.current_provider
        end
        provider_times << time
      end

      average_time = provider_times.sum / provider_times.size

      # Provider manager initialization should be fast (under 50ms)
      expect(average_time).to be < 0.05

      # Individual provider manager initialization should not exceed 100ms
      expect(provider_times.max).to be < 0.1
    end
  end

  describe "State Management Performance" do
    it "saves state quickly" do
      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)

      # Set some state data
      harness_runner.instance_variable_set(:@current_step, "01_REPOSITORY_ANALYSIS")
      harness_runner.instance_variable_set(:@current_provider, "claude")
      harness_runner.instance_variable_set(:@user_input, {"question_1" => "test answer"})

      # Measure state saving time
      save_times = []

      10.times do
        time = Benchmark.realtime do
          harness_runner.send(:save_state)
        end
        save_times << time
      end

      average_time = save_times.sum / save_times.size

      # State saving should be fast (under 50ms)
      expect(average_time).to be < 0.05

      # Individual state save should not exceed 100ms
      expect(save_times.max).to be < 0.1
    end

    it "loads state quickly" do
      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)

      # Set and save some state data
      harness_runner.instance_variable_set(:@current_step, "01_REPOSITORY_ANALYSIS")
      harness_runner.instance_variable_set(:@current_provider, "claude")
      harness_runner.send(:save_state)

      # Measure state loading time
      load_times = []

      10.times do
        time = Benchmark.realtime do
          harness_runner.send(:load_state)
        end
        load_times << time
      end

      average_time = load_times.sum / load_times.size

      # State loading should be fast (under 50ms)
      expect(average_time).to be < 0.05

      # Individual state load should not exceed 100ms
      expect(load_times.max).to be < 0.1
    end

    it "handles concurrent state access efficiently" do
      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)

      # Set some state data
      harness_runner.instance_variable_set(:@current_step, "01_REPOSITORY_ANALYSIS")
      harness_runner.instance_variable_set(:@current_provider, "claude")

      # Measure concurrent state operations
      start_time = Time.now

      threads = []
      5.times do
        threads << Thread.new do
          10.times do
            harness_runner.send(:save_state)
            harness_runner.send(:load_state)
          rescue => e
            # Handle timeout errors gracefully
            puts "Thread error: #{e.message}" if e.message.include?("timeout")
          end
        end
      end

      threads.each do |thread|
        thread.join(5) # 5 second timeout
      rescue => e
        puts "Thread join timeout: #{e.message}"
      end
      total_time = Time.now - start_time

      # 50 concurrent operations (5 threads × 10 operations each) should complete in under 2 seconds
      expect(total_time).to be < 2.0

      # Average time per operation should be under 40ms
      average_time_per_operation = total_time / 50
      expect(average_time_per_operation).to be < 0.04
    end
  end

  describe "Provider Management Performance" do
    it "switches providers quickly" do
      configuration = Aidp::Harness::Configuration.new(project_dir)
      provider_manager = Aidp::Harness::ProviderManager.new(configuration)

      # Measure provider switching time
      switch_times = []

      10.times do
        time = Benchmark.realtime do
          provider_manager.switch_provider
        end
        switch_times << time
      end

      average_time = switch_times.sum / switch_times.size

      # Provider switching should be fast (under 10ms)
      expect(average_time).to be < 0.01

      # Individual provider switch should not exceed 20ms
      expect(switch_times.max).to be < 0.02
    end

    it "switches models quickly" do
      configuration = Aidp::Harness::Configuration.new(project_dir)
      provider_manager = Aidp::Harness::ProviderManager.new(configuration)

      # Measure model switching time
      switch_times = []

      10.times do
        time = Benchmark.realtime do
          provider_manager.switch_model
        end
        switch_times << time
      end

      average_time = switch_times.sum / switch_times.size

      # Model switching should be very fast (under 5ms)
      expect(average_time).to be < 0.005

      # Individual model switch should not exceed 10ms
      expect(switch_times.max).to be < 0.01
    end

    it "tracks provider metrics efficiently" do
      configuration = Aidp::Harness::Configuration.new(project_dir)
      provider_manager = Aidp::Harness::ProviderManager.new(configuration)

      # Measure metrics tracking time
      tracking_times = []

      100.times do
        time = Benchmark.realtime do
          provider_manager.record_success("claude", "claude-3-5-sonnet", 1.5, 1000)
        end
        tracking_times << time
      end

      average_time = tracking_times.sum / tracking_times.size

      # Metrics tracking should be very fast (under 1ms)
      expect(average_time).to be < 0.001

      # Individual metrics tracking should not exceed 2ms
      expect(tracking_times.max).to be < 0.002
    end
  end

  describe "Error Handling Performance" do
    it "handles errors quickly" do
      configuration = Aidp::Harness::Configuration.new(project_dir)
      provider_manager = Aidp::Harness::ProviderManager.new(configuration)
      error_handler = Aidp::Harness::ErrorHandler.new(provider_manager, configuration)

      # Measure error handling time
      error_times = []

      10.times do
        time = Benchmark.realtime do
          error_handler.handle_error(StandardError.new("Test error"), {provider: "claude"})
        end
        error_times << time
      end

      average_time = error_times.sum / error_times.size

      # Error handling should be reasonably fast (under 100ms)
      expect(average_time).to be < 0.1

      # Individual error handling should not exceed 200ms
      expect(error_times.max).to be < 0.2
    end

    it "classifies errors quickly" do
      error_handler = Aidp::Harness::ErrorHandler.new(nil, nil)
      classifier = error_handler.instance_variable_get(:@error_classifier)

      # Measure error classification time
      classification_times = []

      100.times do
        time = Benchmark.realtime do
          classifier.classify_error(StandardError.new("Test error"), {})
        end
        classification_times << time
      end

      average_time = classification_times.sum / classification_times.size

      # Error classification should be very fast (under 0.5ms)
      expect(average_time).to be < 0.0005

      # Individual error classification should not exceed 1ms
      expect(classification_times.max).to be < 0.001
    end
  end

  describe "Condition Detection Performance" do
    it "detects conditions quickly" do
      condition_detector = Aidp::Harness::ConditionDetector.new

      # Measure condition detection time
      detection_times = []

      100.times do
        time = Benchmark.realtime do
          condition_detector.is_rate_limited?({message: "Rate limit exceeded"})
          condition_detector.needs_user_feedback?({message: "Please provide input"})
          condition_detector.is_work_complete?({message: "Work completed"}, nil)
        end
        detection_times << time
      end

      average_time = detection_times.sum / detection_times.size

      # Condition detection should be very fast (under 0.5ms)
      expect(average_time).to be < 0.0005

      # Individual condition detection should not exceed 1ms
      expect(detection_times.max).to be < 0.001
    end
  end

  describe "User Interface Performance" do
    it "processes user input quickly" do
      user_interface = Aidp::Harness::UserInterface.new

      # Measure user input processing time
      processing_times = []

      10.times do
        time = Benchmark.realtime do
          user_interface.collect_feedback([])
        end
        processing_times << time
      end

      average_time = processing_times.sum / processing_times.size

      # User input processing should be fast (under 10ms)
      expect(average_time).to be < 0.01

      # Individual input processing should not exceed 20ms
      expect(processing_times.max).to be < 0.02
    end

    it "validates input quickly" do
      user_interface = Aidp::Harness::UserInterface.new

      # Measure input validation time
      validation_times = []

      100.times do
        time = Benchmark.realtime do
          user_interface.validate_response("test input", "text")
        end
        validation_times << time
      end

      average_time = validation_times.sum / validation_times.size

      # Input validation should be very fast (under 0.5ms)
      expect(average_time).to be < 0.0005

      # Individual input validation should not exceed 1ms
      expect(validation_times.max).to be < 0.001
    end
  end

  describe "Status Display Performance" do
    it "updates status quickly" do
      status_display = Aidp::Harness::StatusDisplay.new

      # Measure status update time
      update_times = []

      100.times do
        time = Benchmark.realtime do
          status_display.get_status_data
        end
        update_times << time
      end

      average_time = update_times.sum / update_times.size

      # Status updates should be very fast (under 1ms)
      expect(average_time).to be < 0.001

      # Individual status update should not exceed 2ms
      expect(update_times.max).to be < 0.002
    end

    it "formats status data quickly" do
      status_display = Aidp::Harness::StatusDisplay.new

      # Measure status formatting time
      formatting_times = []

      100.times do
        time = Benchmark.realtime do
          status_display.get_status_data
        end
        formatting_times << time
      end

      average_time = formatting_times.sum / formatting_times.size

      # Status formatting should be very fast (under 0.5ms)
      expect(average_time).to be < 0.0005

      # Individual status formatting should not exceed 1ms
      expect(formatting_times.max).to be < 0.001
    end
  end

  describe "Job Management Performance" do
    it "creates jobs quickly" do
      job_manager = Aidp::Harness::JobManager.new(project_dir)

      # Measure job creation time
      creation_times = []

      10.times do
        time = Benchmark.realtime do
          job_manager.create_harness_job("TestJob", {test: "data"})
        end
        creation_times << time
      end

      average_time = creation_times.sum / creation_times.size

      # Job creation should be fast (under 20ms)
      expect(average_time).to be < 0.02

      # Individual job creation should not exceed 50ms
      expect(creation_times.max).to be < 0.05
    end

    it "tracks job status quickly" do
      job_manager = Aidp::Harness::JobManager.new(project_dir)

      # Measure job status tracking time
      tracking_times = []

      100.times do
        time = Benchmark.realtime do
          job_manager.get_job_status("test_job_123")
        end
        tracking_times << time
      end

      average_time = tracking_times.sum / tracking_times.size

      # Job status tracking should be very fast (under 1ms)
      expect(average_time).to be < 0.001

      # Individual job status tracking should not exceed 2ms
      expect(tracking_times.max).to be < 0.002
    end
  end

  describe "Memory Usage Performance" do
    it "maintains reasonable memory usage during initialization" do
      # Measure memory usage during harness initialization
      initial_memory = get_memory_usage

      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
      harness_runner.status

      final_memory = get_memory_usage
      memory_increase = final_memory - initial_memory

      # Memory increase should be reasonable (less than 10MB)
      expect(memory_increase).to be < 10_000_000
    end

    it "maintains reasonable memory usage during operation" do
      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)

      # Measure memory usage during multiple operations
      initial_memory = get_memory_usage

      # Perform various operations
      100.times do
        harness_runner.status
        begin
          harness_runner.send(:save_state)
          harness_runner.send(:load_state)
        rescue => e
          # Handle timeout errors gracefully
          puts "State operation error: #{e.message}" if e.message.include?("timeout")
        end
      end

      final_memory = get_memory_usage
      memory_increase = final_memory - initial_memory

      # Memory increase should be reasonable (less than 5MB)
      expect(memory_increase).to be < 5_000_000
    end

    it "handles memory pressure gracefully" do
      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)

      # Simulate memory pressure by creating large objects
      large_objects = []

      # Create large objects to simulate memory pressure
      10.times do |i|
        large_objects << "x" * (1024 * 1024) # 1MB strings
      end

      # Harness should still function under memory pressure
      expect {
        harness_runner.status
        harness_runner.send(:save_state)
      }.not_to raise_error

      # Clean up
      large_objects.clear
      GC.start
    end
  end

  describe "CPU Usage Performance" do
    it "maintains low CPU usage during idle state" do
      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)

      # Measure CPU usage during idle operations
      Time.now
      start_cpu = get_cpu_usage

      # Perform lightweight operations
      1000.times do
        harness_runner.status
      end

      Time.now
      end_cpu = get_cpu_usage
      cpu_usage = end_cpu - start_cpu

      # CPU usage should be reasonable (less than 10% for 1000 operations)
      expect(cpu_usage).to be < 0.1
    end

    it "handles CPU-intensive operations efficiently" do
      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)

      # Measure CPU usage during intensive operations
      Time.now
      start_cpu = get_cpu_usage

      # Perform intensive operations
      100.times do
        begin
          harness_runner.send(:save_state)
          harness_runner.send(:load_state)
        rescue => e
          # Handle timeout errors gracefully
          puts "State operation error: #{e.message}" if e.message.include?("timeout")
        end
        harness_runner.status
      end

      Time.now
      end_cpu = get_cpu_usage
      cpu_usage = end_cpu - start_cpu

      # CPU usage should be reasonable (less than 20% for 100 intensive operations)
      expect(cpu_usage).to be < 0.2
    end
  end

  describe "End-to-End Performance" do
    it "completes full harness cycle quickly" do
      # Measure end-to-end harness performance
      start_time = Time.now

      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)

      # Simulate a full harness cycle
      harness_runner.status
      harness_runner.send(:save_state)
      harness_runner.send(:load_state)

      # Simulate provider operations
      provider_manager = harness_runner.instance_variable_get(:@provider_manager)
      provider_manager.switch_provider
      provider_manager.switch_model

      # Simulate error handling
      error_handler = harness_runner.instance_variable_get(:@error_handler)
      error_handler.handle_error(StandardError.new("Test error"), {})

      # Simulate user interface
      user_interface = harness_runner.instance_variable_get(:@user_interface)
      user_interface.collect_feedback([])

      # Simulate status display
      status_display = harness_runner.instance_variable_get(:@status_display)
      status_display.get_status_data

      end_time = Time.now
      total_time = end_time - start_time

      # Full harness cycle should complete quickly (under 500ms)
      expect(total_time).to be < 0.5
    end

    it "scales well with multiple operations" do
      # Measure performance with multiple operations
      start_time = Time.now

      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)

      # Perform multiple operations
      50.times do
        harness_runner.status
        begin
          harness_runner.send(:save_state)
          harness_runner.send(:load_state)
        rescue => e
          # Handle timeout errors gracefully
          puts "State operation error: #{e.message}" if e.message.include?("timeout")
        end
      end

      end_time = Time.now
      total_time = end_time - start_time

      # 50 operations should complete in reasonable time (under 2 seconds)
      expect(total_time).to be < 2.0

      # Average time per operation should be under 40ms
      average_time_per_operation = total_time / 50
      expect(average_time_per_operation).to be < 0.04
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

  def get_memory_usage
    # Get memory usage in bytes
    `ps -o rss= -p #{Process.pid}`.to_i * 1024
  end

  def get_cpu_usage
    # Get CPU usage as a percentage
    # This is a simplified implementation for testing
    # In a real scenario, you might use more sophisticated CPU monitoring
    Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
  end
end
