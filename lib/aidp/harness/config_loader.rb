# frozen_string_literal: true

require "yaml"
require_relative "config_schema"
require_relative "config_validator"

module Aidp
  module Harness
    # Enhanced configuration loader for harness
    class ConfigLoader
      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
        @validator = ConfigValidator.new(project_dir)
        @config_cache = nil
        @last_loaded = nil
      end

      # Load and validate configuration with caching
      def load_config(force_reload = false)
        return @config_cache if @config_cache && !force_reload && !config_file_changed?

        # Load and validate configuration
        validation_result = @validator.load_and_validate

        if validation_result[:valid]
          @config_cache = @validator.get_validated_config
          @last_loaded = Time.now

          # Log warnings if any
          unless validation_result[:warnings].empty?
            log_warnings(validation_result[:warnings])
          end

          @config_cache
        else
          # Handle validation errors
          handle_validation_errors(validation_result[:errors])
          nil
        end
      end

      # Get harness configuration with defaults
      def get_harness_config(force_reload = false)
        config = load_config(force_reload)
        return nil unless config

        config[:harness] || {}
      end

      # Get provider configuration with defaults
      def get_provider_config(provider_name, force_reload = false)
        config = load_config(force_reload)
        return nil unless config

        providers = config[:providers] || {}
        providers[provider_name.to_sym] || providers[provider_name.to_s]
      end

      # Get all provider configurations
      def get_all_provider_configs(force_reload = false)
        config = load_config(force_reload)
        return {} unless config

        config[:providers] || {}
      end

      # Get configured provider names
      def get_configured_providers(force_reload = false)
        config = load_config(force_reload)
        return [] unless config

        providers = config[:providers] || {}
        providers.keys.map(&:to_s)
      end

      # Check if configuration exists
      def config_exists?
        @validator.config_exists?
      end

      # Get configuration file path
      def config_file_path
        @validator.config_file_path
      end

      # Create example configuration
      def create_example_config
        @validator.create_example_config
      end

      # Fix configuration issues
      def fix_config_issues
        @validator.fix_common_issues
      end

      # Get configuration summary
      def get_config_summary
        @validator.get_summary
      end

      # Validate specific provider
      def validate_provider(provider_name)
        @validator.validate_provider(provider_name)
      end

      # Check if provider is configured
      def provider_configured?(provider_name)
        @validator.provider_configured?(provider_name)
      end

      # Get configuration with specific overrides
      def get_config_with_overrides(overrides = {})
        base_config = load_config
        return nil unless base_config

        merge_overrides(base_config, overrides)
      end

      # Get harness configuration with overrides
      def get_harness_config_with_overrides(overrides = {})
        harness_config = get_harness_config
        return nil unless harness_config

        harness_overrides = overrides[:harness] || overrides["harness"] || {}
        deep_merge(harness_config, harness_overrides)
      end

      # Get provider configuration with overrides
      def get_provider_config_with_overrides(provider_name, overrides = {})
        provider_config = get_provider_config(provider_name)
        return nil unless provider_config

        provider_overrides = overrides[:providers]&.dig(provider_name.to_sym) ||
          overrides[:providers]&.dig(provider_name.to_s) ||
          overrides["providers"]&.dig(provider_name.to_s) ||
          overrides["providers"]&.dig(provider_name.to_sym) ||
          {}

        deep_merge(provider_config, provider_overrides)
      end

      # Export configuration
      def export_config(format = :yaml)
        @validator.export_config(format)
      end

      # Reload configuration from file
      def reload_config
        @config_cache = nil
        @last_loaded = nil
        load_config(true)
      end

      # Check if configuration is valid
      def config_valid?
        validation_result = @validator.validate_existing
        validation_result[:valid]
      end

      # Get validation errors
      def get_validation_errors
        validation_result = @validator.validate_existing
        validation_result[:errors] || []
      end

      # Get validation warnings
      def get_validation_warnings
        validation_result = @validator.validate_existing
        validation_result[:warnings] || []
      end

      # Get configuration for specific harness mode
      def get_mode_config(mode, force_reload = false)
        config = load_config(force_reload)
        return nil unless config

        case mode.to_s
        when "analyze"
          get_analyze_mode_config(config)
        when "execute"
          get_execute_mode_config(config)
        else
          config
        end
      end

      # Get environment-specific configuration
      def get_environment_config(environment = nil, force_reload = false)
        environment ||= ENV["AIDP_ENV"] || "development"
        config = load_config(force_reload)
        return nil unless config

        env_config = config[:environments]&.dig(environment.to_sym) ||
          config[:environments]&.dig(environment.to_s) ||
          config["environments"]&.dig(environment.to_s) ||
          config["environments"]&.dig(environment.to_sym) ||
          {}

        merge_overrides(config, env_config)
      end

      # Get configuration for specific step
      def get_step_config(step_name, force_reload = false)
        config = load_config(force_reload)
        return nil unless config

        step_config = config[:steps]&.dig(step_name.to_sym) ||
          config[:steps]&.dig(step_name.to_s) ||
          config["steps"]&.dig(step_name.to_s) ||
          config["steps"]&.dig(step_name.to_sym) ||
          {}

        merge_overrides(config, step_config)
      end

      # Get configuration with feature flags
      def get_config_with_features(features = {}, force_reload = false)
        config = load_config(force_reload)
        return nil unless config

        feature_overrides = {}

        features.each do |feature, enabled|
          if enabled
            feature_config = config[:features]&.dig(feature.to_sym) ||
              config[:features]&.dig(feature.to_s) ||
              config["features"]&.dig(feature.to_s) ||
              config["features"]&.dig(feature.to_sym) ||
              {}
            feature_overrides = deep_merge(feature_overrides, feature_config)
          end
        end

        merge_overrides(config, feature_overrides)
      end

      # Get configuration for specific user
      def get_user_config(user_id = nil, force_reload = false)
        user_id ||= ENV["USER"] || "default"
        config = load_config(force_reload)
        return nil unless config

        user_config = config[:users]&.dig(user_id.to_sym) ||
          config[:users]&.dig(user_id.to_s) ||
          config["users"]&.dig(user_id.to_s) ||
          config["users"]&.dig(user_id.to_sym) ||
          {}

        merge_overrides(config, user_config)
      end

      # Get configuration with time-based overrides
      def get_time_based_config(force_reload = false)
        config = load_config(force_reload)
        return nil unless config

        time_overrides = {}
        current_hour = Time.now.hour

        # Check for time-based configurations
        if config[:time_based]
          time_config = config[:time_based]

          # Check for hour-based overrides
          if time_config[:hours]
            time_config[:hours].each do |hour_range, hour_config|
              if hour_in_range?(current_hour, hour_range)
                time_overrides = deep_merge(time_overrides, hour_config)
              end
            end
          end

          # Check for day-based overrides
          if time_config[:days]
            current_day = Time.now.strftime("%A").downcase
            day_config = time_config[:days][current_day.to_sym] || time_config[:days][current_day]
            if day_config
              time_overrides = deep_merge(time_overrides, day_config)
            end
          end
        end

        merge_overrides(config, time_overrides)
      end

      private

      def config_file_changed?
        return true unless @last_loaded && @validator.config_file_path

        File.mtime(@validator.config_file_path) > @last_loaded
      rescue
        true
      end

      def handle_validation_errors(errors)
        error_message = "Configuration validation failed:\n" + errors.join("\n")

        # Log error
        if defined?(Rails) && Rails.logger
          Rails.logger.error(error_message)
        else
          warn(error_message)
        end

        # In development, try to fix common issues
        if ENV["AIDP_ENV"] == "development" || ENV["RACK_ENV"] == "development"
          if @validator.fix_common_issues
            warn("Attempted to fix configuration issues. Please review the updated configuration file.")
          end
        end
      end

      def log_warnings(warnings)
        warning_message = "Configuration warnings:\n" + warnings.join("\n")

        # Log warnings
        if defined?(Rails) && Rails.logger
          Rails.logger.warn(warning_message)
        else
          warn(warning_message)
        end
      end

      def merge_overrides(base_config, overrides)
        return base_config if overrides.empty?

        deep_merge(base_config, overrides)
      end

      def deep_merge(base, override)
        result = base.dup

        override.each do |key, value|
          result[key] = if result[key].is_a?(Hash) && value.is_a?(Hash)
            deep_merge(result[key], value)
          else
            value
          end
        end

        result
      end

      def get_analyze_mode_config(config)
        analyze_overrides = config[:analyze_mode] || config["analyze_mode"] || {}
        merge_overrides(config, analyze_overrides)
      end

      def get_execute_mode_config(config)
        execute_overrides = config[:execute_mode] || config["execute_mode"] || {}
        merge_overrides(config, execute_overrides)
      end

      def hour_in_range?(hour, range)
        case range
        when Integer
          hour == range
        when Range
          range.include?(hour)
        when String
          # Parse "9-17" format
          if range.include?("-")
            start_hour, end_hour = range.split("-").map(&:to_i)
            hour >= start_hour && hour <= end_hour
          else
            hour == range.to_i
          end
        else
          false
        end
      end
    end
  end
end
