# frozen_string_literal: true

require "spec_helper"
require "benchmark"
require_relative "../../support/test_prompt"

RSpec.describe "Harness Performance Testing (Simple)", type: :performance do
  let(:project_dir) { Dir.mktmpdir("aidp_harness_performance_simple_test") }
  let(:config_file) { File.join(project_dir, ".aidp", "aidp.yml") }
  let(:test_prompt) { TestPrompt.new }

  before do
    # Set up mock mode for tests
    # Create a mock project structure
    setup_mock_project
    mock_cli_operations
    # Create harness configuration
    setup_harness_config
    # Mock provider manager operations to avoid real CLI calls
    mock_provider_operations
  end

  after do
    FileUtils.remove_entry(project_dir)
  end

  describe "Core Component Performance" do
    it "initializes harness components quickly" do
      # Measure component initialization times
      times = {}

      # Configuration initialization
      times[:config] = Benchmark.realtime do
        configuration = Aidp::Harness::Configuration.new(project_dir)
        configuration.default_provider
      end

      # Provider manager initialization
      times[:provider_manager] = Benchmark.realtime do
        configuration = Aidp::Harness::Configuration.new(project_dir)
        provider_manager = Aidp::Harness::ProviderManager.new(configuration, prompt: test_prompt)
        provider_manager.current_provider
      end

      # Error handler initialization
      times[:error_handler] = Benchmark.realtime do
        configuration = Aidp::Harness::Configuration.new(project_dir)
        provider_manager = Aidp::Harness::ProviderManager.new(configuration, prompt: test_prompt)
        error_handler = Aidp::Harness::ErrorHandler.new(provider_manager, configuration)
        error_handler.instance_variable_get(:@retry_strategies)
      end

      # Condition detector initialization
      times[:condition_detector] = Benchmark.realtime do
        condition_detector = Aidp::Harness::ConditionDetector.new
        condition_detector.is_rate_limited?({message: "test"})
      end

      # User interface initialization
      times[:user_interface] = Benchmark.realtime do
        user_interface = Aidp::Harness::UserInterface.new
        user_interface.collect_feedback([])
      end

      # Status display initialization
      times[:status_display] = Benchmark.realtime do
        status_display = Aidp::Harness::StatusDisplay.new
        status_display.status_data
      end

      # All components should initialize quickly (under 100ms each)
      times.each do |component, time|
        expect(time).to be < 0.1, "#{component} initialization took #{time}s, expected < 0.1s"
      end

      # Total initialization time should be reasonable (under 500ms)
      total_time = times.values.sum
      expect(total_time).to be < 0.5, "Total initialization took #{total_time}s, expected < 0.5s"
    end

    it "performs basic operations efficiently" do
      # Initialize components
      configuration = Aidp::Harness::Configuration.new(project_dir)
      provider_manager = Aidp::Harness::ProviderManager.new(configuration, prompt: test_prompt)
      error_handler = Aidp::Harness::ErrorHandler.new(provider_manager, configuration)
      condition_detector = Aidp::Harness::ConditionDetector.new
      Aidp::Harness::UserInterface.new
      status_display = Aidp::Harness::StatusDisplay.new

      # Measure basic operation times
      times = {}

      # Provider switching
      times[:provider_switch] = Benchmark.realtime do
        10.times { provider_manager.switch_provider }
      end

      # Model switching
      times[:model_switch] = Benchmark.realtime do
        10.times { provider_manager.switch_model }
      end

      # Error classification
      times[:error_classification] = Benchmark.realtime do
        100.times do
          error_handler.instance_variable_get(:@error_classifier).classify_error(
            StandardError.new("test"), {}
          )
        end
      end

      # Condition detection
      times[:condition_detection] = Benchmark.realtime do
        100.times do
          condition_detector.is_rate_limited?({message: "Rate limit exceeded"})
          condition_detector.needs_user_feedback?({message: "Please provide input"})
          condition_detector.is_work_complete?({message: "Work completed"}, nil)
        end
      end

      # Status data retrieval
      times[:status_retrieval] = Benchmark.realtime do
        100.times { status_display.status_data }
      end

      # All operations should be efficient
      expect(times[:provider_switch]).to be < 0.1, "Provider switching took #{times[:provider_switch]}s"
      expect(times[:model_switch]).to be < 0.05, "Model switching took #{times[:model_switch]}s"
      expect(times[:error_classification]).to be < 0.1, "Error classification took #{times[:error_classification]}s"
      expect(times[:condition_detection]).to be < 0.1, "Condition detection took #{times[:condition_detection]}s"
      expect(times[:status_retrieval]).to be < 0.1, "Status retrieval took #{times[:status_retrieval]}s"
    end

    it "handles memory usage efficiently" do
      # Measure memory usage during component creation
      initial_memory = get_memory_usage

      # Create multiple instances of components
      components = []
      10.times do
        configuration = Aidp::Harness::Configuration.new(project_dir)
        provider_manager = Aidp::Harness::ProviderManager.new(configuration, prompt: test_prompt)
        error_handler = Aidp::Harness::ErrorHandler.new(provider_manager, configuration)
        condition_detector = Aidp::Harness::ConditionDetector.new
        user_interface = Aidp::Harness::UserInterface.new
        status_display = Aidp::Harness::StatusDisplay.new

        components << {
          config: configuration,
          provider_manager: provider_manager,
          error_handler: error_handler,
          condition_detector: condition_detector,
          user_interface: user_interface,
          status_display: status_display
        }
      end

      final_memory = get_memory_usage
      memory_increase = final_memory - initial_memory

      # Memory increase should be reasonable (less than 50MB for 10 component sets)
      expect(memory_increase).to be < 50_000_000, "Memory increased by #{memory_increase} bytes, expected < 50MB"

      # Average memory per component set should be reasonable (less than 5MB)
      average_memory_per_set = memory_increase / 10
      expect(average_memory_per_set).to be < 5_000_000, "Average memory per component set: #{average_memory_per_set} bytes"
    end

    it "maintains consistent performance across multiple runs" do
      # Initialize components
      configuration = Aidp::Harness::Configuration.new(project_dir)
      provider_manager = Aidp::Harness::ProviderManager.new(configuration, prompt: test_prompt)
      condition_detector = Aidp::Harness::ConditionDetector.new

      # Measure performance across multiple runs
      run_times = []

      10.times do
        time = Benchmark.realtime do
          100.times do
            provider_manager.switch_provider
            condition_detector.is_rate_limited?({message: "test"})
          end
        end
        run_times << time
      end

      # Calculate statistics
      average_time = run_times.sum / run_times.size
      min_time = run_times.min
      max_time = run_times.max
      variance = run_times.map { |t| (t - average_time)**2 }.sum / run_times.size
      standard_deviation = Math.sqrt(variance)

      # Performance should be consistent
      expect(average_time).to be < 0.2, "Average time: #{average_time}s"
      expect(max_time - min_time).to be < 0.1, "Time variance: #{max_time - min_time}s"
      expect(standard_deviation).to be < 0.05, "Standard deviation: #{standard_deviation}s"
    end
  end

  describe "Harness Runner Performance" do
    it "initializes harness runner quickly" do
      # Measure harness runner initialization
      initialization_times = []

      5.times do
        time = Benchmark.realtime do
          harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
          harness_runner.status
        end
        initialization_times << time
      end

      average_time = initialization_times.sum / initialization_times.size
      max_time = initialization_times.max

      # Harness runner initialization should be fast
      expect(average_time).to be < 0.2, "Average initialization time: #{average_time}s"
      expect(max_time).to be < 0.5, "Max initialization time: #{max_time}s"
    end

    it "performs status operations efficiently" do
      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)

      # Measure status operation performance
      status_times = []

      100.times do
        time = Benchmark.realtime do
          harness_runner.status
        end
        status_times << time
      end

      average_time = status_times.sum / status_times.size
      max_time = status_times.max

      # Status operations should be very fast
      expect(average_time).to be < 0.01, "Average status time: #{average_time}s"
      expect(max_time).to be < 0.05, "Max status time: #{max_time}s"
    end

    it "handles provider operations efficiently" do
      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)
      provider_manager = harness_runner.instance_variable_get(:@provider_manager)

      # Measure provider operation performance
      provider_times = []

      50.times do
        time = Benchmark.realtime do
          provider_manager.switch_provider
          provider_manager.switch_model
          provider_manager.current_provider
          provider_manager.current_model
        end
        provider_times << time
      end

      average_time = provider_times.sum / provider_times.size
      max_time = provider_times.max

      # Provider operations should be fast
      expect(average_time).to be < 0.02, "Average provider operation time: #{average_time}s"
      expect(max_time).to be < 0.05, "Max provider operation time: #{max_time}s"
    end
  end

  describe "Performance Benchmarks" do
    it "meets performance benchmarks for critical operations" do
      # Define performance benchmarks
      benchmarks = {
        config_initialization: 0.05,      # 50ms
        provider_switch: 0.01,            # 10ms
        model_switch: 0.01,               # 10ms (relaxed from 5ms for CI variance)
        error_classification: 0.001,      # 1ms
        condition_detection: 0.001,       # 1ms
        status_retrieval: 0.001,          # 1ms
        harness_initialization: 0.2,      # 200ms
        harness_status: 0.01              # 10ms
      }

      # Initialize components
      configuration = Aidp::Harness::Configuration.new(project_dir)
      provider_manager = Aidp::Harness::ProviderManager.new(configuration, prompt: test_prompt)
      error_handler = Aidp::Harness::ErrorHandler.new(provider_manager, configuration)
      condition_detector = Aidp::Harness::ConditionDetector.new
      status_display = Aidp::Harness::StatusDisplay.new
      harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze)

      # Measure actual performance
      actual_times = {}

      # Configuration initialization
      actual_times[:config_initialization] = Benchmark.realtime do
        Aidp::Harness::Configuration.new(project_dir)
      end

      # Provider switch
      actual_times[:provider_switch] = Benchmark.realtime do
        provider_manager.switch_provider
      end

      # Model switch
      actual_times[:model_switch] = Benchmark.realtime do
        provider_manager.switch_model
      end

      # Error classification
      actual_times[:error_classification] = Benchmark.realtime do
        error_handler.instance_variable_get(:@error_classifier).classify_error(
          StandardError.new("test"), {}
        )
      end

      # Condition detection
      actual_times[:condition_detection] = Benchmark.realtime do
        condition_detector.is_rate_limited?({message: "test"})
      end

      # Status retrieval
      actual_times[:status_retrieval] = Benchmark.realtime do
        status_display.status_data
      end

      # Harness status
      actual_times[:harness_status] = Benchmark.realtime do
        harness_runner.status
      end

      # Harness initialization (already done above, but measure separately)
      actual_times[:harness_initialization] = Benchmark.realtime do
        Aidp::Harness::Runner.new(project_dir, :analyze)
      end

      # Check benchmarks
      benchmarks.each do |operation, benchmark_time|
        actual_time = actual_times[operation]
        expect(actual_time).to be < benchmark_time,
          "#{operation}: actual #{actual_time}s, benchmark #{benchmark_time}s"
      end
    end
  end

  private

  def mock_provider_operations
    # Wrap constructor to apply stubs to each real instance (avoids any_instance_of)
    provider_manager_class = Aidp::Harness::ProviderManager
    original_new = provider_manager_class.method(:new)
    allow(provider_manager_class).to receive(:new) do |*args, **kwargs, &blk|
      pm = original_new.call(*args, **kwargs, &blk)
      allow(pm).to receive(:switch_provider).and_return("anthropic")
      allow(pm).to receive(:switch_model).and_return("claude-3-5-sonnet-20241022")
      allow(pm).to receive(:provider_cli_available?).and_return(true)
      allow(pm).to receive(:find_next_healthy_provider).and_return("anthropic")
      allow(pm).to receive(:fallback_chain).and_return(["anthropic", "cursor", "macos"]) # used internally
      allow(pm).to receive(:execute_command_with_timeout).and_return({success: true, output: "mocked output", exit_code: 0})
      pm
    end
  end

  def setup_mock_project
    mock_cli_operations
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
      "harness" => {
        "default_provider" => "anthropic",
        "max_retries" => 3,
        "fallback_providers" => ["cursor", "macos"],
        "auto_switch_on_error" => true,
        "auto_switch_on_rate_limit" => true,
        "concurrent_requests" => 1,
        "timeout" => 300,
        "ui" => {
          "interactive" => true,
          "show_progress" => true
        },
        "error_handling" => {
          "retry_on_error" => true,
          "max_retries" => 3
        },
        "performance" => {
          "enable_metrics" => true,
          "enable_caching" => true
        }
      },
      "providers" => {
        "anthropic" => {
          "type" => "usage_based",
          "priority" => 1,
          "max_tokens" => 100_000,
          "models" => ["anthropic-3-5-sonnet-20241022"],
          "auth" => {
            "api_key_env" => "ANTHROPIC_API_KEY"
          }
        },
        "cursor" => {
          "type" => "subscription",
          "priority" => 2,
          "models" => ["cursor-default"]
        },
        "macos" => {
          "type" => "passthrough",
          "priority" => 3,
          "underlying_service" => "cursor",
          "models" => ["cursor-chat"]
        }
      }
    }

    FileUtils.mkdir_p(File.dirname(config_file))
    File.write(config_file, YAML.dump(config))
  end

  def get_memory_usage
    # Get memory usage in bytes
    `ps -o rss= -p #{Process.pid}`.to_i * 1024
  end
end
