# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/ai_decision_engine"
require "aidp/harness/thinking_depth_manager"
require "aidp/harness/provider_factory"
require "aidp/harness/configuration"

# Integration tests that exercise the real code paths without mocking internal classes.
# These tests catch method signature mismatches that unit tests with mocks would miss.
#
# Background: PR review reported "wrong number of arguments (given 3, expected 2)"
# but unit tests didn't catch this because they mock ThinkingDepthManager.
RSpec.describe Aidp::Harness::AIDecisionEngine, :integration do
  let(:project_dir) { Dir.mktmpdir }
  let(:config_path) { File.join(project_dir, ".aidp", "config.yml") }

  # Create a real configuration with minimal setup
  let(:config_content) do
    {
      "harness" => {
        "default_provider" => "anthropic"
      },
      "providers" => {
        "anthropic" => {
          "type" => "usage_based",
          "model_family" => "claude",
          "auth" => {
            "api_key_env" => "ANTHROPIC_API_KEY"
          },
          "thinking_tiers" => {
            "mini" => {"models" => ["claude-3-haiku-20240307"]},
            "standard" => {"models" => ["claude-3-5-sonnet-20241022"]},
            "thinking" => {"models" => ["claude-3-5-sonnet-20241022"]}
          }
        }
      },
      "thinking" => {
        "default_tier" => "mini",
        "max_tier" => "thinking"
      }
    }
  end

  before do
    FileUtils.mkdir_p(File.dirname(config_path))
    File.write(config_path, config_content.to_yaml)
    allow(Aidp).to receive(:log_debug)
    allow(Aidp).to receive(:log_error)
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "integration with ThinkingDepthManager" do
    # This test verifies that AIDecisionEngine correctly calls ThinkingDepthManager
    # with the right argument types (no mocking of internal classes)
    it "correctly calls select_model_for_tier with expected arguments" do
      config = Aidp::Harness::Configuration.new(project_dir)
      provider = instance_double(Aidp::Providers::Base)
      provider_factory = instance_double(Aidp::Harness::ProviderFactory)

      allow(provider_factory).to receive(:create_provider).and_return(provider)
      allow(provider).to receive(:send_message).and_return(
        {condition: "rate_limit", confidence: 0.9, reasoning: "test"}.to_json
      )

      engine = described_class.new(config, provider_factory: provider_factory)

      # This exercises the real ThinkingDepthManager.select_model_for_tier call
      # If there's a signature mismatch, this test will fail
      expect {
        engine.decide(:condition_detection, context: {response: "rate limit"})
      }.not_to raise_error
    end

    it "ThinkingDepthManager.select_model_for_tier returns expected format" do
      config = Aidp::Harness::Configuration.new(project_dir)
      thinking_manager = Aidp::Harness::ThinkingDepthManager.new(config)

      # Verify the method signature and return format
      result = thinking_manager.select_model_for_tier("mini", provider: "anthropic")

      expect(result).to be_an(Array)
      expect(result.length).to eq(3)

      provider_name, model_name, model_data = result
      expect(provider_name).to be_a(String)
      expect(model_name).to be_a(String)
      expect(model_data).to be_a(Hash)
    end
  end

  describe "integration with ImplementationVerifier decision type" do
    it "implementation_verification decision type exists and is callable" do
      config = Aidp::Harness::Configuration.new(project_dir)
      provider = instance_double(Aidp::Providers::Base)
      provider_factory = instance_double(Aidp::Harness::ProviderFactory)

      allow(provider_factory).to receive(:create_provider).and_return(provider)
      allow(provider).to receive(:send_message).and_return(
        {
          fully_implemented: true,
          reasoning: "All requirements met",
          missing_requirements: [],
          additional_work_needed: []
        }.to_json
      )

      engine = described_class.new(config, provider_factory: provider_factory)

      # This is the decision type used by ImplementationVerifier
      # Verify the whole path works without argument errors
      expect {
        engine.decide(
          :implementation_verification,
          context: {prompt: "Test verification prompt"},
          schema: {
            type: "object",
            properties: {
              fully_implemented: {type: "boolean"},
              reasoning: {type: "string"},
              missing_requirements: {type: "array", items: {type: "string"}},
              additional_work_needed: {type: "array", items: {type: "string"}}
            },
            required: %w[fully_implemented reasoning missing_requirements additional_work_needed]
          },
          tier: :mini,
          cache_ttl: nil
        )
      }.not_to raise_error
    end
  end

  describe "method signature compatibility" do
    # These tests verify that method signatures match what callers expect
    # They catch "wrong number of arguments" errors early

    it "AIDecisionEngine.decide accepts expected keyword arguments" do
      config = Aidp::Harness::Configuration.new(project_dir)
      provider = instance_double(Aidp::Providers::Base)
      provider_factory = instance_double(Aidp::Harness::ProviderFactory)

      allow(provider_factory).to receive(:create_provider).and_return(provider)
      allow(provider).to receive(:send_message).and_return(
        {condition: "none", confidence: 0.9, reasoning: "test"}.to_json
      )

      engine = described_class.new(config, provider_factory: provider_factory)

      # Verify all keyword argument combinations work
      expect {
        # Minimal call
        engine.decide(:condition_detection, context: {response: "test"})
      }.not_to raise_error

      expect {
        # With schema
        engine.decide(:condition_detection, context: {response: "test"}, schema: nil)
      }.not_to raise_error

      expect {
        # With tier
        engine.decide(:condition_detection, context: {response: "test"}, tier: "mini")
      }.not_to raise_error

      expect {
        # With cache_ttl
        engine.decide(:condition_detection, context: {response: "test"}, cache_ttl: 60)
      }.not_to raise_error

      expect {
        # All keyword args
        engine.decide(
          :condition_detection,
          context: {response: "test"},
          schema: nil,
          tier: "mini",
          cache_ttl: 60
        )
      }.not_to raise_error
    end

    it "ThinkingDepthManager.select_model_for_tier accepts expected arguments" do
      config = Aidp::Harness::Configuration.new(project_dir)
      manager = Aidp::Harness::ThinkingDepthManager.new(config)

      # Verify argument combinations that are used in AIDecisionEngine
      expect {
        manager.select_model_for_tier("mini", provider: "anthropic")
      }.not_to raise_error

      expect {
        manager.select_model_for_tier("mini", provider: nil)
      }.not_to raise_error

      expect {
        manager.select_model_for_tier(nil, provider: "anthropic")
      }.not_to raise_error
    end
  end
end
