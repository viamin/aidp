# frozen_string_literal: true

require "json"
require_relative "base"
require_relative "../debug_mixin"
require_relative "../harness/deprecation_cache"

module Aidp
  module Providers
    class Anthropic < Base
      include Aidp::DebugMixin

      attr_reader :model

      # Model name pattern for Anthropic Claude models
      MODEL_PATTERN = /^claude-[\d.-]+-(?:opus|sonnet|haiku)(?:-\d{8})?$/i

      # Get deprecation cache instance (lazy loaded)
      def self.deprecation_cache
        @deprecation_cache ||= Aidp::Harness::DeprecationCache.new
      end

      def self.available?
        !!Aidp::Util.which("claude")
      end

      # Normalize a provider-specific model name to its model family
      #
      # Anthropic uses date-versioned models (e.g., "claude-3-5-sonnet-20241022").
      # This method strips the date suffix to get the family name.
      #
      # @param provider_model_name [String] The versioned model name
      # @return [String] The model family name (e.g., "claude-3-5-sonnet")
      def self.model_family(provider_model_name)
        # Strip date suffix: "claude-3-5-sonnet-20241022" → "claude-3-5-sonnet"
        provider_model_name.sub(/-\d{8}$/, "")
      end

      # Convert a model family name to the provider's preferred model name
      #
      # Returns the family name as-is. Users can configure specific versions in aidp.yml.
      #
      # @param family_name [String] The model family name
      # @return [String] The model name (same as family for flexibility)
      def self.provider_model_name(family_name)
        family_name
      end

      # Check if this provider supports a given model family
      #
      # @param family_name [String] The model family name
      # @return [Boolean] True if it matches Claude model pattern
      def self.supports_model_family?(family_name)
        MODEL_PATTERN.match?(family_name)
      end

      # Discover available models from Claude CLI
      #
      # @return [Array<Hash>] Array of discovered models
      def self.discover_models
        return [] unless available?

        begin
          require "open3"
          output, _, status = Open3.capture3("claude", "models", "list", {timeout: 10})
          return [] unless status.success?

          parse_models_list(output)
        rescue => e
          Aidp.log_debug("anthropic_provider", "discovery failed", error: e.message)
          []
        end
      end

      # Get firewall requirements for Anthropic provider
      def self.firewall_requirements
        {
          domains: [
            "api.anthropic.com",
            "claude.ai",
            "console.anthropic.com"
          ],
          ip_ranges: []
        }
      end

      class << self
        private

        def parse_models_list(output)
          return [] if output.nil? || output.empty?

          models = []
          lines = output.lines.map(&:strip)

          # Skip header and separator lines
          lines.reject! { |line| line.empty? || line.match?(/^[-=]+$/) || line.match?(/^(Model|Name)/i) }

          lines.each do |line|
            model_info = parse_model_line(line)
            models << model_info if model_info
          end

          Aidp.log_info("anthropic_provider", "discovered models", count: models.size)
          models
        end

        def parse_model_line(line)
          # Format 1: Simple list of model names
          if line.match?(/^claude-\d/)
            model_name = line.split.first
            return build_model_info(model_name)
          end

          # Format 2: Table format with columns
          parts = line.split(/\s{2,}/)
          if parts.size >= 1 && parts[0].match?(/^claude/)
            model_name = parts[0]
            model_name = "#{model_name}-#{parts[1]}" if parts.size > 1 && parts[1].match?(/^\d{8}$/)
            return build_model_info(model_name)
          end

          # Format 3: JSON-like or key-value pairs
          if line.match?(/name:\s*(.+)/)
            model_name = $1.strip
            return build_model_info(model_name)
          end

          nil
        end

        def build_model_info(model_name)
          family = model_family(model_name)
          tier = classify_tier(model_name)

          {
            name: model_name,
            family: family,
            tier: tier,
            capabilities: extract_capabilities(model_name),
            context_window: infer_context_window(family),
            provider: "anthropic"
          }
        end

        def classify_tier(model_name)
          name_lower = model_name.downcase
          return "advanced" if name_lower.include?("opus")
          return "mini" if name_lower.include?("haiku")
          return "standard" if name_lower.include?("sonnet")
          "standard"
        end

        def extract_capabilities(model_name)
          capabilities = ["chat", "code"]
          name_lower = model_name.downcase
          capabilities << "vision" unless name_lower.include?("haiku")
          capabilities
        end

        def infer_context_window(family)
          family.match?(/claude-3/) ? 200_000 : nil
        end
      end

      # Public instance methods (called from workflows and harness)
      public

      def name
        "anthropic"
      end

      def display_name
        "Anthropic Claude CLI"
      end

      def supports_mcp?
        true
      end

      def fetch_mcp_servers
        return [] unless self.class.available?

        begin
          # Use claude mcp list command
          result = debug_execute_command("claude", args: ["mcp", "list"], timeout: 5)
          return [] unless result.exit_status == 0

          parse_claude_mcp_output(result.out)
        rescue => e
          debug_log("Failed to fetch MCP servers via Claude CLI: #{e.message}", level: :debug)
          []
        end
      end

      def available?
        self.class.available?
      end

      # ProviderAdapter interface methods

      def capabilities
        {
          reasoning_tiers: ["mini", "standard", "thinking"],
          context_window: 200_000,
          supports_json_mode: true,
          supports_tool_use: true,
          supports_vision: false,
          supports_file_upload: true
        }
      end

      def supports_dangerous_mode?
        true
      end

      def dangerous_mode_flags
        ["--dangerously-skip-permissions"]
      end

      # Classify provider error using string matching
      #
      # ZFC EXCEPTION: Cannot use AI to classify provider errors because:
      # 1. The failing provider IS the AI we'd use for classification (circular dependency)
      # 2. Provider may be rate-limited, down, or misconfigured
      # 3. Error classification must work even when AI unavailable
      #
      # This is a legitimate exception to ZFC principles per LLM_STYLE_GUIDE:
      # "Structural safety checks" are allowed in code when AI cannot be used.
      #
      # @param error_message [String] The error message to classify
      # @return [Hash] Classification result with :type, :is_deprecation, :is_rate_limit, :confidence
      def self.classify_provider_error(error_message)
        msg_lower = error_message.downcase

        # Use simple string.include? checks (not regex) to avoid ReDoS vulnerabilities
        is_rate_limit = msg_lower.include?("rate limit") || msg_lower.include?("session limit")
        is_deprecation = msg_lower.include?("deprecat") || msg_lower.include?("end-of-life")
        is_auth_error = msg_lower.include?("auth") && (msg_lower.include?("expired") || msg_lower.include?("invalid"))

        # Determine primary type
        type = if is_rate_limit
          "rate_limit"
        elsif is_deprecation
          "deprecation"
        elsif is_auth_error
          "auth_error"
        else
          "other"
        end

        Aidp.log_debug("anthropic", "Provider error classification",
          type: type,
          is_rate_limit: is_rate_limit,
          is_deprecation: is_deprecation,
          is_auth_error: is_auth_error)

        {
          type: type,
          is_rate_limit: is_rate_limit,
          is_deprecation: is_deprecation,
          is_auth_error: is_auth_error,
          confidence: 0.85, # Good confidence for clear error messages
          reasoning: "Pattern-based classification (ZFC exception: circular dependency)"
        }
      end

      # Error patterns for classify_error method (legacy support)
      # NOTE: ZFC-based classification preferred - see classify_error_with_zfc
      # These patterns serve as fallback when ZFC is unavailable
      def error_patterns
        {
          rate_limited: [
            /rate.?limit/i,
            /too.?many.?requests/i,
            /429/,
            /overloaded/i
          ],
          auth_expired: [
            /oauth.*token.*expired/i,
            /authentication.*error/i,
            /invalid.*api.*key/i,
            /unauthorized/i,
            /401/
          ],
          quota_exceeded: [
            /quota.*exceeded/i,
            /usage.*limit/i,
            /credit.*exhausted/i
          ],
          transient: [
            /timeout/i,
            /connection.*reset/i,
            /temporary.*error/i,
            /service.*unavailable/i,
            /503/,
            /502/,
            /504/
          ],
          permanent: [
            /invalid.*model/i,
            /unsupported.*operation/i,
            /not.*found/i,
            /404/,
            /bad.*request/i,
            /400/,
            /model.*deprecated/i,
            /end-of-life/i
          ]
        }
      end

      # Check if a model is deprecated and return replacement
      # @param model_name [String] The model name to check
      # @return [String, nil] Replacement model name if deprecated, nil otherwise
      def self.check_model_deprecation(model_name)
        deprecation_cache.replacement_for(provider: "anthropic", model_id: model_name)
      end

      # Find replacement model for deprecated one using RubyLLM registry
      # @param deprecated_model [String] The deprecated model name
      # @param provider_name [String] Provider name for registry lookup
      # @return [String, nil] Latest model in the same family, or configured replacement
      def self.find_replacement_model(deprecated_model, provider_name: "anthropic")
        # First check the deprecation cache for explicit replacement
        replacement = deprecation_cache.replacement_for(provider: provider_name, model_id: deprecated_model)
        return replacement if replacement

        # Try to find latest model in same family using registry
        require_relative "../harness/ruby_llm_registry" unless defined?(Aidp::Harness::RubyLLMRegistry)

        begin
          registry = Aidp::Harness::RubyLLMRegistry.new

          # Search for non-deprecated models in the same family
          # Prefer models without "latest" suffix, sorted by ID (newer dates first)
          models = registry.models_for_provider(provider_name)
          candidates = models.select { |m| m.include?("sonnet") && !deprecation_cache.deprecated?(provider: provider_name, model_id: m) }

          # Prioritize: versioned models over -latest, newer versions first
          versioned = candidates.reject { |m| m.end_with?("-latest") }.sort.reverse
          latest_models = candidates.select { |m| m.end_with?("-latest") }

          replacement = versioned.first || latest_models.first

          if replacement
            Aidp.log_info("anthropic", "Found replacement model",
              deprecated: deprecated_model,
              replacement: replacement)
          end

          replacement
        rescue => e
          Aidp.log_error("anthropic", "Failed to find replacement model",
            deprecated: deprecated_model,
            error: e.message)
          nil
        end
      end

      def send_message(prompt:, session: nil, options: {})
        raise "claude CLI not available" unless self.class.available?

        # Check if current model is deprecated and warn
        if @model && (replacement = self.class.check_model_deprecation(@model))
          Aidp.log_warn("anthropic", "Using deprecated model",
            current: @model,
            replacement: replacement)
          debug_log("⚠️  Model #{@model} is deprecated. Consider upgrading to #{replacement}", level: :warn)
        end

        # Smart timeout calculation with tier awareness
        timeout_seconds = calculate_timeout(options)

        debug_provider("claude", "Starting execution", {timeout: timeout_seconds, tier: options[:tier]})
        debug_log("📝 Sending prompt to claude...", level: :info)

        # Build command arguments
        args = ["--print", "--output-format=text"]

        # Add model if specified
        if @model && !@model.empty?
          args << "--model" << @model
        end

        # Check if we should skip permissions (devcontainer support)
        if should_skip_permissions?
          args << "--dangerously-skip-permissions"
          debug_log("🔓 Running with elevated permissions (devcontainer mode)", level: :info)
        end

        begin
          result = debug_execute_command("claude", args: args, input: prompt, timeout: timeout_seconds)

          # Log the results
          debug_command("claude", args: args, input: prompt, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            result.out
          else
            # Detect issues in stdout/stderr (Claude sometimes prints to stdout)
            combined = [result.out, result.err].compact.join("\n")

            # Classify provider error using pattern matching
            # ZFC EXCEPTION: Cannot use AI to classify provider's own errors (circular dependency)
            error_classification = self.class.classify_provider_error(combined)

            Aidp.log_debug("anthropic_provider", "error_classified",
              exit_code: result.exit_status,
              type: error_classification[:type],
              confidence: error_classification[:confidence])            # Check for rate limit
            if error_classification[:is_rate_limit]
              Aidp.log_debug("anthropic_provider", "rate_limit_detected",
                exit_code: result.exit_status,
                confidence: error_classification[:confidence],
                message: combined)
              notify_rate_limit(combined)
              error_message = "Rate limit reached for Claude CLI.\n#{combined}"
              error = RuntimeError.new(error_message)
              debug_error(error, {exit_code: result.exit_status, stdout: result.out, stderr: result.err})
              raise error
            end

            # Check for model deprecation
            if error_classification[:is_deprecation]
              deprecated_model = @model
              Aidp.log_error("anthropic", "Model deprecation detected",
                model: deprecated_model,
                message: combined)

              # Try to find replacement
              replacement = deprecated_model ? self.class.find_replacement_model(deprecated_model) : nil

              # Record deprecation in cache for future runs
              if replacement
                self.class.deprecation_cache.add_deprecated_model(
                  provider: "anthropic",
                  model_id: deprecated_model,
                  replacement: replacement,
                  reason: combined.lines.first&.strip || "Model deprecated"
                )

                Aidp.log_info("anthropic", "Auto-upgrading to non-deprecated model",
                  old_model: deprecated_model,
                  new_model: replacement)
                debug_log("🔄 Upgrading from deprecated model #{deprecated_model} to #{replacement}", level: :info)

                # Update model and retry
                @model = replacement

                # Retry with new model
                debug_log("🔄 Retrying with upgraded model: #{replacement}", level: :info)
                return send_message(prompt: prompt, session: session, options: options)
              else
                # Record deprecation even without replacement
                if deprecated_model
                  self.class.deprecation_cache.add_deprecated_model(
                    provider: "anthropic",
                    model_id: deprecated_model,
                    replacement: nil,
                    reason: combined.lines.first&.strip || "Model deprecated"
                  )
                end

                error_message = "Model '#{deprecated_model}' is deprecated and no replacement found.\n#{combined}"
                error = RuntimeError.new(error_message)
                debug_error(error, {exit_code: result.exit_status, stdout: result.out, stderr: result.err})
                raise error
              end
            end

            # Check for auth issues
            if combined.downcase.include?("oauth token has expired") || combined.downcase.include?("authentication_error")
              error_message = "Authentication error from Claude CLI: token expired or invalid.\n" \
                              "Run 'claude /login' or refresh credentials.\n" \
                              "Note: Model discovery requires valid authentication."
              error = RuntimeError.new(error_message)
              debug_error(error, {exit_code: result.exit_status, stdout: result.out, stderr: result.err})
              raise error
            end

            error_message = "claude failed with exit code #{result.exit_status}: #{result.err}"
            error = RuntimeError.new(error_message)
            debug_error(error, {exit_code: result.exit_status, stderr: result.err})
            raise error
          end
        rescue => e
          debug_error(e, {provider: "claude", prompt_length: prompt.length})
          raise
        end
      end

      private

      # Notify harness about rate limit detection
      def notify_rate_limit(message)
        return unless @harness_context

        # Extract reset time from message (e.g., "resets 4am")
        reset_time = extract_reset_time_from_message(message)

        # Notify provider manager if available
        if @harness_context.respond_to?(:provider_manager)
          provider_manager = @harness_context.provider_manager
          if provider_manager.respond_to?(:mark_rate_limited)
            provider_manager.mark_rate_limited("anthropic", reset_time)
            Aidp.log_debug("anthropic_provider", "notified_provider_manager",
              reset_time: reset_time)
          end
        end
      rescue => e
        Aidp.log_debug("anthropic_provider", "notify_rate_limit_failed",
          error: e.message)
      end

      # Extract reset time from rate limit message
      def extract_reset_time_from_message(message)
        # Handle expressions like "resets 4am" or "reset at 4:30pm"
        time_of_day_match = message.match(/reset(?:s)?(?:\s+at)?\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)/i)
        if time_of_day_match
          hour = time_of_day_match[1].to_i
          minute = time_of_day_match[2] ? time_of_day_match[2].to_i : 0
          meridiem = time_of_day_match[3].downcase

          hour %= 12
          hour += 12 if meridiem == "pm"

          now = Time.now
          reset_time = Time.new(now.year, now.month, now.day, hour, minute, 0, now.utc_offset)
          reset_time += 86_400 if reset_time <= now
          return reset_time
        end

        # Default to 1 hour from now if no specific time found
        Time.now + 3600
      end

      # Check if we should skip permissions based on devcontainer configuration
      # Overrides base class to add logging and Claude-specific config check
      def should_skip_permissions?
        # Use base class devcontainer detection
        if in_devcontainer_or_codespace?
          debug_log("🔓 Detected devcontainer/codespace environment - enabling full permissions", level: :info)
          return true
        end

        # Fallback: Check harness context for Claude-specific configuration
        if @harness_context&.config&.respond_to?(:should_use_full_permissions?)
          return @harness_context.config.should_use_full_permissions?("claude")
        end

        false
      end

      # Parse Claude MCP server list output
      def parse_claude_mcp_output(output)
        servers = []
        return servers unless output

        lines = output.lines
        lines.reject! { |line| /checking mcp server health/i.match?(line) }

        lines.each do |line|
          line = line.strip
          next if line.empty?

          # Try to parse Claude format: "name: command - ✓ Connected"
          if line =~ /^([^:]+):\s*(.+?)\s*-\s*(✓|✗)\s*(.+)$/
            name = Regexp.last_match(1).strip
            command = Regexp.last_match(2).strip
            status_symbol = Regexp.last_match(3)
            status_text = Regexp.last_match(4).strip

            servers << {
              name: name,
              status: (status_symbol == "✓") ? "connected" : "error",
              description: command,
              enabled: status_symbol == "✓",
              error: (status_symbol == "✗") ? status_text : nil,
              source: "claude_cli"
            }
            next
          end

          # Try to parse legacy table format
          next if /Name.*Status/i.match?(line)
          next if /^[-=]+$/.match?(line)

          parts = line.split(/\s{2,}/)
          next if parts.size < 2

          name = parts[0]&.strip
          status = parts[1]&.strip
          description = parts[2..]&.join(" ")&.strip

          next unless name && !name.empty?

          servers << {
            name: name,
            status: status || "unknown",
            description: description,
            enabled: status&.downcase == "enabled" || status&.downcase == "connected",
            source: "claude_cli"
          }
        end

        servers
      end
    end
  end
end
