# Agent-Harness Gem Extraction Plan

> **Gem Name:** `agent-harness` | **Namespace:** `AgentHarness`
>
> The name "harness" conveys control and orchestration of AI agents, similar to the concept of a "test harness" in software testing.

## Executive Summary

This plan details the extraction of AIDP's agent CLI interaction code into a standalone Ruby gem. The gem will provide:

1. **Unified interface** for CLI-based AI coding agents (Claude Code, Cursor, Gemini CLI, etc.)
2. **Full orchestration layer** with provider switching, circuit breakers, and health monitoring
3. **Flexible configuration** via YAML, Rails initializer, or environment variables
4. **Dynamic provider registration** for custom provider support
5. **Token usage tracking** (consumed by applications for cost/limit calculations)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Module Structure](#2-module-structure)
3. [Configuration System](#3-configuration-system)
4. [Provider Interface](#4-provider-interface)
5. [Orchestration Layer](#5-orchestration-layer)
6. [Command Execution](#6-command-execution)
7. [Error Handling](#7-error-handling)
8. [Token Usage Tracking](#8-token-usage-tracking)
9. [MCP Support](#9-mcp-support)
10. [AIDP Adaptation](#10-aidp-adaptation)
11. [Preparation Work (Pre-Extraction Refactoring)](#11-preparation-work-pre-extraction-refactoring)
12. [Migration Strategy (Post-Preparation)](#12-migration-strategy-post-preparation)
13. [Testing Strategy](#13-testing-strategy)
14. [Phased Implementation](#14-phased-implementation)

---

## 1. Architecture Overview

### Current AIDP Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AIDP Application                          │
├─────────────────────────────────────────────────────────────┤
│  Work Loops │ Watch Mode │ Workflows │ AI Decision Engine   │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────────┐
│                    Harness Layer                             │
├─────────────────────────────────────────────────────────────┤
│  Runner │ ProviderManager │ ProviderFactory │ Configuration │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────────┐
│                    Provider Layer                            │
├─────────────────────────────────────────────────────────────┤
│  Base │ Adapter │ ErrorTaxonomy │ Individual Providers       │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────────┐
│                    External CLIs                             │
├─────────────────────────────────────────────────────────────┤
│  claude │ cursor │ gemini │ gh copilot │ codex │ aider      │
└─────────────────────────────────────────────────────────────┘
```

### Target Architecture (After Extraction)

```
┌─────────────────────────────────────────────────────────────┐
│                    AIDP Application                          │
├─────────────────────────────────────────────────────────────┤
│  Work Loops │ Watch Mode │ Workflows │ AI Decision Engine   │
│  Usage Limits │ AIDP-specific UI │ Harness Runner            │
└──────────────────────────┬──────────────────────────────────┘
                           │ uses
┌──────────────────────────┴──────────────────────────────────┐
│                 AgentHarness Gem (agent-harness)                 │
├─────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────┐ │
│ │                  Orchestration Layer                     │ │
│ │  Conductor │ ProviderManager │ CircuitBreaker │ Health   │ │
│ └─────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │                    Provider Layer                        │ │
│ │  Registry │ Base │ Adapter │ ErrorTaxonomy │ Providers   │ │
│ └─────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │                    Core Layer                            │ │
│ │  Configuration │ CommandExecutor │ Logger │ TokenTracker │ │
│ └─────────────────────────────────────────────────────────┘ │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────────┐
│                    External CLIs                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Module Structure

### Gem Directory Structure

```
agent-harness/
├── exe/
│   └── agent-harness                 # CLI executable
│
├── lib/
│   ├── agent_harness.rb              # Main entry point
│   └── agent_harness/
│       ├── version.rb
│       │
│       ├── # Core Layer
│       ├── configuration.rb          # Configuration management
│       ├── configuration/
│       │   ├── yaml_loader.rb        # YAML config loading
│       │   ├── env_loader.rb         # Environment variable loading
│       │   └── dsl.rb                # Ruby DSL configuration
│       ├── command_executor.rb       # Shell command execution
│       ├── logger.rb                 # Logger interface
│       ├── token_tracker.rb          # Token usage tracking
│       ├── activity_monitor.rb       # Stuck detection & activity tracking
│       │
│       ├── # Error Handling
│       ├── errors.rb                 # Error classes
│       ├── error_taxonomy.rb         # Error classification
│       │
│       ├── # Provider Layer
│       ├── providers/
│       │   ├── registry.rb           # Dynamic provider registration
│       │   ├── adapter.rb            # Provider interface (module)
│       │   ├── base.rb               # Base provider class
│       │   ├── binary_checker.rb     # CLI availability checking
│       │   ├── capabilities.rb       # Capability definitions
│       │   ├── anthropic.rb          # Claude Code provider
│       │   ├── cursor.rb             # Cursor provider
│       │   ├── gemini.rb             # Gemini CLI provider
│       │   ├── github_copilot.rb     # GitHub Copilot provider
│       │   ├── codex.rb              # OpenAI Codex provider
│       │   ├── opencode.rb           # OpenCode provider
│       │   ├── kilocode.rb           # Kilocode provider
│       │   └── aider.rb              # Aider provider
│       │
│       ├── # Orchestration Layer
│       ├── orchestration/
│       │   ├── conductor.rb          # Main orchestration entry point
│       │   ├── provider_manager.rb   # Provider switching & selection
│       │   ├── model_manager.rb      # Model switching within providers
│       │   ├── circuit_breaker.rb    # Circuit breaker logic
│       │   ├── rate_limiter.rb       # Rate limit tracking
│       │   ├── health_monitor.rb     # Provider health tracking
│       │   ├── health_calculator.rb  # Health score calculation
│       │   ├── load_balancer.rb      # Load balancing strategies
│       │   ├── fallback_chain.rb     # Fallback chain management
│       │   └── metrics.rb            # Metrics collection
│       │
│       ├── # MCP Support
│       ├── mcp/
│       │   ├── client.rb             # MCP client interface
│       │   └── server_registry.rb    # MCP server management
│       │
│       ├── # Observability
│       ├── observability/
│       │   └── otel.rb               # OpenTelemetry integration
│       │
│       ├── # CLI
│       ├── cli/
│       │   ├── main.rb               # CLI entry point
│       │   ├── commands/
│       │   │   ├── test.rb           # Test provider connectivity
│       │   │   ├── validate.rb       # Validate configuration
│       │   │   ├── health.rb         # Check provider health
│       │   │   ├── prompt.rb         # Quick prompt for testing
│       │   │   └── providers.rb      # List available providers
│       │   └── formatters/
│       │       ├── text.rb           # Plain text output
│       │       └── json.rb           # JSON output
│       │
│       └── # Rails Integration (optional)
│           └── railtie.rb            # Rails integration
│
├── spec/
│   ├── spec_helper.rb
│   ├── agent_harness_spec.rb
│   ├── configuration_spec.rb
│   ├── providers/
│   │   ├── base_spec.rb
│   │   ├── anthropic_spec.rb
│   │   └── ...
│   ├── orchestration/
│   │   ├── conductor_spec.rb
│   │   ├── provider_manager_spec.rb
│   │   ├── health_calculator_spec.rb
│   │   └── ...
│   └── cli/
│       └── commands/
│           └── ...
│
├── agent_harness.gemspec
├── Gemfile
├── README.md
├── CHANGELOG.md
└── LICENSE
```

### Namespace Structure

```ruby
module AgentHarness
  # Core
  class Configuration; end
  class CommandExecutor; end
  class Logger; end
  class TokenTracker; end

  # Errors
  class Error < StandardError; end
  class ProviderError < Error; end
  class ConfigurationError < Error; end
  class TimeoutError < Error; end
  class RateLimitError < Error; end
  class AuthenticationError < Error; end
  class CircuitOpenError < Error; end

  module ErrorTaxonomy; end

  # Providers
  module Providers
    class Registry; end
    module Adapter; end
    class Base; end
    class Anthropic < Base; end
    class Cursor < Base; end
    class Gemini < Base; end
    class GithubCopilot < Base; end
    class Codex < Base; end
    class Opencode < Base; end
    class Kilocode < Base; end
    class Aider < Base; end
  end

  # Orchestration
  module Orchestration
    class Conductor; end
    class ProviderManager; end
    class ModelManager; end
    class CircuitBreaker; end
    class RateLimiter; end
    class HealthMonitor; end
    class LoadBalancer; end
    class FallbackChain; end
    class Metrics; end
  end

  # MCP
  module MCP
    class Client; end
    class ServerRegistry; end
  end
end
```

---

## 3. Configuration System

### Configuration Sources (Priority Order)

1. **Explicit Ruby configuration** (highest priority)
2. **YAML file** (`agent_harness.yml` or custom path)
3. **Environment variables** (lowest priority, for secrets)

### 3.1 YAML Configuration

```yaml
# agent_harness.yml
agent_harness:
  # Logging
  log_level: info  # debug, info, warn, error

  # Default behavior
  default_provider: cursor
  fallback_providers:
    - claude
    - gemini

  # Orchestration settings
  orchestration:
    enabled: true
    auto_switch_on_error: true
    auto_switch_on_rate_limit: true

    # Circuit breaker
    circuit_breaker:
      enabled: true
      failure_threshold: 5
      timeout: 300
      half_open_max_calls: 3

    # Retry settings
    retry:
      enabled: true
      max_attempts: 3
      base_delay: 1.0
      max_delay: 60.0
      exponential_base: 2.0
      jitter: true

    # Rate limiting
    rate_limit:
      enabled: true
      default_reset_time: 3600

    # Load balancing
    load_balancing:
      enabled: true
      strategy: weighted_round_robin  # weighted_round_robin, least_connections, random

    # Health monitoring
    health_check:
      enabled: true
      interval: 60
      failure_threshold: 3

  # Provider configurations
  providers:
    cursor:
      enabled: true
      type: subscription
      priority: 1
      models:
        - cursor-default
        - cursor-fast
      default_flags: []
      timeout: 600

    claude:
      enabled: true
      type: usage_based
      priority: 2
      models:
        - claude-sonnet-4-20250514
        - claude-3-5-haiku-20241022
      timeout: 300
      # Note: dangerous mode requires explicit per-call opt-in, not defaults

    gemini:
      enabled: true
      type: usage_based
      priority: 3
      models:
        - gemini-2.5-pro
        - gemini-2.0-flash
      timeout: 300
```

### 3.2 Ruby DSL Configuration

```ruby
# config/initializers/agent_harness.rb (Rails)
# or anywhere in Ruby application

AgentHarness.configure do |config|
  # Logger (inject your own)
  config.logger = Rails.logger  # or any Logger-compatible object
  config.log_level = :info

  # Default provider
  config.default_provider = :cursor
  config.fallback_providers = [:claude, :gemini]

  # Command executor (optional, for custom execution)
  config.command_executor = MyCustomExecutor.new

  # Orchestration
  config.orchestration do |orch|
    orch.enabled = true
    orch.auto_switch_on_error = true

    orch.circuit_breaker do |cb|
      cb.enabled = true
      cb.failure_threshold = 5
      cb.timeout = 300
    end

    orch.retry do |r|
      r.max_attempts = 3
      r.base_delay = 1.0
      r.jitter = true
    end
  end

  # Provider configuration
  config.provider :cursor do |p|
    p.enabled = true
    p.type = :subscription
    p.priority = 1
    p.models = ["cursor-default", "cursor-fast"]
    p.timeout = 600
  end

  config.provider :claude do |p|
    p.enabled = true
    p.type = :usage_based
    p.priority = 2
    p.models = ["claude-sonnet-4-20250514"]
    # Note: dangerous mode requires explicit per-call opt-in via send_message(dangerous: true)
  end

  # Register custom provider
  config.register_provider :my_custom_agent, MyCustomProvider

  # Token tracking callback (for AIDP's usage limits)
  config.on_tokens_used do |event|
    # event.provider, event.model, event.input_tokens,
    # event.output_tokens, event.total_tokens, event.timestamp
    MyUsageTracker.record(event)
  end

  # Event callbacks
  config.on_provider_switch do |event|
    # event.from_provider, event.to_provider, event.reason
  end

  config.on_circuit_open do |event|
    # event.provider, event.failure_count
  end
end
```

### 3.3 Environment Variables

```bash
# Provider API keys (secrets)
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=...
OPENAI_API_KEY=...

# Override configuration
AGENT_HARNESS_DEFAULT_PROVIDER=claude
AGENT_HARNESS_LOG_LEVEL=debug

# Provider-specific
AGENT_HARNESS_CLAUDE_TIMEOUT=600
AGENT_HARNESS_CURSOR_ENABLED=false
```

### 3.4 Configuration Class Implementation

```ruby
# lib/agent_harness/configuration.rb
module AgentHarness
  class Configuration
    attr_accessor :logger, :log_level, :default_provider, :fallback_providers
    attr_accessor :command_executor, :config_file_path

    attr_reader :providers, :orchestration_config, :callbacks

    def initialize
      @logger = nil  # Will use null logger if not set
      @log_level = :info
      @default_provider = :cursor
      @fallback_providers = []
      @command_executor = CommandExecutor.new
      @config_file_path = nil
      @providers = {}
      @orchestration_config = OrchestrationConfig.new
      @callbacks = CallbackRegistry.new
      @custom_provider_classes = {}
    end

    def orchestration(&block)
      block.call(@orchestration_config) if block_given?
      @orchestration_config
    end

    def provider(name, &block)
      config = ProviderConfig.new(name)
      block.call(config) if block_given?
      @providers[name.to_sym] = config
    end

    def register_provider(name, klass)
      @custom_provider_classes[name.to_sym] = klass
    end

    def on_tokens_used(&block)
      @callbacks.register(:tokens_used, block)
    end

    def on_provider_switch(&block)
      @callbacks.register(:provider_switch, block)
    end

    def on_circuit_open(&block)
      @callbacks.register(:circuit_open, block)
    end

    # Load from YAML file
    def load_yaml(path)
      loader = Configuration::YamlLoader.new(path)
      loader.apply_to(self)
    end

    # Load from environment variables
    def load_env
      loader = Configuration::EnvLoader.new
      loader.apply_to(self)
    end

    def validate!
      # Validate configuration completeness
      raise ConfigurationError, "No providers configured" if @providers.empty?
      raise ConfigurationError, "Default provider not configured" unless @providers[@default_provider]
    end
  end
end
```

---

## 4. Provider Interface

### 4.1 Provider Adapter (Interface Contract)

```ruby
# lib/agent_harness/providers/adapter.rb
module AgentHarness
  module Providers
    # Interface that all providers must implement
    module Adapter
      # Required methods
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Human-readable provider name
        def provider_name
          raise NotImplementedError
        end

        # Check if provider CLI is available on the system
        def available?
          raise NotImplementedError
        end

        # CLI binary name
        def binary_name
          raise NotImplementedError
        end

        # Required domains for firewall configuration
        def firewall_requirements
          { domains: [], ip_ranges: [] }
        end

        # Paths to instruction files (e.g., CLAUDE.md, .cursorrules)
        def instruction_file_paths
          []
        end

        # Discover available models
        def discover_models
          []
        end
      end

      # Instance methods

      # Send a message/prompt to the provider
      # @param prompt [String] The prompt to send
      # @param options [Hash] Provider-specific options
      #   - :model [String] Model to use
      #   - :timeout [Integer] Timeout in seconds
      #   - :session [String] Session identifier
      #   - :dangerous_mode [Boolean] Skip permission checks
      # @return [Response] Response object with output and metadata
      def send_message(prompt:, **options)
        raise NotImplementedError
      end

      # Provider capabilities
      # @return [Hash] Capability flags
      def capabilities
        {
          streaming: false,
          file_upload: false,
          vision: false,
          tool_use: false,
          json_mode: false,
          mcp: false,
          dangerous_mode: false
        }
      end

      # Error patterns for classification
      # @return [Hash<Symbol, Array<Regexp>>] Error patterns by category
      def error_patterns
        {}
      end

      # Check if provider supports MCP
      def supports_mcp?
        capabilities[:mcp]
      end

      # Fetch configured MCP servers
      def fetch_mcp_servers
        []
      end

      # Check if provider supports dangerous mode
      def supports_dangerous_mode?
        capabilities[:dangerous_mode]
      end

      # Get dangerous mode flags
      def dangerous_mode_flags
        []
      end

      # Validate provider configuration
      def validate_config
        { valid: true, errors: [] }
      end

      # Health check
      def health_status
        { healthy: true, message: "OK" }
      end
    end
  end
end
```

### 4.2 Base Provider Class

```ruby
# lib/agent_harness/providers/base.rb
module AgentHarness
  module Providers
    class Base
      include Adapter

      attr_reader :config, :executor, :logger, :token_tracker

      def initialize(config: nil, executor: nil, logger: nil)
        @config = config || ProviderConfig.new(self.class.provider_name)
        @executor = executor || AgentHarness.configuration.command_executor
        @logger = logger || AgentHarness.logger
        @token_tracker = AgentHarness.token_tracker
      end

      # Configure the provider instance
      def configure(options = {})
        @config.merge!(options)
        self
      end

      # Main send_message implementation
      def send_message(prompt:, **options)
        log_debug("send_message_start", prompt_length: prompt.length, options: options.keys)

        # Build command
        command = build_command(prompt, options)

        # Calculate timeout
        timeout = options[:timeout] || @config.timeout || default_timeout

        # Execute command
        start_time = Time.now
        result = execute_with_timeout(command, timeout: timeout, env: build_env(options))
        duration = Time.now - start_time

        # Parse response
        response = parse_response(result, duration: duration)

        # Track tokens
        track_tokens(response) if response.tokens

        log_debug("send_message_complete", duration: duration, tokens: response.tokens)

        response
      rescue => e
        handle_error(e, prompt: prompt, options: options)
      end

      protected

      # Build CLI command - override in subclasses
      def build_command(prompt, options)
        raise NotImplementedError
      end

      # Build environment variables - override in subclasses
      def build_env(options)
        {}
      end

      # Parse CLI output into Response - override in subclasses
      def parse_response(result, duration:)
        Response.new(
          output: result.stdout,
          exit_code: result.exit_code,
          duration: duration,
          provider: self.class.provider_name
        )
      end

      # Default timeout
      def default_timeout
        300
      end

      private

      def execute_with_timeout(command, timeout:, env:)
        @executor.execute(command, timeout: timeout, env: env)
      end

      def track_tokens(response)
        return unless @token_tracker && response.tokens

        @token_tracker.record(
          provider: self.class.provider_name,
          model: @config.model,
          input_tokens: response.tokens[:input],
          output_tokens: response.tokens[:output],
          total_tokens: response.tokens[:total]
        )
      end

      def handle_error(error, prompt:, options:)
        # Classify error
        classification = ErrorTaxonomy.classify(error, self.class.error_patterns)

        log_error("send_message_error",
          error: error.class.name,
          message: error.message,
          classification: classification)

        # Wrap in appropriate error class
        raise map_to_error_class(classification, error)
      end

      def map_to_error_class(classification, original_error)
        case classification
        when :rate_limited
          RateLimitError.new(original_error.message)
        when :auth_expired
          AuthenticationError.new(original_error.message)
        when :timeout
          TimeoutError.new(original_error.message)
        else
          ProviderError.new(original_error.message)
        end
      end

      def log_debug(action, **context)
        @logger&.debug("[AgentHarness::#{self.class.provider_name}] #{action}: #{context.inspect}")
      end

      def log_error(action, **context)
        @logger&.error("[AgentHarness::#{self.class.provider_name}] #{action}: #{context.inspect}")
      end
    end
  end
end
```

### 4.3 Response Object

```ruby
# lib/agent_harness/response.rb
module AgentHarness
  class Response
    attr_reader :output, :exit_code, :duration, :provider, :model
    attr_reader :tokens, :metadata, :error

    def initialize(output:, exit_code:, duration:, provider:, model: nil,
                   tokens: nil, metadata: {}, error: nil)
      @output = output
      @exit_code = exit_code
      @duration = duration
      @provider = provider
      @model = model
      @tokens = tokens
      @metadata = metadata
      @error = error
    end

    def success?
      @exit_code == 0 && @error.nil?
    end

    def failed?
      !success?
    end

    def to_h
      {
        output: @output,
        exit_code: @exit_code,
        duration: @duration,
        provider: @provider,
        model: @model,
        tokens: @tokens,
        metadata: @metadata,
        error: @error
      }
    end
  end
end
```

### 4.4 Example Provider Implementation (Anthropic/Claude)

```ruby
# lib/agent_harness/providers/anthropic.rb
module AgentHarness
  module Providers
    class Anthropic < Base
      class << self
        def provider_name
          :claude
        end

        def binary_name
          "claude"
        end

        def available?
          system("which claude > /dev/null 2>&1")
        end

        def firewall_requirements
          {
            domains: [
              "api.anthropic.com",
              "claude.ai",
              "statsig.anthropic.com"
            ],
            ip_ranges: []
          }
        end

        def instruction_file_paths
          ["CLAUDE.md", ".claude/settings.json"]
        end

        def discover_models
          # Parse output of `claude models list`
          output = `claude models list 2>/dev/null`
          return [] unless $?.success?

          output.lines.map(&:strip).reject(&:empty?)
        rescue
          []
        end
      end

      def capabilities
        {
          streaming: true,
          file_upload: true,
          vision: true,
          tool_use: true,
          json_mode: true,
          mcp: true,
          dangerous_mode: true
        }
      end

      def error_patterns
        {
          rate_limited: [
            /rate.?limit/i,
            /too many requests/i,
            /quota exceeded/i
          ],
          auth_expired: [
            /invalid.*api.*key/i,
            /authentication.*failed/i,
            /unauthorized/i
          ],
          timeout: [
            /timeout/i,
            /timed out/i
          ]
        }
      end

      def dangerous_mode_flags
        ["--dangerously-skip-permissions"]
      end

      def supports_mcp?
        true
      end

      def fetch_mcp_servers
        # Parse MCP configuration from Claude settings
        settings_path = File.expand_path("~/.claude/settings.json")
        return [] unless File.exist?(settings_path)

        settings = JSON.parse(File.read(settings_path))
        settings.dig("mcp", "servers") || []
      rescue
        []
      end

      protected

      def build_command(prompt, options)
        cmd = [self.class.binary_name]

        # Add model flag
        if options[:model]
          cmd += ["--model", options[:model]]
        end

        # Add dangerous mode if requested
        if options[:dangerous_mode] && supports_dangerous_mode?
          cmd += dangerous_mode_flags
        end

        # Add custom flags from config
        cmd += @config.default_flags if @config.default_flags

        # Add prompt flag
        cmd += ["--print", "--prompt", prompt]

        cmd
      end

      def parse_response(result, duration:)
        # Parse Claude-specific output format
        output = result.stdout
        tokens = extract_tokens_from_output(output)

        Response.new(
          output: output,
          exit_code: result.exit_code,
          duration: duration,
          provider: self.class.provider_name,
          model: @config.model,
          tokens: tokens
        )
      end

      private

      def extract_tokens_from_output(output)
        # Claude CLI may include token info in output
        # Parse if available
        nil  # Implement based on actual output format
      end
    end
  end
end
```

### 4.5 Provider Registry (Dynamic Registration)

```ruby
# lib/agent_harness/providers/registry.rb
module AgentHarness
  module Providers
    class Registry
      include Singleton

      def initialize
        @providers = {}
        @aliases = {}
        register_builtin_providers
      end

      # Register a provider class
      def register(name, klass, aliases: [])
        name = name.to_sym
        validate_provider_class!(klass)

        @providers[name] = klass

        aliases.each do |alias_name|
          @aliases[alias_name.to_sym] = name
        end

        AgentHarness.logger&.debug("Registered provider: #{name}")
      end

      # Get provider class by name
      def get(name)
        name = resolve_alias(name.to_sym)
        @providers[name] || raise(ConfigurationError, "Unknown provider: #{name}")
      end

      # Check if provider is registered
      def registered?(name)
        name = resolve_alias(name.to_sym)
        @providers.key?(name)
      end

      # List all registered providers
      def all
        @providers.keys
      end

      # List available providers (CLI installed)
      def available
        @providers.select { |_, klass| klass.available? }.keys
      end

      private

      def resolve_alias(name)
        @aliases[name] || name
      end

      def validate_provider_class!(klass)
        unless klass.included_modules.include?(Adapter)
          raise ConfigurationError, "Provider class must include AgentHarness::Providers::Adapter"
        end

        [:provider_name, :available?, :binary_name].each do |method|
          unless klass.respond_to?(method)
            raise ConfigurationError, "Provider class must implement .#{method}"
          end
        end
      end

      def register_builtin_providers
        register(:claude, Anthropic, aliases: [:anthropic])
        register(:cursor, Cursor)
        register(:gemini, Gemini)
        register(:github_copilot, GithubCopilot, aliases: [:copilot])
        register(:codex, Codex)
        register(:opencode, Opencode)
        register(:kilocode, Kilocode)
        register(:aider, Aider)
      end
    end
  end
end
```

---

## 5. Orchestration Layer

### 5.1 Conductor (Main Entry Point)

```ruby
# lib/agent_harness/orchestration/conductor.rb
module AgentHarness
  module Orchestration
    # Main orchestration entry point
    # Provides a simple interface while managing complexity internally
    class Conductor
      attr_reader :provider_manager, :metrics

      def initialize(config: nil)
        @config = config || AgentHarness.configuration
        @provider_manager = ProviderManager.new(@config)
        @metrics = Metrics.new
      end

      # Send a message with full orchestration
      # Handles provider selection, fallback, retries, etc.
      def send_message(prompt, provider: nil, model: nil, **options)
        provider_name = provider || @config.default_provider

        with_orchestration(provider_name, model, options) do |selected_provider|
          selected_provider.send_message(prompt: prompt, model: model, **options)
        end
      end

      # Execute with explicit provider (bypass orchestration)
      def execute_direct(prompt, provider:, **options)
        provider_instance = @provider_manager.get_provider(provider)
        provider_instance.send_message(prompt: prompt, **options)
      end

      # Get current status
      def status
        {
          current_provider: @provider_manager.current_provider,
          available_providers: @provider_manager.available_providers,
          health: @provider_manager.health_status,
          metrics: @metrics.summary
        }
      end

      # Reset all state (useful for testing)
      def reset!
        @provider_manager.reset!
        @metrics.reset!
      end

      private

      def with_orchestration(provider_name, model, options)
        retries = 0
        max_retries = @config.orchestration_config.retry.max_attempts

        begin
          # Select provider (may return different provider based on health)
          provider = @provider_manager.select_provider(provider_name)

          # Record attempt
          @metrics.record_attempt(provider.class.provider_name)

          start_time = Time.now
          response = yield(provider)
          duration = Time.now - start_time

          # Record success
          @metrics.record_success(provider.class.provider_name, duration)
          @provider_manager.record_success(provider.class.provider_name)

          response

        rescue RateLimitError, CircuitOpenError => e
          handle_provider_failure(e, provider_name, :switch)
          retry if (retries += 1) < max_retries
          raise

        rescue TimeoutError, ProviderError => e
          @provider_manager.record_failure(provider_name)
          handle_provider_failure(e, provider_name, :retry)
          retry if (retries += 1) < max_retries
          raise
        end
      end

      def handle_provider_failure(error, provider_name, strategy)
        @metrics.record_failure(provider_name, error)

        case strategy
        when :switch
          new_provider = @provider_manager.switch_provider(
            reason: error.class.name,
            context: { error: error.message }
          )
          emit_callback(:provider_switch, from: provider_name, to: new_provider, reason: error.message)
        when :retry
          delay = calculate_retry_delay
          sleep(delay) if delay > 0
        end
      end

      def calculate_retry_delay
        retry_config = @config.orchestration_config.retry
        # Exponential backoff with jitter
        base = retry_config.base_delay
        # Add implementation
        base
      end

      def emit_callback(event, **data)
        @config.callbacks.emit(event, data)
      end
    end
  end
end
```

### 5.2 Provider Manager

```ruby
# lib/agent_harness/orchestration/provider_manager.rb
module AgentHarness
  module Orchestration
    class ProviderManager
      attr_reader :current_provider, :provider_instances

      def initialize(config)
        @config = config
        @registry = Providers::Registry.instance
        @provider_instances = {}
        @current_provider = config.default_provider

        @circuit_breakers = {}
        @rate_limiters = {}
        @health_monitor = HealthMonitor.new
        @fallback_chains = {}
        @provider_health = {}

        initialize_providers
      end

      # Select best available provider
      def select_provider(preferred = nil)
        preferred ||= @current_provider

        # Check circuit breaker
        if circuit_open?(preferred)
          return select_fallback(preferred, reason: :circuit_open)
        end

        # Check rate limit
        if rate_limited?(preferred)
          return select_fallback(preferred, reason: :rate_limited)
        end

        # Check health
        unless healthy?(preferred)
          return select_fallback(preferred, reason: :unhealthy)
        end

        get_provider(preferred)
      end

      # Get or create provider instance
      def get_provider(name)
        name = name.to_sym
        @provider_instances[name] ||= create_provider(name)
      end

      # Switch to next available provider
      def switch_provider(reason:, context: {})
        old_provider = @current_provider

        fallback = select_fallback(@current_provider, reason: reason)
        return nil unless fallback

        @current_provider = fallback.class.provider_name

        AgentHarness.logger&.info(
          "[AgentHarness] Provider switch: #{old_provider} -> #{@current_provider} (#{reason})"
        )

        fallback
      end

      # Record success for provider
      def record_success(provider_name)
        @health_monitor.record_success(provider_name)
        @circuit_breakers[provider_name]&.record_success
      end

      # Record failure for provider
      def record_failure(provider_name)
        @health_monitor.record_failure(provider_name)
        @circuit_breakers[provider_name]&.record_failure
      end

      # Get available providers
      def available_providers
        @provider_instances.keys.select do |name|
          !circuit_open?(name) && !rate_limited?(name) && healthy?(name)
        end
      end

      # Get health status for all providers
      def health_status
        @provider_instances.keys.map do |name|
          {
            provider: name,
            healthy: healthy?(name),
            circuit_open: circuit_open?(name),
            rate_limited: rate_limited?(name),
            metrics: @health_monitor.metrics_for(name)
          }
        end
      end

      # Reset all state
      def reset!
        @circuit_breakers.each_value(&:reset!)
        @rate_limiters.each_value(&:reset!)
        @health_monitor.reset!
        @current_provider = @config.default_provider
      end

      private

      def initialize_providers
        @config.providers.each do |name, provider_config|
          next unless provider_config.enabled

          @circuit_breakers[name] = CircuitBreaker.new(
            @config.orchestration_config.circuit_breaker
          )

          @rate_limiters[name] = RateLimiter.new(
            @config.orchestration_config.rate_limit
          )

          @fallback_chains[name] = build_fallback_chain(name)
        end
      end

      def create_provider(name)
        klass = @registry.get(name)
        config = @config.providers[name]

        klass.new(
          config: config,
          executor: @config.command_executor,
          logger: AgentHarness.logger
        )
      end

      def select_fallback(provider_name, reason:)
        chain = @fallback_chains[provider_name] || build_fallback_chain(provider_name)

        chain.each do |fallback_name|
          next if fallback_name == provider_name
          next if circuit_open?(fallback_name)
          next if rate_limited?(fallback_name)
          next unless healthy?(fallback_name)

          return get_provider(fallback_name)
        end

        nil  # No fallback available
      end

      def build_fallback_chain(provider_name)
        chain = [provider_name] + @config.fallback_providers
        chain += @config.providers.keys
        chain.uniq
      end

      def circuit_open?(provider_name)
        @circuit_breakers[provider_name]&.open? || false
      end

      def rate_limited?(provider_name)
        @rate_limiters[provider_name]&.limited? || false
      end

      def healthy?(provider_name)
        @health_monitor.healthy?(provider_name)
      end
    end
  end
end
```

### 5.3 Circuit Breaker

```ruby
# lib/agent_harness/orchestration/circuit_breaker.rb
module AgentHarness
  module Orchestration
    class CircuitBreaker
      STATES = [:closed, :open, :half_open].freeze

      attr_reader :state, :failure_count, :success_count

      def initialize(config)
        @config = config
        @failure_threshold = config.failure_threshold || 5
        @timeout = config.timeout || 300
        @half_open_max_calls = config.half_open_max_calls || 3

        reset!
      end

      def open?
        return false unless @config.enabled

        if @state == :open && timeout_elapsed?
          transition_to(:half_open)
        end

        @state == :open
      end

      def closed?
        @state == :closed
      end

      def record_success
        @success_count += 1

        if @state == :half_open && @success_count >= @half_open_max_calls
          transition_to(:closed)
        end
      end

      def record_failure
        @failure_count += 1

        if @failure_count >= @failure_threshold
          transition_to(:open)
        end
      end

      def reset!
        @state = :closed
        @failure_count = 0
        @success_count = 0
        @opened_at = nil
      end

      private

      def transition_to(new_state)
        old_state = @state
        @state = new_state

        case new_state
        when :open
          @opened_at = Time.now
          @failure_count = 0
          emit_event(:circuit_opened)
        when :half_open
          @success_count = 0
          emit_event(:circuit_half_open)
        when :closed
          @failure_count = 0
          @success_count = 0
          @opened_at = nil
          emit_event(:circuit_closed)
        end

        AgentHarness.logger&.info(
          "[AgentHarness::CircuitBreaker] State transition: #{old_state} -> #{new_state}"
        )
      end

      def timeout_elapsed?
        return true unless @opened_at
        Time.now - @opened_at >= @timeout
      end

      def emit_event(event)
        AgentHarness.configuration.callbacks.emit(event, circuit_breaker: self)
      end
    end
  end
end
```

---

## 6. Command Execution

### 6.1 Command Executor

```ruby
# lib/agent_harness/command_executor.rb
require "open3"
require "timeout"
require "shellwords"

module AgentHarness
  class CommandExecutor
    Result = Struct.new(:stdout, :stderr, :exit_code, :duration, keyword_init: true)

    def initialize(logger: nil)
      @logger = logger
    end

    # Execute a command with timeout support
    # @param command [Array<String>, String] Command to execute
    # @param timeout [Integer, nil] Timeout in seconds
    # @param env [Hash] Environment variables
    # @param stdin_data [String, nil] Data to send to stdin
    # @return [Result] Execution result
    def execute(command, timeout: nil, env: {}, stdin_data: nil)
      cmd_array = normalize_command(command)
      cmd_string = cmd_array.shelljoin

      log_debug("Executing command", command: cmd_string, timeout: timeout)

      start_time = Time.now

      stdout, stderr, status = if timeout
        execute_with_timeout(cmd_array, timeout: timeout, env: env, stdin_data: stdin_data)
      else
        execute_without_timeout(cmd_array, env: env, stdin_data: stdin_data)
      end

      duration = Time.now - start_time

      Result.new(
        stdout: stdout,
        stderr: stderr,
        exit_code: status.exitstatus,
        duration: duration
      )
    end

    # Check if a binary exists in PATH
    # @param binary [String] Binary name
    # @return [String, nil] Full path or nil
    def which(binary)
      ENV["PATH"].split(File::PATH_SEPARATOR).each do |path|
        full_path = File.join(path, binary)
        return full_path if File.executable?(full_path)
      end
      nil
    end

    private

    def normalize_command(command)
      case command
      when Array
        command.map(&:to_s)
      when String
        Shellwords.split(command)
      else
        raise ArgumentError, "Command must be Array or String"
      end
    end

    def execute_with_timeout(cmd_array, timeout:, env:, stdin_data:)
      stdout = ""
      stderr = ""
      status = nil

      Timeout.timeout(timeout) do
        Open3.popen3(env, *cmd_array) do |stdin, stdout_io, stderr_io, wait_thr|
          if stdin_data
            stdin.write(stdin_data)
            stdin.close
          else
            stdin.close
          end

          stdout = stdout_io.read
          stderr = stderr_io.read
          status = wait_thr.value
        end
      end

      [stdout, stderr, status]
    rescue Timeout::Error
      raise TimeoutError, "Command timed out after #{timeout} seconds"
    end

    def execute_without_timeout(cmd_array, env:, stdin_data:)
      Open3.popen3(env, *cmd_array) do |stdin, stdout_io, stderr_io, wait_thr|
        if stdin_data
          stdin.write(stdin_data)
          stdin.close
        else
          stdin.close
        end

        stdout = stdout_io.read
        stderr = stderr_io.read
        status = wait_thr.value

        [stdout, stderr, status]
      end
    end

    def log_debug(message, **context)
      @logger&.debug("[AgentHarness::CommandExecutor] #{message}: #{context.inspect}")
    end
  end
end
```

---

## 7. Error Handling

### 7.1 Error Classes

```ruby
# lib/agent_harness/errors.rb
module AgentHarness
  class Error < StandardError
    attr_reader :original_error, :context

    def initialize(message = nil, original_error: nil, context: {})
      @original_error = original_error
      @context = context
      super(message)
    end
  end

  # Provider-related errors
  class ProviderError < Error; end
  class ProviderNotFoundError < ProviderError; end
  class ProviderUnavailableError < ProviderError; end

  # Execution errors
  class TimeoutError < Error; end
  class CommandExecutionError < Error; end

  # Rate limiting and circuit breaker
  class RateLimitError < Error
    attr_reader :reset_time

    def initialize(message = nil, reset_time: nil, **kwargs)
      @reset_time = reset_time
      super(message, **kwargs)
    end
  end

  class CircuitOpenError < Error
    attr_reader :provider

    def initialize(message = nil, provider: nil, **kwargs)
      @provider = provider
      super(message, **kwargs)
    end
  end

  # Authentication errors
  class AuthenticationError < Error; end

  # Configuration errors
  class ConfigurationError < Error; end

  # Orchestration errors
  class NoProvidersAvailableError < Error; end
end
```

### 7.2 Error Taxonomy

```ruby
# lib/agent_harness/error_taxonomy.rb
module AgentHarness
  module ErrorTaxonomy
    CATEGORIES = {
      rate_limited: {
        description: "Rate limit exceeded",
        action: :switch_provider,
        retryable: false
      },
      auth_expired: {
        description: "Authentication failed or expired",
        action: :switch_provider,
        retryable: false
      },
      quota_exceeded: {
        description: "Usage quota exceeded",
        action: :switch_provider,
        retryable: false
      },
      transient: {
        description: "Temporary error",
        action: :retry_with_backoff,
        retryable: true
      },
      permanent: {
        description: "Unrecoverable error",
        action: :escalate,
        retryable: false
      },
      timeout: {
        description: "Operation timed out",
        action: :retry_with_backoff,
        retryable: true
      },
      unknown: {
        description: "Unknown error",
        action: :retry_with_backoff,
        retryable: true
      }
    }.freeze

    class << self
      # Classify an error based on provider patterns
      # @param error [Exception] The error to classify
      # @param patterns [Hash<Symbol, Array<Regexp>>] Provider-specific patterns
      # @return [Symbol] Error category
      def classify(error, patterns = {})
        message = error.message.to_s.downcase

        # Check provider-specific patterns first
        patterns.each do |category, regexes|
          return category if regexes.any? { |r| message.match?(r) }
        end

        # Fall back to generic patterns
        classify_generic(message)
      end

      # Get recommended action for error category
      def action_for(category)
        CATEGORIES.dig(category, :action) || :escalate
      end

      # Check if error category is retryable
      def retryable?(category)
        CATEGORIES.dig(category, :retryable) || false
      end

      private

      def classify_generic(message)
        case message
        when /rate.?limit|too many requests|429/i
          :rate_limited
        when /quota|usage.?limit|billing/i
          :quota_exceeded
        when /auth|unauthorized|forbidden|invalid.*(key|token)|401|403/i
          :auth_expired
        when /timeout|timed.?out/i
          :timeout
        when /temporary|retry|503|502|500/i
          :transient
        when /invalid|malformed|bad.?request|400/i
          :permanent
        else
          :unknown
        end
      end
    end
  end
end
```

---

## 8. Token Usage Tracking

```ruby
# lib/agent_harness/token_tracker.rb
module AgentHarness
  class TokenTracker
    TokenEvent = Struct.new(
      :provider, :model, :input_tokens, :output_tokens, :total_tokens,
      :timestamp, :request_id,
      keyword_init: true
    )

    def initialize
      @events = []
      @callbacks = []
      @mutex = Mutex.new
    end

    # Record token usage
    def record(provider:, model: nil, input_tokens: 0, output_tokens: 0, total_tokens: nil, request_id: nil)
      total = total_tokens || (input_tokens + output_tokens)

      event = TokenEvent.new(
        provider: provider,
        model: model,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        total_tokens: total,
        timestamp: Time.now,
        request_id: request_id || SecureRandom.uuid
      )

      @mutex.synchronize do
        @events << event
      end

      # Notify callbacks
      notify_callbacks(event)

      event
    end

    # Get usage summary
    def summary(since: nil, provider: nil)
      events = filtered_events(since: since, provider: provider)

      {
        total_requests: events.size,
        total_input_tokens: events.sum(&:input_tokens),
        total_output_tokens: events.sum(&:output_tokens),
        total_tokens: events.sum(&:total_tokens),
        by_provider: group_by_provider(events),
        by_model: group_by_model(events)
      }
    end

    # Get recent events
    def recent_events(limit: 100)
      @mutex.synchronize do
        @events.last(limit)
      end
    end

    # Register callback for token events
    def on_tokens_used(&block)
      @callbacks << block
    end

    # Clear all recorded events
    def clear!
      @mutex.synchronize do
        @events.clear
      end
    end

    private

    def filtered_events(since: nil, provider: nil)
      @mutex.synchronize do
        events = @events.dup
        events = events.select { |e| e.timestamp >= since } if since
        events = events.select { |e| e.provider.to_s == provider.to_s } if provider
        events
      end
    end

    def group_by_provider(events)
      events.group_by(&:provider).transform_values do |provider_events|
        {
          requests: provider_events.size,
          input_tokens: provider_events.sum(&:input_tokens),
          output_tokens: provider_events.sum(&:output_tokens),
          total_tokens: provider_events.sum(&:total_tokens)
        }
      end
    end

    def group_by_model(events)
      events.group_by { |e| "#{e.provider}:#{e.model}" }.transform_values do |model_events|
        {
          requests: model_events.size,
          input_tokens: model_events.sum(&:input_tokens),
          output_tokens: model_events.sum(&:output_tokens),
          total_tokens: model_events.sum(&:total_tokens)
        }
      end
    end

    def notify_callbacks(event)
      @callbacks.each do |callback|
        callback.call(event)
      rescue => e
        AgentHarness.logger&.error("[AgentHarness::TokenTracker] Callback error: #{e.message}")
      end
    end
  end
end
```

---

## 9. MCP Support

```ruby
# lib/agent_harness/mcp/client.rb
module AgentHarness
  module MCP
    class Client
      def initialize(provider:)
        @provider = provider
      end

      # Check if provider supports MCP
      def supported?
        @provider.supports_mcp?
      end

      # Get configured MCP servers
      def servers
        @provider.fetch_mcp_servers
      end

      # Connect to MCP server (if applicable)
      def connect(server_config)
        # Implementation depends on MCP protocol
        raise NotImplementedError
      end
    end

    # lib/agent_harness/mcp/server_registry.rb
    class ServerRegistry
      def initialize
        @servers = {}
      end

      def register(name, config)
        @servers[name.to_sym] = config
      end

      def get(name)
        @servers[name.to_sym]
      end

      def all
        @servers.dup
      end
    end
  end
end
```

---

## 10. AIDP Adaptation

### 10.1 Changes Required in AIDP

After extracting to the gem, AIDP will need to:

#### 10.1.1 Add Gem Dependency

```ruby
# Gemfile
gem "agent-harness", "~> 1.0"
```

#### 10.1.2 Create Adapter Layer

```ruby
# lib/aidp/agent_harness_adapter.rb
module Aidp
  class AgentHarnessAdapter
    def initialize
      configure_agent_harness
    end

    def send_message(prompt:, provider: nil, **options)
      # Convert AIDP options to AgentHarness options
      pa_options = convert_options(options)

      # Use AgentHarness conductor
      response = AgentHarness.conductor.send_message(prompt, provider: provider, **pa_options)

      # Convert response back to AIDP format
      convert_response(response)
    end

    private

    def configure_agent_harness
      AgentHarness.configure do |config|
        # Inject AIDP's logger
        config.logger = Aidp.logger

        # Load AIDP's configuration
        aidp_config = Aidp::Config.load_harness_config
        apply_aidp_config(config, aidp_config)

        # Set up token tracking callback for usage limits
        config.on_tokens_used do |event|
          Aidp::Harness::UsageLimitTracker.record(
            provider: event.provider,
            model: event.model,
            tokens: event.total_tokens,
            timestamp: event.timestamp
          )
        end

        # Set up provider switch callback
        config.on_provider_switch do |event|
          Aidp.log_debug("provider_switch",
            from: event[:from],
            to: event[:to],
            reason: event[:reason])
        end
      end
    end

    def apply_aidp_config(pa_config, aidp_config)
      harness = aidp_config[:harness] || {}
      providers = aidp_config[:providers] || {}

      pa_config.default_provider = harness[:default_provider]&.to_sym
      pa_config.fallback_providers = Array(harness[:fallback_providers]).map(&:to_sym)

      # Configure orchestration
      pa_config.orchestration do |orch|
        if cb = harness[:circuit_breaker]
          orch.circuit_breaker do |circuit|
            circuit.enabled = cb[:enabled]
            circuit.failure_threshold = cb[:failure_threshold]
            circuit.timeout = cb[:timeout]
          end
        end

        if retry_config = harness[:retry]
          orch.retry do |r|
            r.enabled = retry_config[:enabled]
            r.max_attempts = retry_config[:max_attempts]
            r.base_delay = retry_config[:base_delay]
          end
        end
      end

      # Configure providers
      providers.each do |name, provider_config|
        pa_config.provider(name) do |p|
          p.enabled = provider_config[:enabled] != false
          p.type = provider_config[:type]&.to_sym
          p.priority = provider_config[:priority]
          p.models = provider_config[:models]
          p.default_flags = provider_config[:default_flags]
          p.timeout = provider_config[:timeout]
        end
      end
    end

    def convert_options(options)
      # Map AIDP options to AgentHarness options
      {
        model: options[:model],
        timeout: options[:timeout],
        dangerous_mode: options[:dangerous_mode] || options[:skip_permissions],
        session: options[:session]
      }.compact
    end

    def convert_response(pa_response)
      # Return format expected by AIDP
      {
        output: pa_response.output,
        status: pa_response.success? ? "completed" : "error",
        provider: pa_response.provider,
        model: pa_response.model,
        duration: pa_response.duration,
        tokens: pa_response.tokens,
        metadata: pa_response.metadata
      }
    end
  end
end
```

#### 10.1.3 Update Provider Usage Throughout AIDP

```ruby
# Before (direct provider usage)
provider = Aidp::Providers::Anthropic.new
result = provider.send_message(prompt: prompt, options: options)

# After (via adapter)
adapter = Aidp::AgentHarnessAdapter.new
result = adapter.send_message(prompt: prompt, **options)
```

#### 10.1.4 Keep AIDP-Specific Code in AIDP

The following should remain in AIDP:
- `Aidp::Harness::Runner` (work loop orchestration)
- `Aidp::Harness::UsageLimit*` (usage limit enforcement)
- `Aidp::MessageDisplay` (TUI output)
- Watch mode components
- Workflow components
- AI Decision Engine (ZFC)

### 10.2 Compatibility Shim (Temporary)

For gradual migration, provide a compatibility shim:

```ruby
# lib/aidp/providers/base.rb (modified)
module Aidp
  module Providers
    class Base
      def initialize
        @agent_harness_provider = AgentHarness::Providers::Registry.instance.get(provider_name).new
      end

      def send_message(prompt:, **options)
        # Delegate to AgentHarness
        response = @agent_harness_provider.send_message(prompt: prompt, **options)

        # Convert to legacy format for backward compatibility
        legacy_response(response)
      end

      private

      def provider_name
        raise NotImplementedError
      end

      def legacy_response(response)
        response.output  # Or whatever the legacy format was
      end
    end
  end
end
```

---

## 11. Preparation Work (Pre-Extraction Refactoring)

Before beginning the extraction, several refactoring tasks can be performed in AIDP to create cleaner seams and reduce extraction complexity. This work can be done incrementally alongside planning.

### 11.1 AIDP-Specific Coupling to Remove

The following AIDP-specific dependencies are scattered throughout the provider and harness code:

| Coupling Type | Count | Files Affected | Abstraction Needed |
|---------------|-------|----------------|-------------------|
| `Aidp.log_*` calls | 150+ | 25+ | Logger interface |
| `TTY::*` components | 50+ | 6 | UI abstraction |
| `Aidp::Harness::*` classes | 20+ | 5 | Interface extraction |
| `ENV["AIDP_*"]` vars | 8 | 4 | Config provider |
| `.aidp/` file paths | 10+ | 4 | Path provider |
| `Aidp::Util.*` calls | 15+ | 8 | Utility interfaces |
| `Aidp::*` mixins | 10+ | 10 | Composition |

### 11.2 Pre-Extraction Refactoring Tasks

#### Phase 0A: Create Abstraction Interfaces (Can Start Immediately)

**Task 0A.1: Extract Logger Interface**
```ruby
# lib/aidp/interfaces/logger_interface.rb
module Aidp
  module Interfaces
    module LoggerInterface
      def log_debug(component, message, **context); end
      def log_info(component, message, **context); end
      def log_warn(component, message, **context); end
      def log_error(component, message, **context); end
    end
  end
end
```
- Create interface in AIDP
- Gradually migrate providers to use injected logger
- Agent-harness will use this same interface

**Task 0A.2: Extract Command Executor Interface**
```ruby
# lib/aidp/interfaces/command_executor_interface.rb
module Aidp
  module Interfaces
    module CommandExecutorInterface
      def execute(command, args:, input: nil, timeout: nil, env: {})
        # Returns Result with stdout, stderr, exit_code
      end
      def which(binary); end
    end
  end
end
```
- Replace `Aidp::Util.which()` and `debug_execute_command()` calls
- Inject executor into providers

**Task 0A.3: Extract Binary Checker Interface**
```ruby
# lib/aidp/interfaces/binary_checker_interface.rb
module Aidp
  module Interfaces
    module BinaryCheckerInterface
      def available?(binary_name, timeout: 3); end
      def version(binary_name); end
    end
  end
end
```
- Used by `available?()` checks in providers
- Can cache results with TTL

#### Phase 0B: Standardize Provider Implementations (Critical)

**Task 0B.1: Implement Missing Model Interface Methods**

GitHub Copilot is missing critical model methods:
- [ ] Add `MODEL_PATTERN` constant
- [ ] Add `discover_models()` class method
- [ ] Add `supports_model_family?()` class method
- [ ] Add `model_family()` class method
- [ ] Add `provider_model_name()` class method

**Task 0B.2: Standardize Error Patterns**

All providers should implement `error_patterns()`:
```ruby
def error_patterns
  {
    rate_limited: [/rate.?limit/i, /too many requests/i],
    auth_expired: [/unauthorized/i, /invalid.*key/i],
    quota_exceeded: [/quota/i, /billing/i],
    timeout: [/timeout/i, /timed.?out/i],
    transient: [/temporary/i, /retry/i],
    permanent: [/invalid/i, /malformed/i]
  }
end
```

Current status:
- ✅ Anthropic: Full implementation
- ❌ Cursor: Missing
- ❌ Gemini: Missing
- ❌ GitHub Copilot: Missing
- ❌ Codex: Missing
- ❌ Aider: Missing
- ❌ OpenCode: Missing
- ❌ Kilocode: Missing

**Task 0B.3: Standardize Input Passing Pattern**

Decide on canonical pattern and apply to all:
```ruby
# Option A: Use input parameter (preferred - separates prompt from flags)
debug_execute_command(binary, args: flags, input: prompt, timeout: timeout)

# Option B: Include in args (current mixed approach)
debug_execute_command(binary, args: [..., "--prompt", prompt], timeout: timeout)
```

Providers needing update if Option A chosen:
- Gemini
- GitHub Copilot
- Codex
- OpenCode

**Task 0B.4: Standardize Dangerous Mode Handling**

All providers should implement `dangerous_mode_flags()` from adapter:
```ruby
def dangerous_mode_flags
  ["--flag-for-this-provider"]  # or []
end
```

And use it in `build_command()`:
```ruby
def build_command(prompt, options)
  cmd = [...]
  cmd += dangerous_mode_flags if options[:dangerous_mode]
  cmd
end
```

**Task 0B.5: Document Session Parameter Interface**

Create standard interface for session handling:
```ruby
def session_flags(session_id)
  return [] unless session_id
  # Provider-specific implementation
end
```

Map current implementations:
- GitHub Copilot: `["--resume", session_id]`
- Codex: `["--session", session_id]`
- Aider: `["--restore-chat-history", session_id]`
- Others: `[]` (not supported)

#### Phase 0C: Extract Reusable Modules (Medium Priority)

**Task 0C.1: Extract Deprecation Handling**

Move Anthropic's deprecation logic to shared module:
```ruby
# lib/aidp/providers/concerns/deprecation_handler.rb
module Aidp
  module Providers
    module DeprecationHandler
      def check_model_deprecation(model, output); end
      def find_replacement_model(deprecated_model); end
      def deprecation_cache; end
    end
  end
end
```

**Task 0C.2: Extract Activity Monitoring**

Create module for stuck detection:
```ruby
# lib/aidp/providers/concerns/activity_monitor.rb
module Aidp
  module Providers
    module ActivityMonitor
      STATES = [:idle, :working, :stuck, :completed, :failed]

      def setup_activity_monitoring(timeout:, callback:); end
      def update_activity_state(state, message); end
    end
  end
end
```

**Task 0C.3: Extract Timeout Calculator**

Adaptive timeout logic as module:
```ruby
# lib/aidp/providers/concerns/timeout_calculator.rb
module Aidp
  module Providers
    module TimeoutCalculator
      TIER_MULTIPLIERS = {
        mini: 1.0, standard: 1.5, thinking: 6.0, pro: 8.0, max: 12.0
      }

      def calculate_timeout(options = {}); end
      def adaptive_timeout(tier); end
    end
  end
end
```

#### Phase 0D: Remove TTY Direct Dependencies (Before Extraction)

**Task 0D.1: Create UI Abstraction**
```ruby
# lib/aidp/interfaces/ui_interface.rb
module Aidp
  module Interfaces
    module UIInterface
      def spinner(message, &block); end
      def say(message); end
      def ask(prompt, **options); end
      def select(prompt, choices, **options); end
    end
  end
end
```

**Task 0D.2: Replace `include Aidp::MessageDisplay`**

Change from mixin to injected dependency:
```ruby
# Before
class Base
  include Aidp::MessageDisplay
  def initialize
    @prompt = TTY::Prompt.new
  end
end

# After
class Base
  def initialize(ui: nil)
    @ui = ui || NullUI.new
  end
end
```

### 11.3 Provider Standardization Checklist

Before extraction, verify all providers meet these criteria:

**Required Interface Methods:**
- [ ] `self.provider_name` - Returns symbol
- [ ] `self.binary_name` - Returns string
- [ ] `self.available?` - Returns boolean
- [ ] `self.firewall_requirements` - Returns {domains:, ip_ranges:}
- [ ] `self.instruction_file_paths` - Returns array of hashes
- [ ] `self.discover_models` - Returns array of model hashes
- [ ] `self.supports_model_family?(family)` - Returns boolean
- [ ] `send_message(prompt:, **options)` - Core method
- [ ] `capabilities` - Returns capability hash
- [ ] `error_patterns` - Returns pattern hash

**Optional but Recommended:**
- [ ] `self.model_family(model_name)` - Normalizes model name
- [ ] `self.provider_model_name(family)` - Converts family to provider format
- [ ] `dangerous_mode_flags` - Returns array of flags
- [ ] `session_flags(session_id)` - Returns array of flags

### 11.4 Files to Refactor Before Extraction

| File | Refactoring Needed | Priority |
|------|-------------------|----------|
| `providers/base.rb` | Remove `include MessageDisplay`, inject logger/UI | High |
| `providers/anthropic.rb` | Extract deprecation module, standardize | High |
| `providers/github_copilot.rb` | Add model interface methods | High |
| `providers/cursor.rb` | Add error_patterns, standardize input | Medium |
| `providers/gemini.rb` | Add error_patterns, standardize input | Medium |
| `providers/codex.rb` | Add error_patterns, standardize | Medium |
| `providers/aider.rb` | Add error_patterns, standardize | Medium |
| `providers/opencode.rb` | Add error_patterns, model methods | Medium |
| `providers/kilocode.rb` | Add error_patterns, model methods | Medium |
| `harness/provider_manager.rb` | Extract orchestration logic | High |
| `harness/provider_factory.rb` | Convert to registry pattern | High |

### 11.5 Preparation Timeline

| Week | Tasks | Outcome |
|------|-------|---------|
| Pre-1 | Tasks 0A.1-0A.3 (interfaces) | Clean injection points |
| Pre-2 | Tasks 0B.1-0B.5 (standardization) | Consistent providers |
| Pre-3 | Tasks 0C.1-0C.3 (modules) | Reusable components |
| Pre-4 | Tasks 0D.1-0D.2 (UI abstraction) | TTY-free core |

This preparation work can run in parallel with planning and will significantly reduce extraction complexity.

---

## 12. Migration Strategy (Post-Preparation)

### Phase 1: Create Gem Structure (Week 1)

1. Create new gem repository
2. Set up gem structure with bundler
3. Implement core classes (Configuration, CommandExecutor, Logger interface)
4. Implement Error classes and ErrorTaxonomy
5. Write initial tests

### Phase 2: Extract Provider Layer (Week 2)

1. Extract Provider Adapter interface
2. Extract Provider Base class (remove AIDP dependencies)
3. Extract individual providers one at a time:
   - Anthropic (Claude)
   - Cursor
   - Gemini
   - GitHub Copilot
   - Codex
   - Opencode
   - Kilocode
   - Aider
4. Implement Provider Registry
5. Add provider tests

### Phase 3: Extract Orchestration Layer (Week 3)

1. Extract CircuitBreaker
2. Extract RateLimiter
3. Extract HealthMonitor
4. Extract LoadBalancer
5. Extract ProviderManager
6. Implement Conductor
7. Add orchestration tests

### Phase 4: Configuration & Integration (Week 4)

1. Implement YAML configuration loading
2. Implement environment variable loading
3. Implement Ruby DSL configuration
4. Implement Rails Railtie (optional)
5. Implement TokenTracker
6. Add MCP support
7. Write integration tests (mocked)

### Phase 5: AIDP Integration (Week 5)

1. Add agent-harness gem to AIDP
2. Create AgentHarnessAdapter in AIDP
3. Update AIDP to use adapter
4. Ensure all existing tests pass
5. Remove extracted code from AIDP
6. Update documentation

### Phase 6: Polish & Release (Week 6)

1. Write comprehensive README
2. Write CHANGELOG
3. Add CI/CD pipeline
4. Publish gem (private or public)
5. Final testing in AIDP

---

## 13. Testing Strategy

### 13.1 Test Structure

```
spec/
├── spec_helper.rb
├── agent_harness_spec.rb
│
├── unit/
│   ├── configuration_spec.rb
│   ├── command_executor_spec.rb
│   ├── error_taxonomy_spec.rb
│   ├── token_tracker_spec.rb
│   │
│   ├── providers/
│   │   ├── registry_spec.rb
│   │   ├── base_spec.rb
│   │   ├── anthropic_spec.rb
│   │   ├── cursor_spec.rb
│   │   └── ...
│   │
│   └── orchestration/
│       ├── conductor_spec.rb
│       ├── provider_manager_spec.rb
│       ├── circuit_breaker_spec.rb
│       ├── rate_limiter_spec.rb
│       └── ...
│
└── integration/
    ├── configuration_integration_spec.rb
    └── orchestration_integration_spec.rb  # Mocked, no real API calls
```

### 13.2 Testing Principles

1. **Unit tests** for all classes
2. **Mocked integration tests** for end-to-end flows
3. **No real API/CLI calls** in automated tests
4. **Dependency injection** for testability
5. **Extract relevant specs** from AIDP during migration

### 13.3 Example Test

```ruby
# spec/unit/orchestration/circuit_breaker_spec.rb
RSpec.describe AgentHarness::Orchestration::CircuitBreaker do
  let(:config) do
    double(
      enabled: true,
      failure_threshold: 3,
      timeout: 60,
      half_open_max_calls: 2
    )
  end

  subject { described_class.new(config) }

  describe "#open?" do
    context "when below failure threshold" do
      it "returns false" do
        2.times { subject.record_failure }
        expect(subject.open?).to be false
      end
    end

    context "when at failure threshold" do
      it "returns true" do
        3.times { subject.record_failure }
        expect(subject.open?).to be true
      end
    end

    context "after timeout elapsed" do
      it "transitions to half-open" do
        3.times { subject.record_failure }
        expect(subject.open?).to be true

        Timecop.travel(61.seconds.from_now) do
          expect(subject.open?).to be false
          expect(subject.state).to eq(:half_open)
        end
      end
    end
  end

  describe "#record_success" do
    context "in half-open state" do
      before do
        3.times { subject.record_failure }
        Timecop.travel(61.seconds.from_now)
        subject.open?  # Trigger half-open transition
      end

      it "closes after enough successes" do
        2.times { subject.record_success }
        expect(subject.closed?).to be true
      end
    end
  end
end
```

---

## 14. Phased Implementation

### Summary Timeline

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| 1. Gem Structure | Week 1 | Core gem with configuration and errors |
| 2. Provider Layer | Week 2 | All providers extracted and working |
| 3. Orchestration | Week 3 | Full orchestration layer |
| 4. Configuration | Week 4 | All config methods, TokenTracker, MCP |
| 5. AIDP Integration | Week 5 | AIDP using gem, old code removed |
| 6. Polish & Release | Week 6 | Published gem, documentation |

### Success Criteria

1. **All existing AIDP features work** after migration
2. **No regression** in AIDP's test suite
3. **Gem is usable standalone** by other projects
4. **Configuration is flexible** (YAML, DSL, env vars)
5. **Dynamic provider registration** works
6. **Token tracking** provides data for usage limits
7. **Full orchestration** with circuit breakers, fallback, health monitoring

---

## Appendix A: File Mapping (AIDP → Gem)

| AIDP File | Gem File | Notes |
|-----------|----------|-------|
| `lib/aidp/providers/adapter.rb` | `lib/agent_harness/providers/adapter.rb` | Remove AIDP deps |
| `lib/aidp/providers/base.rb` | `lib/agent_harness/providers/base.rb` | Major refactor |
| `lib/aidp/providers/error_taxonomy.rb` | `lib/agent_harness/error_taxonomy.rb` | Minor changes |
| `lib/aidp/providers/anthropic.rb` | `lib/agent_harness/providers/anthropic.rb` | Remove AIDP deps |
| `lib/aidp/providers/cursor.rb` | `lib/agent_harness/providers/cursor.rb` | Remove AIDP deps |
| `lib/aidp/providers/gemini.rb` | `lib/agent_harness/providers/gemini.rb` | Remove AIDP deps |
| `lib/aidp/providers/*.rb` | `lib/agent_harness/providers/*.rb` | Each provider |
| `lib/aidp/harness/provider_factory.rb` | `lib/agent_harness/providers/registry.rb` | Redesigned |
| `lib/aidp/harness/provider_manager.rb` | `lib/agent_harness/orchestration/provider_manager.rb` | Refactored |
| `lib/aidp/concurrency/backoff.rb` | `lib/agent_harness/orchestration/retry_strategy.rb` | Internalized |
| `lib/aidp/config.rb` | `lib/agent_harness/configuration.rb` | New design |
| N/A | `lib/agent_harness/orchestration/conductor.rb` | New |
| N/A | `lib/agent_harness/orchestration/circuit_breaker.rb` | Extracted from PM |
| N/A | `lib/agent_harness/token_tracker.rb` | New |

---

## Appendix B: API Quick Reference

```ruby
# Basic usage
AgentHarness.send_message("Write a hello world function", provider: :claude)

# With configuration
AgentHarness.configure do |config|
  config.logger = Logger.new(STDOUT)
  config.default_provider = :cursor
end

# Direct provider access
provider = AgentHarness.provider(:claude)
provider.send_message(prompt: "Hello")

# Orchestration control
conductor = AgentHarness.conductor
conductor.status
conductor.reset!

# Token tracking
AgentHarness.token_tracker.summary(since: 1.hour.ago)

# Provider registration
AgentHarness.configure do |config|
  config.register_provider :my_agent, MyAgentProvider
end
```

---

## Appendix C: Design Decisions

### C.1 Persistence Strategy

**Decision:** Agent-harness is stateless. It publishes data via callbacks but does not persist anything.

Consumers receive data through callbacks and handle their own persistence:
```ruby
AgentHarness.configure do |config|
  config.on_tokens_used do |event|
    MyDatabase.save_token_usage(event)
  end

  config.on_provider_health_change do |event|
    MyMetricsStore.record_health(event)
  end

  config.on_circuit_state_change do |event|
    Redis.set("circuit:#{event.provider}", event.state)
  end
end
```

### C.2 Activity Monitoring & Stuck Detection

**Decision:** Include activity monitoring with stuck detection.

```ruby
# Provider tracks activity state
provider.on_activity_change do |state, message|
  # state: :idle, :working, :stuck, :completed, :failed
  case state
  when :stuck
    # Provider hasn't produced output for configured timeout
    notify_user("Provider appears stuck: #{message}")
  end
end
```

### C.3 Timeouts

**Decision:** Use simple configurable timeouts (not adaptive).

```ruby
AgentHarness.configure do |config|
  config.default_timeout = 300  # 5 minutes

  config.provider :claude do |p|
    p.timeout = 600  # 10 minutes for Claude
  end
end
```

### C.4 Model-Level Management

**Decision:** Agent-harness tracks and publishes model-level data (health, metrics, circuit state) but consumers decide what to do with it.

The gem publishes:
- Model health events
- Model metrics events
- Model circuit breaker state changes

Consumers handle:
- Persistence of model state
- Model denylisting decisions
- Model fallback chain configuration

### C.5 Binary Availability Checking

**Decision:** Include binary availability checking with caching.

```ruby
# Check if provider CLI is available
AgentHarness::Providers::Anthropic.available?  # => true/false

# Includes version check with timeout
# Results cached with configurable TTL (default 5 minutes)
```

### C.6 Health Score Calculation

**Decision:** Include health score calculation.

```ruby
# Health score formula
health_score = (success_rate * 50) +
               ((1 - rate_limit_ratio) * 30) +
               (response_time_score * 20)

# Exposed via
provider.health_score        # => 0.0 - 100.0
provider.healthy?            # => true if health_score > 50
```

### C.7 Ruby Version Compatibility

**Decision:**
- Minimum: Ruby 3.3
- CI Matrix: Ruby 3.3, 3.4, 4.0

### C.8 Thread Safety & Process Forking

**Decision:** Not addressed in v1. Documented as single-threaded, single-process design. May address in future versions.

### C.9 Gem Distribution

**Decision:** Public RubyGems.org

```bash
gem install agent-harness
```

### C.10 Documentation

**Decision:** RDoc for API documentation.

```bash
rdoc lib/
```

Additional:
- README with quick start guide
- Examples directory
- CHANGELOG (auto-generated via release-please)

### C.11 CLI Tool

**Decision:** Include CLI for testing and validation.

```bash
# Test provider connectivity
agent-harness test claude

# Validate configuration
agent-harness validate

# Check provider health
agent-harness health

# Quick prompt (for testing)
agent-harness prompt "Hello world" --provider claude

# List available providers
agent-harness providers
```

### C.12 Observability

**Decision:** Support OpenTelemetry (OTEL) for tracing and metrics.

```ruby
AgentHarness.configure do |config|
  config.otel_enabled = true
  # Uses OTEL_* environment variables for configuration
end
```

Emits:
- `agent_harness.request` spans with provider, model, duration attributes
- `agent_harness.requests_total` counter
- `agent_harness.request_duration_seconds` histogram
- `agent_harness.tokens_used_total` counter

### C.13 Security

**Decision:**
- Agent-harness does NOT store secrets in configuration or files
- Provides helpers to check if user is logged into provider CLIs
- Authentication to providers is out of scope (users log in via provider CLIs directly)

```ruby
# Check login status
AgentHarness.provider(:claude).authenticated?  # => true/false

# Require authentication before use
AgentHarness.configure do |config|
  config.require_authentication = true  # Raises if not logged in
end
```

### C.14 Hooks/Middleware

**Decision:** Not in v1. May add in future versions.

### C.15 Debug Mode

**Decision:** Use `AGENT_HARNESS_DEBUG=1` environment variable for enhanced logging.

```bash
AGENT_HARNESS_DEBUG=1 ruby my_script.rb
```

No dry-run mode.

### C.16 Graceful Degradation

**Decision:** When all providers fail, raise `NoProvidersAvailableError`.

```ruby
begin
  AgentHarness.send_message("prompt")
rescue AgentHarness::NoProvidersAvailableError => e
  # All providers exhausted
  puts e.attempted_providers  # [:claude, :cursor, :gemini]
  puts e.errors               # { claude: "Rate limited", ... }
end
```

### C.17 Provider Authentication

**Decision:** Out of scope. Users authenticate directly with provider CLIs:
- `claude login`
- `gh auth login`
- `gcloud auth login`

Agent-harness only checks authentication status, does not perform authentication.

### C.18 Versioning & Releases

**Decision:**
- Semantic Versioning (SemVer)
- Conventional Commits for commit messages
- release-please for automated releases and changelog generation

Commit message format:
```
feat: add cursor provider support
fix: handle rate limit errors correctly
feat!: change Response API (BREAKING)
docs: update README
chore: update dependencies
```
