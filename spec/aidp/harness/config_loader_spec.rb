# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/harness/config_loader"
require_relative "../../../lib/aidp/harness/config_manager"

RSpec.describe Aidp::Harness::ConfigLoader do
  let(:project_dir) { "/tmp/test_project" }
  let(:config_file) { File.join(project_dir, ".aidp", "aidp.yml") }
  let(:loader) { described_class.new(project_dir) }

  before do
    FileUtils.mkdir_p(project_dir)
    FileUtils.mkdir_p(File.dirname(config_file))
  end

  after do
    FileUtils.rm_rf(project_dir) if Dir.exist?(project_dir)
  end

  describe "initialization" do
    it "creates loader successfully" do
      expect(loader).to be_a(described_class)
      expect(loader.config_file_path).to be_nil
      expect(loader.config_exists?).to be false
    end
  end

  describe "configuration loading" do
    let(:valid_config) do
      {
        harness: {
          default_provider: "cursor",
          max_retries: 3,
          fallback_providers: ["claude"],
          retry: {
            enabled: true,
            max_attempts: 5
          }
        },
        providers: {
          cursor: {
            type: "subscription",
            priority: 1,
            models: ["cursor-default"],
            features: {
              file_upload: true,
              code_generation: true,
              analysis: true
            }
          },
          claude: {
            type: "usage_based",
            priority: 2,
            max_tokens: 100_000,
            auth: {
              api_key_env: "ANTHROPIC_API_KEY"
            },
            features: {
              file_upload: true,
              code_generation: true,
              analysis: true
            }
          }
        }
      }
    end

    before do
      File.write(config_file, YAML.dump(valid_config))
    end

    it "loads valid configuration successfully" do
      config = loader.load_config

      expect(config).to be_a(Hash)
      expect(config[:harness][:default_provider]).to eq("cursor")
      expect(config[:providers][:cursor][:type]).to eq("subscription")
    end

    it "caches configuration on subsequent loads" do
      config1 = loader.load_config
      config2 = loader.load_config

      expect(config1).to eq(config2)
      expect(config1.object_id).to eq(config2.object_id)
    end

    it "reloads configuration when forced" do
      loader.load_config

      # Modify the file
      modified_config = valid_config.dup
      modified_config[:harness][:max_retries] = 5
      File.write(config_file, YAML.dump(modified_config))

      config2 = loader.load_config(force_reload: true)

      expect(config2[:harness][:max_retries]).to eq(5)
    end

    it "gets harness configuration" do
      harness_config = loader.harness_config

      expect(harness_config).to be_a(Hash)
      expect(harness_config[:default_provider]).to eq("cursor")
      expect(harness_config[:max_retries]).to eq(3)
    end

    it "gets provider configuration" do
      cursor_config = loader.provider_config("cursor")
      claude_config = loader.provider_config("claude")

      expect(cursor_config[:type]).to eq("subscription")
      expect(claude_config[:type]).to eq("usage_based")
      expect(claude_config[:max_tokens]).to eq(100_000)
    end

    it "gets all provider configurations" do
      all_providers = loader.all_provider_configs

      expect(all_providers).to have_key(:cursor)
      expect(all_providers).to have_key(:claude)
      expect(all_providers[:cursor][:type]).to eq("subscription")
      expect(all_providers[:claude][:type]).to eq("usage_based")
    end

    it "gets configured provider names" do
      provider_names = loader.configured_providers

      expect(provider_names).to include("cursor", "claude")
    end
  end

  describe "configuration with overrides" do
    let(:base_config) do
      {
        harness: {
          default_provider: "cursor",
          max_retries: 2
        },
        providers: {
          cursor: {
            type: "subscription",
            priority: 1
          }
        }
      }
    end

    before do
      File.write(config_file, YAML.dump(base_config))
    end

    it "gets configuration with overrides" do
      overrides = {
        harness: {
          max_retries: 5
        },
        providers: {
          cursor: {
            priority: 3
          }
        }
      }

      config = loader.config_with_overrides(overrides)

      expect(config[:harness][:default_provider]).to eq("cursor")
      expect(config[:harness][:max_retries]).to eq(5)
      expect(config[:providers][:cursor][:priority]).to eq(3)
    end

    it "gets harness configuration with overrides" do
      overrides = {
        harness: {
          max_retries: 5
        }
      }

      harness_config = loader.harness_config_with_overrides(overrides)

      expect(harness_config[:default_provider]).to eq("cursor")
      expect(harness_config[:max_retries]).to eq(5)
    end

    it "gets provider configuration with overrides" do
      overrides = {
        providers: {
          cursor: {
            priority: 3
          }
        }
      }

      provider_config = loader.provider_config_with_overrides("cursor", overrides)

      expect(provider_config[:type]).to eq("subscription")
      expect(provider_config[:priority]).to eq(3)
    end
  end

  describe "mode-specific configuration" do
    let(:config_with_modes) do
      {
        harness: {
          default_provider: "cursor",
          max_retries: 2
        },
        analyze_mode: {
          harness: {
            max_retries: 5
          }
        },
        execute_mode: {
          harness: {
            max_retries: 3
          }
        },
        providers: {
          cursor: {
            type: "subscription"
          }
        }
      }
    end

    before do
      File.write(config_file, YAML.dump(config_with_modes))
    end

    it "gets analyze mode configuration" do
      config = loader.mode_config("analyze")

      expect(config[:harness][:max_retries]).to eq(5)
    end

    it "gets execute mode configuration" do
      config = loader.mode_config("execute")

      expect(config[:harness][:max_retries]).to eq(3)
    end

    it "gets default configuration for unknown mode" do
      config = loader.mode_config("unknown")

      expect(config[:harness][:max_retries]).to eq(2)
    end
  end

  describe "environment-specific configuration" do
    let(:config_with_environments) do
      {
        harness: {
          default_provider: "cursor",
          max_retries: 2
        },
        environments: {
          production: {
            harness: {
              max_retries: 1
            }
          },
          development: {
            harness: {
              max_retries: 10
            }
          }
        },
        providers: {
          cursor: {
            type: "subscription"
          }
        }
      }
    end

    before do
      File.write(config_file, YAML.dump(config_with_environments))
    end

    it "gets production environment configuration" do
      config = loader.environment_config("production")
      expect(config[:harness][:max_retries]).to eq(1)
    end

    it "gets development environment configuration" do
      config = loader.environment_config("development")

      expect(config[:harness][:max_retries]).to eq(10)
    end

    it "uses environment from ENV when not specified" do
      original_env = ENV["AIDP_ENV"]
      ENV["AIDP_ENV"] = "production"

      config = loader.environment_config

      expect(config[:harness][:max_retries]).to eq(1)

      ENV["AIDP_ENV"] = original_env
    end
  end

  describe "feature-based configuration" do
    let(:config_with_features) do
      {
        harness: {
          default_provider: "cursor",
          max_retries: 2
        },
        features: {
          high_performance: {
            harness: {
              max_retries: 1
            }
          },
          debugging: {
            harness: {
              max_retries: 10
            }
          }
        },
        providers: {
          cursor: {
            type: "subscription"
          }
        }
      }
    end

    before do
      File.write(config_file, YAML.dump(config_with_features))
    end

    it "gets configuration with enabled features" do
      features = {
        high_performance: true,
        debugging: false
      }

      config = loader.config_with_features(features)

      expect(config[:harness][:max_retries]).to eq(1)
    end

    it "gets configuration with multiple enabled features" do
      features = {
        high_performance: true,
        debugging: true
      }

      config = loader.config_with_features(features)

      # Should use the last feature's configuration (debugging overrides high_performance)
      expect(config[:harness][:max_retries]).to eq(10)
    end
  end

  describe "time-based configuration" do
    let(:config_with_time) do
      {
        harness: {
          default_provider: "cursor",
          max_retries: 2
        },
        time_based: {
          hours: {
            "9-17" => {
              harness: {
                max_retries: 1
              }
            }
          },
          days: {
            "monday" => {
              harness: {
                max_retries: 5
              }
            }
          }
        },
        providers: {
          cursor: {
            type: "subscription"
          }
        }
      }
    end

    before do
      File.write(config_file, YAML.dump(config_with_time))
    end

    it "gets time-based configuration for business hours" do
      # Mock Time.now to return 10 AM on Tuesday (not Monday)
      allow(Time).to receive(:now).and_return(Time.new(2024, 1, 16, 10, 0, 0))

      config = loader.time_based_config

      expect(config[:harness][:max_retries]).to eq(1)
    end

    it "gets time-based configuration for Monday" do
      # Mock Time.now to return Monday
      allow(Time).to receive(:now).and_return(Time.new(2024, 1, 15, 8, 0, 0)) # Monday

      config = loader.time_based_config

      expect(config[:harness][:max_retries]).to eq(5)
    end
  end

  describe "configuration validation" do
    let(:valid_config) do
      {
        harness: {
          default_provider: "cursor"
        },
        providers: {
          cursor: {
            type: "subscription"
          }
        }
      }
    end

    it "handles invalid configuration gracefully" do
      invalid_config = {
        harness: {
          default_provider: "" # Invalid: empty string
        }
      }

      File.write(config_file, YAML.dump(invalid_config))

      config = loader.load_config

      expect(config).to be_nil
    end

    it "checks if configuration is valid" do
      File.write(config_file, YAML.dump(valid_config))

      expect(loader.config_valid?).to be true
    end

    it "gets validation errors" do
      invalid_config = {
        harness: {
          default_provider: ""
        }
      }

      File.write(config_file, YAML.dump(invalid_config))

      errors = loader.validation_errors

      expect(errors).not_to be_empty
    end

    it "logs warnings when config has warnings but is valid" do
      # Create config with warnings (this depends on validator implementation)
      File.write(config_file, YAML.dump(valid_config))

      # Stub validator to return warnings
      allow_any_instance_of(Aidp::Harness::ConfigValidator).to receive(:load_and_validate).and_return({
        valid: true,
        warnings: ["Warning: Some deprecation notice"],
        errors: []
      })
      allow_any_instance_of(Aidp::Harness::ConfigValidator).to receive(:validated_config).and_return(valid_config)

      # Should not raise, but should log warnings
      expect { loader.load_config(true) }.not_to raise_error
    end

    context "in development environment" do
      it "attempts to fix configuration issues" do
        invalid_config = {
          harness: {
            default_provider: ""
          }
        }

        File.write(config_file, YAML.dump(invalid_config))

        # Set development environment
        original_env = ENV["AIDP_ENV"]
        ENV["AIDP_ENV"] = "development"

        # Stub fix_common_issues to return true
        allow_any_instance_of(Aidp::Harness::ConfigValidator).to receive(:fix_common_issues).and_return(true)

        # Should attempt to fix
        loader.load_config

        ENV["AIDP_ENV"] = original_env
      end

      it "does not attempt fix when fix_common_issues returns false" do
        invalid_config = {
          harness: {
            default_provider: ""
          }
        }

        File.write(config_file, YAML.dump(invalid_config))

        # Set development environment
        original_env = ENV["RACK_ENV"]
        ENV["RACK_ENV"] = "development"

        # Stub fix_common_issues to return false
        allow_any_instance_of(Aidp::Harness::ConfigValidator).to receive(:fix_common_issues).and_return(false)

        # Should attempt to fix but not warn about success
        loader.load_config

        ENV["RACK_ENV"] = original_env
      end
    end

    it "gets validation warnings" do
      File.write(config_file, YAML.dump(valid_config))

      # Stub validator to return warnings
      allow_any_instance_of(Aidp::Harness::ConfigValidator).to receive(:validate_existing).and_return({
        valid: true,
        warnings: ["Test warning"],
        errors: []
      })

      warnings = loader.validation_warnings

      expect(warnings).to include("Test warning")
    end
  end

  describe "configuration operations" do
    let(:valid_config) do
      {
        harness: {
          default_provider: "cursor",
          max_retries: 2
        },
        providers: {
          cursor: {
            type: "subscription"
          }
        }
      }
    end

    it "creates example configuration" do
      result = loader.create_example_config

      expect(result).to be true
      expect(File.exist?(config_file)).to be true
    end

    it "fixes configuration issues" do
      config_with_issues = {
        "harness" => { # String keys
          "default_provider" => "cursor"
        },
        "providers" => {
          "cursor" => {
            "type" => "subscription"
          }
        }
      }

      File.write(config_file, YAML.dump(config_with_issues))

      # Load the configuration first
      loader.load_config
      fixed = loader.fix_config_issues

      expect(fixed).to be true
    end

    it "exports configuration" do
      File.write(config_file, YAML.dump(valid_config))

      yaml_export = loader.export_config(:yaml)
      json_export = loader.export_config(:json)

      expect(yaml_export).to be_a(String)
      expect(json_export).to be_a(String)
      expect(yaml_export).to include("harness:")
      expect(json_export).to include('"harness"')
    end

    it "reloads configuration" do
      File.write(config_file, YAML.dump(valid_config))

      loader.load_config

      # Modify file
      modified_config = valid_config.dup
      modified_config[:harness][:max_retries] = 5
      File.write(config_file, YAML.dump(modified_config))

      config2 = loader.reload_config

      expect(config2[:harness][:max_retries]).to eq(5)
    end
  end

  describe "cache invalidation" do
    let(:base_config) do
      {
        harness: {default_provider: "cursor", max_retries: 2},
        providers: {cursor: {type: "subscription"}}
      }
    end

    before do
      File.write(config_file, YAML.dump(base_config))
    end

    it "detects when config file has changed" do
      # Load initial config
      config1 = loader.load_config
      expect(config1[:harness][:max_retries]).to eq(2)

      # Modify file (FileUtils.touch will ensure mtime changes)
      modified_config = base_config.dup
      modified_config[:harness][:max_retries] = 10
      File.write(config_file, YAML.dump(modified_config))

      # Touch file to update mtime - no sleep needed
      FileUtils.touch(config_file)

      # Should reload automatically
      config2 = loader.load_config
      expect(config2[:harness][:max_retries]).to eq(10)
    end

    it "handles missing config file when checking for changes" do
      loader.load_config

      # Delete the config file
      FileUtils.rm_f(config_file)

      # Should handle gracefully
      expect { loader.load_config }.not_to raise_error
    end
  end

  describe "nil handling" do
    let(:base_config) do
      {
        harness: {default_provider: "cursor"},
        providers: {cursor: {type: "subscription"}}
      }
    end

    before do
      File.write(config_file, YAML.dump(base_config))
    end

    it "returns nil for harness_config when config fails to load" do
      # Corrupt the config file
      File.write(config_file, "invalid: yaml: content: [")

      harness_config = loader.harness_config
      expect(harness_config).to be_nil
    end

    it "returns nil for provider_config when config fails to load" do
      # Corrupt the config file
      File.write(config_file, "invalid: yaml: [[[")

      provider_config = loader.provider_config("cursor")
      expect(provider_config).to be_nil
    end

    it "returns empty hash for all_provider_configs when config fails to load" do
      # Corrupt the config file
      File.write(config_file, "bad yaml")

      all_configs = loader.all_provider_configs
      expect(all_configs).to eq({})
    end

    it "returns empty array for configured_providers when config fails to load" do
      # Corrupt the config file
      File.write(config_file, "bad: yaml: [")

      providers = loader.configured_providers
      expect(providers).to eq([])
    end

    it "returns nil for config_with_overrides when config fails to load" do
      # Corrupt the config file
      File.write(config_file, "invalid")

      config = loader.config_with_overrides({harness: {max_retries: 5}})
      expect(config).to be_nil
    end

    it "returns nil for harness_config_with_overrides when harness_config is nil" do
      # Corrupt the config file
      File.write(config_file, "bad")

      config = loader.harness_config_with_overrides({harness: {max_retries: 5}})
      expect(config).to be_nil
    end

    it "returns nil for provider_config_with_overrides when provider_config is nil" do
      # Corrupt the config file
      File.write(config_file, "invalid")

      config = loader.provider_config_with_overrides("cursor", {providers: {cursor: {priority: 5}}})
      expect(config).to be_nil
    end

    it "returns nil for mode_config when config fails to load" do
      # Corrupt the config file
      File.write(config_file, "bad")

      config = loader.mode_config("analyze")
      expect(config).to be_nil
    end

    it "returns nil for environment_config when config fails to load" do
      # Corrupt the config file
      File.write(config_file, "bad")

      config = loader.environment_config("production")
      expect(config).to be_nil
    end

    it "returns nil for get_step_config when config fails to load" do
      # Corrupt the config file
      File.write(config_file, "bad")

      config = loader.get_step_config("build")
      expect(config).to be_nil
    end

    it "returns nil for config_with_features when config fails to load" do
      # Corrupt the config file
      File.write(config_file, "bad")

      config = loader.config_with_features({feature1: true})
      expect(config).to be_nil
    end

    it "returns nil for get_user_config when config fails to load" do
      # Corrupt the config file
      File.write(config_file, "bad")

      config = loader.get_user_config("user123")
      expect(config).to be_nil
    end

    it "returns nil for time_based_config when config fails to load" do
      # Corrupt the config file
      File.write(config_file, "bad")

      config = loader.time_based_config
      expect(config).to be_nil
    end
  end

  describe "string vs symbol key access" do
    let(:config_with_string_keys) do
      {
        "harness" => {"default_provider" => "cursor"},
        "providers" => {
          "cursor" => {"type" => "subscription"}
        },
        "environments" => {
          "production" => {"harness" => {"max_retries" => 1}}
        },
        "steps" => {
          "build" => {"harness" => {"timeout" => 600}}
        },
        "features" => {
          "fast_mode" => {"harness" => {"max_retries" => 0}}
        },
        "users" => {
          "alice" => {"harness" => {"max_retries" => 20}}
        }
      }
    end

    before do
      File.write(config_file, YAML.dump(config_with_string_keys))
    end

    it "accesses provider config with string key" do
      provider_config = loader.provider_config("cursor")
      expect(provider_config).not_to be_nil
      expect(provider_config["type"]).to eq("subscription")
    end

    it "accesses environment config with string key" do
      env_config = loader.environment_config("production")
      expect(env_config).not_to be_nil
    end

    it "accesses step config with string key" do
      step_config = loader.get_step_config("build")
      expect(step_config).not_to be_nil
    end

    it "accesses feature config with string key" do
      feature_config = loader.config_with_features({"fast_mode" => true})
      expect(feature_config).not_to be_nil
    end

    it "accesses user config with string key" do
      user_config = loader.get_user_config("alice")
      expect(user_config).not_to be_nil
    end

    it "handles harness_config_with_overrides with string keys" do
      overrides = {"harness" => {"max_retries" => 5}}
      config = loader.harness_config_with_overrides(overrides)
      expect(config["max_retries"]).to eq(5)
    end

    it "handles provider_config_with_overrides with string provider key" do
      overrides = {"providers" => {"cursor" => {"priority" => 10}}}
      config = loader.provider_config_with_overrides("cursor", overrides)
      expect(config["priority"]).to eq(10)
    end

    it "handles provider_config_with_overrides with symbol provider key" do
      overrides = {providers: {cursor: {priority: 15}}}
      config = loader.provider_config_with_overrides(:cursor, overrides)
      expect(config[:priority]).to eq(15)
    end

    it "handles mode_config with string keys" do
      config_with_modes = {
        "harness" => {"default_provider" => "cursor"},
        "analyze_mode" => {"harness" => {"max_retries" => 5}},
        "execute_mode" => {"harness" => {"max_retries" => 3}},
        "providers" => {"cursor" => {"type" => "subscription"}}
      }
      File.write(config_file, YAML.dump(config_with_modes))

      analyze_config = loader.mode_config("analyze")
      expect(analyze_config["harness"]["max_retries"]).to eq(5)

      execute_config = loader.mode_config("execute")
      expect(execute_config["harness"]["max_retries"]).to eq(3)
    end
  end

  describe "hour_in_range? edge cases" do
    # Test the private hour_in_range? method directly with different types

    it "handles Integer hour match" do
      result = loader.send(:hour_in_range?, 9, 9)
      expect(result).to be true
    end

    it "handles Integer hour mismatch" do
      result = loader.send(:hour_in_range?, 10, 9)
      expect(result).to be false
    end

    it "handles Range hour within range" do
      result = loader.send(:hour_in_range?, 11, 10..12)
      expect(result).to be true
    end

    it "handles Range hour outside range" do
      result = loader.send(:hour_in_range?, 15, 10..12)
      expect(result).to be false
    end

    it "handles String hour range with dash - within range" do
      result = loader.send(:hour_in_range?, 14, "13-15")
      expect(result).to be true
    end

    it "handles String hour range with dash - outside range" do
      result = loader.send(:hour_in_range?, 16, "13-15")
      expect(result).to be false
    end

    it "handles String single hour - match" do
      result = loader.send(:hour_in_range?, 16, "16")
      expect(result).to be true
    end

    it "handles String single hour - mismatch" do
      result = loader.send(:hour_in_range?, 17, "16")
      expect(result).to be false
    end

    it "handles invalid hour range type" do
      result = loader.send(:hour_in_range?, 10, ["invalid"])
      expect(result).to be false
    end

    it "handles nil hour range" do
      result = loader.send(:hour_in_range?, 10, nil)
      expect(result).to be false
    end
  end

  describe "missing configuration sections" do
    let(:minimal_config) do
      {
        harness: {default_provider: "cursor"},
        providers: {cursor: {type: "subscription"}}
      }
    end

    before do
      File.write(config_file, YAML.dump(minimal_config))
    end

    it "returns nil when harness section is missing (invalid config)" do
      config_no_harness = {providers: {cursor: {type: "subscription"}}}
      File.write(config_file, YAML.dump(config_no_harness))

      # Config is invalid without harness section, so returns nil
      harness_config = loader.harness_config
      expect(harness_config).to be_nil
    end

    it "returns empty hash when providers section is missing" do
      config_no_providers = {harness: {default_provider: "cursor"}}
      File.write(config_file, YAML.dump(config_no_providers))

      all_providers = loader.all_provider_configs
      expect(all_providers).to eq({})
    end

    it "returns nil when specific provider not found" do
      provider_config = loader.provider_config("nonexistent")
      expect(provider_config).to be_nil
    end

    it "returns empty hash when environments section is missing" do
      env_config = loader.environment_config("production")
      expect(env_config[:harness][:default_provider]).to eq("cursor")
      expect(env_config[:environments]).to be_nil
    end

    it "returns empty hash when steps section is missing" do
      step_config = loader.get_step_config("build")
      expect(step_config[:harness][:default_provider]).to eq("cursor")
      expect(step_config[:steps]).to be_nil
    end

    it "returns base config when features section is missing" do
      feature_config = loader.config_with_features({feature1: true})
      expect(feature_config[:harness][:default_provider]).to eq("cursor")
      expect(feature_config[:features]).to be_nil
    end

    it "returns empty hash when feature is disabled" do
      config_with_features = {
        harness: {default_provider: "cursor", max_retries: 2},
        providers: {cursor: {type: "subscription"}},
        features: {
          feature1: {harness: {max_retries: 10}}
        }
      }
      File.write(config_file, YAML.dump(config_with_features))

      feature_config = loader.config_with_features({feature1: false})
      # Should not apply feature overrides when feature is disabled
      expect(feature_config[:harness][:max_retries]).to eq(2)
    end

    it "returns base config when users section is missing" do
      user_config = loader.get_user_config("alice")
      expect(user_config[:harness][:default_provider]).to eq("cursor")
      expect(user_config[:users]).to be_nil
    end

    it "returns base config when time_based section is missing" do
      time_config = loader.time_based_config
      expect(time_config[:harness][:default_provider]).to eq("cursor")
      expect(time_config[:time_based]).to be_nil
    end

    it "handles missing hours in time_based config" do
      config_with_days_only = {
        harness: {default_provider: "cursor"},
        providers: {cursor: {type: "subscription"}},
        time_based: {
          days: {monday: {harness: {max_retries: 5}}}
        }
      }
      File.write(config_file, YAML.dump(config_with_days_only))

      time_config = loader.time_based_config
      expect(time_config).not_to be_nil
    end

    it "handles missing days in time_based config" do
      config_with_hours_only = {
        harness: {default_provider: "cursor"},
        providers: {cursor: {type: "subscription"}},
        time_based: {
          hours: {"9-17" => {harness: {max_retries: 1}}}
        }
      }
      File.write(config_file, YAML.dump(config_with_hours_only))

      time_config = loader.time_based_config
      expect(time_config).not_to be_nil
    end
  end

  describe "empty overrides" do
    let(:base_config) do
      {
        harness: {default_provider: "cursor", max_retries: 2},
        providers: {cursor: {type: "subscription", priority: 1}}
      }
    end

    before do
      File.write(config_file, YAML.dump(base_config))
    end

    it "returns base config when overrides are empty" do
      config = loader.config_with_overrides({})
      expect(config[:harness][:max_retries]).to eq(2)
    end

    it "returns base provider config when provider overrides are empty" do
      config = loader.provider_config_with_overrides("cursor", {})
      expect(config[:priority]).to eq(1)
    end

    it "handles empty feature overrides" do
      config = loader.config_with_features({})
      expect(config[:harness][:max_retries]).to eq(2)
    end
  end

  describe "default values" do
    let(:base_config) do
      {
        harness: {default_provider: "cursor"},
        providers: {cursor: {type: "subscription"}}
      }
    end

    before do
      File.write(config_file, YAML.dump(base_config))
    end

    it "uses default environment when ENV not set" do
      original_env = ENV["AIDP_ENV"]
      ENV.delete("AIDP_ENV")

      # Should default to "development"
      config = loader.environment_config
      expect(config).not_to be_nil

      ENV["AIDP_ENV"] = original_env if original_env
    end

    it "uses default user when ENV[USER] not set" do
      original_user = ENV["USER"]
      ENV.delete("USER")

      # Should default to "default"
      config = loader.get_user_config
      expect(config).not_to be_nil

      ENV["USER"] = original_user if original_user
    end

    it "uses provided user_id instead of ENV[USER]" do
      config = loader.get_user_config("specific_user")
      expect(config).not_to be_nil
    end

    it "uses provided environment instead of ENV[AIDP_ENV]" do
      config = loader.environment_config("staging")
      expect(config).not_to be_nil
    end
  end
