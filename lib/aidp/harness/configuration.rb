# frozen_string_literal: true

require_relative "../config"
require_relative "../config/paths"

module Aidp
  module Harness
    # Handles loading and validation of harness configuration from aidp.yml
    class Configuration
      attr_reader :project_dir

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
        normalize_commands(work_loop_config[:test_commands] || [])
      end

      # Get lint commands
      def lint_commands
        normalize_commands(work_loop_config[:lint_commands] || [])
      end

      # Get formatter commands
      def formatter_commands
        normalize_commands(work_loop_config[:formatter_commands] || [])
      end

      # Get build commands
      def build_commands
        normalize_commands(work_loop_config[:build_commands] || [])
      end

      # Get documentation commands
      def documentation_commands
        normalize_commands(work_loop_config[:documentation_commands] || [])
      end

      # Get test output mode
      def test_output_mode
        work_loop_config.dig(:test, :output_mode) || :full
      end

      # Get max output lines for tests
      def test_max_output_lines
        work_loop_config.dig(:test, :max_output_lines) || 500
      end

      # Get lint output mode
      def lint_output_mode
        work_loop_config.dig(:lint, :output_mode) || :full
      end

      # Get max output lines for linters
      def lint_max_output_lines
        work_loop_config.dig(:lint, :max_output_lines) || 300
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

      # Get version control configuration
      def version_control_config
        work_loop_config[:version_control] || default_version_control_config
      end

      # Get VCS tool
      def vcs_tool
        version_control_config[:tool]
      end

      # Get VCS behavior (stage/commit/nothing)
      def vcs_behavior
        version_control_config[:behavior]
      end

      # Check if conventional commits are enabled
      def conventional_commits?
        version_control_config[:conventional_commits] == true
      end

      # Get coverage configuration
      def coverage_config
        work_loop_config[:coverage] || default_coverage_config
      end

      # Check if coverage is enabled
      def coverage_enabled?
        coverage_config[:enabled] == true
      end

      # Get coverage tool
      def coverage_tool
        coverage_config[:tool]
      end

      # Get coverage run command
      def coverage_run_command
        coverage_config[:run_command]
      end

      # Get coverage report paths
      def coverage_report_paths
        coverage_config[:report_paths] || []
      end

      # Check if should fail on coverage drop
      def coverage_fail_on_drop?
        coverage_config[:fail_on_drop] == true
      end

      # Get minimum coverage threshold
      def coverage_minimum
        coverage_config[:minimum_coverage]
      end

      # Get interactive testing configuration
      def interactive_testing_config
        work_loop_config[:interactive_testing] || default_interactive_testing_config
      end

      # Check if interactive testing is enabled
      def interactive_testing_enabled?
        interactive_testing_config[:enabled] == true
      end

      # Get interactive testing app type
      def interactive_testing_app_type
        interactive_testing_config[:app_type]
      end

      # Get interactive testing tools configuration
      def interactive_testing_tools
        interactive_testing_config[:tools] || {}
      end

      # Get model family for a provider
      def model_family(provider_name)
        provider_config(provider_name)[:model_family] || "auto"
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

      # Get thinking depth configuration
      def thinking_config
        @config[:thinking] || default_thinking_config
      end

      # Get default thinking tier
      def default_tier
        thinking_config[:default_tier] || default_thinking_config[:default_tier]
      end

      # Get maximum thinking tier
      def max_tier
        thinking_config[:max_tier] || default_thinking_config[:max_tier]
      end

      # Check if provider switching for tier is allowed
      def allow_provider_switch_for_tier?
        thinking_config[:allow_provider_switch] != false
      end

      # Get escalation configuration
      def escalation_config
        thinking_config[:escalation] || default_escalation_config
      end

      # Get fail attempts threshold for escalation
      def escalation_fail_attempts
        escalation_config[:on_fail_attempts] || 2
      end

      # Get complexity threshold configuration for escalation
      def escalation_complexity_threshold
        escalation_config[:on_complexity_threshold] || {}
      end

      # Get permissions by tier configuration
      def permissions_by_tier
        thinking_config[:permissions_by_tier] || {}
      end

      # Get permission level for a tier
      def permission_for_tier(tier)
        permissions_by_tier[tier] || permissions_by_tier[tier.to_sym] || "tools"
      end

      # Get thinking tier overrides
      def thinking_overrides
        thinking_config[:overrides] || {}
      end

      # Get tier override for a skill or template
      # @param key [String] skill or template key (e.g., "skill.generate_tests", "template.large_refactor")
      def tier_override_for(key)
        thinking_overrides[key] || thinking_overrides[key.to_sym]
      end

      # Get thinking tiers configuration for a specific provider
      # @param provider_name [String] The provider name
      # @return [Hash] The thinking tiers configuration for the provider
      def provider_thinking_tiers(provider_name)
        provider_cfg = provider_config(provider_name)
        provider_cfg[:thinking_tiers] || provider_cfg["thinking_tiers"] || {}
      end

      # Get models configured for a specific tier and provider
      # @param tier [String, Symbol] The tier name (mini, standard, thinking, pro, max)
      # @param provider_name [String] The provider name (required)
      # @return [Array<String>] Array of model names for the tier
      def models_for_tier(tier, provider_name)
        return [] unless provider_name

        tier_config = provider_thinking_tiers(provider_name)[tier] ||
          provider_thinking_tiers(provider_name)[tier.to_sym]
        return [] unless tier_config

        models = tier_config[:models] || tier_config["models"]
        return [] unless models

        # Return simple array of model name strings
        Array(models).map(&:to_s).compact
      end

      # Get all configured tiers for a provider
      # @param provider_name [String] The provider name
      # @return [Array<String>] Array of tier names
      def configured_tiers(provider_name)
        provider_thinking_tiers(provider_name).keys.map(&:to_s)
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

      # Check if auto-escalation is enabled
      def auto_escalate?
        thinking_config[:auto_escalate] != false
      end

      # Get escalation threshold
      def escalation_threshold
        thinking_config[:escalation_threshold] || 2
      end

      # Get tier overrides
      def tier_overrides
        thinking_config[:overrides] || {}
      end

      # Get ZFC configuration
      def zfc_config
        @config[:zfc] || default_zfc_config
      end

      # Check if ZFC is enabled
      def zfc_enabled?
        zfc_config[:enabled] == true
      end

      # Check if ZFC should fallback to legacy on failure
      def zfc_fallback_to_legacy?
        zfc_config[:fallback_to_legacy] != false
      end

      # Get ZFC decision configuration
      def zfc_decision_config(decision_type)
        zfc_config.dig(:decisions, decision_type.to_sym) || {}
      end

      # Check if specific ZFC decision type is enabled
      def zfc_decision_enabled?(decision_type)
        return false unless zfc_enabled?
        decision_config = zfc_decision_config(decision_type)
        decision_config[:enabled] == true
      end

      # Get ZFC decision tier
      def zfc_decision_tier(decision_type)
        zfc_decision_config(decision_type)[:tier] || "mini"
      end

      # Get ZFC decision cache TTL
      def zfc_decision_cache_ttl(decision_type)
        zfc_decision_config(decision_type)[:cache_ttl]
      end

      # Get ZFC decision confidence threshold
      def zfc_decision_confidence_threshold(decision_type)
        zfc_decision_config(decision_type)[:confidence_threshold] || 0.7
      end

      # Get ZFC cost limits
      def zfc_cost_limits
        zfc_config[:cost_limits] || default_zfc_cost_limits
      end

      # Get ZFC A/B testing configuration
      def zfc_ab_testing_config
        zfc_config[:ab_testing] || default_zfc_ab_testing_config
      end

      # Check if ZFC A/B testing is enabled
      def zfc_ab_testing_enabled?
        zfc_ab_testing_config[:enabled] == true
      end

      # Prompt optimization configuration methods

      # Get prompt optimization configuration
      def prompt_optimization_config
        @config[:prompt_optimization] || default_prompt_optimization_config
      end

      # Check if prompt optimization is enabled
      def prompt_optimization_enabled?
        prompt_optimization_config[:enabled] == true
      end

      # Get maximum tokens for prompt
      def prompt_max_tokens
        prompt_optimization_config[:max_tokens] || 16000
      end

      # Get include threshold configuration
      def prompt_include_thresholds
        prompt_optimization_config[:include_threshold] || default_include_thresholds
      end

      # Get style guide include threshold
      def prompt_style_guide_threshold
        prompt_include_thresholds[:style_guide] || 0.75
      end

      # Get templates include threshold
      def prompt_templates_threshold
        prompt_include_thresholds[:templates] || 0.8
      end

      # Get source code include threshold
      def prompt_source_threshold
        prompt_include_thresholds[:source] || 0.7
      end

      # Check if dynamic adjustment is enabled
      def prompt_dynamic_adjustment?
        prompt_optimization_config[:dynamic_adjustment] != false
      end

      # Check if fragment logging is enabled
      def prompt_log_fragments?
        prompt_optimization_config[:log_selected_fragments] == true
      end

      # Devcontainer configuration methods

      # Get devcontainer configuration
      def devcontainer_config
        return @devcontainer_config if defined?(@devcontainer_config)

        raw_config = @config[:devcontainer] || @config["devcontainer"]
        base = deep_dup(default_devcontainer_config)

        @devcontainer_config = if raw_config.is_a?(Hash)
          deep_merge_hashes(base, deep_symbolize_keys(raw_config))
        else
          base
        end
      end

      # Check if devcontainer features are enabled
      def devcontainer_enabled?
        devcontainer_config[:enabled] != false
      end

      # Check if full permissions should be granted in devcontainer
      def full_permissions_in_devcontainer?
        devcontainer_config[:full_permissions_when_in_devcontainer] == true
      end

      # Get forced detection value (nil for auto-detection)
      def devcontainer_force_detection
        devcontainer_config[:force_detection]
      end

      # Check if currently in devcontainer (with optional force override)
      def in_devcontainer?
        forced = devcontainer_force_detection
        return forced unless forced.nil?

        require_relative "../utils/devcontainer_detector"
        Aidp::Utils::DevcontainerDetector.in_devcontainer?
      end

      # Get devcontainer permissions config
      def devcontainer_permissions
        permissions = devcontainer_config[:permissions]
        return {} unless permissions.is_a?(Hash)

        permissions.transform_keys { |key| key.to_sym }
      end

      # Check if dangerous filesystem operations are allowed in devcontainer
      def devcontainer_dangerous_ops_allowed?
        devcontainer_permissions[:dangerous_filesystem_ops] == true
      end

      # Get list of providers that should skip permission checks in devcontainer
      def devcontainer_skip_permission_checks
        permissions = devcontainer_config[:permissions]
        list = nil

        if permissions.is_a?(Hash)
          list = permissions[:skip_permission_checks] || permissions["skip_permission_checks"]
        end

        list = default_skip_permission_checks if list.nil?
        Array(list).map(&:to_s)
      end

      # Check if a specific provider should skip permission checks in devcontainer
      def devcontainer_skip_permissions_for?(provider_name)
        devcontainer_skip_permission_checks.include?(provider_name.to_s)
      end

      # Get devcontainer settings
      def devcontainer_settings
        devcontainer_config[:settings] || {}
      end

      # Get timeout multiplier for devcontainer
      def devcontainer_timeout_multiplier
        devcontainer_settings[:timeout_multiplier] || 1.0
      end

      # Check if verbose logging is enabled in devcontainer
      def devcontainer_verbose_logging?
        devcontainer_settings[:verbose_logging] == true
      end

      # Get allowed domains for devcontainer firewall
      def devcontainer_allowed_domains
        devcontainer_settings[:allowed_domains] || []
      end

      # Check if provider should run with full permissions
      # Combines devcontainer detection with configuration
      def should_use_full_permissions?(provider_name)
        return false unless devcontainer_enabled?
        return false unless in_devcontainer?

        # Check if full permissions are globally enabled for devcontainer
        return true if full_permissions_in_devcontainer?

        # Check if this specific provider should skip permissions
        devcontainer_skip_permissions_for?(provider_name)
      end

      private

      # Normalize command configuration to consistent format
      # Supports both string format and object format with required flag
      # Examples:
      #   "bundle exec rspec" -> {command: "bundle exec rspec", required: true}
      #   {command: "rubocop", required: false} -> {command: "rubocop", required: false}
      def normalize_commands(commands)
        return [] if commands.nil? || commands.empty?

        commands.map do |cmd|
          case cmd
          when String
            {command: cmd, required: true}
          when Hash
            # Handle both symbol and string keys
            command_value = cmd[:command] || cmd["command"]
            required_value = if cmd.key?(:required)
              cmd[:required]
            else
              (cmd.key?("required") ? cmd["required"] : true)
            end

            unless command_value.is_a?(String) && !command_value.empty?
              raise ConfigurationError, "Command must be a non-empty string, got: #{command_value.inspect}"
            end

            unless [true, false].include?(required_value)
              raise ConfigurationError, "Required flag must be boolean, got: #{required_value.inspect}"
            end

            {command: command_value, required: required_value}
          else
            raise ConfigurationError, "Command must be a string or hash, got: #{cmd.class}"
          end
        end
      end

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
                failure: :diagnose_failures,
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
                failure: :diagnose_failures,
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

      def default_version_control_config
        {
          tool: "git",
          behavior: "nothing",
          conventional_commits: false
        }
      end

      def default_coverage_config
        {
          enabled: false,
          tool: nil,
          run_command: nil,
          report_paths: [],
          fail_on_drop: false,
          minimum_coverage: nil
        }
      end

      def default_interactive_testing_config
        {
          enabled: false,
          app_type: "web",
          tools: {}
        }
      end

      def default_thinking_config
        {
          default_tier: "mini",  # Use mini tier by default for cost optimization
          max_tier: "max",
          allow_provider_switch: true,
          auto_escalate: true,
          escalation_threshold: 2,
          escalation: default_escalation_config,
          permissions_by_tier: {},
          overrides: {}
        }
      end

      def default_escalation_config
        {
          on_fail_attempts: 2,
          on_complexity_threshold: {}
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

      # Default ZFC configuration
      def default_zfc_config
        {
          enabled: false,  # Experimental feature - disabled by default
          fallback_to_legacy: true,
          decisions: {},
          cost_limits: default_zfc_cost_limits,
          ab_testing: default_zfc_ab_testing_config
        }
      end

      # Default ZFC cost limits
      def default_zfc_cost_limits
        {
          max_daily_cost: 5.00,
          max_cost_per_decision: 0.01,
          alert_threshold: 0.8
        }
      end

      # Default ZFC A/B testing configuration
      def default_zfc_ab_testing_config
        {
          enabled: false,
          sample_rate: 0.1,
          log_comparisons: true
        }
      end

      # Default prompt optimization configuration
      def default_prompt_optimization_config
        {
          enabled: false,  # Experimental feature - disabled by default
          max_tokens: 16000,
          include_threshold: default_include_thresholds,
          dynamic_adjustment: true,
          log_selected_fragments: false
        }
      end

      # Default include thresholds for prompt optimization
      def default_include_thresholds
        {
          style_guide: 0.75,
          templates: 0.8,
          source: 0.7
        }
      end

      def default_devcontainer_config
        {
          enabled: true,
          full_permissions_when_in_devcontainer: false,
          force_detection: nil,
          permissions: {
            dangerous_filesystem_ops: false,
            skip_permission_checks: ["claude"]
          },
          settings: {
            timeout_multiplier: 1.0,
            verbose_logging: false,
            allowed_domains: []
          }
        }
      end

      def default_skip_permission_checks
        Array(default_devcontainer_config.dig(:permissions, :skip_permission_checks)).map(&:to_s)
      end

      def deep_symbolize_keys(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, val), memo|
            memo[key.to_sym] = deep_symbolize_keys(val)
          end
        when Array
          value.map { |item| deep_symbolize_keys(item) }
        else
          value
        end
      end

      def deep_merge_hashes(base, overrides)
        overrides.each do |key, value|
          base[key] = if base[key].is_a?(Hash) && value.is_a?(Hash)
            deep_merge_hashes(base[key], value)
          else
            value
          end
        end
        base
      end

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, val), memo|
            memo[key] = deep_dup(val)
          end
        when Array
          value.map { |item| deep_dup(item) }
        else
          value
        end
      end

      # Custom error class for configuration issues
      class ConfigurationError < StandardError; end
    end
  end
end
