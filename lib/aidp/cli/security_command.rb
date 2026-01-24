# frozen_string_literal: true

require "tty-prompt"
require "tty-table"
require_relative "../config"
require_relative "../security"

module Aidp
  class CLI
    # CLI commands for security management
    #
    # Provides commands for:
    # - aidp security status         Show current security posture
    # - aidp security register <name> Register a secret with the proxy
    # - aidp security unregister <name> Remove a registered secret
    # - aidp security list           List registered secrets (names only)
    # - aidp security audit          Run security audit (RSpec tests)
    class SecurityCommand
      def initialize(project_dir: Dir.pwd, prompt: TTY::Prompt.new)
        @project_dir = project_dir
        @prompt = prompt
      end

      # Run security command
      #
      # @param args [Array<String>] Command arguments
      # @return [Integer] Exit code
      def run(args)
        subcommand = args.shift

        case subcommand
        when "status"
          run_status
        when "register", "register-secret"
          secret_name = args.shift
          unless secret_name
            @prompt.error("Error: secret name required")
            @prompt.say("Usage: aidp security register <name> [--env-var VAR_NAME]")
            return 1
          end
          # Parse optional --env-var flag
          env_var = parse_env_var_option(args) || secret_name
          run_register(secret_name, env_var)
        when "unregister"
          secret_name = args.shift
          unless secret_name
            @prompt.error("Error: secret name required")
            @prompt.say("Usage: aidp security unregister <name>")
            return 1
          end
          run_unregister(secret_name)
        when "list", "secrets"
          run_list
        when "audit"
          run_audit(args)
        when "proxy-status"
          run_proxy_status
        when nil, "help", "--help", "-h"
          show_help
          0
        else
          @prompt.error("Unknown subcommand: #{subcommand}")
          show_help
          1
        end
      end

      # Show help message
      def show_help
        @prompt.say("\nAIDP Security Management")
        @prompt.say("\n" + "=" * 40)
        @prompt.say("\nUsage:")
        @prompt.say("  aidp security status                 Show current security posture")
        @prompt.say("  aidp security register <name>        Register a secret with the proxy")
        @prompt.say("  aidp security unregister <name>      Remove a registered secret")
        @prompt.say("  aidp security list                   List registered secrets (names only)")
        @prompt.say("  aidp security proxy-status           Show secrets proxy status")
        @prompt.say("  aidp security audit                  Run security audit tests")
        @prompt.say("\nOptions for register:")
        @prompt.say("  --env-var VAR_NAME    Environment variable containing the secret")
        @prompt.say("                        (defaults to the secret name if not provided)")
        @prompt.say("\nExamples:")
        @prompt.say("  aidp security status")
        @prompt.say("  aidp security register GITHUB_TOKEN")
        @prompt.say("  aidp security register github_token --env-var GITHUB_TOKEN")
        @prompt.say("  aidp security list")
        @prompt.say("\n" + "=" * 40)
      end

      # Run status command - show current security posture
      def run_status
        Aidp.log_debug("security_cli", "showing_status")

        config = Aidp::Config.security_config(@project_dir)
        rule_of_two = config[:rule_of_two] || {}
        proxy_config = config[:secrets_proxy] || {}

        @prompt.say("\n" + "=" * 50)
        @prompt.say("AIDP Security Status")
        @prompt.say("=" * 50)

        # Rule of Two status
        @prompt.say("\n Rule of Two Enforcement")
        @prompt.say("-" * 30)
        enabled = rule_of_two.fetch(:enabled, true)
        policy = rule_of_two[:policy] || "strict"
        status_icon = enabled ? "\u2713" : "\u2717"
        @prompt.say("  Status: #{status_icon} #{enabled ? "Enabled" : "Disabled"}")
        @prompt.say("  Policy: #{policy}")

        # Enforcer status
        enforcer = Aidp::Security.enforcer
        summary = enforcer.status_summary
        @prompt.say("  Active work units: #{summary[:active_work_units]}")
        @prompt.say("  Completed work units: #{summary[:completed_work_units]}")

        # Secrets Proxy status
        @prompt.say("\n Secrets Proxy")
        @prompt.say("-" * 30)
        proxy_enabled = proxy_config.fetch(:enabled, true)
        token_ttl = proxy_config[:token_ttl] || 300
        status_icon = proxy_enabled ? "\u2713" : "\u2717"
        @prompt.say("  Status: #{status_icon} #{proxy_enabled ? "Enabled" : "Disabled"}")
        @prompt.say("  Token TTL: #{token_ttl} seconds")

        # Registered secrets count
        registry = Aidp::Security.secrets_registry
        secrets = registry.list
        @prompt.say("  Registered secrets: #{secrets.count}")

        # Active tokens
        proxy = Aidp::Security.secrets_proxy
        active_tokens = proxy.active_tokens_summary
        @prompt.say("  Active tokens: #{active_tokens.count}")

        @prompt.say("\n" + "=" * 50)
        @prompt.say("Use 'aidp security list' to see registered secrets")
        @prompt.say("Use 'aidp security register <name>' to add secrets")
        @prompt.say("")

        0
      end

      # Run register command - register a secret with the proxy
      def run_register(secret_name, env_var)
        Aidp.log_info("security_cli", "registering_secret",
          name: secret_name,
          env_var: env_var)

        registry = Aidp::Security.secrets_registry

        # Check if already registered
        if registry.registered?(secret_name)
          @prompt.warn("Secret '#{secret_name}' is already registered")
          existing = registry.get(secret_name)
          @prompt.say("  Env var: #{existing[:env_var] || existing["env_var"]}")
          return 1
        end

        # Check if env var exists
        unless ENV.key?(env_var)
          @prompt.warn("Warning: Environment variable '#{env_var}' is not currently set")
          return 1 unless @prompt.yes?("Continue anyway?")
        end

        # Ask for optional description
        description = @prompt.ask("Description (optional):") do |q|
          q.required false
        end

        # Ask for optional scopes
        scopes = @prompt.ask("Allowed scopes (comma-separated, optional):") do |q|
          q.required false
        end
        scope_list = scopes&.split(",")&.map(&:strip)&.reject(&:empty?) || []

        begin
          result = registry.register(
            name: secret_name,
            env_var: env_var,
            description: description,
            scopes: scope_list
          )

          @prompt.ok("Secret '#{secret_name}' registered successfully")
          @prompt.say("  ID: #{result[:id]}")
          @prompt.say("  Env var: #{env_var}")
          @prompt.say("  Registered at: #{result[:registered_at]}")

          @prompt.say("  Scopes: #{scope_list.join(", ")}") if scope_list.any?

          @prompt.say("\nThe secret value will be proxied through short-lived tokens.")
          @prompt.say("Agent processes will not have direct access to '#{env_var}'.")

          0
        rescue => e
          @prompt.error("Failed to register secret: #{e.message}")
          Aidp.log_error("security_cli", "registration_failed",
            name: secret_name,
            error: e.message)
          1
        end
      end

      # Run unregister command - remove a registered secret
      def run_unregister(secret_name)
        Aidp.log_info("security_cli", "unregistering_secret", name: secret_name)

        registry = Aidp::Security.secrets_registry

        unless registry.registered?(secret_name)
          @prompt.error("Secret '#{secret_name}' is not registered")
          return 1
        end

        # Confirm unregistration
        unless @prompt.yes?("Are you sure you want to unregister '#{secret_name}'?")
          @prompt.say("Cancelled")
          return 0
        end

        # Revoke any active tokens for this secret
        proxy = Aidp::Security.secrets_proxy
        revoked_count = proxy.revoke_all_for_secret(secret_name)

        if registry.unregister(name: secret_name)
          @prompt.ok("Secret '#{secret_name}' unregistered")
          @prompt.say("  Revoked #{revoked_count} active token(s)") if revoked_count > 0
          0
        else
          @prompt.error("Failed to unregister secret")
          1
        end
      end

      # Run list command - list registered secrets
      def run_list
        Aidp.log_debug("security_cli", "listing_secrets")

        registry = Aidp::Security.secrets_registry
        secrets = registry.list

        if secrets.empty?
          @prompt.say("\nNo secrets registered")
          @prompt.say("Use 'aidp security register <name>' to register a secret")
          return 0
        end

        @prompt.say("\n" + "=" * 60)
        @prompt.say("Registered Secrets")
        @prompt.say("=" * 60)

        headers = ["Name", "Env Var", "Has Value", "Scopes", "Registered"]
        rows = secrets.map do |secret|
          scopes = secret[:scopes] || []
          scope_str = scopes.any? ? scopes.join(", ") : "(any)"
          has_value = secret[:has_value] ? "\u2713" : "\u2717"
          registered = secret[:registered_at]&.split("T")&.first || "unknown"

          [secret[:name], secret[:env_var], has_value, scope_str, registered]
        end

        table = TTY::Table.new(headers, rows)
        @prompt.say(table.render(:unicode, padding: [0, 1]))

        @prompt.say("\n#{secrets.count} secret(s) registered")
        @prompt.say("")

        0
      end

      # Run proxy-status command - show secrets proxy status
      def run_proxy_status
        Aidp.log_debug("security_cli", "showing_proxy_status")

        proxy = Aidp::Security.secrets_proxy
        active_tokens = proxy.active_tokens_summary

        @prompt.say("\n" + "=" * 60)
        @prompt.say("Secrets Proxy Status")
        @prompt.say("=" * 60)

        @prompt.say("\nActive Tokens: #{active_tokens.count}")

        if active_tokens.any?
          headers = ["Secret", "Scope", "Expires In", "Used"]
          rows = active_tokens.map do |token|
            ttl = token[:remaining_ttl]
            expires = (ttl > 60) ? "#{ttl / 60}m #{ttl % 60}s" : "#{ttl}s"
            used = token[:used] ? "\u2713" : "\u2717"
            [token[:secret_name], token[:scope] || "(any)", expires, used]
          end

          table = TTY::Table.new(headers, rows)
          @prompt.say(table.render(:unicode, padding: [0, 1]))
        end

        # Show usage log
        usage_log = proxy.usage_log(limit: 10)
        if usage_log.any?
          @prompt.say("\nRecent Token Usage (last 10):")
          usage_log.each do |entry|
            @prompt.say("  - #{entry[:secret_name]} (#{entry[:scope] || "any"}) at #{entry[:used_at]}")
          end
        end

        @prompt.say("")
        0
      end

      # Default timeout for audit command (5 minutes)
      AUDIT_TIMEOUT_SECONDS = 300

      # Run audit command - run security audit tests
      def run_audit(args)
        Aidp.log_info("security_cli", "running_audit")

        @prompt.say("\nRunning Security Audit...")
        @prompt.say("=" * 40)

        # Check for RSpec
        rspec_path = File.join(@project_dir, "spec", "aidp", "security")

        unless Dir.exist?(rspec_path)
          @prompt.warn("Security spec directory not found: #{rspec_path}")
          @prompt.say("Creating security audit scenarios...")

          # Create the directory
          FileUtils.mkdir_p(rspec_path)
          @prompt.ok("Created #{rspec_path}")
        end

        # Run RSpec for security specs
        @prompt.say("\nRunning security RSpec tests...")

        # Check if there are any spec files
        spec_files = Dir.glob(File.join(rspec_path, "**/*_spec.rb"))

        if spec_files.empty?
          @prompt.warn("No security spec files found")
          @prompt.say("Add security tests to: #{rspec_path}")
          return 0
        end

        # Run RSpec with timeout protection
        cmd = "bundle exec rspec #{rspec_path} --format failures"
        @prompt.say("$ #{cmd}\n")
        @prompt.say("(timeout: #{AUDIT_TIMEOUT_SECONDS / 60} minutes)\n")

        exit_status = run_with_timeout(cmd, AUDIT_TIMEOUT_SECONDS)

        case exit_status
        when 0
          @prompt.ok("\nSecurity audit passed")
        when :timeout
          @prompt.error("\nSecurity audit timed out after #{AUDIT_TIMEOUT_SECONDS / 60} minutes")
          return 1
        else
          @prompt.error("\nSecurity audit failed")
        end

        exit_status.is_a?(Integer) ? exit_status : 1
      end

      private

      # Run a command with timeout protection
      # @param cmd [String] The command to execute
      # @param timeout [Integer] Timeout in seconds
      # @return [Integer, Symbol] Exit status or :timeout
      def run_with_timeout(cmd, timeout)
        pid = spawn(cmd)
        start_time = Time.now

        loop do
          # Check if process has exited
          result = Process.waitpid(pid, Process::WNOHANG)
          return $?.exitstatus if result

          # Check timeout
          if Time.now - start_time > timeout
            Process.kill("TERM", pid)
            sleep 0.5
            begin
              Process.kill("KILL", pid)
            rescue Errno::ESRCH
              # Process already exited
            end
            Process.waitpid(pid)
            return :timeout
          end

          sleep 0.5
        end
      rescue => e
        Aidp.log_error("security_cli", "audit_execution_error", error: e.message)
        1
      end

      # Parse --env-var option from args
      def parse_env_var_option(args)
        idx = args.index("--env-var")
        return nil unless idx

        args.delete_at(idx) # Remove --env-var
        args.delete_at(idx) # Remove the value and return it
      end
    end
  end
end
