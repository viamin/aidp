# frozen_string_literal: true

require "tty-prompt"
require "tty-spinner"
require_relative "adapter"

module Aidp
  module Providers
    class ProviderUnavailableError < StandardError; end

    class Base
      include Aidp::MessageDisplay
      include Aidp::Providers::Adapter

      # Activity indicator states
      ACTIVITY_STATES = {
        idle: "⏳",
        working: "🔄",
        stuck: "⚠️",
        completed: "✅",
        failed: "❌"
      }.freeze

      # Default timeout for stuck detection (2 minutes)
      DEFAULT_STUCK_TIMEOUT = 120

      # Configurable timeout values (can be overridden via environment or config)
      # These defaults provide reasonable values for different execution scenarios
      TIMEOUT_QUICK_MODE = 120 # 2 minutes - for quick testing
      TIMEOUT_DEFAULT = 300 # 5 minutes - standard interactive timeout
      TIMEOUT_REPOSITORY_ANALYSIS = 180 # 3 minutes - repository analysis
      TIMEOUT_ARCHITECTURE_ANALYSIS = 600 # 10 minutes - architecture analysis
      TIMEOUT_TEST_ANALYSIS = 300 # 5 minutes - test analysis
      TIMEOUT_FUNCTIONALITY_ANALYSIS = 600 # 10 minutes - functionality analysis
      TIMEOUT_DOCUMENTATION_ANALYSIS = 300 # 5 minutes - documentation analysis
      TIMEOUT_STATIC_ANALYSIS = 450 # 7.5 minutes - static analysis
      TIMEOUT_REFACTORING_RECOMMENDATIONS = 600 # 10 minutes - refactoring
      TIMEOUT_IMPLEMENTATION = 900 # 15 minutes - implementation (write files, run tests, fix issues)

      # Tier-based timeout multipliers (applied on top of base timeouts)
      # Higher tiers need more time for deeper reasoning
      TIER_TIMEOUT_MULTIPLIERS = {
        "mini" => 1.0,      # 5 minutes default (300s base)
        "standard" => 2.0,  # 10 minutes default (600s base)
        "thinking" => 6.0,  # 30 minutes default (1800s base)
        "pro" => 6.0,       # 30 minutes default (1800s base)
        "max" => 12.0       # 60 minutes default (3600s base)
      }.freeze

      attr_reader :activity_state, :last_activity_time, :start_time, :step_name, :model
      # Expose for testability
      attr_writer :harness_context

      def initialize(output: nil, prompt: TTY::Prompt.new)
        @activity_state = :idle
        @last_activity_time = Time.now
        @start_time = nil
        @step_name = nil
        @activity_callback = nil
        @stuck_timeout = DEFAULT_STUCK_TIMEOUT
        @output_count = 0
        @last_output_time = Time.now
        @job_context = nil
        @harness_context = nil
        @output = output
        @prompt = prompt
        @model = nil
        @harness_metrics = {
          total_requests: 0,
          successful_requests: 0,
          failed_requests: 0,
          rate_limited_requests: 0,
          total_tokens_used: 0,
          total_cost: 0.0,
          average_response_time: 0.0,
          last_request_time: nil
        }
      end

      def name
        raise NotImplementedError, "#{self.class} must implement #name"
      end

      # Human-friendly display name for UI
      # Override in subclasses to provide a better display name
      def display_name
        name
      end

      # Configure the provider with options
      # @param config [Hash] Configuration options, may include :model
      def configure(config)
        if config[:model]
          @model = resolve_model_name(config[:model].to_s)
        end
      end

      def send_message(prompt:, session: nil, options: {})
        raise NotImplementedError, "#{self.class} must implement #send_message"
      end

      # Fetch MCP servers configured for this provider
      # Returns an array of server hashes with keys: :name, :status, :description, :enabled
      # Override in subclasses to provide provider-specific MCP server detection
      def fetch_mcp_servers
        []
      end

      # Check if this provider supports MCP servers
      # Override in subclasses to provide accurate MCP support detection
      def supports_mcp?
        false
      end

      # Set job context for background execution
      def set_job_context(job_id:, execution_id:, job_manager:)
        @job_context = {
          job_id: job_id,
          execution_id: execution_id,
          job_manager: job_manager
        }
      end

      # Set up activity monitoring for a step
      def setup_activity_monitoring(step_name, activity_callback = nil, stuck_timeout = nil)
        @step_name = step_name
        @activity_callback = activity_callback
        @stuck_timeout = stuck_timeout || DEFAULT_STUCK_TIMEOUT
        @start_time = Time.now
        @last_activity_time = @start_time
        @output_count = 0
        @last_output_time = @start_time
        update_activity_state(:working)
      end

      # Update activity state and notify callback
      def update_activity_state(state, message = nil)
        @activity_state = state
        @last_activity_time = Time.now if state == :working

        # Log state change to job if in background mode
        if @job_context
          level = case state
          when :completed then "info"
          when :failed then "error"
          else "debug"
          end

          log_to_job(message || "Provider state changed to #{state}", level)
        end

        @activity_callback&.call(state, message, self)
      end

      # Check if provider appears to be stuck
      def stuck?
        return false unless @activity_state == :working

        time_since_activity = Time.now - @last_activity_time
        time_since_activity > @stuck_timeout
      end

      # Get current execution time
      def execution_time
        return 0 unless @start_time
        Time.now - @start_time
      end

      # Get time since last activity
      def time_since_last_activity
        Time.now - @last_activity_time
      end

      # Record activity (called when provider produces output)
      def record_activity(message = nil)
        @output_count += 1
        @last_output_time = Time.now
        update_activity_state(:working, message)
      end

      # Mark as completed
      def mark_completed
        update_activity_state(:completed)
      end

      # Mark as failed
      def mark_failed(error_message = nil)
        update_activity_state(:failed, error_message)
      end

      # Get activity summary for metrics
      def activity_summary
        {
          provider: name,
          step_name: @step_name,
          start_time: @start_time&.iso8601,
          end_time: Time.now.iso8601,
          duration: execution_time,
          final_state: @activity_state,
          stuck_detected: stuck?,
          output_count: @output_count
        }
      end

      # Check if provider supports activity monitoring
      def supports_activity_monitoring?
        true # Default to true, override in subclasses if needed
      end

      # Get stuck timeout for this provider
      attr_reader :stuck_timeout

      # Harness integration methods

      # Set harness context for provider
      def set_harness_context(harness_runner)
        @harness_context = harness_runner
      end

      # Check if provider is operating in harness mode
      def harness_mode?
        !@harness_context.nil?
      end

      # Get harness metrics
      def harness_metrics
        @harness_metrics.dup
      end

      # Record harness request metrics
      def record_harness_request(success:, tokens_used: 0, cost: 0.0, response_time: 0.0, rate_limited: false)
        @harness_metrics[:total_requests] += 1
        @harness_metrics[:last_request_time] = Time.now

        if success
          @harness_metrics[:successful_requests] += 1
        else
          @harness_metrics[:failed_requests] += 1
        end

        if rate_limited
          @harness_metrics[:rate_limited_requests] += 1
        end

        @harness_metrics[:total_tokens_used] += tokens_used
        @harness_metrics[:total_cost] += cost

        # Update average response time
        total_time = @harness_metrics[:average_response_time] * (@harness_metrics[:total_requests] - 1) + response_time
        @harness_metrics[:average_response_time] = total_time / @harness_metrics[:total_requests]

        # Notify harness context if available
        @harness_context&.record_provider_metrics(name, @harness_metrics)
      end

      # Get provider health status for harness
      def harness_health_status
        {
          provider: name,
          activity_state: @activity_state,
          stuck: stuck?,
          success_rate: calculate_success_rate,
          average_response_time: @harness_metrics[:average_response_time],
          total_requests: @harness_metrics[:total_requests],
          rate_limit_ratio: calculate_rate_limit_ratio,
          last_activity: @last_activity_time,
          health_score: calculate_health_score
        }
      end

      # Check if provider is healthy for harness use
      def harness_healthy?
        return false if stuck?
        return false if @harness_metrics[:total_requests] > 0 && calculate_success_rate < 0.5
        return false if calculate_rate_limit_ratio > 0.3

        true
      end

      # Get provider configuration for harness
      def harness_config
        {
          name: name,
          supports_activity_monitoring: supports_activity_monitoring?,
          default_timeout: @stuck_timeout,
          available: available?,
          health_status: harness_health_status
        }
      end

      # Check if provider is available (override in subclasses)
      def available?
        true # Default to true, override in subclasses
      end

      # Enhanced send method that integrates with harness
      def send_with_harness(prompt:, session: nil, _options: {})
        start_time = Time.now
        success = false
        rate_limited = false
        tokens_used = 0
        cost = 0.0
        error_message = nil

        begin
          # Call the original send_message method
          result = send_message(prompt: prompt, session: session)
          success = true

          # Extract token usage and cost if available
          if result.is_a?(Hash) && result[:token_usage]
            tokens_used = result[:token_usage][:total] || 0
            cost = result[:token_usage][:cost] || 0.0
          end

          # Check for rate limiting in result
          if result.is_a?(Hash) && result[:rate_limited]
            rate_limited = true
          end

          result
        rescue => e
          error_message = e.message

          # Check if error is rate limiting
          if e.message.match?(/rate.?limit/i) || e.message.match?(/quota/i) || e.message.match?(/session limit/i)
            rate_limited = true
          end

          raise e
        ensure
          response_time = Time.now - start_time
          record_harness_request(
            success: success,
            tokens_used: tokens_used,
            cost: cost,
            response_time: response_time,
            rate_limited: rate_limited
          )

          # Log to harness context if available
          if @harness_context && error_message
            @harness_context.record_provider_error(name, error_message, rate_limited)
          end
        end
      end

      # Helper method for registry-based model discovery
      #
      # Providers that use the model registry can call this method to discover models
      # based on a model family pattern.
      #
      # @param model_pattern [Regexp] Pattern to match model families
      # @param provider_name [String] Name of the provider
      # @return [Array<Hash>] Array of discovered models
      def self.discover_models_from_registry(model_pattern, provider_name)
        require_relative "../harness/model_registry"
        registry = Aidp::Harness::ModelRegistry.new

        # Get all models from registry that match the pattern
        models = registry.all_families.filter_map do |family|
          next unless model_pattern.match?(family)

          info = registry.get_model_info(family)
          next unless info

          {
            name: family,
            family: family,
            tier: info["tier"],
            capabilities: info["capabilities"] || [],
            context_window: info["context_window"],
            provider: provider_name
          }
        end

        Aidp.log_info("#{provider_name}_provider", "using registry models", count: models.size)
        models
      rescue => e
        Aidp.log_debug("#{provider_name}_provider", "discovery failed", error: e.message)
        []
      end

      # Get firewall requirements for this provider
      #
      # Returns domains and IP ranges that need to be accessible for this provider
      # to function properly. Used by devcontainer firewall configuration.
      #
      # @return [Hash] Firewall requirements with :domains and :ip_ranges keys
      #   - domains: Array of domain strings
      #   - ip_ranges: Array of CIDR strings
      #
      # Override in subclasses to provide provider-specific requirements
      def self.firewall_requirements
        {
          domains: [],
          ip_ranges: []
        }
      end

      # Get instruction file paths for this provider
      #
      # Returns an array of file paths where this provider looks for agent instructions.
      # These paths are relative to the project root.
      #
      # @return [Array<Hash>] Array of instruction file info with keys:
      #   - path: Relative file path (e.g., "CLAUDE.md")
      #   - description: Human-readable description of the file
      #   - symlink: Whether this should be a symlink to AGENTS.md (optional, default: true)
      #
      # Override in subclasses to provide provider-specific instruction file paths
      def self.instruction_file_paths
        []
      end

      protected

      # Log message to job if in background mode
      def log_to_job(message, level = "info", metadata = {})
        return unless @job_context && @job_context[:job_manager]

        metadata = metadata.merge(
          provider: name,
          step_name: @step_name,
          activity_state: @activity_state,
          execution_time: execution_time,
          output_count: @output_count
        )

        @job_context[:job_manager].log_message(
          @job_context[:job_id],
          @job_context[:execution_id],
          message,
          level,
          metadata
        )
      end

      # Calculate success rate for harness metrics
      def calculate_success_rate
        return 1.0 if @harness_metrics[:total_requests] == 0
        @harness_metrics[:successful_requests].to_f / @harness_metrics[:total_requests]
      end

      # Calculate rate limit ratio for harness metrics
      def calculate_rate_limit_ratio
        return 0.0 if @harness_metrics[:total_requests] == 0
        @harness_metrics[:rate_limited_requests].to_f / @harness_metrics[:total_requests]
      end

      # Calculate overall health score for harness
      def calculate_health_score
        return 100.0 if @harness_metrics[:total_requests] == 0

        success_rate = calculate_success_rate
        rate_limit_ratio = calculate_rate_limit_ratio
        response_time_score = [100 - (@harness_metrics[:average_response_time] * 10), 0].max

        # Weighted health score
        (success_rate * 50) + ((1 - rate_limit_ratio) * 30) + (response_time_score * 0.2)
      end

      # Update spinner status with elapsed time
      # This is a shared method used by all providers to display progress
      def update_spinner_status(spinner, elapsed, provider_name)
        minutes = (elapsed / 60).to_i
        seconds = (elapsed % 60).to_i

        if minutes > 0
          spinner.update(title: "#{provider_name} is running... (#{minutes}m #{seconds}s)")
        else
          spinner.update(title: "#{provider_name} is running... (#{seconds}s)")
        end
      end

      # Clean up activity display thread and spinner
      # Used by providers to ensure proper cleanup in both success and error paths
      def cleanup_activity_display(activity_display_thread, spinner)
        activity_display_thread.kill if activity_display_thread&.alive?
        activity_display_thread&.join(0.1) # Give it 100ms to finish
        spinner&.stop
      end

      # Check if we should skip permissions based on devcontainer/codespace environment
      # This enables providers to run with elevated permissions in safe development environments
      # Returns true if running in a devcontainer or GitHub Codespace
      def in_devcontainer_or_codespace?
        ENV["REMOTE_CONTAINERS"] == "true" || ENV["CODESPACES"] == "true"
      end

      # Check if provider should skip sandbox permissions
      # Providers can override this to add additional logic beyond environment detection
      def should_skip_permissions?
        # First, check for devcontainer/codespace environment (most reliable)
        return true if in_devcontainer_or_codespace?

        # Fallback: Check if harness context is available and has configuration
        return false unless @harness_context

        # Get configuration from harness
        config = @harness_context.config
        return false unless config

        # Use configuration method to determine if full permissions should be used
        # Provider subclasses should pass their provider name
        false # Base implementation returns false, subclasses should override
      end

      # Calculate timeout for provider operations
      #
      # Priority order:
      # 1. Quick mode (for testing)
      # 2. Provider-specific environment variable override
      # 3. Adaptive timeout based on step type and thinking tier
      # 4. Default timeout (with tier multiplier)
      #
      # Override provider_env_var to customize the environment variable name
      # @param options [Hash] Options hash that may include :tier
      def calculate_timeout(options = {})
        if ENV["AIDP_QUICK_MODE"]
          display_message("⚡ Quick mode enabled - #{TIMEOUT_QUICK_MODE / 60} minute timeout", type: :highlight)
          return TIMEOUT_QUICK_MODE
        end

        provider_env_var = "AIDP_#{name.upcase}_TIMEOUT"
        return ENV[provider_env_var].to_i if ENV[provider_env_var]

        tier = options[:tier]&.to_s
        step_timeout = adaptive_timeout(tier)
        if step_timeout
          tier_label = tier ? " (tier: #{tier})" : ""
          display_message("🧠 Using adaptive timeout: #{step_timeout} seconds#{tier_label}", type: :info)
          return step_timeout
        end

        # Default timeout with tier multiplier
        base_timeout = TIMEOUT_DEFAULT
        final_timeout = apply_tier_multiplier(base_timeout, tier)
        tier_label = tier ? " (tier: #{tier})" : ""
        display_message("📋 Using default timeout: #{final_timeout / 60} minutes#{tier_label}", type: :info)
        final_timeout
      end

      # Get adaptive timeout based on step type and thinking tier
      #
      # This method returns different timeout values based on the type of operation
      # being performed, as indicated by the AIDP_CURRENT_STEP environment variable,
      # and applies a multiplier based on the thinking tier (mini/standard/thinking/pro/max).
      # Returns nil for unknown steps to allow calculate_timeout to use the default.
      #
      # @param tier [String, nil] The thinking tier (mini, standard, thinking, pro, max)
      def adaptive_timeout(tier = nil)
        # Don't cache - tier may change between calls
        step_name = ENV["AIDP_CURRENT_STEP"] || ""

        base_timeout = case step_name
        when /REPOSITORY_ANALYSIS/
          TIMEOUT_REPOSITORY_ANALYSIS
        when /ARCHITECTURE_ANALYSIS/
          TIMEOUT_ARCHITECTURE_ANALYSIS
        when /TEST_ANALYSIS/
          TIMEOUT_TEST_ANALYSIS
        when /FUNCTIONALITY_ANALYSIS/
          TIMEOUT_FUNCTIONALITY_ANALYSIS
        when /DOCUMENTATION_ANALYSIS/
          TIMEOUT_DOCUMENTATION_ANALYSIS
        when /STATIC_ANALYSIS/
          TIMEOUT_STATIC_ANALYSIS
        when /REFACTORING_RECOMMENDATIONS/
          TIMEOUT_REFACTORING_RECOMMENDATIONS
        when /IMPLEMENTATION/
          TIMEOUT_IMPLEMENTATION
        else
          nil # Return nil for unknown steps
        end

        return nil unless base_timeout

        apply_tier_multiplier(base_timeout, tier)
      end

      # Apply tier-based multiplier to a base timeout
      #
      # @param base_timeout [Integer] The base timeout in seconds
      # @param tier [String, nil] The thinking tier (mini, standard, thinking, pro, max)
      # @return [Integer] The adjusted timeout with tier multiplier applied
      def apply_tier_multiplier(base_timeout, tier)
        return base_timeout unless tier

        multiplier = TIER_TIMEOUT_MULTIPLIERS[tier.to_s] || 1.0
        (base_timeout * multiplier).to_i
      end

      # Resolve a model name using the RubyLLM registry
      #
      # Attempts to resolve a model family name (e.g., "claude-3-5-haiku") to a
      # versioned model name (e.g., "claude-3-5-haiku-20241022") using the RubyLLM
      # registry. Falls back to using the name as-is if resolution fails.
      #
      # @param model_name [String] The model family name or versioned name
      # @return [String] The resolved model name (versioned if found, original if not)
      def resolve_model_name(model_name)
        require_relative "../harness/ruby_llm_registry" unless defined?(Aidp::Harness::RubyLLMRegistry)

        begin
          registry = Aidp::Harness::RubyLLMRegistry.new
          resolved = registry.resolve_model(model_name, provider: name)

          if resolved
            Aidp.log_debug(name, "Resolved model using registry",
              requested: model_name,
              resolved: resolved)
            resolved
          else
            # Fall back to using the name as-is
            Aidp.log_warn(name, "Model not found in registry, using as-is",
              model: model_name)
            model_name
          end
        rescue => e
          # If registry fails, fall back to using the name as-is
          Aidp.log_error(name, "Registry lookup failed, using model name as-is",
            model: model_name,
            error: e.message)
          model_name
        end
      end

      private
    end
  end
end
