# frozen_string_literal: true

require "yaml"
require_relative "config_schema"
require_relative "../config/paths"

module Aidp
  module Harness
    # Configuration validator for harness
    class ConfigValidator
      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
        @config_file = find_config_file
        @config = nil
        @validation_result = nil
      end

      # Load and validate configuration
      def load_and_validate
        unless @config_file
          @validation_result = {
            valid: false,
            errors: ["No configuration file found"],
            warnings: []
          }
          return @validation_result
        end

        load_config
        validate_config
        @validation_result
      end

      # Validate existing configuration
      def validate_existing
        return {valid: false, errors: ["No configuration file found"], warnings: []} unless @config_file

        load_config
        validate_config
        @validation_result
      end

      # Get configuration with defaults applied
      def validated_config
        return nil unless @validation_result&.dig(:valid)

        ConfigSchema.apply_defaults(@config)
      end

      # Check if configuration is valid
      def valid?
        @validation_result&.dig(:valid) || false
      end

      # Get validation errors
      def errors
        @validation_result&.dig(:errors) || []
      end

      # Get validation warnings
      def warnings
        @validation_result&.dig(:warnings) || []
      end

      # Get configuration file path
      def config_file_path
        @config_file
      end

      # Check if configuration file exists
      def config_exists?
        !@config_file.nil?
      end

      # Create example configuration file
      def create_example_config
        return false if config_exists?

        example_config = ConfigSchema.generate_example
        config_path = Aidp::ConfigPaths.config_file(@project_dir)

        Aidp::ConfigPaths.ensure_config_dir(@project_dir)
        File.write(config_path, YAML.dump(example_config))
        true
      end

      # Fix common configuration issues
      def fix_common_issues
        return false unless @config_file && @config

        original_config = @config.dup

        # Fix string/symbol key inconsistencies
        @config = normalize_keys(@config)

        # Apply missing defaults
        @config = ConfigSchema.apply_defaults(@config)

        # Fix common validation issues
        fix_validation_issues

        # Check if any changes were made
        if @config != original_config
          # Write fixed configuration back to file
          File.write(@config_file, YAML.dump(@config))
          true
        else
          false
        end
      end

      # Get configuration summary
      def summary
        return {error: "No configuration file found"} unless @config_file

        load_config
        summary = {
          config_file: @config_file,
          valid: valid?,
          errors_count: errors.size,
          warnings_count: warnings.size,
          harness_configured: !(@config[:harness] || @config["harness"]).nil?,
          providers_count: 0,
          providers: []
        }

        providers_config = @config[:providers] || @config["providers"] || {}
        summary[:providers_count] = providers_config.size
        summary[:providers] = providers_config.keys.map(&:to_s)

        summary
      end

      # Validate specific provider configuration
      def validate_provider(provider_name)
        return {valid: false, errors: ["No configuration file found"], warnings: []} unless @config_file

        load_config
        providers_config = @config[:providers] || @config["providers"] || {}
        provider_config = providers_config[provider_name] || providers_config[provider_name.to_sym]

        return {valid: false, errors: ["Provider '#{provider_name}' not found"], warnings: []} unless provider_config

        # Create a minimal config with harness section and just this provider for validation
        test_config = {
          harness: {
            max_retries: 2,
            default_provider: provider_name,
            fallback_providers: [provider_name]
          },
          providers: {
            provider_name => provider_config
          }
        }

        ConfigSchema.validate(test_config)
      end

      # Get provider configuration with defaults
      def provider_config(provider_name)
        return nil unless @config_file

        load_config
        providers_config = @config[:providers] || @config["providers"] || {}
        provider_config = providers_config[provider_name] || providers_config[provider_name.to_sym]

        return nil unless provider_config

        # Apply defaults for this provider
        providers_schema = ConfigSchema::SCHEMA[:providers][:pattern_properties][/^[a-zA-Z0-9_-]+$/]
        ConfigSchema.apply_section_defaults(provider_config, providers_schema)
      end

      # Check if provider is properly configured
      def provider_configured?(provider_name)
        return false unless @config_file

        load_config
        providers_config = @config[:providers] || @config["providers"] || {}
        provider_config = providers_config[provider_name] || providers_config[provider_name.to_sym]

        return false unless provider_config

        # Basic validation
        provider_type = provider_config[:type] || provider_config["type"]
        return false unless provider_type

        # For usage-based providers, check for required fields
        if provider_type == "usage_based"
          max_tokens = provider_config[:max_tokens] || provider_config["max_tokens"]
          return false unless max_tokens&.positive?
        end

        true
      end

      # Get harness configuration with defaults
      def harness_config
        return nil unless @config_file

        load_config
        harness_config = @config[:harness] || @config["harness"] || {}

        # Apply defaults
        harness_schema = ConfigSchema::SCHEMA[:harness]
        ConfigSchema.apply_section_defaults(harness_config, harness_schema)
      end

      # Export configuration to different formats
      def export_config(format = :yaml)
        return nil unless @config_file

        load_config
        validate_config
        config = validated_config
        return nil unless config

        case format
        when :yaml
          YAML.dump(config)
        when :json
          require "json"
          JSON.pretty_generate(config)
        when :ruby
          "CONFIG = #{config.inspect}"
        else
          raise ArgumentError, "Unsupported format: #{format}"
        end
      end

      # Validate configuration data (public method for external use)
      def validate_config(config_data = nil)
        if config_data
          # Validate provided configuration data
          @config = config_data
        end
        return unless @config

        # Don't override validation result if it was already set due to loading errors
        return if @validation_result && !@validation_result[:valid]

        @validation_result = ConfigSchema.validate(@config)
      end

      private

      def find_config_file
        config_file = Aidp::ConfigPaths.config_file(@project_dir)

        if File.exist?(config_file)
          config_file
        end
      end

      def load_config
        return unless @config_file

        begin
          @config = YAML.safe_load_file(@config_file, permitted_classes: [Date, Time, Symbol], aliases: true) || {}
        rescue => e
          @config = {}
          @validation_result = {
            valid: false,
            errors: ["Failed to load configuration file: #{e.message}"],
            warnings: []
          }
        end
      end

      def normalize_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(key, value), result|
          new_key = key.is_a?(String) ? key.to_sym : key
          new_value = value.is_a?(Hash) ? normalize_keys(value) : value
          result[new_key] = new_value
        end
      end

      def fix_validation_issues
        return unless @config

        # Fix common issues that can be automatically corrected

        # Ensure harness section exists
        unless @config.key?(:harness)
          @config[:harness] = {}
        end

        # Ensure providers section exists
        unless @config.key?(:providers)
          @config[:providers] = {}
        end

        # Fix string/symbol key inconsistencies
        @config = normalize_keys(@config)

        # Ensure default_provider is set if not specified
        unless @config[:harness][:default_provider]
          available_providers = @config[:providers].keys.map(&:to_s)
          if available_providers.include?("cursor")
            @config[:harness][:default_provider] = "cursor"
          elsif available_providers.any?
            @config[:harness][:default_provider] = available_providers.first
          end
        end

        # Ensure fallback_providers is an array
        unless @config[:harness][:fallback_providers].is_a?(Array)
          @config[:harness][:fallback_providers] = []
        end

        # Fix provider configurations
        @config[:providers].each do |_provider_name, provider_config|
          # Ensure type is specified
          unless provider_config[:type]
            provider_config[:type] = "subscription" # Default to subscription
          end

          # Ensure default_flags is an array
          unless provider_config[:default_flags].is_a?(Array)
            provider_config[:default_flags] = []
          end

          # Ensure models is an array
          unless provider_config[:models].is_a?(Array)
            provider_config[:models] = []
          end

          # Ensure model_weights is a hash
          unless provider_config[:model_weights].is_a?(Hash)
            provider_config[:model_weights] = {}
          end

          # Ensure models_config is a hash
          unless provider_config[:models_config].is_a?(Hash)
            provider_config[:models_config] = {}
          end

          # Ensure features is a hash
          unless provider_config[:features].is_a?(Hash)
            provider_config[:features] = {}
          end

          # Ensure monitoring is a hash
          unless provider_config[:monitoring].is_a?(Hash)
            provider_config[:monitoring] = {}
          end
        end
      end
    end
  end
end
