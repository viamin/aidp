# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "Provider failure exhaustion handling" do
  let(:temp_dir) { Dir.mktmpdir("aidp_provider_failure_test") }
  let(:config_file) { File.join(temp_dir, ".aidp", "aidp.yml") }
  let(:configuration) do
    # Create a test configuration file
    create_test_configuration
    Aidp::Harness::Configuration.new(temp_dir)
  end
  let(:binary_checker) { double("BinaryChecker", which: "/usr/bin/claude") }
  let(:provider_manager) { Aidp::Harness::ProviderManager.new(configuration, binary_checker: binary_checker) }
  let(:test_sleeper) { double("Sleeper", sleep: nil) }
  let(:error_handler) { Aidp::Harness::ErrorHandler.new(provider_manager, configuration, nil, sleeper: test_sleeper) }

  before do
    # Ensure binary checker returns a path (CLI available) and sleeper is no-op
    allow(binary_checker).to receive(:which).and_return("/usr/bin/claude")
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  # Simulate execution block that always raises a generic error (non-auth)
  it "marks provider unhealthy with reason fail_exhausted after retries exhausted" do
    # Ensure starting provider is known
    start_provider = provider_manager.current_provider
    expect(start_provider).not_to be_nil

    result = error_handler.execute_with_retry do
      raise StandardError, "generic failure for testing"
    end

    expect(result[:status]).to eq("failed")
    expect(provider_manager.provider_health_status[start_provider][:unhealthy_reason]).to eq("fail_exhausted")
  end

  it "does not override auth unhealthy state with fail_exhausted" do
    start_provider = provider_manager.current_provider
    provider_manager.mark_provider_auth_failure(start_provider)
    # Marked auth failure should persist after generic retry exhaustion

    result = error_handler.execute_with_retry do
      raise StandardError, "another generic failure" # triggers exhaustion
    end

    expect(result[:status]).to eq("failed")
    health_after = provider_manager.instance_variable_get(:@provider_health)[start_provider]
    expect(health_after[:unhealthy_reason]).to eq("auth")
    expect(health_after[:status]).to eq("unhealthy_auth")
  end

  private

  def create_test_configuration
    config = {
      "harness" => {
        "default_provider" => "anthropic",
        "max_retries" => 1, # Reduced from 3 for faster tests
        "retry_delay" => 0, # No delay for tests (if supported)
        "fallback_providers" => ["cursor", "macos"]
      },
      "providers" => {
        "anthropic" => {
          "type" => "usage_based",
          "priority" => 1,
          "models" => ["claude-3-5-sonnet-20241022"]
        },
        "cursor" => {
          "type" => "subscription",
          "priority" => 2,
          "models" => ["cursor-default"]
        },
        "macos" => {
          "type" => "passthrough",
          "priority" => 3,
          "models" => ["cursor-chat"]
        }
      }
    }

    FileUtils.mkdir_p(File.dirname(config_file))
    File.write(config_file, YAML.dump(config))
  end
end
