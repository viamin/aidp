# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "Provider failure exhaustion handling" do
  let(:configuration) do
    # Use real configuration class if available; minimal stub otherwise
    Aidp::Harness::Configuration.new(Dir.pwd)
  end
  let(:provider_manager) { Aidp::Harness::ProviderManager.new(configuration) }
  let(:error_handler) { Aidp::Harness::ErrorHandler.new(provider_manager, configuration, nil) }

  # Simulate execution block that always raises a generic error (non-auth)
  it "marks provider unhealthy with reason fail_exhausted after retries exhausted" do
    # Ensure starting provider is known
    start_provider = provider_manager.current_provider
    expect(start_provider).not_to be_nil

    result = error_handler.execute_with_retry do
      raise StandardError, "generic failure for testing"
    end

    expect(result[:status]).to eq("failed")
    health = provider_manager.instance_variable_get(:@provider_health)[start_provider]
    expect(health[:unhealthy_reason]).to eq("fail_exhausted")
    expect(health[:status]).to eq("unhealthy")
    expect(health[:circuit_breaker_open]).to be true
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
end
