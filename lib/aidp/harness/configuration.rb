# frozen_string_literal: true

require_relative "../config"
require_relative "../config/paths"

module Aidp
  module Harness
    # Handles loading and validation of harness configuration from aidp.yml
    class Configuration
      def initialize(project_dir)
        @project_dir = project_dir
        @config = Aidp::Config.load_harness_config(project_dir)
        validate_configuration!
      end

      # Get harness-specific configuration
      def harness_config
        @config[:harness]
      end

      # Get provider configuration
      def provider_config(provider_name)
        @config.dig(:providers, provider_name.to_sym) || {}
      end

      # Get all configured providers
      def configured_providers
        @config[:providers]&.keys&.map(&:to_s) || []
      end

      # Get default provider
      def default_provider
        harness_config[:default_provider]
      end

      # Get fallback providers
      def fallback_providers
        harness_config[:fallback_providers]
      end

      # Get maximum retries
      def max_retries
        harness_config[:max_retries]
      end

      # Check if restricted to providers that don't require API keys
      def no_api_keys_required?
        harness_config[:no_api_keys_required]
      end

      # Get provider type (usage_based, subscription, etc.)
      def provider_type(provider_name)
        provider_config(provider_name)[:type] || "unknown"
      end

      # Get maximum tokens for API providers
      def max_tokens(provider_name)
        provider_config(provider_name)[:max_tokens]
      end

      # Get default flags for a provider
      def default_flags(provider_name)
        provider_config(provider_name)[:default_flags] || []
      end

      # Get provider models configuration
      def provider_models(provider_name)
        provider_config(provider_name)[:models] || default_models_for_provider(provider_name)
      end

      # Get default model for provider
      def default_model(provider_name)
        models = provider_models(provider_name)
        models.first || default_model_for_provider(provider_name)
      end

      # Get model configuration for provider
      def model_config(provider_name, model_name)
        models_config = provider_config(provider_name)[:models_config] || {}
        models_config[model_name] || {}
      end

      # Get model-specific flags
      def model_flags(provider_name, model_name)
        model_config(provider_name, model_name)[:flags] || []
      end

      # Get model-specific max tokens
      def model_max_tokens(provider_name, model_name)
        model_config(provider_name, model_name)[:max_tokens] || max_tokens(provider_name)
      end

      # Get model-specific timeout
      def model_timeout(provider_name, model_name)
        model_config(provider_name, model_name)[:timeout] || default_timeout_for_provider(provider_name)
      end

      # Get provider weights for load balancing
      def provider_weights
        harness_config[:provider_weights] || {}
      end

      # Get model weights for load balancing
      def model_weights(provider_name)
        provider_config(provider_name)[:model_weights] || {}
      end

      # Get circuit breaker configuration
      def circuit_breaker_config
        harness_config[:circuit_breaker] || default_circuit_breaker_config
      end

      # Get retry configuration
      def retry_config
        harness_config[:retry] || default_retry_config
      end

      # Get rate limit configuration
      def rate_limit_config
        harness_config[:rate_limit] || default_rate_limit_config
      end

      # Get load balancing configuration
      def load_balancing_config
        harness_config[:load_balancing] || default_load_balancing_config
      end

      # Get model switching configuration
      def model_switching_config
        harness_config[:model_switching] || default_model_switching_config
      end

      # Get provider health check configuration
      def health_check_config
        harness_config[:health_check] || default_health_check_config
      end

      # Get metrics configuration
      def metrics_config
        harness_config[:metrics] || default_metrics_config
      end

      # Get session configuration
      def session_config
        harness_config[:session] || default_session_config
      end

      # Get work loop configuration
      def work_loop_config
        harness_config[:work_loop] || default_work_loop_config
      end

      def work_loop_units_config
        work_loop_config[:units] || default_units_config
      end

      # Check if work loops are enabled
      def work_loop_enabled?
        work_loop_config[:enabled]
      end

      # Get maximum iterations for work loops
      def work_loop_max_iterations
        work_loop_config[:max_iterations]
      end

      # Get test commands
      def test_commands
        work_loop_config[:test_commands] || []
      end

      # Get lint commands
      def lint_commands
        work_loop_config[:lint_commands] || []
      end

      # Get guards configuration
      def guards_config
        work_loop_config[:guards] || default_guards_config
      end

      # Check if guards are enabled
      def guards_enabled?
        guards_config[:enabled] == true
      end

      # Get include file patterns for guards
      def guards_include_files
        guards_config[:include_files] || []
      end

      # Get exclude file patterns for guards
      def guards_exclude_files
        guards_config[:exclude_files] || []
      end

      # Get files requiring confirmation for guards
      def guards_confirm_files
        guards_config[:confirm_files] || []
      end

      # Get max lines per commit for guards
      def guards_max_lines_per_commit
        guards_config[:max_lines_per_commit]
      end

      # Check if guards are bypassed
      def guards_bypass?
        guards_config[:bypass] == true
      end

      # Get provider priority
      def provider_priority(provider_name)
        provider_config(provider_name)[:priority] || 0
      end

      # Get provider cost configuration
      def provider_cost_config(provider_name)
        provider_config(provider_name)[:cost] || {}
      end

      # Get provider region configuration
      def provider_regions(provider_name)
        provider_config(provider_name)[:regions] || []
      end

      # Get provider authentication configuration
      def provider_auth_config(provider_name)
        provider_config(provider_name)[:auth] || {}
      end

      # Get provider endpoint configuration
      def provider_endpoints(provider_name)
        provider_config(provider_name)[:endpoints] || {}
      end

      # Get provider feature flags
      def provider_features(provider_name)
        provider_config(provider_name)[:features] || {}
      end

      # Get provider monitoring configuration
      def provider_monitoring_config(provider_name)
        provider_config(provider_name)[:monitoring] || {}
      end

      # Check if provider is configured
      def provider_configured?(provider_name)
        configured_providers.include?(provider_name.to_s)
      end

      # Get configuration path
      def config_path
        Aidp::ConfigPaths.config_file(@project_dir)
      end

      # Get logging configuration
      def logging_config
        harness_config[:logging] || default_logging_config
      end

      # Get fallback configuration
      def fallback_config
        harness_config[:fallback] || default_fallback_config
      end

      # Check if configuration file exists
      def config_exists?
        Aidp::Config.config_exists?(@project_dir)
      end

      # Create example configuration
      def create_example_config
        Aidp::Config.create_example_config(@project_dir)
      end

      # Get raw configuration
      def raw_config
        @config.dup
      end

      # Validate model configuration
      def validate_model_config(provider_name, model_name, model_config, errors)
        # Validate model-specific fields
        if model_config[:max_tokens] && !model_config[:max_tokens].is_a?(Integer)
          errors << "Model '#{provider_name}:#{model_name}' max_tokens must be integer"
        end

        if model_config[:timeout] && !model_config[:timeout].is_a?(Integer)
          errors << "Model '#{provider_name}:#{model_name}' timeout must be integer"
        end

        if model_config[:flags] && !model_config[:flags].is_a?(Array)
          errors << "Model '#{provider_name}:#{model_name}' flags must be array"
        end
      end

      # Get configuration summary
      def configuration_summary
        {
          providers: configured_providers.size,
          default_provider: default_provider,
          fallback_providers: fallback_providers.size,
          max_retries: max_retries,
          no_api_keys_required: no_api_keys_required?,
          load_balancing_enabled: load_balancing_config[:enabled],
          model_switching_enabled: model_switching_config[:enabled],
          circuit_breaker_enabled: circuit_breaker_config[:enabled],
          health_check_enabled: health_check_config[:enabled],
          metrics_enabled: metrics_config[:enabled]
        }
      end

      # Validate provider configuration
      def validate_provider_config(provider_name)
        errors = []

        unless provider_configured?(provider_name)
          errors << "Provider '#{provider_name}' not configured"
          return errors
        end

        # Validate provider type
        provider_type = provider_type(provider_name)
        unless %w[usage_based subscription passthrough].include?(provider_type)
          errors << "Provider '#{provider_name}' has invalid type: #{provider_type}"
        end

        # Validate required fields based on type
        case provider_type
        when "usage_based"
          unless max_tokens(provider_name)
            errors << "Provider '#{provider_name}' missing max_tokens for usage_based type"
          end
        when "passthrough"
          unless provider_config(provider_name)[:underlying_service]
            errors << "Provider '#{provider_name}' missing underlying_service for passthrough type"
          end
        end

        errors
      end

      private

      def validate_configuration!
        errors = Aidp::Config.validate_harness_config(@config, @project_dir)

        # Additional harness-specific validation
        unless harness_config[:default_provider]
          errors << "Default provider not specified"
        end

        unless configured_providers.include?(default_provider)
          errors << "Default provider '#{default_provider}' not configured"
        end

        # Validate fallback providers
        fallback_providers.each do |provider|
          unless configured_providers.include?(provider)
            errors << "Fallback provider '#{provider}' not configured"
          end
        end

        # Validate each provider configuration using config_validator
        # Only validate providers that are actually referenced in the harness configuration
        providers_to_validate = [default_provider] + fallback_providers
        providers_to_validate.uniq.each do |provider|
          require_relative "config_validator"
          validator = ConfigValidator.new(@project_dir)
          validation_result = validator.validate_provider(provider)
          unless validation_result[:valid]
            errors.concat(validation_result[:errors])
          end
        end

        raise ConfigurationError, errors.join(", ") if errors.any?

        true
      end

      # Default configuration methods
      def default_models_for_provider(provider_name)
        case provider_name
        when "anthropic"
          ["anthropic-3-5-sonnet-20241022", "anthropic-3-5-haiku-20241022", "anthropic-3-opus-20240229"]
        when "cursor"
          ["cursor-default", "cursor-fast", "cursor-precise"]
        else
          ["default"]
        end
      end

      def default_model_for_provider(provider_name)
        case provider_name
        when "anthropic"
          "anthropic-3-5-sonnet-20241022"
        when "cursor"
          "cursor-default"
        else
          "default"
        end
      end

      def default_timeout_for_provider(provider_name)
        300 # 5 minutes - default timeout for all providers
      end

      def default_circuit_breaker_config
        {
          enabled: true,
          failure_threshold: 5,
          timeout: 300, # 5 minutes
          half_open_max_calls: 3
        }
      end

      def default_retry_config
        {
          enabled: true,
          max_attempts: 3,
          base_delay: 1.0,
          max_delay: 60.0,
          exponential_base: 2.0,
          jitter: true
        }
      end

      def default_rate_limit_config
        {
          enabled: true,
          default_reset_time: 3600, # 1 hour
          burst_limit: 10,
          sustained_limit: 5
        }
      end

      def default_load_balancing_config
        {
          enabled: true,
          strategy: "weighted_round_robin", # weighted_round_robin, least_connections, random
          health_check_interval: 30,
          unhealthy_threshold: 3
        }
      end

      def default_model_switching_config
        {
          enabled: true,
          auto_switch_on_error: true,
          auto_switch_on_rate_limit: true,
          fallback_strategy: "sequential" # sequential, load_balanced, random
        }
      end

      def default_health_check_config
        {
          enabled: true,
          interval: 60, # 1 minute
          timeout: 10,
          failure_threshold: 3,
          success_threshold: 2
        }
      end

      def default_metrics_config
        {
          enabled: true,
          retention_days: 30,
          aggregation_interval: 300, # 5 minutes
          export_interval: 3600 # 1 hour
        }
      end

      def default_session_config
        {
          enabled: true,
          timeout: 1800, # 30 minutes
          sticky_sessions: true,
          session_affinity: "provider_model" # provider, model, provider_model
        }
      end

      def default_work_loop_config
        {
          enabled: true,
          max_iterations: 50,
          test_commands: [],
          lint_commands: [],
          guards: default_guards_config,
          units: default_units_config
        }
      end

      def default_units_config
        {
          deterministic: [
            {
              name: "run_full_tests",
              command: "bundle exec rake spec",
              output_file: ".aidp/out/run_full_tests.yml",
              enabled: false,
              min_interval_seconds: 300,
              max_backoff_seconds: 1800,
              next: {
                success: :agentic,
                failure: :decide_whats_next,
                else: :decide_whats_next
              }
            },
            {
              name: "run_lint",
              command: "bundle exec standardrb",
              output_file: ".aidp/out/run_lint.yml",
              enabled: false,
              min_interval_seconds: 300,
              max_backoff_seconds: 1800,
              next: {
                success: :agentic,
                failure: :decide_whats_next,
                else: :decide_whats_next
              }
            },
            {
              name: "wait_for_github",
              type: :wait,
              output_file: ".aidp/out/wait_for_github.yml",
              metadata: {
                interval_seconds: 60,
                backoff_seconds: 60
              },
              min_interval_seconds: 60,
              max_backoff_seconds: 900,
              next: {
                event: :agentic,
                else: :wait_for_github
              }
            }
          ],
          defaults: {
            initial_unit: :agentic,
            on_no_next_step: :wait_for_github,
            fallback_agentic: :decide_whats_next,
            max_consecutive_deciders: 1
          }
        }
      end

      def default_guards_config
        {
          enabled: false,
          include_files: [],
          exclude_files: [],
          confirm_files: [],
          max_lines_per_commit: nil,
          bypass: false
        }
      end

      def default_logging_config
        {
          log_level: :info,
          retention_days: 30,
          max_file_size: 10485760, # 10MB
          max_files: 5,
          format: :json,
          include_stack_traces: true,
          include_context: true
        }
      end

      def default_fallback_config
        {
          strategies: {
            rate_limit: {
              action: :switch_provider,
              priority: :high,
              max_attempts: 3,
              cooldown_period: 300
            },
            network_error: {
              action: :switch_provider,
              priority: :high,
              max_attempts: 2,
              cooldown_period: 60
            },
            server_error: {
              action: :switch_provider,
              priority: :medium,
              max_attempts: 2,
              cooldown_period: 120
            },
            timeout: {
              action: :switch_model,
              priority: :medium,
              max_attempts: 2,
              cooldown_period: 60
            },
            authentication: {
              action: :escalate,
              priority: :critical,
              max_attempts: 0,
              cooldown_period: 0
            }
          },
          selection_strategies: {
            health_based: :health_based,
            load_balanced: :load_balanced,
            circuit_breaker_aware: :circuit_breaker_aware,
            performance_based: :performance_based,
            round_robin: :round_robin
          }
        }
      end

      # Custom error class for configuration issues
      class ConfigurationError < StandardError; end
    end
  end
end
