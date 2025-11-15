# frozen_string_literal: true

require_relative "model_cache"
require_relative "model_registry"
require_relative "model_discoverers/base"
require_relative "model_discoverers/anthropic"
require_relative "model_discoverers/cursor"
require_relative "model_discoverers/gemini"

module Aidp
  module Harness
    # Service for discovering available models from providers
    #
    # Orchestrates model discovery across multiple providers:
    # 1. Checks cache first (with TTL)
    # 2. Falls back to dynamic discovery via provider CLIs
    # 3. Merges with static registry for comprehensive results
    # 4. Caches results for future use
    #
    # Usage:
    #   service = ModelDiscoveryService.new
    #   models = service.discover_models("anthropic")
    #   all_models = service.discover_all_models
    class ModelDiscoveryService
      attr_reader :cache, :registry

      def initialize(cache: nil, registry: nil)
        @cache = cache || ModelCache.new
        @registry = registry || ModelRegistry.new
        @discoverers = build_discoverers
        Aidp.log_debug("model_discovery_service", "initialized",
          discoverers: @discoverers.keys)
      end

      # Discover models for a specific provider
      #
      # @param provider [String] Provider name (e.g., "anthropic", "cursor")
      # @param use_cache [Boolean] Whether to use cached results (default: true)
      # @return [Array<Hash>] Discovered models
      def discover_models(provider, use_cache: true)
        Aidp.log_info("model_discovery_service", "discovering models",
          provider: provider, use_cache: use_cache)

        # Check cache first
        if use_cache
          cached = @cache.get_cached_models(provider)
          if cached
            Aidp.log_debug("model_discovery_service", "using cached models",
              provider: provider, count: cached.size)
            return cached
          end
        end

        # Perform discovery
        models = perform_discovery(provider)

        # Cache the results
        @cache.cache_models(provider, models) if models.any?

        models
      rescue => e
        Aidp.log_error("model_discovery_service", "discovery failed",
          provider: provider, error: e.message, backtrace: e.backtrace.first(3))
        []
      end

      # Discover models from all available providers
      #
      # @param use_cache [Boolean] Whether to use cached results
      # @return [Hash] Hash of provider => models array
      def discover_all_models(use_cache: true)
        results = {}

        @discoverers.each_key do |provider|
          models = discover_models(provider, use_cache: use_cache)
          results[provider] = models if models.any?
        end

        Aidp.log_info("model_discovery_service", "discovered all models",
          providers: results.keys, total_models: results.values.flatten.size)
        results
      end

      # Discover models concurrently from multiple providers
      #
      # @param providers [Array<String>] List of provider names
      # @param use_cache [Boolean] Whether to use cached results
      # @return [Hash] Hash of provider => models array
      def discover_concurrent(providers, use_cache: true)
        require "concurrent"

        results = {}
        mutex = Mutex.new

        # Create a thread pool
        pool = Concurrent::FixedThreadPool.new(providers.size)

        # Submit discovery tasks
        futures = providers.map do |provider|
          Concurrent::Future.execute(executor: pool) do
            models = discover_models(provider, use_cache: use_cache)
            mutex.synchronize { results[provider] = models }
          end
        end

        # Wait for all to complete
        futures.each(&:wait)

        pool.shutdown
        pool.wait_for_termination(30)

        Aidp.log_info("model_discovery_service", "concurrent discovery complete",
          providers: results.keys, total_models: results.values.flatten.size)
        results
      rescue LoadError => e
        # Fallback to sequential if concurrent gem not available
        Aidp.log_warn("model_discovery_service", "concurrent gem not available, using sequential",
          error: e.message)
        providers.each_with_object({}) do |provider, hash|
          hash[provider] = discover_models(provider, use_cache: use_cache)
        end
      rescue => e
        Aidp.log_error("model_discovery_service", "concurrent discovery failed",
          error: e.message)
        {}
      end

      # Get all available models (discovery + static registry)
      #
      # Combines dynamically discovered models with static registry
      #
      # @param use_cache [Boolean] Whether to use cached results
      # @return [Hash] Hash with :discovered and :registry keys
      def all_available_models(use_cache: true)
        discovered = discover_all_models(use_cache: use_cache)
        registry_families = @registry.all_families

        {
          discovered: discovered,
          registry: registry_families.map { |family| @registry.get_model_info(family) }.compact
        }
      end

      # Find which providers support a given model family
      #
      # @param family_name [String] Model family name
      # @return [Array<String>] List of provider names
      def providers_supporting(family_name)
        providers = []

        @discoverers.each do |provider, discoverer|
          next unless discoverer.available?

          # Check if provider supports this family
          provider_class = get_provider_class(provider)
          if provider_class&.respond_to?(:supports_model_family?)
            providers << provider if provider_class.supports_model_family?(family_name)
          end
        end

        providers
      end

      # Refresh cache for all providers
      def refresh_all_caches
        @cache.invalidate_all
        discover_all_models(use_cache: false)
      end

      # Refresh cache for specific provider
      #
      # @param provider [String] Provider name
      def refresh_cache(provider)
        @cache.invalidate(provider)
        discover_models(provider, use_cache: false)
      end

      private

      def build_discoverers
        {
          "anthropic" => ModelDiscoverers::Anthropic.new,
          "cursor" => ModelDiscoverers::Cursor.new,
          "gemini" => ModelDiscoverers::Gemini.new
        }
      end

      def perform_discovery(provider)
        discoverer = @discoverers[provider]
        unless discoverer
          Aidp.log_warn("model_discovery_service", "no discoverer for provider",
            provider: provider)
          return []
        end

        unless discoverer.available?
          Aidp.log_debug("model_discovery_service", "provider not available",
            provider: provider)
          return []
        end

        models = discoverer.discover_models
        Aidp.log_info("model_discovery_service", "discovered models",
          provider: provider, count: models.size)
        models
      end

      def get_provider_class(provider)
        case provider
        when "anthropic"
          Aidp::Providers::Anthropic
        when "cursor"
          Aidp::Providers::Cursor
        when "gemini"
          Aidp::Providers::Gemini
        else
          nil
        end
      end
    end
  end
end
