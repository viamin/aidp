# frozen_string_literal: true

require "json"
require "fileutils"

module Aidp
  module Harness
    # Manages a dynamic cache of deprecated models detected at runtime
    # When deprecation errors are detected from provider APIs, models are
    # added to this cache with metadata (replacement, detected date, etc.)
    #
    # This class is designed to be extractable to the agent-harness gem.
    # It uses dependency injection for logging to decouple from AIDP.
    class DeprecationCache
      class CacheError < StandardError; end

      # Component name for logging
      COMPONENT = "deprecation_cache"

      attr_reader :cache_path

      # Initialize the deprecation cache.
      #
      # All parameters are optional for backward compatibility. Existing callers
      # that don't pass a logger will use AIDP's built-in logging.
      #
      # @param cache_path [String, nil] custom cache file path (optional)
      # @param root_dir [String, nil] root directory for default cache path (optional)
      # @param logger [#log_info, #log_warn, #log_error, nil] logger instance (optional,
      #   falls back to Aidp.log_* methods if nil)
      def initialize(cache_path: nil, root_dir: nil, logger: nil)
        @root_dir = root_dir || safe_root_dir
        @cache_path = cache_path || default_cache_path
        @cache_data = nil
        @logger = logger
        ensure_cache_directory
      end

      # Add a deprecated model to the cache
      # @param provider [String] Provider name (e.g., "anthropic")
      # @param model_id [String] Deprecated model ID
      # @param replacement [String, nil] Replacement model ID (if known)
      # @param reason [String, nil] Deprecation reason/message
      def add_deprecated_model(provider:, model_id:, replacement: nil, reason: nil)
        load_cache unless @cache_data

        @cache_data["providers"][provider] ||= {}
        @cache_data["providers"][provider][model_id] = {
          "deprecated_at" => Time.now.iso8601,
          "replacement" => replacement,
          "reason" => reason
        }.compact

        save_cache
        log_info("added_deprecated_model", provider: provider, model: model_id, replacement: replacement)
      end

      # Check if a model is deprecated
      # @param provider [String] Provider name
      # @param model_id [String] Model ID to check
      # @return [Boolean]
      def deprecated?(provider:, model_id:)
        load_cache unless @cache_data
        @cache_data.dig("providers", provider, model_id) != nil
      end

      # Get replacement model for a deprecated model
      # @param provider [String] Provider name
      # @param model_id [String] Deprecated model ID
      # @return [String, nil] Replacement model ID or nil
      def replacement_for(provider:, model_id:)
        load_cache unless @cache_data
        @cache_data.dig("providers", provider, model_id, "replacement")
      end

      # Get all deprecated models for a provider
      # @param provider [String] Provider name
      # @return [Array<String>] List of deprecated model IDs
      def deprecated_models(provider:)
        load_cache unless @cache_data
        (@cache_data.dig("providers", provider) || {}).keys
      end

      # Remove a model from the deprecated cache
      # Useful if a model comes back or was incorrectly marked
      # @param provider [String] Provider name
      # @param model_id [String] Model ID to remove
      def remove_deprecated_model(provider:, model_id:)
        load_cache unless @cache_data
        return unless @cache_data.dig("providers", provider, model_id)

        @cache_data["providers"][provider].delete(model_id)
        @cache_data["providers"].delete(provider) if @cache_data["providers"][provider].empty?

        save_cache
        log_info("removed_deprecated_model", provider: provider, model: model_id)
      end

      # Get full deprecation info for a model
      # @param provider [String] Provider name
      # @param model_id [String] Model ID
      # @return [Hash, nil] Deprecation metadata or nil
      def info(provider:, model_id:)
        load_cache unless @cache_data
        @cache_data.dig("providers", provider, model_id)
      end

      # Clear all cached deprecations
      def clear!
        @cache_data = default_cache_structure
        save_cache
        log_info("cleared_all_deprecations")
      end

      # Get cache statistics
      # @return [Hash] Statistics about cached deprecations
      def stats
        load_cache unless @cache_data
        {
          providers: @cache_data["providers"].keys.sort,
          total_deprecated: @cache_data["providers"].sum { |_, models| models.size },
          by_provider: @cache_data["providers"].transform_values(&:size)
        }
      end

      private

      # Get a safe root directory for the cache
      # Uses Dir.pwd if writable, otherwise falls back to tmpdir
      def safe_root_dir
        pwd = Dir.pwd
        aidp_dir = File.join(pwd, ".aidp")

        # Try to create the directory to test writability
        begin
          FileUtils.mkdir_p(aidp_dir) unless File.exist?(aidp_dir)
          pwd
        rescue Errno::EACCES, Errno::EROFS, Errno::EPERM
          # Permission denied or read-only filesystem - use temp directory
          require "tmpdir"
          Dir.tmpdir
        end
      end

      def default_cache_path
        File.join(@root_dir, ".aidp", "deprecated_models.json")
      end

      def ensure_cache_directory
        dir = File.dirname(@cache_path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end

      def load_cache
        if File.exist?(@cache_path)
          @cache_data = JSON.parse(File.read(@cache_path))
          validate_cache_structure
        else
          @cache_data = default_cache_structure
        end
      rescue JSON::ParserError => e
        log_warn("invalid_cache_file_resetting", error: e.message, path: @cache_path)
        @cache_data = default_cache_structure
      end

      def save_cache
        File.write(@cache_path, JSON.pretty_generate(@cache_data))
      rescue => e
        log_error("failed_to_save_cache", error: e.message, path: @cache_path)
        raise CacheError, "Failed to save deprecation cache: #{e.message}"
      end

      def default_cache_structure
        {
          "version" => "1.0",
          "updated_at" => Time.now.iso8601,
          "providers" => {}
        }
      end

      def validate_cache_structure
        unless @cache_data.is_a?(Hash) && @cache_data["providers"].is_a?(Hash)
          log_warn("invalid_cache_structure_resetting")
          @cache_data = default_cache_structure
        end
      end

      # Logging helpers with fallback to Aidp.log_* if no logger injected
      def log_info(message, **metadata)
        if @logger
          @logger.log_info(COMPONENT, message, **metadata)
        else
          Aidp.log_info(COMPONENT, message, **metadata)
        end
      end

      def log_warn(message, **metadata)
        if @logger
          @logger.log_warn(COMPONENT, message, **metadata)
        else
          Aidp.log_warn(COMPONENT, message, **metadata)
        end
      end

      def log_error(message, **metadata)
        if @logger
          @logger.log_error(COMPONENT, message, **metadata)
        else
          Aidp.log_error(COMPONENT, message, **metadata)
        end
      end
    end
  end
end
