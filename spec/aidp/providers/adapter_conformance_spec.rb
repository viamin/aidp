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

    describe "dangerous mode state management" do
      it "defaults to disabled" do
        expect(provider.dangerous_mode_enabled?).to be false
      end

      it "can be enabled" do
        provider.dangerous_mode = true
        expect(provider.dangerous_mode_enabled?).to be true
      end

      it "can be disabled" do
        provider.dangerous_mode = true
        provider.dangerous_mode = false
        expect(provider.dangerous_mode_enabled?).to be false
      end

      it "persists state across multiple calls" do
        provider.dangerous_mode = true
        expect(provider.dangerous_mode_enabled?).to be true
        expect(provider.dangerous_mode_enabled?).to be true # Call again
      end
    end

    describe "#display_name" do
      it "defaults to name when not overridden" do
        expect(provider.display_name).to eq(provider.name)
      end
    end

    describe "#classify_error with provider-specific patterns" do
      let(:test_class_with_patterns) do
        Class.new do
          include Aidp::Providers::Adapter

          def name
            "test_provider"
          end

          def send_message(prompt:, session: nil, **options)
            "test response"
          end

          def error_patterns
            {
              rate_limited: [/custom rate limit/i],
              auth_expired: [/custom auth error/i],
              quota_exceeded: [/custom quota/i]
            }
          end
        end
      end

      let(:provider_with_patterns) { test_class_with_patterns.new }

      it "uses provider-specific patterns first" do
        error = StandardError.new("custom rate limit exceeded")
        expect(provider_with_patterns.classify_error(error)).to eq(:rate_limited)
      end

      it "matches auth errors with provider patterns" do
        error = StandardError.new("custom auth error occurred")
        expect(provider_with_patterns.classify_error(error)).to eq(:auth_expired)
      end

      it "matches quota errors with provider patterns" do
        error = StandardError.new("custom quota exceeded")
        expect(provider_with_patterns.classify_error(error)).to eq(:quota_exceeded)
      end

      it "falls back to ErrorTaxonomy when no pattern matches" do
        error = StandardError.new("timeout error")
        expect(provider_with_patterns.classify_error(error)).to eq(:transient)
      end
    end

    describe "#error_metadata" do
      it "includes all required metadata fields" do
        error = StandardError.new("test error")
        metadata = provider.error_metadata(error)

        expect(metadata[:provider]).to eq("test_provider")
        expect(metadata[:error_category]).to be_a(Symbol)
        expect(metadata[:error_class]).to eq("StandardError")
        expect(metadata[:message]).to be_a(String)
        expect(metadata[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        expect([true, false]).to include(metadata[:retryable])
      end

      it "redacts secrets in error messages" do
        error = StandardError.new("Error: api_key=sk-secret123")
        metadata = provider.error_metadata(error)

        expect(metadata[:message]).to include("[REDACTED]")
        expect(metadata[:message]).not_to include("sk-secret123")
      end

      it "sets retryable to true for transient errors" do
        error = StandardError.new("timeout error")
        metadata = provider.error_metadata(error)

        expect(metadata[:retryable]).to be true
      end

      it "sets retryable to false for non-transient errors" do
        error = StandardError.new("invalid model")
        metadata = provider.error_metadata(error)

        expect(metadata[:retryable]).to be false
      end
    end

    describe "#retryable_error?" do
      it "returns true for transient errors" do
        error = StandardError.new("connection timeout")
        expect(provider.retryable_error?(error)).to be true
      end

      it "returns false for permanent errors" do
        error = StandardError.new("invalid model")
        expect(provider.retryable_error?(error)).to be false
      end

      it "returns false for rate limit errors" do
        error = StandardError.new("rate limit exceeded")
        expect(provider.retryable_error?(error)).to be false
      end
    end

    describe "#logging_metadata" do
      it "includes all required fields" do
        metadata = provider.logging_metadata

        expect(metadata[:provider]).to eq("test_provider")
        expect(metadata[:display_name]).to eq("test_provider")
        expect(metadata[:supports_mcp]).to be false
        expect(metadata[:available]).to be true
        expect(metadata[:dangerous_mode]).to be false
      end

      it "reflects dangerous mode state" do
        provider.dangerous_mode = true
        metadata = provider.logging_metadata

        expect(metadata[:dangerous_mode]).to be true
      end
    end

    describe "#redact_secrets" do
      it "redacts API keys with underscores" do
        message = "api_key: sk-1234567890abcdefghij"
        redacted = provider.redact_secrets(message)
        expect(redacted).to include("[REDACTED]")
        expect(redacted).not_to include("sk-1234567890abcdefghij")
      end

      it "redacts API keys with hyphens" do
        message = "api-key=sk-secret"
        redacted = provider.redact_secrets(message)
        expect(redacted).to include("[REDACTED]")
      end

      it "redacts API keys case-insensitively" do
        message = "API_KEY: sk-secret"
        redacted = provider.redact_secrets(message)
        expect(redacted).to include("[REDACTED]")
      end

      it "redacts tokens" do
        message = "token: my_secret_token"
        redacted = provider.redact_secrets(message)
        expect(redacted).to include("[REDACTED]")
        expect(redacted).not_to include("my_secret_token")
      end

      it "redacts passwords" do
        message = "password=supersecret"
        redacted = provider.redact_secrets(message)
        expect(redacted).to include("[REDACTED]")
        expect(redacted).not_to include("supersecret")
      end

      it "redacts bearer tokens" do
        message = "Authorization: Bearer abc123xyz"
        redacted = provider.redact_secrets(message)
        expect(redacted).to include("[REDACTED]")
        expect(redacted).not_to include("abc123xyz")
      end

      it "redacts OpenAI-style keys" do
        message = "key is sk-proj-1234567890abcdefghijk"
        redacted = provider.redact_secrets(message)
        expect(redacted).to include("sk-[REDACTED]")
        expect(redacted).not_to include("sk-proj-1234567890abcdefghijk")
      end

      it "handles multiple secrets in one message" do
        message = "api_key=sk-secret and password=pass123 with token=tok456"
        redacted = provider.redact_secrets(message)
        expect(redacted).not_to include("sk-secret")
        expect(redacted).not_to include("pass123")
        expect(redacted).not_to include("tok456")
        expect(redacted.scan("REDACTED").length).to be >= 3
      end

      it "preserves non-secret content" do
        message = "Error occurred at line 42: connection failed"
        redacted = provider.redact_secrets(message)
        expect(redacted).to eq(message)
      end
    end

    describe "#validate_config" do
      it "requires type field" do
        config = {}
        result = provider.validate_config(config)

        expect(result[:valid]).to be false
        expect(result[:errors]).to include("Provider type is required")
      end

      it "validates type is in allowed list" do
        config = {type: "invalid"}
        result = provider.validate_config(config)

        expect(result[:valid]).to be false
        expect(result[:errors]).to include("Provider type must be one of: usage_based, subscription, passthrough")
      end

      it "accepts usage_based type" do
        config = {type: "usage_based"}
        result = provider.validate_config(config)

        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end

      it "accepts subscription type" do
        config = {type: "subscription"}
        result = provider.validate_config(config)

        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end

      it "accepts passthrough type" do
        config = {type: "passthrough"}
        result = provider.validate_config(config)

        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end

      it "validates models is an array" do
        config = {type: "usage_based", models: "not-an-array"}
        result = provider.validate_config(config)

        expect(result[:valid]).to be false
        expect(result[:errors]).to include("Models must be an array")
      end

      it "accepts valid models array" do
        config = {type: "usage_based", models: ["model1", "model2"]}
        result = provider.validate_config(config)

        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end

      it "returns warnings array" do
        config = {type: "usage_based"}
        result = provider.validate_config(config)

        expect(result[:warnings]).to be_an(Array)
      end

      it "handles multiple validation errors" do
        config = {models: "not-an-array"}
        result = provider.validate_config(config)

        expect(result[:valid]).to be false
        expect(result[:errors].length).to be >= 1
      end
    end

    describe "#health_status" do
      it "includes provider name" do
        status = provider.health_status
        expect(status[:provider]).to eq("test_provider")
      end

      it "includes availability status" do
        status = provider.health_status
        expect(status[:available]).to be true
      end

      it "sets healthy to match available" do
        status = provider.health_status
        expect(status[:healthy]).to eq(status[:available])
      end

      it "includes timestamp" do
        status = provider.health_status
        expect(status[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end
    end

    describe "NotImplementedError for core methods" do
      let(:incomplete_class) do
        Class.new do
          include Aidp::Providers::Adapter
        end
      end

      let(:incomplete_provider) { incomplete_class.new }

      it "raises NotImplementedError for #name" do
        expect { incomplete_provider.name }.to raise_error(NotImplementedError, /must implement #name/)
      end

      it "raises NotImplementedError for #send_message" do
        expect { incomplete_provider.send_message(prompt: "test") }
          .to raise_error(NotImplementedError, /must implement #send_message/)
      end
    end

    describe "default implementations" do
      it "returns empty hash for capabilities" do
        caps = provider.capabilities
        expect(caps[:reasoning_tiers]).to eq([])
        expect(caps[:context_window]).to eq(100_000)
        expect(caps[:supports_json_mode]).to be false
        expect(caps[:supports_tool_use]).to be false
        expect(caps[:supports_vision]).to be false
        expect(caps[:supports_file_upload]).to be false
        expect(caps[:streaming]).to be false
      end
    end
  end
end