end

RSpec.describe Aidp::Harness::ConfigManager do
  let(:project_dir) { "/tmp/test_project" }
  let(:config_file) { File.join(project_dir, ".aidp", "aidp.yml") }

  # Default config for contexts that don't define their own
  let(:test_config) { nil }

  # Lazy-evaluated manager - will load config when first accessed in test
  let(:manager) { described_class.new(project_dir) }

  before do
    FileUtils.mkdir_p(project_dir)
    FileUtils.mkdir_p(File.dirname(config_file))

    # Write config if defined by the test context
    if test_config
      File.write(config_file, YAML.dump(test_config))
    end
  end

  after do
    FileUtils.rm_rf(project_dir) if Dir.exist?(project_dir)
  end

  describe "initialization" do
    it "creates manager successfully" do
      expect(manager).to be_a(described_class)
    end
  end

  describe "configuration access" do
    let(:test_config) do
      {
        harness: {
          default_provider: "cursor",
          max_retries: 3,
          fallback_providers: ["claude"],
          provider_weights: {
            "cursor" => 3,
            "claude" => 2
          },
          retry: {
            enabled: true,
            max_attempts: 5,
            base_delay: 2.0
          },
          circuit_breaker: {
            enabled: true,
            failure_threshold: 3
          },
          rate_limit: {
            enabled: true,
            default_reset_time: 1800
          },
          load_balancing: {
            enabled: true,
            strategy: "round_robin"
          },
          model_switching: {
            enabled: true,
            auto_switch_on_error: true
          },
          health_check: {
            enabled: true,
            interval: 30
          },
          metrics: {
            enabled: true,
            retention_days: 7
          },
          session: {
            enabled: true,
            timeout: 900
          }
        },
        providers: {
          cursor: {
            type: "subscription",
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
            }
          },
          claude: {
            type: "usage_based",
            priority: 2,
            max_tokens: 100_000,
            default_flags: ["--dangerously-skip-permissions"],
            models: ["claude-3-5-sonnet-20241022"],
            auth: {
              api_key_env: "ANTHROPIC_API_KEY"
            },
            endpoints: {
              default: "https://api.anthropic.com/v1/messages"
            },
            features: {
              file_upload: true,
              code_generation: true,
              analysis: true,
              vision: true
            }
          }
        }
      }
    end

    it "gets complete configuration" do
      config = manager.config

      expect(config).to be_a(Hash)
      expect(config[:harness]).to be_a(Hash)
      expect(config[:providers]).to be_a(Hash)
    end

    it "gets harness configuration" do
      harness_config = manager.harness_config

      expect(harness_config[:default_provider]).to eq("cursor")
      expect(harness_config[:max_retries]).to eq(3)
    end

    it "gets provider configuration" do
      cursor_config = manager.provider_config("cursor")
      claude_config = manager.provider_config("claude")

      expect(cursor_config[:type]).to eq("subscription")
      expect(claude_config[:type]).to eq("usage_based")
    end

    it "gets all providers" do
      providers = manager.all_providers

      expect(providers).to have_key(:cursor)
      expect(providers).to have_key(:claude)
    end

    it "gets provider names" do
      names = manager.provider_names

      expect(names).to include("cursor", "claude")
    end

    it "gets default provider" do
      default = manager.default_provider

      expect(default).to eq("cursor")
    end

    it "gets fallback providers" do
      fallbacks = manager.fallback_providers

      expect(fallbacks).to include("claude")
    end

    it "gets provider weights" do
      weights = manager.provider_weights

      expect(weights["cursor"]).to eq(3)
      expect(weights["claude"]).to eq(2)
    end
  end

  describe "configuration sections" do
    let(:test_config) do
      {
        harness: {
          default_provider: "cursor",
          retry: {
            enabled: true,
            max_attempts: 5,
            base_delay: 2.0,
            max_delay: 120.0,
            exponential_base: 3.0,
            jitter: true
          },
          circuit_breaker: {
            enabled: true,
            failure_threshold: 3,
            timeout: 600,
            half_open_max_calls: 2
          },
          rate_limit: {
            enabled: true,
            default_reset_time: 1800,
            burst_limit: 20,
            sustained_limit: 10
          },
          load_balancing: {
            enabled: true,
            strategy: "least_connections",
            health_check_interval: 60,
            unhealthy_threshold: 5
          },
          model_switching: {
            enabled: true,
            auto_switch_on_error: true,
            auto_switch_on_rate_limit: true,
            fallback_strategy: "random"
          },
          health_check: {
            enabled: true,
            interval: 30,
            timeout: 15,
            failure_threshold: 2,
            success_threshold: 3
          },
          metrics: {
            enabled: true,
            retention_days: 7,
            aggregation_interval: 600,
            export_interval: 1800
          },
          session: {
            enabled: true,
            timeout: 900,
            sticky_sessions: false,
            session_affinity: "provider"
          }
        },
        providers: {
          cursor: {
            type: "subscription",
            priority: 1,
            models: ["cursor-default"],
            model_weights: {
              "cursor-default" => 3
            },
            models_config: {
              "cursor-default" => {
                flags: [],
                timeout: 600
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
            }
          }
        }
      }
    end

    it "gets retry configuration" do
      retry_config = manager.retry_config

      expect(retry_config[:enabled]).to be true
      expect(retry_config[:max_attempts]).to eq(5)
      expect(retry_config[:base_delay]).to eq(2.0)
      expect(retry_config[:max_delay]).to eq(120.0)
      expect(retry_config[:exponential_base]).to eq(3.0)
      expect(retry_config[:jitter]).to be true
    end

    it "gets circuit breaker configuration" do
      cb_config = manager.circuit_breaker_config

      expect(cb_config[:enabled]).to be true
      expect(cb_config[:failure_threshold]).to eq(3)
      expect(cb_config[:timeout]).to eq(600)
      expect(cb_config[:half_open_max_calls]).to eq(2)
    end

    it "gets rate limit configuration" do
      rate_limit_config = manager.rate_limit_config

      expect(rate_limit_config[:enabled]).to be true
      expect(rate_limit_config[:default_reset_time]).to eq(1800)
      expect(rate_limit_config[:burst_limit]).to eq(20)
      expect(rate_limit_config[:sustained_limit]).to eq(10)
    end

    it "gets load balancing configuration" do
      lb_config = manager.load_balancing_config

      expect(lb_config[:enabled]).to be true
      expect(lb_config[:strategy]).to eq("least_connections")
      expect(lb_config[:health_check_interval]).to eq(60)
      expect(lb_config[:unhealthy_threshold]).to eq(5)
    end

    it "gets model switching configuration" do
      ms_config = manager.model_switching_config

      expect(ms_config[:enabled]).to be true
      expect(ms_config[:auto_switch_on_error]).to be true
      expect(ms_config[:auto_switch_on_rate_limit]).to be true
      expect(ms_config[:fallback_strategy]).to eq("random")
    end

    it "gets health check configuration" do
      hc_config = manager.health_check_config

      expect(hc_config[:enabled]).to be true
      expect(hc_config[:interval]).to eq(30)
      expect(hc_config[:timeout]).to eq(15)
      expect(hc_config[:failure_threshold]).to eq(2)
      expect(hc_config[:success_threshold]).to eq(3)
    end

    it "gets metrics configuration" do
      metrics_config = manager.metrics_config

      expect(metrics_config[:enabled]).to be true
      expect(metrics_config[:retention_days]).to eq(7)
      expect(metrics_config[:aggregation_interval]).to eq(600)
      expect(metrics_config[:export_interval]).to eq(1800)
    end

    it "gets session configuration" do
      session_config = manager.session_config

      expect(session_config[:enabled]).to be true
      expect(session_config[:timeout]).to eq(900)
      expect(session_config[:sticky_sessions]).to be false
      expect(session_config[:session_affinity]).to eq("provider")
    end
  end

  describe "provider-specific configuration" do
    let(:test_config) do
      {
        harness: {
          default_provider: "cursor"
        },
        providers: {
          cursor: {
            type: "subscription",
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
            }
          },
          claude: {
            type: "usage_based",
            priority: 2,
            max_tokens: 100_000,
            default_flags: ["--dangerously-skip-permissions"],
            models: ["claude-3-5-sonnet-20241022"],
            auth: {
              api_key_env: "ANTHROPIC_API_KEY"
            },
            endpoints: {
              default: "https://api.anthropic.com/v1/messages"
            },
            features: {
              file_upload: true,
              code_generation: true,
              analysis: true,
              vision: true
            }
          }
        }
      }
    end

    it "gets provider models" do
      cursor_models = manager.provider_models("cursor")
      claude_models = manager.provider_models("claude")

      expect(cursor_models).to include("cursor-default", "cursor-fast")
      expect(claude_models).to include("claude-3-5-sonnet-20241022")
    end

    it "gets provider model weights" do
      cursor_weights = manager.provider_model_weights("cursor")

      expect(cursor_weights["cursor-default"]).to eq(3)
      expect(cursor_weights["cursor-fast"]).to eq(2)
    end

    it "gets provider model configuration" do
      default_config = manager.provider_model_config("cursor", "cursor-default")
      fast_config = manager.provider_model_config("cursor", "cursor-fast")

      expect(default_config[:flags]).to eq([])
      expect(default_config[:timeout]).to eq(600)
      expect(fast_config[:flags]).to eq(["--fast"])
      expect(fast_config[:timeout]).to eq(300)
    end

    it "gets provider features" do
      cursor_features = manager.provider_features("cursor")
      claude_features = manager.provider_features("claude")

      expect(cursor_features[:file_upload]).to be true
      expect(cursor_features[:vision]).to be false
      expect(claude_features[:file_upload]).to be true
      expect(claude_features[:vision]).to be true
    end

    it "gets provider monitoring configuration" do
      cursor_monitoring = manager.provider_monitoring_config("cursor")

      expect(cursor_monitoring[:enabled]).to be true
      expect(cursor_monitoring[:metrics_interval]).to eq(30)
    end

    it "checks if provider supports feature" do
      expect(manager.provider_supports_feature?("cursor", "file_upload")).to be true
      expect(manager.provider_supports_feature?("cursor", "vision")).to be false
      expect(manager.provider_supports_feature?("claude", "vision")).to be true
    end

    it "gets provider priority" do
      cursor_priority = manager.provider_priority("cursor")
      claude_priority = manager.provider_priority("claude")

      expect(cursor_priority).to eq(1)
      expect(claude_priority).to eq(2)
    end

    it "gets provider type" do
      cursor_type = manager.provider_type("cursor")
      claude_type = manager.provider_type("claude")

      expect(cursor_type).to eq("subscription")
      expect(claude_type).to eq("usage_based")
    end

    it "checks provider types" do
      expect(manager.subscription_provider?("cursor")).to be true
      expect(manager.usage_based_provider?("cursor")).to be false
      expect(manager.usage_based_provider?("claude")).to be true
      expect(manager.subscription_provider?("claude")).to be false
    end

    it "gets provider max tokens" do
      cursor_tokens = manager.provider_max_tokens("cursor")
      claude_tokens = manager.provider_max_tokens("claude")

      expect(cursor_tokens).to be_nil
      expect(claude_tokens).to eq(100_000)
    end

    it "gets provider default flags" do
      cursor_flags = manager.provider_default_flags("cursor")
      claude_flags = manager.provider_default_flags("claude")

      expect(cursor_flags).to eq([])
      expect(claude_flags).to eq(["--dangerously-skip-permissions"])
    end

    it "gets provider auth configuration" do
      cursor_auth = manager.provider_auth_config("cursor")
      claude_auth = manager.provider_auth_config("claude")

      expect(cursor_auth[:api_key_env]).to be_nil
      expect(claude_auth[:api_key_env]).to eq("ANTHROPIC_API_KEY")
    end

    it "gets provider endpoints" do
      cursor_endpoints = manager.provider_endpoints("cursor")
      claude_endpoints = manager.provider_endpoints("claude")

      expect(cursor_endpoints[:default]).to be_nil
      expect(claude_endpoints[:default]).to eq("https://api.anthropic.com/v1/messages")
    end
  end

  describe "configuration validation" do
    # Provide a minimal valid config for this context
    let(:test_config) do
      {
        harness: {default_provider: "cursor"},
        providers: {cursor: {type: "subscription"}}
      }
    end

    it "checks if configuration is valid" do
      valid_config = {
        harness: {
          default_provider: "cursor"
        },
        providers: {
          cursor: {
            type: "subscription",
            features: {
              file_upload: true,
              code_generation: true,
              analysis: true
            }
          }
        }
      }

      File.write(config_file, YAML.dump(valid_config))
      manager.reload_config

      expect(manager.config_valid?).to be true
    end

    it "gets validation errors" do
      invalid_config = {
        harness: {
          default_provider: ""
        }
      }

      File.write(config_file, YAML.dump(invalid_config))

      errors = manager.validation_errors

      expect(errors).not_to be_empty
    end

    it "reloads configuration" do
      config1 = {
        harness: {
          default_provider: "cursor"
        },
        providers: {
          cursor: {
            type: "subscription"
          },
          claude: {
            type: "usage_based",
            max_tokens: 100_000
          }
        }
      }

      File.write(config_file, YAML.dump(config1))
      manager.reload_config

      config = manager.config
      expect(config[:harness][:default_provider]).to eq("cursor")

      # Modify configuration
      config2 = config1.dup
      config2[:harness][:default_provider] = "claude"
      File.write(config_file, YAML.dump(config2))

      manager.reload_config
      config = manager.config

      expect(config[:harness][:default_provider]).to eq("claude")
    end
  end
end
