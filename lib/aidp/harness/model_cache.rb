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

      def initialize(cache_file: nil)
        @cache_file = cache_file || default_cache_file
        ensure_cache_directory
        Aidp.log_debug("model_cache", "initialized", cache_file: @cache_file)
      end

      # Get cached models for a provider if not expired
      #
      # @param provider [String] Provider name
      # @return [Array<Hash>, nil] Cached models or nil if expired/not found
      def get_cached_models(provider)
        cache_data = load_cache
        provider_cache = cache_data[provider]

        return nil unless provider_cache

        cached_at = Time.parse(provider_cache["cached_at"]) rescue nil
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
      rescue => e
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
        cache_data = load_cache

        cache_data[provider] = {
          "cached_at" => Time.now.iso8601,
          "ttl" => ttl,
          "models" => models
        }

        save_cache(cache_data)
        Aidp.log_info("model_cache", "cached models",
          provider: provider, count: models.size, ttl: ttl)
      rescue => e
        Aidp.log_error("model_cache", "failed to write cache",
          provider: provider, error: e.message)
        raise CacheError, "Failed to cache models: #{e.message}"
      end

      # Invalidate cache for a specific provider
      #
      # @param provider [String] Provider name
      def invalidate(provider)
        cache_data = load_cache
        cache_data.delete(provider)
        save_cache(cache_data)
        Aidp.log_info("model_cache", "invalidated cache", provider: provider)
      rescue => e
        Aidp.log_error("model_cache", "failed to invalidate cache",
          provider: provider, error: e.message)
      end

      # Invalidate all cached models
      def invalidate_all
        save_cache({})
        Aidp.log_info("model_cache", "invalidated all caches")
      rescue => e
        Aidp.log_error("model_cache", "failed to invalidate all",
          error: e.message)
      end

      # Get list of providers with cached models
      #
      # @return [Array<String>] Provider names with valid caches
      def cached_providers
        cache_data = load_cache
        providers = []

        cache_data.each do |provider, data|
          cached_at = Time.parse(data["cached_at"]) rescue nil
          next unless cached_at

          ttl = data["ttl"] || DEFAULT_TTL
          expires_at = cached_at + ttl

          providers << provider if Time.now <= expires_at
        end

        providers
      rescue => e
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
      rescue => e
        Aidp.log_error("model_cache", "failed to get stats",
          error: e.message)
        {total_providers: 0, cached_providers: [], cache_file_size: 0}
      end

      private

      def default_cache_file
        File.join(Dir.home, ".aidp", "cache", "models.json")
      end

      def ensure_cache_directory
        cache_dir = File.dirname(@cache_file)
        FileUtils.mkdir_p(cache_dir) unless File.directory?(cache_dir)
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
      rescue => e
        Aidp.log_error("model_cache", "failed to load cache",
          error: e.message)
        {}
      end

      def save_cache(data)
        ensure_cache_directory
        File.write(@cache_file, JSON.pretty_generate(data))
      end
    end
  end
end
