# frozen_string_literal: true

require "agent_harness"

module Aidp
  # Wraps AIDP's logger to provide standard Ruby Logger interface
  # for AgentHarness compatibility
  class LoggerAdapter
    def initialize(aidp_logger, component: "agent_harness")
      @logger = aidp_logger
      @component = component
    end

    def debug(message = nil, &block)
      msg = message || (block ? block.call : "")
      @logger&.debug(@component, msg.to_s)
    end

    def info(message = nil, &block)
      msg = message || (block ? block.call : "")
      @logger&.info(@component, msg.to_s)
    end

    def warn(message = nil, &block)
      msg = message || (block ? block.call : "")
      @logger&.warn(@component, msg.to_s)
    end

    def error(message = nil, &block)
      msg = message || (block ? block.call : "")
      @logger&.error(@component, msg.to_s)
    end

    def fatal(message = nil, &block)
      msg = message || (block ? block.call : "")
      @logger&.error(@component, msg.to_s)
    end

    def level
      :debug
    end

    def level=(val)
      # no-op
    end
  end

  # Adapter for using the AgentHarness gem within AIDP
  #
  # This adapter bridges AIDP's existing provider interface with the
  # new AgentHarness gem, allowing gradual migration.
  #
  # Usage:
  #   adapter = Aidp::AgentHarnessAdapter.new(config)
  #   response = adapter.send_message(prompt: "Hello", provider: :claude)
  #
  class AgentHarnessAdapter
    attr_reader :conductor

    # Create a new adapter
    #
    # @param aidp_config [Aidp::Config] AIDP configuration
    # @param logger [Logger] logger instance
    def initialize(aidp_config, logger: nil)
      @aidp_config = aidp_config
      @logger = logger || Aidp.logger

      configure_agent_harness
    end

    # Send a message through AgentHarness
    #
    # @param prompt [String] the prompt to send
    # @param provider [Symbol, nil] provider to use
    # @param options [Hash] additional options
    # @return [Hash] AIDP-compatible response
    def send_message(prompt:, provider: nil, **options)
      start_time = Time.now

      # Map AIDP options to AgentHarness options
      harness_options = map_options(options)

      # Use the conductor for orchestrated requests
      response = @conductor.send_message(prompt, provider: provider, **harness_options)

      # Convert Response to AIDP-compatible hash
      convert_response(response, Time.now - start_time)
    rescue AgentHarness::RateLimitError => e
      handle_rate_limit(e, provider)
    rescue AgentHarness::NoProvidersAvailableError => e
      handle_no_providers(e)
    rescue AgentHarness::Error => e
      handle_error(e, provider)
    end

    # Get a specific provider instance
    #
    # @param name [Symbol] provider name
    # @return [AgentHarness::Providers::Base] provider instance
    def provider(name)
      @conductor.provider_manager.get_provider(name)
    end

    # Check if a provider is available
    #
    # @param name [Symbol] provider name
    # @return [Boolean] true if available
    def provider_available?(name)
      provider_class = AgentHarness::Providers::Registry.instance.get(name)
      provider_class.available?
    rescue AgentHarness::ConfigurationError
      false
    end

    # Get orchestration status
    #
    # @return [Hash] status information
    def status
      @conductor.status
    end

    # Get token usage summary
    #
    # @return [Hash] token usage
    def token_summary
      AgentHarness.token_tracker.summary
    end

    # Register callback for token events
    #
    # @yield [TokenEvent] token event
    def on_tokens_used(&block)
      AgentHarness.token_tracker.on_tokens_used(&block)
    end

    # Reset the adapter (useful for testing)
    def reset!
      @conductor.reset!
      AgentHarness.token_tracker.clear!
    end

    private

    def configure_agent_harness
      AgentHarness.configure do |config|
        config.logger = LoggerAdapter.new(@logger)
        config.log_level = begin
          @aidp_config.log_level
        rescue
          :info
        end
        config.default_timeout = begin
          @aidp_config.default_timeout
        rescue
          300
        end

        # Set default provider from AIDP config
        config.default_provider = map_provider_name(@aidp_config.default_provider)

        # Configure fallback providers
        config.fallback_providers = (@aidp_config.fallback_providers || []).map { |p| map_provider_name(p) }

        # Configure orchestration
        config.orchestration do |orch|
          orch.enabled = true
          orch.auto_switch_on_error = true
          orch.auto_switch_on_rate_limit = true

          orch.circuit_breaker do |cb|
            cb.enabled = true
            cb.failure_threshold = 5
            cb.timeout = 300
          end

          orch.retry do |r|
            r.enabled = true
            r.max_attempts = 3
            r.base_delay = 1.0
          end
        end

        # Configure providers from AIDP config
        configure_providers(config)

        # Register token usage callback
        config.on_tokens_used do |event|
          Aidp.log_debug("agent_harness_adapter", "token_usage",
            provider: event.provider,
            total_tokens: event.total_tokens)
        end

        # Register provider switch callback
        config.on_provider_switch do |event|
          Aidp.log_info("agent_harness_adapter", "provider_switch",
            from: event[:from],
            to: event[:to],
            reason: event[:reason])
        end
      end

      @conductor = AgentHarness.conductor
    end

    def configure_providers(config)
      # Configure enabled providers from AIDP config
      provider_configs = begin
        @aidp_config.providers
      rescue
        {}
      end

      provider_configs.each do |name, provider_config|
        harness_name = map_provider_name(name)

        config.provider(harness_name) do |p|
          p.enabled = provider_config[:enabled] != false
          p.type = provider_config[:type]&.to_sym || :usage_based
          p.priority = provider_config[:priority] || 10
          p.timeout = provider_config[:timeout]
          p.model = provider_config[:model]
          p.models = provider_config[:models] || []
        end
      end

      # Ensure default provider is configured
      unless config.providers.key?(config.default_provider)
        config.provider(config.default_provider) { |p| p.enabled = true }
      end
    end

    def map_provider_name(name)
      case name.to_s
      when "anthropic", "claude"
        :claude
      when "github_copilot", "copilot"
        :github_copilot
      else
        name.to_sym
      end
    end

    def map_options(options)
      harness_options = {}

      harness_options[:model] = options[:model] if options[:model]
      harness_options[:timeout] = options[:timeout] if options[:timeout]
      harness_options[:session] = options[:session] if options[:session]
      harness_options[:dangerous_mode] = options[:dangerous] if options[:dangerous]
      harness_options[:tier] = options[:tier] if options[:tier]

      harness_options
    end

    def convert_response(response, duration)
      {
        output: response.output,
        success: response.success?,
        exit_code: response.exit_code,
        provider: response.provider,
        model: response.model,
        duration: duration,
        tokens: response.tokens,
        error: response.error
      }
    end

    def handle_rate_limit(error, provider)
      Aidp.log_warn("agent_harness_adapter", "rate_limited",
        provider: provider,
        reset_time: error.reset_time)

      {
        output: nil,
        success: false,
        error: error.message,
        rate_limited: true,
        reset_time: error.reset_time
      }
    end

    def handle_no_providers(error)
      Aidp.log_error("agent_harness_adapter", "no_providers_available",
        attempted: error.attempted_providers)

      {
        output: nil,
        success: false,
        error: error.message,
        no_providers: true,
        attempted_providers: error.attempted_providers
      }
    end

    def handle_error(error, provider)
      Aidp.log_error("agent_harness_adapter", "provider_error",
        provider: provider,
        error: error.class.name,
        message: error.message)

      {
        output: nil,
        success: false,
        error: error.message,
        provider: provider
      }
    end
  end
end
