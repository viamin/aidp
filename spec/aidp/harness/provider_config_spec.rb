# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/harness/provider_config"
require_relative "../../../lib/aidp/harness/provider_factory"

RSpec.describe Aidp::Harness::ProviderConfig do
  let(:project_dir) { "/tmp/test_project" }
  let(:config_file) { File.join(project_dir, "aidp.yml") }
  let(:config_manager) { Aidp::Harness::ConfigManager.new(project_dir) }
  let(:provider_name) { "cursor" }
  let(:provider_config) { described_class.new(provider_name, config_manager) }

  before do
    FileUtils.mkdir_p(project_dir)
  end

  after do
    FileUtils.rm_rf(project_dir) if Dir.exist?(project_dir)
  end

  describe "initialization" do
    it "creates provider config successfully" do
      expect(provider_config).to be_a(described_class)
      expect(provider_config.instance_variable_get(:@provider_name)).to eq("cursor")
    end
  end

  describe "configuration access" do
    let(:valid_config) do
      {
        harness: {
          default_provider: "cursor"
        },
        providers: {
          cursor: {
            type: "package",
            priority: 1,
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
              code_generation: true,
              analysis: true,
              vision: false
            },
            monitoring: {
              enabled: true,
              metrics_interval: 30
            },
            rate_limit: {
              enabled: true,
              requests_per_minute: 60
            },
            retry: {
              enabled: true,
              max_attempts: 3
            },
            circuit_breaker: {
              enabled: true,
              failure_threshold: 5
            },
            cost: {
              input_cost_per_token: 0.0001,
              output_cost_per_token: 0.0002
            },
            harness: {
              enabled: true,
              auto_switch_on_error: true
            },
            health_check: {
              enabled: true,
              interval: 60
            },
            auth: {
              api_key_env: "CURSOR_API_KEY"
            },
            endpoints: {
              default: "https://api.cursor.sh/v1"
            }
          }
        }
      }
    end

    before do
      File.write(config_file, YAML.dump(valid_config))
    end

    it "gets provider configuration" do
      config = provider_config.get_config

      expect(config).to be_a(Hash)
      expect(config[:type]).to eq("package")
      expect(config[:priority]).to eq(1)
    end

    it "gets provider type" do
      expect(provider_config.get_type).to eq("package")
    end

    it "checks provider types" do
      expect(provider_config.package_provider?).to be true
      expect(provider_config.api_provider?).to be false
      expect(provider_config.byok_provider?).to be false
    end

    it "gets provider priority" do
      expect(provider_config.get_priority).to eq(1)
    end

    it "gets provider models" do
      models = provider_config.get_models

      expect(models).to include("cursor-default", "cursor-fast")
    end

    it "gets default model" do
      expect(provider_config.get_default_model).to eq("cursor-default")
    end

    it "gets model weights" do
      weights = provider_config.get_model_weights

      expect(weights["cursor-default"]).to eq(3)
      expect(weights["cursor-fast"]).to eq(2)
    end

    it "gets model configuration" do
      default_config = provider_config.get_model_config("cursor-default")
      fast_config = provider_config.get_model_config("cursor-fast")

      expect(default_config[:flags]).to eq([])
      expect(default_config[:timeout]).to eq(600)
      expect(fast_config[:flags]).to eq(["--fast"])
      expect(fast_config[:timeout]).to eq(300)
    end

    it "gets provider features" do
      features = provider_config.get_features

      expect(features[:file_upload]).to be true
      expect(features[:code_generation]).to be true
      expect(features[:analysis]).to be true
      expect(features[:vision]).to be false
    end

    it "checks feature support" do
      expect(provider_config.supports_feature?(:file_upload)).to be true
      expect(provider_config.supports_feature?(:vision)).to be false
    end

    it "gets provider capabilities" do
      capabilities = provider_config.get_capabilities

      expect(capabilities).to include("file_upload", "code_generation", "analysis")
      expect(capabilities).not_to include("vision")
    end

    it "gets provider max tokens" do
      expect(provider_config.get_max_tokens).to be_nil
    end

    it "gets provider timeout" do
      expect(provider_config.get_timeout).to eq(300)
    end

    it "gets provider default flags" do
      flags = provider_config.get_default_flags

      expect(flags).to eq([])
    end

    it "gets model-specific flags" do
      default_flags = provider_config.get_model_flags("cursor-default")
      fast_flags = provider_config.get_model_flags("cursor-fast")

      expect(default_flags).to eq([])
      expect(fast_flags).to eq(["--fast"])
    end

    it "gets combined flags" do
      default_combined = provider_config.get_combined_flags("cursor-default")
      fast_combined = provider_config.get_combined_flags("cursor-fast")

      expect(default_combined).to eq([])
      expect(fast_combined).to eq(["--fast"])
    end

    it "gets authentication configuration" do
      auth_config = provider_config.get_auth_config

      expect(auth_config[:api_key_env]).to eq("CURSOR_API_KEY")
    end

    it "gets API key" do
      # Mock environment variable
      allow(ENV).to receive(:[]).with("CURSOR_API_KEY").and_return("test_api_key")

      api_key = provider_config.get_api_key

      expect(api_key).to eq("test_api_key")
    end

    it "gets endpoints configuration" do
      endpoints = provider_config.get_endpoints

      expect(endpoints[:default]).to eq("https://api.cursor.sh/v1")
    end

    it "gets default endpoint" do
      expect(provider_config.get_default_endpoint).to eq("https://api.cursor.sh/v1")
    end

    it "gets monitoring configuration" do
      monitoring = provider_config.get_monitoring_config

      expect(monitoring[:enabled]).to be true
      expect(monitoring[:metrics_interval]).to eq(30)
    end

    it "gets rate limit configuration" do
      rate_limit = provider_config.get_rate_limit_config

      expect(rate_limit[:enabled]).to be true
      expect(rate_limit[:requests_per_minute]).to eq(60)
    end

    it "gets retry configuration" do
      retry_config = provider_config.get_retry_config

      expect(retry_config[:enabled]).to be true
      expect(retry_config[:max_attempts]).to eq(3)
    end

    it "gets circuit breaker configuration" do
      cb_config = provider_config.get_circuit_breaker_config

      expect(cb_config[:enabled]).to be true
      expect(cb_config[:failure_threshold]).to eq(5)
    end

    it "gets cost configuration" do
      cost_config = provider_config.get_cost_config

      expect(cost_config[:input_cost_per_token]).to eq(0.0001)
      expect(cost_config[:output_cost_per_token]).to eq(0.0002)
    end

    it "gets harness configuration" do
      harness_config = provider_config.get_harness_config

      expect(harness_config[:enabled]).to be true
      expect(harness_config[:auto_switch_on_error]).to be true
    end

    it "gets health check configuration" do
      health_check = provider_config.get_health_check_config

      expect(health_check[:enabled]).to be true
      expect(health_check[:interval]).to eq(60)
    end

    it "gets environment variables" do
      env_vars = provider_config.get_env_vars

      expect(env_vars).to be_a(Hash)
    end

    it "gets command line arguments" do
      cmd_args = provider_config.get_cmd_args

      expect(cmd_args).to be_a(Array)
    end

    it "gets working directory" do
      working_dir = provider_config.get_working_directory

      expect(working_dir).to eq(Dir.pwd)
    end

    it "gets log configuration" do
      log_config = provider_config.get_log_config

      expect(log_config[:enabled]).to be true
      expect(log_config[:level]).to eq("info")
    end

    it "gets cache configuration" do
      cache_config = provider_config.get_cache_config

      expect(cache_config[:enabled]).to be true
      expect(cache_config[:ttl]).to eq(3600)
    end

    it "gets security configuration" do
      security_config = provider_config.get_security_config

      expect(security_config[:ssl_verify]).to be true
      expect(security_config[:timeout]).to eq(30)
    end
  end

  describe "provider status" do
    it "checks if provider is configured" do
      # No configuration file
      expect(provider_config.configured?).to be false

      # Add configuration
      config = {
        providers: {
          cursor: {
            type: "package"
          }
        }
      }
      File.write(config_file, YAML.dump(config))

      expect(provider_config.configured?).to be true
    end

    it "checks if provider is enabled" do
      # No configuration
      expect(provider_config.enabled?).to be false

      # Add configuration with harness enabled
      config = {
        providers: {
          cursor: {
            type: "package",
            harness: {
              enabled: true
            }
          }
        }
      }
      File.write(config_file, YAML.dump(config))

      expect(provider_config.enabled?).to be true
    end

    it "gets provider status" do
      # No configuration
      expect(provider_config.get_status).to eq(:not_configured)

      # Add configuration
      config = {
        providers: {
          cursor: {
            type: "package",
            harness: {
              enabled: true
            }
          }
        }
      }
      File.write(config_file, YAML.dump(config))

      expect(provider_config.get_status).to eq(:enabled)
    end

    it "gets provider summary" do
      # No configuration
      summary = provider_config.get_summary
      expect(summary).to eq({})

      # Add configuration
      config = {
        providers: {
          cursor: {
            type: "package",
            priority: 1,
            models: ["cursor-default"],
            features: {
              file_upload: true
            },
            harness: {
              enabled: true
            }
          }
        }
      }
      File.write(config_file, YAML.dump(config))

      summary = provider_config.get_summary

      expect(summary[:name]).to eq("cursor")
      expect(summary[:type]).to eq("package")
      expect(summary[:priority]).to eq(1)
      expect(summary[:models]).to include("cursor-default")
      expect(summary[:features]).to include("file_upload")
      expect(summary[:status]).to eq(:enabled)
      expect(summary[:configured]).to be true
      expect(summary[:enabled]).to be true
    end
  end

  describe "configuration reloading" do
    it "reloads configuration" do
      config = {
        providers: {
          cursor: {
            type: "package",
            priority: 1
          }
        }
      }
      File.write(config_file, YAML.dump(config))

      expect(provider_config.get_priority).to eq(1)

      # Modify configuration
      config[:providers][:cursor][:priority] = 2
      File.write(config_file, YAML.dump(config))

      provider_config.reload_config

      expect(provider_config.get_priority).to eq(2)
    end
  end
