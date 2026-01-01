# frozen_string_literal: true

module Aidp
  module Security
    # Handles security policy violations in watch mode with fail-forward logic
    # When a Rule of Two violation occurs, attempts to find alternative approaches
    # using AGD/ZFC before failing. If no path forward, adds a comment and label.
    #
    # Fail-forward flow:
    # 1. Security violation detected
    # 2. Attempt to convert to compliant operation (up to max_retry_attempts)
    #    - Try using secrets proxy instead of direct credential access
    #    - Try sanitizing untrusted input
    #    - Try deferring egress operations
    # 3. If all attempts fail, add PR/issue comment and aidp-needs-input label
    class WatchModeHandler
      DEFAULT_MAX_RETRY_ATTEMPTS = 3
      DEFAULT_NEEDS_INPUT_LABEL = "aidp-needs-input"

      attr_reader :config, :repository_client

      def initialize(repository_client:, config: {})
        @repository_client = repository_client
        @config = normalize_config(config)
        @retry_counts = {}
      end

      # Handle a security policy violation
      # @param violation [PolicyViolation] The violation that occurred
      # @param context [Hash] Context about the operation
      #   - :issue_number or :pr_number - The issue/PR number
      #   - :work_unit_id - The work unit identifier
      #   - :operation - The operation that was attempted
      # @return [Hash] Result of handling: { recovered: bool, action: symbol, message: string }
      def handle_violation(violation, context:)
        work_unit_id = context[:work_unit_id] || "unknown"
        issue_or_pr_number = context[:issue_number] || context[:pr_number]

        Aidp.log_debug("security.watch_handler", "handling_violation",
          work_unit_id: work_unit_id,
          flag: violation.flag,
          source: violation.source)

        # Increment retry count for this work unit
        @retry_counts[work_unit_id] ||= 0
        @retry_counts[work_unit_id] += 1
        retry_count = @retry_counts[work_unit_id]

        if retry_count <= max_retry_attempts
          # Attempt to find alternative approach
          result = attempt_fail_forward(violation, context, retry_count)

          if result[:recovered]
            Aidp.log_info("security.watch_handler", "violation_recovered",
              work_unit_id: work_unit_id,
              attempt: retry_count,
              strategy: result[:strategy])
            return result
          end

          # Not yet at max retries, will try again
          Aidp.log_debug("security.watch_handler", "fail_forward_attempt_failed",
            work_unit_id: work_unit_id,
            attempt: retry_count,
            max_attempts: max_retry_attempts)

          {
            recovered: false,
            action: :retry,
            message: "Security violation, attempting alternative approach (#{retry_count}/#{max_retry_attempts})",
            retry_count: retry_count
          }
        else
          # Max retries exceeded - add comment and label
          Aidp.log_warn("security.watch_handler", "max_retries_exceeded",
            work_unit_id: work_unit_id,
            retry_count: retry_count)

          if issue_or_pr_number
            add_security_comment_and_label(violation, context, issue_or_pr_number)
          end

          # Clear retry count
          @retry_counts.delete(work_unit_id)

          {
            recovered: false,
            action: :fail,
            message: "Security policy violation cannot be resolved automatically. Manual intervention required.",
            needs_input: true
          }
        end
      end

      # Reset retry count for a work unit (call on success or explicit reset)
      def reset_retry_count(work_unit_id)
        @retry_counts.delete(work_unit_id)
      end

      # Check if security handling is enabled
      def enabled?
        @config[:fail_forward_enabled] != false
      end

      private

      def normalize_config(config)
        {
          max_retry_attempts: config[:max_retry_attempts] || config["max_retry_attempts"] || DEFAULT_MAX_RETRY_ATTEMPTS,
          fail_forward_enabled: config.fetch(:fail_forward_enabled, config.fetch("fail_forward_enabled", true)),
          needs_input_label: config[:needs_input_label] || config["needs_input_label"] || DEFAULT_NEEDS_INPUT_LABEL
        }
      end

      def max_retry_attempts
        @config[:max_retry_attempts]
      end

      def needs_input_label
        @config[:needs_input_label]
      end

      # Attempt to find an alternative approach that doesn't violate Rule of Two
      # Returns { recovered: bool, strategy: symbol, ... }
      def attempt_fail_forward(violation, context, attempt_number)
        # Determine which mitigation strategy to try based on the violation
        strategies = build_mitigation_strategies(violation, context)

        if attempt_number <= strategies.length
          strategy = strategies[attempt_number - 1]
          Aidp.log_debug("security.watch_handler", "trying_strategy",
            strategy: strategy[:name],
            attempt: attempt_number)

          result = execute_strategy(strategy, violation, context)
          return result if result[:recovered]
        end

        {recovered: false, strategy: nil}
      end

      # Build ordered list of mitigation strategies based on the violation type
      def build_mitigation_strategies(violation, context)
        strategies = []

        case violation.flag
        when :private_data
          # Try using secrets proxy instead of direct access
          strategies << {
            name: :use_secrets_proxy,
            description: "Route credential access through secrets proxy",
            action: :convert_to_proxy_access
          }

        when :egress
          # Try deferring egress operations
          strategies << {
            name: :defer_egress,
            description: "Queue egress operation for later execution",
            action: :queue_for_later
          }

        when :untrusted_input
          # Try sanitizing the input
          strategies << {
            name: :sanitize_input,
            description: "Sanitize untrusted input before processing",
            action: :sanitize
          }
        end

        # Add generic strategies
        strategies << {
          name: :use_deterministic_unit,
          description: "Convert to deterministic unit (no agent call)",
          action: :convert_to_deterministic
        }

        strategies << {
          name: :request_trusted_context,
          description: "Request elevated trust context",
          action: :request_trust
        }

        strategies
      end

      # Execute a mitigation strategy
      # In MVP, these strategies log the attempt but don't actually recover
      # Future: integrate with AGD/ZFC for intelligent conversion
      def execute_strategy(strategy, violation, context)
        case strategy[:action]
        when :convert_to_proxy_access
          # Check if we can use secrets proxy
          # MVP: Just check if proxy is available, don't actually convert
          begin
            Aidp::Security.secrets_proxy
          rescue
            false
          end
          {recovered: false, strategy: strategy[:name], reason: "Proxy conversion not yet implemented"}

        when :queue_for_later
          # Queue egress for manual execution
          # MVP: Log the operation for manual review
          Aidp.log_info("security.watch_handler", "egress_queued",
            work_unit_id: context[:work_unit_id],
            operation: context[:operation])
          {recovered: false, strategy: strategy[:name], reason: "Egress queued for manual review"}

        when :sanitize
          # Input sanitization would require AGD/ZFC
          # MVP: Not yet implemented
          {recovered: false, strategy: strategy[:name], reason: "Input sanitization not yet implemented"}

        when :convert_to_deterministic
          # Converting to deterministic unit requires context about the operation
          # MVP: Not yet implemented
          {recovered: false, strategy: strategy[:name], reason: "Deterministic conversion not yet implemented"}

        when :request_trust
          # Trust elevation requires human intervention
          {recovered: false, strategy: strategy[:name], reason: "Trust elevation requires manual approval"}

        else
          {recovered: false, strategy: nil, reason: "Unknown strategy"}
        end
      end

      # Add a comment and label to the issue/PR indicating manual intervention is needed
      def add_security_comment_and_label(violation, context, number)
        is_pr = context.key?(:pr_number)

        comment_body = build_security_comment(violation, context)

        begin
          # Add comment
          if is_pr
            @repository_client.add_pr_comment(number, comment_body)
          else
            @repository_client.add_issue_comment(number, comment_body)
          end

          # Add label
          @repository_client.add_labels(number, [needs_input_label])

          Aidp.log_info("security.watch_handler", "needs_input_posted",
            number: number,
            is_pr: is_pr,
            label: needs_input_label)
        rescue => e
          Aidp.log_error("security.watch_handler", "failed_to_post_needs_input",
            number: number,
            error: e.message)
        end
      end

      # Build the comment explaining the security violation
      def build_security_comment(violation, context)
        <<~COMMENT
          ## 🛡️ Security Policy Violation - Manual Intervention Required

          AIDP encountered a **Rule of Two security violation** while processing this #{context.key?(:pr_number) ? "pull request" : "issue"}.

          ### What happened

          The requested operation would have enabled the "lethal trifecta" - a combination of:
          - **Untrusted input** - Processing content from external sources
          - **Private data access** - Access to secrets or credentials
          - **Egress capability** - Ability to communicate externally

          Allowing all three simultaneously creates a security risk where a compromised prompt could exfiltrate sensitive data.

          ### Violation Details

          - **Blocked flag**: `#{violation.flag}`
          - **Source**: #{violation.source || "unknown"}
          - **Work unit**: #{context[:work_unit_id] || "unknown"}

          ### Current state
          #{format_current_state(violation.current_state)}

          ### What you can do

          1. **Use the Secrets Proxy** - Register secrets and use proxy tokens instead of direct credential access
          2. **Sanitize input** - Mark the input source as trusted (if appropriate)
          3. **Defer egress** - Queue the external communication for manual execution
          4. **Review and retry** - Modify the request to avoid the security conflict

          ---
          *This comment was added by AIDP security enforcement. Remove the `#{needs_input_label}` label after resolving.*
        COMMENT
      end

      def format_current_state(state)
        return "No state available" unless state.is_a?(Hash)

        lines = []
        lines << "- `untrusted_input`: #{state[:untrusted_input] ? "✓ enabled (#{state[:untrusted_input_source]})" : "✗ disabled"}"
        lines << "- `private_data`: #{state[:private_data] ? "✓ enabled (#{state[:private_data_source]})" : "✗ disabled"}"
        lines << "- `egress`: #{state[:egress] ? "✓ enabled (#{state[:egress_source]})" : "✗ disabled"}"
        lines.join("\n")
      end
    end
  end
end
