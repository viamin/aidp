# frozen_string_literal: true

require "yaml"

module Aidp
  # Configuration management for both execute and analyze modes
  class Config
    # Default configuration for harness
    DEFAULT_HARNESS_CONFIG = {
      harness: {
        max_retries: 2,
        default_provider: "cursor",
        fallback_providers: ["claude", "gemini"],
        restrict_to_non_byok: false,
        provider_weights: {
          "cursor" => 3,
          "claude" => 2,
          "gemini" => 1
        },
        circuit_breaker: {
          enabled: true,
          failure_threshold: 5,
          timeout: 300,
          half_open_max_calls: 3
        },
        retry: {
          enabled: true,
          max_attempts: 3,
          base_delay: 1.0,
          max_delay: 60.0,
          exponential_base: 2.0,
          jitter: true
        },
        rate_limit: {
          enabled: true,
          default_reset_time: 3600,
          burst_limit: 10,
          sustained_limit: 5
        },
        load_balancing: {
          enabled: true,
          strategy: "weighted_round_robin",
          health_check_interval: 30,
          unhealthy_threshold: 3
        },
        model_switching: {
          enabled: true,
          auto_switch_on_error: true,
          auto_switch_on_rate_limit: true,
          fallback_strategy: "sequential"
        },
        health_check: {
          enabled: true,
          interval: 60,
          timeout: 10,
          failure_threshold: 3,
          success_threshold: 2
        },
        metrics: {
          enabled: true,
          retention_days: 30,
          aggregation_interval: 300,
          export_interval: 3600
        },
        session: {
          enabled: true,
          timeout: 1800,
          sticky_sessions: true,
          session_affinity: "provider_model"
        }
      },
      providers: {
        cursor: {
          type: "package",
          priority: 1,
          default_flags: [],
          models: ["cursor-default", "cursor-fast", "cursor-precise"],
          model_weights: {
            "cursor-default" => 3,
            "cursor-fast" => 2,
            "cursor-precise" => 1
          },
          models_config: {
            "cursor-default" => {
              flags: [],
              timeout: 600
            },
            "cursor-fast" => {
              flags: ["--fast"],
              timeout: 300
            },
            "cursor-precise" => {
              flags: ["--precise"],
              timeout: 900
            }
          },
          features: {
            file_upload: true,
            code_generation: true,
            analysis: true
          },
          monitoring: {
            enabled: true,
            metrics_interval: 60
          }
        },
        claude: {
          type: "api",
          priority: 2,
          max_tokens: 100_000,
          default_flags: ["--dangerously-skip-permissions"],
          models: ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"],
          model_weights: {
            "claude-3-5-sonnet-20241022" => 3,
            "claude-3-5-haiku-20241022" => 2,
            "claude-3-opus-20240229" => 1
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
            },
            "claude-3-opus-20240229" => {
              flags: ["--dangerously-skip-permissions"],
              max_tokens: 200_000,
              timeout: 600
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
            analysis: true,
            vision: true
          },
          monitoring: {
            enabled: true,
            metrics_interval: 60
          }
        },
        gemini: {
          type: "api",
          priority: 3,
          max_tokens: 50_000,
          default_flags: [],
          models: ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"],
          model_weights: {
            "gemini-1.5-pro" => 3,
            "gemini-1.5-flash" => 2,
            "gemini-1.0-pro" => 1
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
            },
            "gemini-1.0-pro" => {
              flags: [],
              max_tokens: 30_000,
              timeout: 300
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
            analysis: true,
            vision: true
          },
          monitoring: {
            enabled: true,
            metrics_interval: 60
          }
        }
      }
    }.freeze

    def self.load(project_dir = Dir.pwd)
      # Try new aidp.yml format first, then fall back to .aidp.yml
      config_file = File.join(project_dir, "aidp.yml")
      legacy_config_file = File.join(project_dir, ".aidp.yml")

      if File.exist?(config_file)
        load_yaml_config(config_file)
      elsif File.exist?(legacy_config_file)
        load_yaml_config(legacy_config_file)
      else
        {}
      end
    end

    # Load harness configuration with defaults
    def self.load_harness_config(project_dir = Dir.pwd)
      config = load(project_dir)
      merge_harness_defaults(config)
    end


    # Validate harness configuration
    def self.validate_harness_config(config)
      errors = []

      # Validate harness section
      harness_config = config[:harness] || config["harness"]
      if harness_config
        unless harness_config[:default_provider] || harness_config["default_provider"]
          errors << "Default provider not specified in harness config"
        end
      end

      # Validate providers section
      providers_config = config[:providers] || config["providers"]
      if providers_config&.any?
        providers_config.each do |provider_name, provider_config|
          validate_provider_config(provider_name, provider_config, errors)
        end
      end

      errors
    end

    # Get harness configuration
    def self.harness_config(project_dir = Dir.pwd)
      config = load_harness_config(project_dir)
      harness_section = config[:harness] || config["harness"] || {}

      # Convert string keys to symbols for consistency
      symbolize_keys(harness_section)
    end

    # Get provider configuration
    def self.provider_config(provider_name, project_dir = Dir.pwd)
      config = load_harness_config(project_dir)
      providers_section = config[:providers] || config["providers"] || {}
      provider_config = providers_section[provider_name.to_s] || providers_section[provider_name.to_sym] || {}

      symbolize_keys(provider_config)
    end

    # Get all configured providers
    def self.configured_providers(project_dir = Dir.pwd)
      config = load_harness_config(project_dir)
      providers_section = config[:providers] || config["providers"] || {}
      providers_section.keys.map(&:to_s)
    end

    # Check if configuration file exists
    def self.config_exists?(project_dir = Dir.pwd)
      File.exist?(File.join(project_dir, "aidp.yml")) ||
        File.exist?(File.join(project_dir, ".aidp.yml"))
    end

    # Create example configuration file
    def self.create_example_config(project_dir = Dir.pwd)
      config_path = File.join(project_dir, "aidp.yml")
      return false if File.exist?(config_path)

      example_config = {
        harness: {
          max_retries: 2,
          default_provider: "cursor",
          fallback_providers: ["claude", "gemini"],
          restrict_to_non_byok: false
        },
        providers: {
          cursor: {
            type: "package",
            default_flags: []
          },
          claude: {
            type: "api",
            max_tokens: 100_000,
            default_flags: ["--dangerously-skip-permissions"]
          },
          gemini: {
            type: "api",
            max_tokens: 50_000,
            default_flags: []
          }
        }
      }

      File.write(config_path, YAML.dump(example_config))
      true
    end


    private_class_method def self.load_yaml_config(config_file)
      YAML.load_file(config_file) || {}
    rescue => e
      warn "Failed to load configuration file #{config_file}: #{e.message}"
      {}
    end

    private_class_method def self.merge_harness_defaults(config)
      merged = DEFAULT_HARNESS_CONFIG.dup

      # Deep merge harness config
      if config[:harness] || config["harness"]
        harness_section = config[:harness] || config["harness"]
        merged[:harness] = merged[:harness].merge(symbolize_keys(harness_section))
      end

      # Deep merge provider configs
      if config[:providers] || config["providers"]
        providers_section = config[:providers] || config["providers"]
        merged[:providers] = merged[:providers].dup
        providers_section.each do |provider, provider_config|
          merged[:providers][provider.to_sym] = (merged[:providers][provider.to_sym] || {}).merge(symbolize_keys(provider_config))
        end
      end

      merged
    end

    private_class_method def self.symbolize_keys(hash)
      return hash unless hash.is_a?(Hash)

      hash.each_with_object({}) do |(key, value), result|
        new_key = key.is_a?(String) ? key.to_sym : key
        new_value = value.is_a?(Hash) ? symbolize_keys(value) : value
        result[new_key] = new_value
      end
    end

    private_class_method def self.validate_provider_config(provider_name, provider_config, errors)
      # Validate provider type
      valid_types = %w[api package byok]
      provider_type = provider_config[:type] || provider_config["type"]

      unless valid_types.include?(provider_type)
        errors << "Provider '#{provider_name}' has invalid type: #{provider_type}"
      end

      # Validate API provider settings
      if provider_type == "api"
        max_tokens = provider_config[:max_tokens] || provider_config["max_tokens"]
        unless max_tokens&.positive?
          errors << "API provider '#{provider_name}' must specify max_tokens"
        end
      end

      # Validate flags
      default_flags = provider_config[:default_flags] || provider_config["default_flags"]
      if default_flags && !default_flags.is_a?(Array)
        errors << "Provider '#{provider_name}' default_flags must be an array"
      end
    end
  end
end
