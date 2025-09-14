# frozen_string_literal: true

require_relative "../config"

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

      # Check if restricted to non-BYOK providers
      def restrict_to_non_byok?
        harness_config[:restrict_to_non_byok]
      end

      # Get provider type (api, package, etc.)
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
        provider_config(provider_name)[:models] || get_default_models_for_provider(provider_name)
      end

      # Get default model for provider
      def default_model(provider_name)
        models = provider_models(provider_name)
        models.first || get_default_model_for_provider(provider_name)
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
        model_config(provider_name, model_name)[:timeout] || get_default_timeout_for_provider(provider_name)
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
        harness_config[:circuit_breaker] || get_default_circuit_breaker_config
      end

      # Get retry configuration
      def retry_config
        harness_config[:retry] || get_default_retry_config
      end

      # Get rate limit configuration
      def rate_limit_config
        harness_config[:rate_limit] || get_default_rate_limit_config
      end

      # Get load balancing configuration
      def load_balancing_config
        harness_config[:load_balancing] || get_default_load_balancing_config
      end

      # Get model switching configuration
      def model_switching_config
        harness_config[:model_switching] || get_default_model_switching_config
      end

      # Get provider health check configuration
      def health_check_config
        harness_config[:health_check] || get_default_health_check_config
      end

      # Get metrics configuration
      def metrics_config
        harness_config[:metrics] || get_default_metrics_config
      end

      # Get session configuration
      def session_config
        harness_config[:session] || get_default_session_config
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

      # Get available providers (filtered by restrictions)
      def available_providers
        providers = configured_providers

        if restrict_to_non_byok?
          providers = providers.select { |p| provider_type(p) != "byok" }
        end

        providers
      end

      # Get configuration path
      def config_path
        File.join(@project_dir, "aidp.yml")
      end

      # Get logging configuration
      def logging_config
        harness_config[:logging] || get_default_logging_config
      end

      # Get fallback configuration
      def fallback_config
        harness_config[:fallback] || get_default_fallback_config
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

      # Validate provider configuration
      def validate_provider_config(provider_name)
        errors = []
        config = provider_config(provider_name)

        # Validate required fields
        unless config[:type]
          errors << "Provider '#{provider_name}' missing type"
        end

        # Validate type-specific fields
        case config[:type]
        when "api"
          unless config[:max_tokens]
            errors << "API provider '#{provider_name}' missing max_tokens"
          end
        when "byok"
          unless config[:auth] && config[:auth][:api_key]
            errors << "BYOK provider '#{provider_name}' missing API key configuration"
          end
        end

        # Validate models configuration
        if config[:models] && !config[:models].is_a?(Array)
          errors << "Provider '#{provider_name}' models must be an array"
        end

        # Validate model configurations
        config[:models_config]&.each do |model_name, model_config|
          validate_model_config(provider_name, model_name, model_config, errors)
        end

        errors
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
          restrict_to_non_byok: restrict_to_non_byok?,
          load_balancing_enabled: load_balancing_config[:enabled],
          model_switching_enabled: model_switching_config[:enabled],
          circuit_breaker_enabled: circuit_breaker_config[:enabled],
          health_check_enabled: health_check_config[:enabled],
          metrics_enabled: metrics_config[:enabled]
        }
      end

      private

      def validate_configuration!
        errors = Aidp::Config.validate_harness_config(@config)

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

        # Validate each provider configuration
        configured_providers.each do |provider|
          provider_errors = validate_provider_config(provider)
          errors.concat(provider_errors)
        end

        raise ConfigurationError, errors.join(", ") if errors.any?

        true
      end

      # Default configuration methods
      def get_default_models_for_provider(provider_name)
        case provider_name
        when "claude"
          ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]
        when "gemini"
          ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"]
        when "cursor"
          ["cursor-default", "cursor-fast", "cursor-precise"]
        else
          ["default"]
        end
      end

      def get_default_model_for_provider(provider_name)
        case provider_name
        when "claude"
          "claude-3-5-sonnet-20241022"
        when "gemini"
          "gemini-1.5-pro"
        when "cursor"
          "cursor-default"
        else
          "default"
        end
      end

      def get_default_timeout_for_provider(provider_name)
        case provider_name
        when "claude"
          300 # 5 minutes
        when "gemini"
          300 # 5 minutes
        when "cursor"
          600 # 10 minutes
        else
          300 # 5 minutes
        end
      end

      def get_default_circuit_breaker_config
        {
          enabled: true,
          failure_threshold: 5,
          timeout: 300, # 5 minutes
          half_open_max_calls: 3
        }
      end

      def get_default_retry_config
        {
          enabled: true,
          max_attempts: 3,
          base_delay: 1.0,
          max_delay: 60.0,
          exponential_base: 2.0,
          jitter: true
        }
      end

      def get_default_rate_limit_config
        {
          enabled: true,
          default_reset_time: 3600, # 1 hour
          burst_limit: 10,
          sustained_limit: 5
        }
      end

      def get_default_load_balancing_config
        {
          enabled: true,
          strategy: "weighted_round_robin", # weighted_round_robin, least_connections, random
          health_check_interval: 30,
          unhealthy_threshold: 3
        }
      end

      def get_default_model_switching_config
        {
          enabled: true,
          auto_switch_on_error: true,
          auto_switch_on_rate_limit: true,
          fallback_strategy: "sequential" # sequential, load_balanced, random
        }
      end

      def get_default_health_check_config
        {
          enabled: true,
          interval: 60, # 1 minute
          timeout: 10,
          failure_threshold: 3,
          success_threshold: 2
        }
      end

      def get_default_metrics_config
        {
          enabled: true,
          retention_days: 30,
          aggregation_interval: 300, # 5 minutes
          export_interval: 3600 # 1 hour
        }
      end

      def get_default_session_config
        {
          enabled: true,
          timeout: 1800, # 30 minutes
          sticky_sessions: true,
          session_affinity: "provider_model" # provider, model, provider_model
        }
      end

      def get_default_logging_config
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

      def get_default_fallback_config
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
