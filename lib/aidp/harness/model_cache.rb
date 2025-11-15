# frozen_string_literal: true

require "json"
require "fileutils"

module Aidp
  module Harness
    # Manages caching of discovered models with TTL support
    #
    # Cache is stored in ~/.aidp/cache/models.json
    # Each provider's models are cached separately with timestamps
    #
    # Usage:
    #   cache = ModelCache.new
    #   cache.cache_models("anthropic", models_array)
    #   cached = cache.get_cached_models("anthropic")
    #   cache.invalidate("anthropic")
    class ModelCache
      class CacheError < StandardError; end

      DEFAULT_TTL = 86400 # 24 hours in seconds

      attr_reader :cache_file

      def initialize(cache_file: nil, cache_dir: nil)
        @cache_file = determine_cache_file(cache_file, cache_dir)
        @cache_enabled = ensure_cache_directory

        if @cache_enabled
          Aidp.log_debug("model_cache", "initialized", cache_file: @cache_file)
        else
          Aidp.log_warn("model_cache", "cache disabled due to permission issues")
        end
      end

      # Get cached models for a provider if not expired
      #
      # @param provider [String] Provider name
      # @return [Array<Hash>, nil] Cached models or nil if expired/not found
      def get_cached_models(provider)
        cache_data = load_cache
        provider_cache = cache_data[provider]

        return nil unless provider_cache

        cached_at = begin
          Time.parse(provider_cache["cached_at"])
        rescue
          nil
        end
        return nil unless cached_at

        ttl = provider_cache["ttl"] || DEFAULT_TTL
        expires_at = cached_at + ttl

        if Time.now > expires_at
          Aidp.log_debug("model_cache", "cache expired",
            provider: provider, cached_at: cached_at, expires_at: expires_at)
          return nil
        end

        models = provider_cache["models"]
        Aidp.log_debug("model_cache", "cache hit",
          provider: provider, count: models&.size || 0)
        models
      rescue StandardError => e
        Aidp.log_error("model_cache", "failed to read cache",
          provider: provider, error: e.message)
        nil
      end

      # Cache models for a provider with TTL
      #
      # @param provider [String] Provider name
      # @param models [Array<Hash>] Models to cache
      # @param ttl [Integer] Time to live in seconds (default: 24 hours)
      def cache_models(provider, models, ttl: DEFAULT_TTL)
        unless @cache_enabled
          Aidp.log_debug("model_cache", "caching disabled, skipping",
            provider: provider)
          return false
        end

        cache_data = load_cache

        cache_data[provider] = {
          "cached_at" => Time.now.iso8601,
          "ttl" => ttl,
          "models" => models
        }

        if save_cache(cache_data)
          Aidp.log_info("model_cache", "cached models",
            provider: provider, count: models.size, ttl: ttl)
          true
        else
          Aidp.log_warn("model_cache", "failed to cache models",
            provider: provider)
          false
        end
      rescue StandardError => e
        Aidp.log_error("model_cache", "error caching models",
          provider: provider, error: e.message)
        false
      end

      # Invalidate cache for a specific provider
      #
      # @param provider [String] Provider name
      def invalidate(provider)
        return false unless @cache_enabled

        cache_data = load_cache
        cache_data.delete(provider)
        save_cache(cache_data)
        Aidp.log_info("model_cache", "invalidated cache", provider: provider)
        true
      rescue StandardError => e
        Aidp.log_error("model_cache", "failed to invalidate cache",
          provider: provider, error: e.message)
        false
      end

      # Invalidate all cached models
      def invalidate_all
        return false unless @cache_enabled

        save_cache({})
        Aidp.log_info("model_cache", "invalidated all caches")
        true
      rescue StandardError => e
        Aidp.log_error("model_cache", "failed to invalidate all",
          error: e.message)
        false
      end

      # Get list of providers with cached models
      #
      # @return [Array<String>] Provider names with valid caches
      def cached_providers
        cache_data = load_cache
        providers = []

        cache_data.each do |provider, data|
          cached_at = begin
            Time.parse(data["cached_at"])
          rescue
            nil
          end
          next unless cached_at

          ttl = data["ttl"] || DEFAULT_TTL
          expires_at = cached_at + ttl

          providers << provider if Time.now <= expires_at
        end

        providers
      rescue StandardError => e
        Aidp.log_error("model_cache", "failed to get cached providers",
          error: e.message)
        []
      end

      # Get cache statistics
      #
      # @return [Hash] Statistics about the cache
      def stats
        cache_data = load_cache
        file_size = begin
          File.size(@cache_file)
        rescue
          0
        end

        {
          total_providers: cache_data.size,
          cached_providers: cached_providers,
          cache_file_size: file_size
        }
      rescue StandardError => e
        Aidp.log_error("model_cache", "failed to get stats",
          error: e.message)
        {total_providers: 0, cached_providers: [], cache_file_size: 0}
      end

      private

      def determine_cache_file(cache_file, cache_dir)
        return cache_file if cache_file

        if cache_dir
          File.join(cache_dir, "models.json")
        else
          default_cache_file
        end
      end

      def default_cache_file
        File.join(Dir.home, ".aidp", "cache", "models.json")
      rescue ArgumentError, StandardError => e
        # Fallback to temp directory if home directory is not accessible
        Aidp.log_debug("model_cache", "home directory not accessible, using temp",
          error: e.message)
        File.join(Dir.tmpdir, "aidp_cache", "models.json")
      end

      def ensure_cache_directory
        cache_dir = File.dirname(@cache_file)
        return true if File.directory?(cache_dir)

        FileUtils.mkdir_p(cache_dir)
        true
      rescue Errno::EACCES, Errno::EPERM => e
        Aidp.log_warn("model_cache", "permission denied creating cache directory",
          cache_dir: cache_dir, error: e.message)

        # Try fallback to temp directory
        @cache_file = File.join(Dir.tmpdir, "aidp_cache", "models.json")
        fallback_dir = File.dirname(@cache_file)

        begin
          FileUtils.mkdir_p(fallback_dir) unless File.directory?(fallback_dir)
          Aidp.log_info("model_cache", "using fallback cache directory",
            cache_file: @cache_file)
          true
        rescue StandardError => fallback_error
          Aidp.log_error("model_cache", "failed to create fallback cache directory",
            error: fallback_error.message)
          false
        end
      rescue StandardError => e
        Aidp.log_error("model_cache", "failed to create cache directory",
          cache_dir: cache_dir, error: e.message)
        false
      end

      def load_cache
        return {} unless File.exist?(@cache_file)

        content = File.read(@cache_file)
        JSON.parse(content)
      rescue JSON::ParserError => e
        Aidp.log_warn("model_cache", "corrupted cache file, resetting",
          error: e.message)
        # Reset corrupted cache
        {}
      rescue StandardError => e
        Aidp.log_error("model_cache", "failed to load cache",
          error: e.message)
        {}
      end

      def save_cache(data)
        return false unless @cache_enabled

        ensure_cache_directory
        File.write(@cache_file, JSON.pretty_generate(data))
        true
      rescue StandardError => e
        Aidp.log_error("model_cache", "failed to save cache",
          error: e.message, cache_file: @cache_file)
        false
      end
    end
  end
end
