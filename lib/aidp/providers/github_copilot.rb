# frozen_string_literal: true

require "timeout"
require_relative "base"
require_relative "../util"
require_relative "../debug_mixin"

module Aidp
  module Providers
    class GithubCopilot < Base
      include Aidp::DebugMixin

      # Model name pattern for GitHub Copilot models
      # Copilot uses OpenAI models (gpt-4, gpt-4o, etc.) but exposes them through its own interface
      MODEL_PATTERN = /^gpt-[\d.o-]+(?:-turbo)?(?:-mini)?$/i

      def self.available?
        !!Aidp::Util.which("copilot")
      end

      # Check if this provider supports a given model family
      #
      # @param family_name [String] The model family name
      # @return [Boolean] True if it matches OpenAI model pattern
      def self.supports_model_family?(family_name)
        MODEL_PATTERN.match?(family_name)
      end

      # Discover available models from GitHub Copilot CLI
      #
      # Note: GitHub Copilot CLI doesn't have a standard model listing command.
      # Returns registry-based models that match OpenAI patterns.
      #
      # @return [Array<Hash>] Array of discovered models
      def self.discover_models
        return [] unless available?

        discover_models_from_registry(MODEL_PATTERN, "github_copilot")
      end

      # Normalize a provider-specific model name to its model family
      #
      # OpenAI models may have version suffixes. This method normalizes them.
      #
      # @param provider_model_name [String] The model name
      # @return [String] The normalized model family name
      def self.model_family(provider_model_name)
        # OpenAI models are generally their own family names
        provider_model_name
      end

      # Convert a model family name to the provider's preferred model name
      #
      # @param family_name [String] The model family name
      # @return [String] The model name (same as family for GitHub Copilot)
      def self.provider_model_name(family_name)
        family_name
      end

      # Get firewall requirements for GitHub Copilot provider
      def self.firewall_requirements
        {
          domains: [
            "copilot-proxy.githubusercontent.com",
            "api.githubcopilot.com",
            "copilot-telemetry.githubusercontent.com",
            "default.exp-tas.com",
            "copilot-completions.githubusercontent.com",
            "business.githubcopilot.com",
            "enterprise.githubcopilot.com",
            "individual.githubcopilot.com"
          ],
          ip_ranges: []
        }
      end

      # Get instruction file paths for GitHub Copilot provider
      #
      # GitHub Copilot looks for .github/copilot-instructions.md
      #
      # @return [Array<Hash>] Instruction file paths
      def self.instruction_file_paths
        [
          {
            path: ".github/copilot-instructions.md",
            description: "GitHub Copilot agent instructions",
            symlink: true
          }
        ]
      end

      def name
        "github_copilot"
      end

      def display_name
        "GitHub Copilot CLI"
      end

      # Check if this provider supports dangerous/elevated permissions mode
      # GitHub Copilot uses --allow-all-tools flag for elevated permissions
      #
      # @return [Boolean] true, copilot supports dangerous mode
      def supports_dangerous_mode?
        true
      end

      # Get the provider-specific flag(s) for enabling dangerous mode
      # Maps the semantic `dangerous: true` flag to Copilot's --allow-all-tools
      #
      # @return [Array<String>] command-line flags for dangerous mode
      def dangerous_mode_flags
        ["--allow-all-tools"]
      end

      # Check if this provider supports session continuation
      # GitHub Copilot supports resuming sessions with --resume flag
      #
      # @return [Boolean] true, copilot supports sessions
      def supports_sessions?
        true
      end

      # Get the CLI flag for session continuation
      #
      # @return [String] the flag name
      def session_flag
        "--resume"
      end

      # Provider-specific error patterns for GitHub Copilot
      # These patterns are used to classify errors into the standard ErrorTaxonomy categories
      #
      # @return [Hash] mapping of error categories to regex patterns
      def error_patterns
        {
          auth_expired: [
            /not.?authorized/i,
            /requires.?an.?enterprise/i,
            /access.?denied/i,
            /permission.?denied/i,
            /not.?enabled/i,
            /copilot.?is.?not.?available/i,
            /subscription.?required/i
          ],
          quota_exceeded: [
            /usage.?limit/i,
            /rate.?limit/i
          ],
          transient: [
            /connection.?error/i,
            /timeout/i,
            /try.?again/i
          ],
          permanent: [
            /invalid.?command/i,
            /unknown.?flag/i
          ]
        }
      end

      def available?
        return false unless self.class.available?

        # Additional check to ensure the CLI is properly configured
        begin
          result = Aidp::Util.execute_command("copilot", ["--version"], timeout: 10)
          result.exit_status == 0
        rescue
          false
        end
      end

      def send_message(prompt:, session: nil, options: {})
        raise "copilot CLI not available" unless self.class.available?

        # Smart timeout calculation
        timeout_seconds = calculate_timeout

        debug_provider("copilot", "Starting execution", {timeout: timeout_seconds})
        debug_log("📝 Sending prompt to copilot (length: #{prompt.length})", level: :info)

        # Set up activity monitoring
        setup_activity_monitoring("copilot", method(:activity_callback))
        record_activity("Starting copilot execution")

        # Create a spinner for activity display
        spinner = TTY::Spinner.new("[:spinner] :title", format: :dots, hide_cursor: true)
        spinner.auto_spin

        activity_display_thread = Thread.new do
          start_time = Time.now
          loop do
            sleep 0.5 # Update every 500ms to reduce spam
            elapsed = Time.now - start_time

            # Break if we've been running too long or state changed
            break if elapsed > timeout_seconds || @activity_state == :completed || @activity_state == :failed

            update_spinner_status(spinner, elapsed, "🤖 GitHub Copilot CLI")
          end
        end

        begin
          # Use non-interactive mode for automation
          args = ["-p", prompt, "--allow-all-tools"]

          # Add session support if provided
          if session && !session.empty?
            args += ["--resume", session]
          end

          # Use debug_execute_command for better debugging (no input since prompt is in args)
          result = debug_execute_command("copilot", args: args, timeout: timeout_seconds)

          # Log the results
          debug_command("copilot", args: args, input: prompt, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            spinner.success("✓")
            mark_completed
            result.out
          else
            # Classify error and handle appropriately
            error = StandardError.new(result.err.to_s)
            error_category = classify_error(error)

            spinner.error("✗")
            debug_error(error, {exit_code: result.exit_status, stderr: result.err, error_category: error_category})

            case error_category
            when :auth_expired
              mark_failed("copilot authorization error: #{result.err}")
              @unavailable = true
              raise Aidp::Providers::ProviderUnavailableError.new("copilot authorization error: #{result.err}")
            when :rate_limited
              mark_failed("copilot rate limited: #{result.err}")
              raise Aidp::Providers::ProviderUnavailableError.new("copilot rate limited, retry later: #{result.err}")
            when :quota_exceeded
              mark_failed("copilot quota exceeded: #{result.err}")
              @unavailable = true
              raise Aidp::Providers::ProviderUnavailableError.new("copilot quota exceeded: #{result.err}")
            else
              # :transient, :permanent, or :unknown - raise generic error
              mark_failed("copilot failed with exit code #{result.exit_status}")
              raise "copilot failed with exit code #{result.exit_status}: #{result.err}"
            end
          end
        rescue Aidp::Providers::ProviderUnavailableError
          raise
        rescue => e
          spinner&.error("✗")
          mark_failed("copilot execution failed: #{e.message}")
          debug_error(e, {provider: "github_copilot", prompt_length: prompt.length})
          raise
        ensure
          cleanup_activity_display(activity_display_thread, spinner)
        end
      end

      # Enhanced send method with additional options
      def send_with_options(prompt:, session: nil, tools: nil, log_level: nil, config_file: nil, directories: nil)
        args = ["-p", prompt]

        # Add session support
        if session && !session.empty?
          args += ["--resume", session]
        end

        # Add tool permissions
        if tools && !tools.empty?
          if tools.include?("all")
            args += ["--allow-all-tools"]
          else
            tools.each do |tool|
              args += ["--allow-tool", tool]
            end
          end
        else
          # Default to allowing all tools for automation
          args += ["--allow-all-tools"]
        end

        # Add logging level
        if log_level
          args += ["--log-level", log_level]
        end

        # Add allowed directories
        if directories && !directories.empty?
          directories.each do |dir|
            args += ["--add-dir", dir]
          end
        end

        # Use the enhanced version of send
        send_with_custom_args(prompt: prompt, args: args)
      end

      # Override health check for GitHub Copilot specific considerations
      def harness_healthy?
        return false unless super

        # Additional health checks specific to GitHub Copilot CLI
        # Check if we can access GitHub (basic connectivity test)
        begin
          result = Aidp::Util.execute_command("copilot", ["--help"], timeout: 5)
          result.exit_status == 0
        rescue
          false
        end
      end

      private

      def send_with_custom_args(prompt:, args:)
        timeout_seconds = calculate_timeout

        debug_provider("copilot", "Starting execution", {timeout: timeout_seconds, args: args})
        debug_log("📝 Sending prompt to copilot with custom args", level: :info)

        setup_activity_monitoring("copilot", method(:activity_callback))
        record_activity("Starting copilot execution with custom args")

        begin
          result = debug_execute_command("copilot", args: args, timeout: timeout_seconds)
          debug_command("copilot", args: args, output: result.out, error: result.err, exit_code: result.exit_status)

          if result.exit_status == 0
            mark_completed
            result.out
          else
            mark_failed("copilot failed with exit code #{result.exit_status}")
            debug_error(StandardError.new("copilot failed"), {exit_code: result.exit_status, stderr: result.err})
            raise "copilot failed with exit code #{result.exit_status}: #{result.err}"
          end
        rescue => e
          mark_failed("copilot execution failed: #{e.message}")
          debug_error(e, {provider: "github_copilot", prompt_length: prompt.length})
          raise
        end
      end

      def activity_callback(state, message, provider)
        # Handle activity state changes
        case state
        when :stuck
          display_message("\n⚠️  GitHub Copilot CLI appears stuck: #{message}", type: :warning)
        when :completed
          display_message("\n✅ GitHub Copilot CLI completed: #{message}", type: :success)
        when :failed
          display_message("\n❌ GitHub Copilot CLI failed: #{message}", type: :error)
        end
      end
    end
  end
end
