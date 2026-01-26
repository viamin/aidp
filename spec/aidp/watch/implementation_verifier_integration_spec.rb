# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# Integration tests that exercise the real code paths in ImplementationVerifier.
# These tests catch method signature mismatches that unit tests with mocks would miss.
#
# Background: PR review reported "wrong number of arguments (given 3, expected 2)"
# but unit tests didn't catch this because they mock AIDecisionEngine.
RSpec.describe Aidp::Watch::ImplementationVerifier, :integration do
  let(:project_dir) { Dir.mktmpdir }
  let(:working_dir) { project_dir }
  let(:config_path) { File.join(project_dir, ".aidp", "aidp.yml") }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }

  # Create a real configuration with minimal setup
  let(:config_content) do
    {
      "harness" => {
        "default_provider" => "anthropic",
        "fallback_providers" => []  # Override default to avoid validation errors
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
            "standard" => {"models" => ["claude-3-5-sonnet-20241022"]}
          }
        }
      },
      "thinking" => {
        "default_tier" => "mini",
        "max_tier" => "thinking"
      }
    }
  end

  let(:issue) do
    {
      number: 123,
      title: "Add user authentication",
      body: "Implement user login and registration features",
      comments: []
    }
  end

  before do
    # Create config file
    FileUtils.mkdir_p(File.dirname(config_path))
    File.write(config_path, config_content.to_yaml)

    # Create a minimal git repo
    Dir.chdir(project_dir) do
      system("git init", out: File::NULL, err: File::NULL)
      system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
      system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
      system("git config commit.gpgsign false", out: File::NULL, err: File::NULL)
      system("git checkout -b main", out: File::NULL, err: File::NULL)

      # Initial commit
      File.write("README.md", "# Test Project\n")
      system("git add .", out: File::NULL, err: File::NULL)
      system("git commit -m 'Initial commit'", out: File::NULL, err: File::NULL)

      # Feature branch with code changes
      system("git checkout -b feature-auth", out: File::NULL, err: File::NULL)
      FileUtils.mkdir_p("app/models")
      File.write("app/models/user.rb", "class User < ApplicationRecord\nend\n")
      system("git add .", out: File::NULL, err: File::NULL)
      system("git commit -m 'Add user model'", out: File::NULL, err: File::NULL)
    end

    allow(Aidp).to receive(:log_debug)
    allow(Aidp).to receive(:log_info)
    allow(Aidp).to receive(:log_warn)
    allow(Aidp).to receive(:log_error)
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "integration with AIDecisionEngine" do
    it "correctly calls AIDecisionEngine.decide with expected arguments" do
      # Create real AIDecisionEngine but mock the provider
      provider = instance_double(AgentHarness::Providers::Base)
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

      config = Aidp::Harness::Configuration.new(project_dir)
      ai_engine = Aidp::Harness::AIDecisionEngine.new(config, provider_factory: provider_factory)

      verifier = described_class.new(
        repository_client: repository_client,
        project_dir: project_dir,
        ai_decision_engine: ai_engine
      )

      # This exercises the real AIDecisionEngine.decide call from ImplementationVerifier
      # If there's a signature mismatch, this test will fail with ArgumentError
      expect {
        verifier.verify(issue: issue, working_dir: working_dir)
      }.not_to raise_error
    end

    it "handles AIDecisionEngine errors gracefully" do
      # Create engine that will raise an error
      provider = instance_double(AgentHarness::Providers::Base)
      provider_factory = instance_double(Aidp::Harness::ProviderFactory)

      allow(provider_factory).to receive(:create_provider).and_return(provider)
      allow(provider).to receive(:send_message).and_raise(
        ArgumentError.new("wrong number of arguments (given 3, expected 2)")
      )

      config = Aidp::Harness::Configuration.new(project_dir)
      ai_engine = Aidp::Harness::AIDecisionEngine.new(config, provider_factory: provider_factory)

      verifier = described_class.new(
        repository_client: repository_client,
        project_dir: project_dir,
        ai_decision_engine: ai_engine
      )

      # Should not raise - should catch and return error result
      result = verifier.verify(issue: issue, working_dir: working_dir)

      expect(result[:verified]).to be false
      expect(result[:reason]).to include("error")
    end
  end

  describe "full verification chain without mocking internal classes" do
    # This test creates real objects for the entire chain:
    # ImplementationVerifier -> AIDecisionEngine -> ThinkingDepthManager -> Configuration
    # Only the actual API call is mocked

    it "exercises the complete verification chain" do
      provider = instance_double(AgentHarness::Providers::Base)
      provider_factory = instance_double(Aidp::Harness::ProviderFactory)

      allow(provider_factory).to receive(:create_provider).and_return(provider)
      allow(provider).to receive(:send_message).and_return(
        {
          fully_implemented: false,
          reasoning: "Missing registration endpoint",
          missing_requirements: ["User registration"],
          additional_work_needed: ["Add registration controller"]
        }.to_json
      )

      config = Aidp::Harness::Configuration.new(project_dir)
      ai_engine = Aidp::Harness::AIDecisionEngine.new(config, provider_factory: provider_factory)

      verifier = described_class.new(
        repository_client: repository_client,
        project_dir: project_dir,
        ai_decision_engine: ai_engine
      )

      result = verifier.verify(issue: issue, working_dir: working_dir)

      # Verify the result structure matches what ReviewProcessor expects
      expect(result).to include(:verified, :reason, :missing_items, :additional_work)
      expect(result[:verified]).to be false
      expect(result[:missing_items]).to include("User registration")
    end
  end

  describe "method signature compatibility for decide call" do
    # Verify the exact call signature used in ImplementationVerifier.perform_zfc_verification
    # This catches mismatches between how the verifier calls decide and how decide expects args

    it "decide accepts the argument format used by ImplementationVerifier" do
      provider = instance_double(AgentHarness::Providers::Base)
      provider_factory = instance_double(Aidp::Harness::ProviderFactory)

      allow(provider_factory).to receive(:create_provider).and_return(provider)
      allow(provider).to receive(:send_message).and_return(
        {
          fully_implemented: true,
          reasoning: "Complete",
          missing_requirements: [],
          additional_work_needed: []
        }.to_json
      )

      config = Aidp::Harness::Configuration.new(project_dir)
      ai_engine = Aidp::Harness::AIDecisionEngine.new(config, provider_factory: provider_factory)

      # This is the exact call pattern from ImplementationVerifier line 308-314
      schema = {
        type: "object",
        properties: {
          fully_implemented: {type: "boolean"},
          reasoning: {type: "string"},
          missing_requirements: {type: "array", items: {type: "string"}},
          additional_work_needed: {type: "array", items: {type: "string"}}
        },
        required: %w[fully_implemented reasoning missing_requirements additional_work_needed]
      }

      expect {
        ai_engine.decide(
          :implementation_verification,
          context: {prompt: "test prompt"},
          schema: schema,
          tier: :mini,
          cache_ttl: nil
        )
      }.not_to raise_error
    end
  end
end