end

RSpec.describe Aidp::Harness::ProviderFactory do
  let(:project_dir) { "/tmp/test_project" }
  let(:config_file) { File.join(project_dir, "aidp.yml") }
  let(:config_manager) { Aidp::Harness::ConfigManager.new(project_dir) }
  let(:factory) { described_class.new(config_manager) }

  before do
    FileUtils.mkdir_p(project_dir)
  end

  after do
    FileUtils.rm_rf(project_dir) if Dir.exist?(project_dir)
  end

  describe "initialization" do
    it "creates factory successfully" do
      expect(factory).to be_a(described_class)
    end
  end

  describe "provider creation" do
    let(:valid_config) do
      {
        harness: {
          default_provider: "cursor"
        },
        providers: {
          cursor: {
            type: "package",
            priority: 1,
            models: ["cursor-default"],
            features: {
              file_upload: true,
              code_generation: true
            },
            harness: {
              enabled: true
            }
          }
        }
      }
    end

    before do
      File.write(config_file, YAML.dump(valid_config))
    end

    it "creates provider instance" do
      provider = factory.create_provider("cursor")

      expect(provider).to be_a(Aidp::Providers::Cursor)
    end

    it "creates multiple providers" do
      providers = factory.create_providers(["cursor"])

      expect(providers).to have(1).item
      expect(providers.first).to be_a(Aidp::Providers::Cursor)
    end

    it "creates all configured providers" do
      providers = factory.create_all_providers

      expect(providers).to have(1).item
      expect(providers.first).to be_a(Aidp::Providers::Cursor)
    end

    it "creates providers by priority" do
      providers = factory.create_providers_by_priority

      expect(providers).to have(1).item
      expect(providers.first).to be_a(Aidp::Providers::Cursor)
    end

    it "creates providers by weight" do
      providers = factory.create_providers_by_weight

      expect(providers).to have(1).item
      expect(providers.first).to be_a(Aidp::Providers::Cursor)
    end

    it "raises error for unconfigured provider" do
      expect {
        factory.create_provider("unknown")
      }.to raise_error("Provider 'unknown' is not configured")
    end

    it "raises error for disabled provider" do
      config = {
        providers: {
          cursor: {
            type: "package",
            harness: {
              enabled: false
            }
          }
        }
      }
      File.write(config_file, YAML.dump(config))

      expect {
        factory.create_provider("cursor")
      }.to raise_error("Provider 'cursor' is disabled")
    end
  end

  describe "provider information" do
    let(:valid_config) do
      {
        providers: {
          cursor: {
            type: "package",
            priority: 1,
            models: ["cursor-default"],
            features: {
              file_upload: true
            },
            harness: {
              enabled: true
            }
          }
        }
      }
    end

    before do
      File.write(config_file, YAML.dump(valid_config))
    end

    it "gets provider configuration" do
      provider_config = factory.get_provider_config("cursor")

      expect(provider_config).to be_a(Aidp::Harness::ProviderConfig)
    end

    it "gets provider class" do
      provider_class = factory.get_provider_class("cursor")

      expect(provider_class).to eq(Aidp::Providers::Cursor)
    end

    it "checks if provider is supported" do
      expect(factory.provider_supported?("cursor")).to be true
      expect(factory.provider_supported?("unknown")).to be false
    end

    it "gets supported provider names" do
      supported = factory.get_supported_providers

      expect(supported).to include("cursor", "anthropic", "gemini", "macos_ui")
    end

    it "gets configured provider names" do
      configured = factory.get_configured_providers

      expect(configured).to include("cursor")
    end

    it "gets enabled provider names" do
      enabled = factory.get_enabled_providers

      expect(enabled).to include("cursor")
    end

    it "gets provider capabilities" do
      capabilities = factory.get_provider_capabilities("cursor")

      expect(capabilities).to include("file_upload", "code_generation")
    end

    it "checks if provider supports feature" do
      expect(factory.provider_supports_feature?("cursor", "file_upload")).to be true
      expect(factory.provider_supports_feature?("cursor", "vision")).to be false
    end

    it "gets provider models" do
      models = factory.get_provider_models("cursor")

      expect(models).to include("cursor-default")
    end

    it "gets provider summary" do
      summary = factory.get_provider_summary("cursor")

      expect(summary[:name]).to eq("cursor")
      expect(summary[:type]).to eq("package")
      expect(summary[:priority]).to eq(1)
    end

    it "gets all provider summaries" do
      summaries = factory.get_all_provider_summaries

      expect(summaries).to have(1).item
      expect(summaries.first[:name]).to eq("cursor")
    end
  end

  describe "configuration validation" do
    it "validates provider configuration" do
      # No configuration
      errors = factory.validate_provider_config("cursor")
      expect(errors).to include("Provider 'cursor' is not configured")

      # Add configuration
      config = {
        providers: {
          cursor: {
            type: "package",
            models: ["cursor-default"],
            harness: {
              enabled: true
            }
          }
        }
      }
      File.write(config_file, YAML.dump(config))

      errors = factory.validate_provider_config("cursor")
      expect(errors).to be_empty
    end

    it "validates all provider configurations" do
      config = {
        providers: {
          cursor: {
            type: "package",
            models: ["cursor-default"],
            harness: {
              enabled: true
            }
          }
        }
      }
      File.write(config_file, YAML.dump(config))

      all_errors = factory.validate_all_provider_configs
      expect(all_errors).to be_empty
    end
  end

  describe "cache management" do
    it "clears cache" do
      factory.clear_cache

      expect(factory.instance_variable_get(:@provider_instances)).to be_empty
      expect(factory.instance_variable_get(:@provider_configs)).to be_empty
    end

    it "reloads configuration" do
      factory.reload_config

      expect(factory.instance_variable_get(:@provider_instances)).to be_empty
      expect(factory.instance_variable_get(:@provider_configs)).to be_empty
    end
  end
end
