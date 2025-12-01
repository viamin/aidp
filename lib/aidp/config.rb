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
        fallback_providers: ["cursor"],
        no_api_keys_required: false,
        provider_weights: {
          "cursor" => 3,
          "anthropic" => 2
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
          type: "subscription",
          priority: 1,
          model_family: "auto",
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
        anthropic: {
          type: "usage_based",
          priority: 2,
          model_family: "claude",
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
            analysis: true,
            vision: true
          },
          monitoring: {
            enabled: true,
            metrics_interval: 60
          }
        }
      },
      skills: {
        search_paths: [],
        default_provider_filter: true,
        enable_custom_skills: true
      },
      waterfall: {
        enabled: true,
        docs_directory: ".aidp/docs",
        generate_decisions_md: true,
        gantt_format: "mermaid",
        wbs_phases: [
          "Requirements",
          "Design",
          "Implementation",
          "Testing",
          "Deployment"
        ],
        effort_estimation: {
          method: "llm_relative",
          units: "story_points"
        },
        persona_assignment: {
          method: "zfc_automatic",
          allow_parallel: true
        }
      },
      evaluations: {
        enabled: true,
        prompt_after_work_loop: false,
        capture_full_context: true,
        directory: ".aidp/evaluations"
      }
    }.freeze

    def self.load(project_dir = Dir.pwd)
      config_file = ConfigPaths.config_file(project_dir)

      if File.exist?(config_file)
        load_yaml_config(config_file)
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
    def self.validate_harness_config(config, project_dir = Dir.pwd)
      errors = []

      # Validate harness section (check the merged config, not original)
      harness_config = config[:harness] || config["harness"]
      if harness_config
        unless harness_config[:default_provider] || harness_config["default_provider"]
          errors << "Default provider not specified in harness config"
        end
      end

      # Validate providers section using config_validator
      # Only validate providers that exist in the original YAML file, not merged defaults
      original_config = load(project_dir)
      original_providers = original_config[:providers] || original_config["providers"]
      if original_providers&.any?
        require_relative "harness/config_validator"
        validator = Aidp::Harness::ConfigValidator.new(project_dir)

        # Only validate if the config file exists
        # Skip validation if we're validating a simple test config (no project_dir specified or simple config)
        should_validate = validator.config_exists? &&
          (project_dir != Dir.pwd || config[:harness]&.keys&.size.to_i > 2)
        if should_validate
          original_providers.each do |provider_name, _provider_config|
            validation_result = validator.validate_provider(provider_name)
            unless validation_result[:valid]
              errors.concat(validation_result[:errors])
            end
          end
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

    # Get skills configuration
    def self.skills_config(project_dir = Dir.pwd)
      config = load_harness_config(project_dir)
      skills_section = config[:skills] || config["skills"] || {}

      # Convert string keys to symbols for consistency
      symbolize_keys(skills_section)
    end

    # Get waterfall configuration
    def self.waterfall_config(project_dir = Dir.pwd)
      config = load_harness_config(project_dir)
      waterfall_section = config[:waterfall] || config["waterfall"] || {}

      # Convert string keys to symbols for consistency
      symbolize_keys(waterfall_section)
    end

    # Get agile configuration
    def self.agile_config(project_dir = Dir.pwd)
      config = load_harness_config(project_dir)
      agile_section = config[:agile] || config["agile"] || {}

      # Convert string keys to symbols for consistency
      symbolize_keys(agile_section)
    end

    # Get tool metadata configuration
    def self.tool_metadata_config(project_dir = Dir.pwd)
      config = load_harness_config(project_dir)
      tool_metadata_section = config[:tool_metadata] || config["tool_metadata"] || {}

      # Convert string keys to symbols for consistency
      symbolize_keys(tool_metadata_section)
    end

    # Get evaluations configuration
    def self.evaluations_config(project_dir = Dir.pwd)
      config = load_harness_config(project_dir)
      evaluations_section = config[:evaluations] || config["evaluations"] || {}

      # Convert string keys to symbols for consistency
      symbolize_keys(evaluations_section)
    end

    # Check if configuration file exists
    def self.config_exists?(project_dir = Dir.pwd)
      ConfigPaths.config_exists?(project_dir)
    end

    # Create example configuration file
    def self.create_example_config(project_dir = Dir.pwd)
      config_path = ConfigPaths.config_file(project_dir)
      return false if File.exist?(config_path)

      ConfigPaths.ensure_config_dir(project_dir)

      example_config = {
        harness: {
          max_retries: 2,
          default_provider: "cursor",
          fallback_providers: ["cursor"],
          no_api_keys_required: false
        },
        providers: {
          cursor: {
            type: "subscription",
            default_flags: []
          },
          claude: {
            type: "usage_based",
            max_tokens: 100_000,
            default_flags: ["--dangerously-skip-permissions"]
          },
          gemini: {
            type: "usage_based",
            max_tokens: 50_000,
            default_flags: []
          }
        },
        agile: {
          mvp_first: true,
          feedback_loops: true,
          auto_iteration: false,
          research_enabled: true,
          marketing_enabled: true,
          legacy_analysis: true,
          personas: ["product_manager", "ux_researcher", "architect", "senior_developer", "qa_engineer", "devops_engineer", "tech_writer", "marketing_strategist"]
        }
      }

      File.write(config_path, YAML.dump(example_config))
      true
    end

    # Expose path methods for convenience
    def self.config_file(project_dir = Dir.pwd)
      ConfigPaths.config_file(project_dir)
    end

    def self.config_dir(project_dir = Dir.pwd)
      ConfigPaths.config_dir(project_dir)
    end

    def self.aidp_dir(project_dir = Dir.pwd)
      ConfigPaths.aidp_dir(project_dir)
    end

    private_class_method def self.load_yaml_config(config_file)
      YAML.safe_load_file(config_file, permitted_classes: [Date, Time, Symbol], aliases: true) || {}
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

      # Deep merge skills config
      if config[:skills] || config["skills"]
        skills_section = config[:skills] || config["skills"]
        merged[:skills] = merged[:skills].merge(symbolize_keys(skills_section))
      end

      # Deep merge thinking config
      if config[:thinking] || config["thinking"]
        thinking_section = config[:thinking] || config["thinking"]
        merged[:thinking] = symbolize_keys(thinking_section)
      end

      # Deep merge waterfall config
      if config[:waterfall] || config["waterfall"]
        waterfall_section = config[:waterfall] || config["waterfall"]
        merged[:waterfall] = merged[:waterfall].merge(symbolize_keys(waterfall_section))
      end

      # Deep merge evaluations config
      if config[:evaluations] || config["evaluations"]
        evaluations_section = config[:evaluations] || config["evaluations"]
        merged[:evaluations] = merged[:evaluations].merge(symbolize_keys(evaluations_section))
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
  end
end
