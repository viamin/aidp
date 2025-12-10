# frozen_string_literal: true

module Aidp
  module Security
    # Adapts the Rule of Two security framework to the WorkLoopRunner
    # Tracks trifecta state per work unit and enforces policy before agent calls
    #
    # Integration points:
    # - Work unit start/end lifecycle
    # - Untrusted input detection (issues, PRs, external data)
    # - Egress detection (git operations, API calls)
    # - Private data detection (registered secrets)
    #
    # Usage:
    #   adapter = WorkLoopSecurityAdapter.new(project_dir: Dir.pwd)
    #   adapter.begin_work_unit(work_unit_id: "unit_123", context: context)
    #   adapter.check_agent_call_allowed!(operation: :git_push)
    #   adapter.end_work_unit
    class WorkLoopSecurityAdapter
      attr_reader :project_dir, :config, :current_work_unit_id, :current_state

      # Sources of untrusted input that trigger the untrusted_input flag
      UNTRUSTED_SOURCES = %w[
        github_issue
        github_pr
        github_comment
        external_url
        user_provided_url
        webhook_payload
      ].freeze

      # Operations that constitute egress (external communication)
      EGRESS_OPERATIONS = %w[
        git_push
        git_fetch
        api_call
        http_request
        webhook_send
        email_send
        file_upload
        pr_comment
        issue_comment
      ].freeze

      def initialize(project_dir:, config: nil, enforcer: nil, secrets_proxy: nil)
        @project_dir = project_dir
        @config = config || load_security_config
        @enforcer = enforcer || Aidp::Security.enforcer
        @secrets_proxy = secrets_proxy || Aidp::Security.secrets_proxy
        @current_work_unit_id = nil
        @current_state = nil
      end

      # Check if security enforcement is enabled
      def enabled?
        rule_of_two_config = @config[:rule_of_two] || {}
        rule_of_two_config.fetch(:enabled, true)
      end

      # Begin tracking a work unit
      # @param work_unit_id [String] Unique identifier for the work unit
      # @param context [Hash] Work context containing source information
      # @return [TrifectaState] The state object for this work unit
      def begin_work_unit(work_unit_id:, context: {})
        return nil unless enabled?

        @current_work_unit_id = work_unit_id
        @current_state = @enforcer.begin_work_unit(work_unit_id: work_unit_id)

        # Analyze context for untrusted input
        detect_and_enable_untrusted_input(context)

        Aidp.log_debug("security.adapter", "work_unit_started",
          work_unit_id: work_unit_id,
          initial_state: @current_state.to_h)

        @current_state
      end

      # End tracking for current work unit
      # @return [Hash] Final state summary
      def end_work_unit
        return nil unless enabled? && @current_work_unit_id

        summary = @enforcer.end_work_unit(@current_work_unit_id)
        @current_work_unit_id = nil
        @current_state = nil

        Aidp.log_debug("security.adapter", "work_unit_ended",
          summary: summary)

        summary
      end

      # Check if an agent call would be allowed and enable egress flag
      # @param operation [String, Symbol] The type of operation (e.g., :git_push)
      # @param requires_credentials [Boolean] Whether operation needs credentials
      # @raise [PolicyViolation] if operation would violate Rule of Two
      # @return [TrifectaState] The current state after enabling egress
      def check_agent_call_allowed!(operation:, requires_credentials: false)
        return @current_state unless enabled? && @current_state

        operation_str = operation.to_s

        # Check if this operation constitutes egress
        if egress_operation?(operation_str)
          begin
            @current_state.enable(:egress, source: "agent_operation:#{operation_str}")
          rescue PolicyViolation => e
            Aidp.log_warn("security.adapter", "egress_blocked",
              operation: operation_str,
              reason: e.message,
              current_state: @current_state.to_h)
            raise
          end
        end

        # If operation requires credentials, check if we can enable private_data
        if requires_credentials
          begin
            @current_state.enable(:private_data, source: "credential_access:#{operation_str}")
          rescue PolicyViolation => e
            Aidp.log_warn("security.adapter", "credential_access_blocked",
              operation: operation_str,
              reason: e.message,
              current_state: @current_state.to_h)
            raise
          end
        end

        @current_state
      end

      # Request credentials through the secrets proxy
      # This enables the private_data flag and returns a short-lived token
      # @param secret_name [String] The registered secret name
      # @param scope [String] The intended use of this credential
      # @return [Hash] Token details from the secrets proxy
      # @raise [PolicyViolation] if credential access would violate Rule of Two
      def request_credential(secret_name:, scope: nil)
        unless enabled?
          # If security is disabled, return direct access (legacy mode)
          env_var = @secrets_proxy.registry.env_var_for(secret_name)
          return {token: ENV[env_var], direct_access: true} if env_var

          raise UnregisteredSecretError.new(secret_name: secret_name)
        end

        # Check if enabling private_data would violate Rule of Two
        if @current_state&.would_create_trifecta?(:private_data)
          raise PolicyViolation.new(
            flag: :private_data,
            source: "credential_request:#{secret_name}",
            current_state: @current_state.to_h,
            message: "Cannot access credentials for '#{secret_name}' - would create lethal trifecta"
          )
        end

        # Enable private_data flag
        @current_state&.enable(:private_data, source: "secrets_proxy:#{secret_name}")

        # Request token from proxy
        @secrets_proxy.request_token(secret_name: secret_name, scope: scope)
      end

      # Get a sanitized environment for agent execution
      # Strips all registered secrets from the environment
      # @return [Hash] Sanitized environment hash
      def sanitized_environment
        @secrets_proxy.sanitized_environment
      end

      # Execute a block with sanitized environment
      # @yield The block to execute
      # @return [Object] The result of the block
      def with_sanitized_environment(&block)
        @secrets_proxy.with_sanitized_environment(&block)
      end

      # Check if current state would allow enabling a flag
      # @param flag [Symbol] :untrusted_input, :private_data, or :egress
      # @return [Hash] { allowed: boolean, reason: string }
      def would_allow?(flag)
        return {allowed: true, reason: "Security disabled"} unless enabled?
        return {allowed: true, reason: "No active work unit"} unless @current_state

        if @current_state.would_create_trifecta?(flag)
          {
            allowed: false,
            reason: "Would create lethal trifecta",
            current_state: @current_state.to_h
          }
        else
          {
            allowed: true,
            reason: "Operation allowed",
            enabled_count: @current_state.enabled_count
          }
        end
      end

      # Get current security status for display
      def status
        return {enabled: false} unless enabled?

        {
          enabled: true,
          active_work_unit: @current_work_unit_id,
          state: @current_state&.to_h,
          status_string: @current_state&.status_string || "No active work unit"
        }
      end

      private

      def load_security_config
        Aidp::Config.security_config(@project_dir)
      rescue
        {} # Fallback to empty config
      end

      # Detect untrusted input sources in the context
      def detect_and_enable_untrusted_input(context)
        sources = []

        # Check for GitHub issue source
        if context[:issue_number] || context[:issue_url] || context.dig(:issue, :number)
          sources << "github_issue"
        end

        # Check for GitHub PR source
        if context[:pr_number] || context[:pr_url] || context.dig(:pull_request, :number)
          sources << "github_pr"
        end

        # Check for external URL input
        if context[:external_url] || context[:user_url]
          sources << "external_url"
        end

        # Check for webhook payload
        if context[:webhook_payload] || context[:webhook_event]
          sources << "webhook_payload"
        end

        # Check for watch mode (processes untrusted issues/PRs)
        if context[:workflow_type].to_s == "watch_mode"
          sources << "watch_mode_untrusted_content"
        end

        # Enable untrusted_input if any sources detected
        if sources.any?
          source_description = sources.join(", ")
          begin
            @current_state.enable(:untrusted_input, source: source_description)
            Aidp.log_debug("security.adapter", "untrusted_input_detected",
              work_unit_id: @current_work_unit_id,
              sources: sources)
          rescue PolicyViolation => e
            # This shouldn't happen at the start of a work unit
            Aidp.log_error("security.adapter", "unexpected_policy_violation",
              error: e.message)
            raise
          end
        end
      end

      # Check if operation constitutes egress
      def egress_operation?(operation)
        EGRESS_OPERATIONS.include?(operation) ||
          operation.start_with?("git_") ||
          operation.start_with?("api_") ||
          operation.start_with?("http_")
      end
    end
  end
end
