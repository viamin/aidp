# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::Configuration do
  let(:project_dir) { "/tmp/test_project" }
  let(:config_file) { File.join(project_dir, "aidp.yml") }
  let(:configuration) { described_class.new(project_dir) }

  before do
    # Mock the configuration loading
    allow(Aidp::Config).to receive(:load_harness_config).and_return(mock_config)
    allow(Aidp::Config).to receive(:validate_harness_config).and_return([])
  end

  let(:mock_config) do
    {
      harness: {
        max_retries: 3,
        default_provider: "claude",
        fallback_providers: ["gemini", "cursor"],
        restrict_to_non_byok: false,
        provider_weights: {
          "claude" => 3,
          "gemini" => 2,
          "cursor" => 1
        },
        circuit_breaker: {
          enabled: true,
          failure_threshold: 5,
          timeout: 300
        },
        retry: {
          enabled: true,
          max_attempts: 3,
          base_delay: 1.0
        },
        rate_limit: {
          enabled: true,
          default_reset_time: 3600
        },
        load_balancing: {
          enabled: true,
          strategy: "weighted_round_robin"
        },
        model_switching: {
          enabled: true,
          auto_switch_on_error: true
        },
        health_check: {
          enabled: true,
          interval: 60
        },
        metrics: {
          enabled: true,
          retention_days: 30
        },
        session: {
          enabled: true,
          timeout: 1800
        }
      },
      providers: {
        claude: {
          type: "api",
          priority: 1,
          max_tokens: 100_000,
          default_flags: ["--dangerously-skip-permissions"],
          models: ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022"],
          model_weights: {
            "claude-3-5-sonnet-20241022" => 3,
            "claude-3-5-haiku-20241022" => 2
          },
          models_config: {
            "claude-3-5-sonnet-20241022" => {
              flags: ["--dangerously-skip-permissions"],
              max_tokens: 200_000,
              timeout: 300
            },
            "claude-3-5-haiku-20241022" => {
              flags: ["--dangerously-skip-permissions"],
              max_tokens: 200_000,
              timeout: 180
            }
          },
          auth: {
            api_key_env: "ANTHROPIC_API_KEY"
          },
          endpoints: {
            default: "https://api.anthropic.com/v1/messages"
          },
          features: {
            file_upload: true,
            code_generation: true,
            vision: true
          },
          monitoring: {
            enabled: true,
            metrics_interval: 60
          }
        },
        gemini: {
          type: "api",
          priority: 2,
          max_tokens: 50_000,
          default_flags: [],
          models: ["gemini-1.5-pro", "gemini-1.5-flash"],
          model_weights: {
            "gemini-1.5-pro" => 3,
            "gemini-1.5-flash" => 2
          },
          models_config: {
            "gemini-1.5-pro" => {
              flags: [],
              max_tokens: 100_000,
              timeout: 300
            },
            "gemini-1.5-flash" => {
              flags: [],
              max_tokens: 100_000,
              timeout: 180
            }
          },
          auth: {
            api_key_env: "GEMINI_API_KEY"
          },
          endpoints: {
            default: "https://generativelanguage.googleapis.com/v1beta/models"
          },
          features: {
            file_upload: true,
            code_generation: true,
            vision: true
          },
          monitoring: {
            enabled: true,
            metrics_interval: 60
          }
        },
        cursor: {
          type: "package",
          priority: 3,
          default_flags: [],
          models: ["cursor-default", "cursor-fast"],
          model_weights: {
            "cursor-default" => 3,
            "cursor-fast" => 2
          },
          models_config: {
            "cursor-default" => {
              flags: [],
              timeout: 600
            },
            "cursor-fast" => {
              flags: ["--fast"],
              timeout: 300
            }
          },
          features: {
            file_upload: true,
            code_generation: true
          },
          monitoring: {
            enabled: true,
            metrics_interval: 60
          }
        }
      }
    }
  end

  describe "initialization" do
    it "loads configuration successfully" do
      expect(configuration).to be_a(described_class)
    end

    it "validates configuration on initialization" do
      expect(Aidp::Config).to receive(:validate_harness_config).with(mock_config)
      described_class.new(project_dir)
    end

    it "raises error for invalid configuration" do
      allow(Aidp::Config).to receive(:validate_harness_config).and_return(["Invalid config"])

      expect {
        described_class.new(project_dir)
      }.to raise_error(described_class::ConfigurationError, "Invalid config")
    end
  end

  describe "harness configuration" do
    it "returns harness configuration" do
      harness_config = configuration.harness_config
      expect(harness_config[:max_retries]).to eq(3)
      expect(harness_config[:default_provider]).to eq("claude")
    end

    it "returns default provider" do
      expect(configuration.default_provider).to eq("claude")
    end

    it "returns fallback providers" do
      expect(configuration.fallback_providers).to eq(["gemini", "cursor"])
    end

    it "returns max retries" do
      expect(configuration.max_retries).to eq(3)
    end

    it "returns restrict to non-BYOK setting" do
      expect(configuration.restrict_to_non_byok?).to be false
    end
  end

  describe "provider configuration" do
    it "returns provider configuration" do
      claude_config = configuration.provider_config("claude")
      expect(claude_config[:type]).to eq("api")
      expect(claude_config[:max_tokens]).to eq(100_000)
    end

    it "returns configured providers" do
      providers = configuration.configured_providers
      expect(providers).to include("claude", "gemini", "cursor")
    end

    it "returns provider type" do
      expect(configuration.provider_type("claude")).to eq("api")
      expect(configuration.provider_type("cursor")).to eq("package")
    end

    it "returns max tokens for provider" do
      expect(configuration.max_tokens("claude")).to eq(100_000)
      expect(configuration.max_tokens("gemini")).to eq(50_000)
    end

    it "returns default flags for provider" do
      expect(configuration.default_flags("claude")).to eq(["--dangerously-skip-permissions"])
      expect(configuration.default_flags("gemini")).to eq([])
    end

    it "checks if provider is configured" do
      expect(configuration.provider_configured?("claude")).to be true
      expect(configuration.provider_configured?("nonexistent")).to be false
    end

    it "returns available providers" do
      providers = configuration.available_providers
      expect(providers).to include("claude", "gemini", "cursor")
    end

    it "filters BYOK providers when restricted" do
      allow(configuration).to receive(:restrict_to_non_byok?).and_return(true)
      allow(configuration).to receive(:provider_type).with("claude").and_return("api")
      allow(configuration).to receive(:provider_type).with("gemini").and_return("api")
      allow(configuration).to receive(:provider_type).with("cursor").and_return("package")

      providers = configuration.available_providers
      expect(providers).to include("claude", "gemini", "cursor")
    end
  end

  describe "model configuration" do
    it "returns provider models" do
      claude_models = configuration.provider_models("claude")
      expect(claude_models).to include("claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022")
    end

    it "returns default model for provider" do
      expect(configuration.default_model("claude")).to eq("claude-3-5-sonnet-20241022")
    end

    it "returns model configuration" do
      model_config = configuration.model_config("claude", "claude-3-5-sonnet-20241022")
      expect(model_config[:max_tokens]).to eq(200_000)
      expect(model_config[:timeout]).to eq(300)
    end

    it "returns model-specific flags" do
      flags = configuration.model_flags("claude", "claude-3-5-sonnet-20241022")
      expect(flags).to eq(["--dangerously-skip-permissions"])
    end

    it "returns model-specific max tokens" do
      max_tokens = configuration.model_max_tokens("claude", "claude-3-5-sonnet-20241022")
      expect(max_tokens).to eq(200_000)
    end

    it "returns model-specific timeout" do
      timeout = configuration.model_timeout("claude", "claude-3-5-sonnet-20241022")
      expect(timeout).to eq(300)
    end

    it "falls back to provider max tokens for model" do
      max_tokens = configuration.model_max_tokens("claude", "nonexistent-model")
      expect(max_tokens).to eq(100_000)
    end
  end

  describe "load balancing configuration" do
    it "returns provider weights" do
      weights = configuration.provider_weights
      expect(weights["claude"]).to eq(3)
      expect(weights["gemini"]).to eq(2)
      expect(weights["cursor"]).to eq(1)
    end

    it "returns model weights for provider" do
      weights = configuration.model_weights("claude")
      expect(weights["claude-3-5-sonnet-20241022"]).to eq(3)
      expect(weights["claude-3-5-haiku-20241022"]).to eq(2)
    end
  end

  describe "system configuration" do
    it "returns circuit breaker configuration" do
      config = configuration.circuit_breaker_config
      expect(config[:enabled]).to be true
      expect(config[:failure_threshold]).to eq(5)
      expect(config[:timeout]).to eq(300)
    end

    it "returns retry configuration" do
      config = configuration.retry_config
      expect(config[:enabled]).to be true
      expect(config[:max_attempts]).to eq(3)
      expect(config[:base_delay]).to eq(1.0)
    end

    it "returns rate limit configuration" do
      config = configuration.rate_limit_config
      expect(config[:enabled]).to be true
      expect(config[:default_reset_time]).to eq(3600)
    end

    it "returns load balancing configuration" do
      config = configuration.load_balancing_config
      expect(config[:enabled]).to be true
      expect(config[:strategy]).to eq("weighted_round_robin")
    end

    it "returns model switching configuration" do
      config = configuration.model_switching_config
      expect(config[:enabled]).to be true
      expect(config[:auto_switch_on_error]).to be true
    end

    it "returns health check configuration" do
      config = configuration.health_check_config
      expect(config[:enabled]).to be true
      expect(config[:interval]).to eq(60)
    end

    it "returns metrics configuration" do
      config = configuration.metrics_config
      expect(config[:enabled]).to be true
      expect(config[:retention_days]).to eq(30)
    end

    it "returns session configuration" do
      config = configuration.session_config
      expect(config[:enabled]).to be true
      expect(config[:timeout]).to eq(1800)
    end
  end

  describe "provider metadata" do
    it "returns provider priority" do
      expect(configuration.provider_priority("claude")).to eq(1)
      expect(configuration.provider_priority("gemini")).to eq(2)
      expect(configuration.provider_priority("cursor")).to eq(3)
    end

    it "returns provider cost configuration" do
      cost_config = configuration.provider_cost_config("claude")
      expect(cost_config).to eq({})
    end

    it "returns provider regions" do
      regions = configuration.provider_regions("claude")
      expect(regions).to eq([])
    end

    it "returns provider authentication configuration" do
      auth_config = configuration.provider_auth_config("claude")
      expect(auth_config[:api_key_env]).to eq("ANTHROPIC_API_KEY")
    end

    it "returns provider endpoints" do
      endpoints = configuration.provider_endpoints("claude")
      expect(endpoints[:default]).to eq("https://api.anthropic.com/v1/messages")
    end

    it "returns provider features" do
      features = configuration.provider_features("claude")
      expect(features[:file_upload]).to be true
      expect(features[:code_generation]).to be true
      expect(features[:vision]).to be true
    end

    it "returns provider monitoring configuration" do
      monitoring_config = configuration.provider_monitoring_config("claude")
      expect(monitoring_config[:enabled]).to be true
      expect(monitoring_config[:metrics_interval]).to eq(60)
    end
  end

  describe "validation" do
    it "validates provider configuration" do
      errors = configuration.validate_provider_config("claude")
      expect(errors).to be_empty
    end

    it "validates model configuration" do
      errors = []
      model_config = {
        max_tokens: 200_000,
        timeout: 300,
        flags: ["--test"]
      }
      configuration.validate_model_config("claude", "test-model", model_config, errors)
      expect(errors).to be_empty
    end

    it "reports validation errors for invalid model configuration" do
      errors = []
      model_config = {
        max_tokens: "invalid",
        timeout: "invalid",
        flags: "invalid"
      }
      configuration.validate_model_config("claude", "test-model", model_config, errors)
      expect(errors).to include("Model 'claude:test-model' max_tokens must be integer")
      expect(errors).to include("Model 'claude:test-model' timeout must be integer")
      expect(errors).to include("Model 'claude:test-model' flags must be array")
    end
  end

  describe "configuration summary" do
    it "returns configuration summary" do
      summary = configuration.configuration_summary
      expect(summary[:providers]).to eq(3)
      expect(summary[:default_provider]).to eq("claude")
      expect(summary[:fallback_providers]).to eq(2)
      expect(summary[:max_retries]).to eq(3)
      expect(summary[:restrict_to_non_byok]).to be false
      expect(summary[:load_balancing_enabled]).to be true
      expect(summary[:model_switching_enabled]).to be true
      expect(summary[:circuit_breaker_enabled]).to be true
      expect(summary[:health_check_enabled]).to be true
      expect(summary[:metrics_enabled]).to be true
    end
  end

  describe "default configurations" do
    it "returns default models for provider" do
      claude_models = configuration.send(:get_default_models_for_provider, "claude")
      expect(claude_models).to include("claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229")

      gemini_models = configuration.send(:get_default_models_for_provider, "gemini")
      expect(gemini_models).to include("gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro")

      cursor_models = configuration.send(:get_default_models_for_provider, "cursor")
      expect(cursor_models).to include("cursor-default", "cursor-fast", "cursor-precise")
    end

    it "returns default model for provider" do
      expect(configuration.send(:get_default_model_for_provider, "claude")).to eq("claude-3-5-sonnet-20241022")
      expect(configuration.send(:get_default_model_for_provider, "gemini")).to eq("gemini-1.5-pro")
      expect(configuration.send(:get_default_model_for_provider, "cursor")).to eq("cursor-default")
    end

    it "returns default timeout for provider" do
      expect(configuration.send(:get_default_timeout_for_provider, "claude")).to eq(300)
      expect(configuration.send(:get_default_timeout_for_provider, "gemini")).to eq(300)
      expect(configuration.send(:get_default_timeout_for_provider, "cursor")).to eq(600)
    end

    it "returns default circuit breaker configuration" do
      config = configuration.send(:get_default_circuit_breaker_config)
      expect(config[:enabled]).to be true
      expect(config[:failure_threshold]).to eq(5)
      expect(config[:timeout]).to eq(300)
      expect(config[:half_open_max_calls]).to eq(3)
    end

    it "returns default retry configuration" do
      config = configuration.send(:get_default_retry_config)
      expect(config[:enabled]).to be true
      expect(config[:max_attempts]).to eq(3)
      expect(config[:base_delay]).to eq(1.0)
      expect(config[:max_delay]).to eq(60.0)
      expect(config[:exponential_base]).to eq(2.0)
      expect(config[:jitter]).to be true
    end

    it "returns default rate limit configuration" do
      config = configuration.send(:get_default_rate_limit_config)
      expect(config[:enabled]).to be true
      expect(config[:default_reset_time]).to eq(3600)
      expect(config[:burst_limit]).to eq(10)
      expect(config[:sustained_limit]).to eq(5)
    end

    it "returns default load balancing configuration" do
      config = configuration.send(:get_default_load_balancing_config)
      expect(config[:enabled]).to be true
      expect(config[:strategy]).to eq("weighted_round_robin")
      expect(config[:health_check_interval]).to eq(30)
      expect(config[:unhealthy_threshold]).to eq(3)
    end

    it "returns default model switching configuration" do
      config = configuration.send(:get_default_model_switching_config)
      expect(config[:enabled]).to be true
      expect(config[:auto_switch_on_error]).to be true
      expect(config[:auto_switch_on_rate_limit]).to be true
      expect(config[:fallback_strategy]).to eq("sequential")
    end

    it "returns default health check configuration" do
      config = configuration.send(:get_default_health_check_config)
      expect(config[:enabled]).to be true
      expect(config[:interval]).to eq(60)
      expect(config[:timeout]).to eq(10)
      expect(config[:failure_threshold]).to eq(3)
      expect(config[:success_threshold]).to eq(2)
    end

    it "returns default metrics configuration" do
      config = configuration.send(:get_default_metrics_config)
      expect(config[:enabled]).to be true
      expect(config[:retention_days]).to eq(30)
      expect(config[:aggregation_interval]).to eq(300)
      expect(config[:export_interval]).to eq(3600)
    end

    it "returns default session configuration" do
      config = configuration.send(:get_default_session_config)
      expect(config[:enabled]).to be true
      expect(config[:timeout]).to eq(1800)
      expect(config[:sticky_sessions]).to be true
      expect(config[:session_affinity]).to eq("provider_model")
    end
  end

  describe "configuration file management" do
    it "returns configuration path" do
      expect(configuration.config_path).to eq(File.join(project_dir, "aidp.yml"))
    end

    it "checks if configuration exists" do
      expect(Aidp::Config).to receive(:config_exists?).with(project_dir)
      configuration.config_exists?
    end

    it "creates example configuration" do
      expect(Aidp::Config).to receive(:create_example_config).with(project_dir)
      configuration.create_example_config
    end

    it "returns raw configuration" do
      raw_config = configuration.raw_config
      expect(raw_config).to eq(mock_config)
      expect(raw_config).not_to be(mock_config) # Should be a copy
    end
  end

  describe "error handling" do
    it "raises ConfigurationError for missing default provider" do
      invalid_config = mock_config.dup
      invalid_config[:harness].delete(:default_provider)
      allow(Aidp::Config).to receive(:load_harness_config).and_return(invalid_config)
      allow(Aidp::Config).to receive(:validate_harness_config).and_return([])

      expect {
        described_class.new(project_dir)
      }.to raise_error(described_class::ConfigurationError, /Default provider not specified/)
    end

    it "raises ConfigurationError for unconfigured default provider" do
      invalid_config = mock_config.dup
      invalid_config[:harness][:default_provider] = "nonexistent"
      allow(Aidp::Config).to receive(:load_harness_config).and_return(invalid_config)
      allow(Aidp::Config).to receive(:validate_harness_config).and_return([])

      expect {
        described_class.new(project_dir)
      }.to raise_error(described_class::ConfigurationError, /Default provider 'nonexistent' not configured/)
    end

    it "raises ConfigurationError for unconfigured fallback provider" do
      invalid_config = mock_config.dup
      invalid_config[:harness][:fallback_providers] = ["nonexistent"]
      allow(Aidp::Config).to receive(:load_harness_config).and_return(invalid_config)
      allow(Aidp::Config).to receive(:validate_harness_config).and_return([])

      expect {
        described_class.new(project_dir)
      }.to raise_error(described_class::ConfigurationError, /Fallback provider 'nonexistent' not configured/)
    end
  end
end
