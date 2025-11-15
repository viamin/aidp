# frozen_string_literal: true

require_relative "model_cache"
require_relative "model_registry"

module Aidp
  module Harness
    # Service for discovering available models from providers
    #
    # Orchestrates model discovery across multiple providers:
    # 1. Checks cache first (with TTL)
    # 2. Falls back to dynamic discovery via provider.discover_models
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
        @provider_classes = discover_provider_classes
        Aidp.log_debug("model_discovery_service", "initialized",
          providers: @provider_classes.keys)
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

        @provider_classes.each_key do |provider|
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

        @provider_classes.each do |provider_name, class_name|
          provider_class = constantize_provider(class_name)
          next unless provider_class

          if provider_class.respond_to?(:supports_model_family?)
            providers << provider_name if provider_class.supports_model_family?(family_name)
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

      def perform_discovery(provider)
        provider_class = get_provider_class(provider)
        unless provider_class
          Aidp.log_warn("model_discovery_service", "unknown provider",
            provider: provider)
          return []
        end

        unless provider_class.respond_to?(:available?) && provider_class.available?
          Aidp.log_debug("model_discovery_service", "provider not available",
            provider: provider)
          return []
        end

        unless provider_class.respond_to?(:discover_models)
          Aidp.log_warn("model_discovery_service", "provider missing discover_models",
            provider: provider)
          return []
        end

        models = provider_class.discover_models
        Aidp.log_info("model_discovery_service", "discovered models",
          provider: provider, count: models.size)
        models
      end

      def get_provider_class(provider)
        class_name = @provider_classes[provider]
        return nil unless class_name

        constantize_provider(class_name)
      end

      def constantize_provider(class_name)
        # Safely constantize the provider class
        parts = class_name.split("::")
        parts.reduce(Object) { |mod, name| mod.const_get(name) }
      rescue NameError => e
        Aidp.log_debug("model_discovery_service", "provider class not found",
          class: class_name, error: e.message)
        nil
      end

      # Dynamically discover all provider classes from the providers directory
      #
      # @return [Hash] Hash of provider_name => class_name
      def discover_provider_classes
        providers_dir = File.join(__dir__, "../providers")
        provider_files = Dir.glob("*.rb", base: providers_dir)

        # Exclude base classes and utility files
        excluded_files = ["base.rb", "adapter.rb", "error_taxonomy.rb", "capability_registry.rb"]
        provider_files -= excluded_files

        providers = {}

        provider_files.each do |file|
          provider_name = File.basename(file, ".rb")
          # Convert to class name (e.g., "anthropic" -> "Anthropic", "github_copilot" -> "GithubCopilot")
          class_name = provider_name.split("_").map(&:capitalize).join
          full_class_name = "Aidp::Providers::#{class_name}"

          # Try to load and verify the provider class exists
          begin
            require_relative "../providers/#{provider_name}"
            provider_class = constantize_provider(full_class_name)
            if provider_class&.respond_to?(:discover_models)
              providers[provider_name] = full_class_name
            end
          rescue => e
            # Skip providers that can't be loaded or don't implement discover_models
            if ENV["DEBUG"]
              Aidp.log_debug("model_discovery_service", "skipping provider",
                provider: provider_name, reason: e.message)
            end
          end
        end

        Aidp.log_debug("model_discovery_service", "discovered provider classes",
          count: providers.size, providers: providers.keys)
        providers
      end
    end
  end
end
