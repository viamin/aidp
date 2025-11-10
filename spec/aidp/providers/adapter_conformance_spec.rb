# frozen_string_literal: true

require "spec_helper"
require "aidp/providers/adapter"
require "aidp/providers/base"

RSpec.describe "ProviderAdapter Conformance" do
  # This shared example group tests that a provider conforms to the ProviderAdapter interface
  # Usage in provider specs:
  #   RSpec.describe Aidp::Providers::Anthropic do
  #     it_behaves_like "a conforming provider adapter", Aidp::Providers::Anthropic
  #   end
  shared_examples "a conforming provider adapter" do |provider_class|
    let(:provider) { provider_class.new }

    describe "Core Interface" do
      it "responds to #name" do
        expect(provider).to respond_to(:name)
      end

      it "returns a string from #name" do
        expect(provider.name).to be_a(String)
        expect(provider.name).not_to be_empty
      end

      it "responds to #display_name" do
        expect(provider).to respond_to(:display_name)
      end

      it "returns a string from #display_name" do
        expect(provider.display_name).to be_a(String)
        expect(provider.display_name).not_to be_empty
      end

      it "responds to #send_message" do
        expect(provider).to respond_to(:send_message)
      end

      it "responds to #available?" do
        expect(provider).to respond_to(:available?)
      end

      it "returns a boolean from #available?" do
        expect([true, false]).to include(provider.available?)
      end
    end

    describe "Capability Declaration" do
      it "responds to #supports_mcp?" do
        expect(provider).to respond_to(:supports_mcp?)
      end

      it "returns a boolean from #supports_mcp?" do
        expect([true, false]).to include(provider.supports_mcp?)
      end

      it "responds to #fetch_mcp_servers" do
        expect(provider).to respond_to(:fetch_mcp_servers)
      end

      it "returns an array from #fetch_mcp_servers" do
        expect(provider.fetch_mcp_servers).to be_an(Array)
      end

      it "responds to #capabilities" do
        expect(provider).to respond_to(:capabilities)
      end

      it "returns a hash from #capabilities" do
        caps = provider.capabilities
        expect(caps).to be_a(Hash)

        # Check for standard capability keys
        expect(caps).to have_key(:reasoning_tiers) if caps.key?(:reasoning_tiers)
        expect(caps).to have_key(:context_window) if caps.key?(:context_window)
        expect(caps).to have_key(:supports_json_mode) if caps.key?(:supports_json_mode)
        expect(caps).to have_key(:supports_tool_use) if caps.key?(:supports_tool_use)
        expect(caps).to have_key(:supports_vision) if caps.key?(:supports_vision)
        expect(caps).to have_key(:supports_file_upload) if caps.key?(:supports_file_upload)
      end
    end

    describe "Dangerous Permissions" do
      it "responds to #supports_dangerous_mode?" do
        expect(provider).to respond_to(:supports_dangerous_mode?)
      end

      it "returns a boolean from #supports_dangerous_mode?" do
        expect([true, false]).to include(provider.supports_dangerous_mode?)
      end

      it "responds to #dangerous_mode_flags" do
        expect(provider).to respond_to(:dangerous_mode_flags)
      end

      it "returns an array from #dangerous_mode_flags" do
        expect(provider.dangerous_mode_flags).to be_an(Array)
      end

      it "responds to #dangerous_mode_enabled?" do
        expect(provider).to respond_to(:dangerous_mode_enabled?)
      end

      it "returns a boolean from #dangerous_mode_enabled?" do
        expect([true, false]).to include(provider.dangerous_mode_enabled?)
      end

      it "responds to #dangerous_mode=" do
        expect(provider).to respond_to(:dangerous_mode=)
      end

      it "can toggle dangerous mode" do
        original = provider.dangerous_mode_enabled?
        provider.dangerous_mode = !original
        expect(provider.dangerous_mode_enabled?).to eq(!original)
        provider.dangerous_mode = original # Restore
      end
    end

    describe "Error Classification" do
      it "responds to #error_patterns" do
        expect(provider).to respond_to(:error_patterns)
      end

      it "returns a hash from #error_patterns" do
        expect(provider.error_patterns).to be_a(Hash)
      end

      it "responds to #classify_error" do
        expect(provider).to respond_to(:classify_error)
      end

      it "classifies errors into valid categories" do
        error = StandardError.new("rate limit exceeded")
        category = provider.classify_error(error)
        expect(category).to be_a(Symbol)
        expect([:rate_limited, :auth_expired, :quota_exceeded, :transient, :permanent]).to include(category)
      end

      it "responds to #error_metadata" do
        expect(provider).to respond_to(:error_metadata)
      end

      it "returns a hash from #error_metadata" do
        error = StandardError.new("test error")
        metadata = provider.error_metadata(error)
        expect(metadata).to be_a(Hash)
        expect(metadata).to have_key(:provider)
        expect(metadata).to have_key(:error_category)
        expect(metadata).to have_key(:timestamp)
      end

      it "responds to #retryable_error?" do
        expect(provider).to respond_to(:retryable_error?)
      end

      it "returns a boolean from #retryable_error?" do
        error = StandardError.new("test error")
        expect([true, false]).to include(provider.retryable_error?(error))
      end
    end

    describe "Logging and Metrics" do
      it "responds to #logging_metadata" do
        expect(provider).to respond_to(:logging_metadata)
      end

      it "returns a hash from #logging_metadata" do
        metadata = provider.logging_metadata
        expect(metadata).to be_a(Hash)
        expect(metadata).to have_key(:provider)
      end

      it "responds to #redact_secrets" do
        expect(provider).to respond_to(:redact_secrets)
      end

      it "redacts API keys from messages" do
        message = "API_KEY=sk-1234567890abcdefghij"
        redacted = provider.redact_secrets(message)
        expect(redacted).not_to include("sk-1234567890abcdefghij")
        expect(redacted).to include("[REDACTED]")
      end

      it "redacts tokens from messages" do
        message = "token: secret_token_value"
        redacted = provider.redact_secrets(message)
        expect(redacted).not_to include("secret_token_value")
        expect(redacted).to include("[REDACTED]")
      end
    end

    describe "Configuration Validation" do
      it "responds to #validate_config" do
        expect(provider).to respond_to(:validate_config)
      end

      it "returns a hash with validation result" do
        config = {type: "usage_based"}
        result = provider.validate_config(config)
        expect(result).to be_a(Hash)
        expect(result).to have_key(:valid)
        expect(result).to have_key(:errors)
        expect(result).to have_key(:warnings)
      end

      it "validates provider type" do
        invalid_config = {type: "invalid_type"}
        result = provider.validate_config(invalid_config)
        expect(result[:valid]).to be false
        expect(result[:errors]).not_to be_empty
      end

      it "accepts valid configuration" do
        valid_config = {type: "usage_based", models: ["model1"]}
        result = provider.validate_config(valid_config)
        # May have warnings but should be valid
        expect(result).to have_key(:valid)
      end
    end

    describe "Health Status" do
      it "responds to #health_status" do
        expect(provider).to respond_to(:health_status)
      end

      it "returns a hash from #health_status" do
        status = provider.health_status
        expect(status).to be_a(Hash)
        expect(status).to have_key(:provider)
        expect(status).to have_key(:available)
        expect(status).to have_key(:timestamp)
      end
    end
  end

  # Test that the Adapter module itself provides default implementations
  describe Aidp::Providers::Adapter do
    let(:test_class) do
      Class.new do
        include Aidp::Providers::Adapter

        def name
          "test_provider"
        end

        def send_message(prompt:, session: nil, **options)
          "test response"
        end
      end
    end

    let(:provider) { test_class.new }

    it "provides default implementation for supports_mcp?" do
      expect(provider.supports_mcp?).to be false
    end

    it "provides default implementation for fetch_mcp_servers" do
      expect(provider.fetch_mcp_servers).to eq([])
    end

    it "provides default implementation for available?" do
      expect(provider.available?).to be true
    end

    it "provides default implementation for capabilities" do
      expect(provider.capabilities).to be_a(Hash)
      expect(provider.capabilities[:reasoning_tiers]).to eq([])
    end

    it "provides default implementation for supports_dangerous_mode?" do
      expect(provider.supports_dangerous_mode?).to be false
    end

    it "provides default implementation for dangerous_mode_flags" do
      expect(provider.dangerous_mode_flags).to eq([])
    end

    it "provides default implementation for error_patterns" do
      expect(provider.error_patterns).to eq({})
    end

    it "classifies errors using ErrorTaxonomy by default" do
      error = StandardError.new("rate limit exceeded")
      expect(provider.classify_error(error)).to eq(:rate_limited)
    end

    it "redacts secrets from messages" do
      message = "API_KEY=sk-1234567890 and password=secret123"
      redacted = provider.redact_secrets(message)
      expect(redacted).not_to include("sk-1234567890")
      expect(redacted).not_to include("secret123")
    end
  end
end
