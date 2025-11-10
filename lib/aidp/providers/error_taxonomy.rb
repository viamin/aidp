# frozen_string_literal: true

module Aidp
  module Providers
    # ErrorTaxonomy defines the five standardized error categories that all providers
    # use for consistent error handling, retry logic, and escalation.
    #
    # Categories:
    # - rate_limited: Provider is rate-limiting requests (switch provider immediately)
    # - auth_expired: Authentication credentials are invalid or expired (escalate or switch)
    # - quota_exceeded: Usage quota has been exceeded (switch provider)
    # - transient: Temporary error that may resolve on retry (retry with backoff)
    # - permanent: Permanent error that won't resolve with retry (escalate or abort)
    #
    # @see https://github.com/viamin/aidp/issues/243
    module ErrorTaxonomy
      # Error category constants
      RATE_LIMITED = :rate_limited
      AUTH_EXPIRED = :auth_expired
      QUOTA_EXCEEDED = :quota_exceeded
      TRANSIENT = :transient
      PERMANENT = :permanent

      # All valid error categories
      CATEGORIES = [
        RATE_LIMITED,
        AUTH_EXPIRED,
        QUOTA_EXCEEDED,
        TRANSIENT,
        PERMANENT
      ].freeze

      # Default error patterns for common error messages
      # Providers can override these with provider-specific patterns
      DEFAULT_PATTERNS = {
        rate_limited: [
          /rate.?limit/i,
          /too.?many.?requests/i,
          /429/,
          /throttl(ed|ing)/i,
          /request.?limit/i,
          /requests.?per.?minute/i,
          /rpm.?exceeded/i
        ],
        auth_expired: [
          /auth(entication|orization).?(fail(ed|ure)|error)/i,
          /invalid.?(api.?key|token|credential)/i,
          /expired.?(api.?key|token|credential)/i,
          /unauthorized/i,
          /401/,
          /403/,
          /permission.?denied/i,
          /access.?denied/i
        ],
        quota_exceeded: [
          /quota.?(exceed(ed)?|limit|exhausted)/i,
          /usage.?limit/i,
          /billing.?limit/i,
          /credit.?limit/i,
          /insufficient.?quota/i,
          /usage.?cap/i
        ],
        transient: [
          /timeout/i,
          /timed?.?out/i,
          /connection.?(reset|refused|lost|closed)/i,
          /temporary.?error/i,
          /try.?again/i,
          /service.?unavailable/i,
          /503/,
          /502/,
          /504/,
          /gateway.?timeout/i,
          /network.?error/i,
          /socket.?error/i,
          /connection.?error/i,
          /broken.?pipe/i,
          /host.?unreachable/i
        ],
        permanent: [
          /invalid.?(model|parameter|request|input)/i,
          /unsupported.?(operation|feature|model)/i,
          /not.?found/i,
          /404/,
          /bad.?request/i,
          /400/,
          /malformed/i,
          /syntax.?error/i,
          /validation.?error/i,
          /model.?not.?available/i,
          /model.?deprecated/i
        ]
      }.freeze

      # Retry policy for each category
      RETRY_POLICIES = {
        rate_limited: {
          retry: false,
          switch_provider: true,
          escalate: false,
          backoff_strategy: :none
        },
        auth_expired: {
          retry: false,
          switch_provider: true,
          escalate: true,
          backoff_strategy: :none
        },
        quota_exceeded: {
          retry: false,
          switch_provider: true,
          escalate: false,
          backoff_strategy: :none
        },
        transient: {
          retry: true,
          switch_provider: false,
          escalate: false,
          backoff_strategy: :exponential
        },
        permanent: {
          retry: false,
          switch_provider: false,
          escalate: true,
          backoff_strategy: :none
        }
      }.freeze

      # Check if a category is valid
      # @param category [Symbol] category to check
      # @return [Boolean] true if valid
      def self.valid_category?(category)
        CATEGORIES.include?(category)
      end

      # Get retry policy for a category
      # @param category [Symbol] error category
      # @return [Hash] retry policy configuration
      def self.retry_policy(category)
        RETRY_POLICIES[category] || RETRY_POLICIES[:transient]
      end

      # Classify an error message using default patterns
      # @param message [String] error message
      # @return [Symbol] error category
      def self.classify_message(message)
        return :transient if message.nil? || message.empty?

        message_lower = message.downcase

        # Check each category's patterns
        DEFAULT_PATTERNS.each do |category, patterns|
          patterns.each do |pattern|
            return category if message_lower.match?(pattern)
          end
        end

        # Default to transient for unknown errors
        :transient
      end

      # Check if an error category is retryable
      # @param category [Symbol] error category
      # @return [Boolean] true if should retry
      def self.retryable?(category)
        policy = retry_policy(category)
        policy[:retry] == true
      end

      # Check if an error category should trigger provider switch
      # @param category [Symbol] error category
      # @return [Boolean] true if should switch provider
      def self.should_switch_provider?(category)
        policy = retry_policy(category)
        policy[:switch_provider] == true
      end

      # Check if an error category should be escalated
      # @param category [Symbol] error category
      # @return [Boolean] true if should escalate
      def self.should_escalate?(category)
        policy = retry_policy(category)
        policy[:escalate] == true
      end

      # Get backoff strategy for a category
      # @param category [Symbol] error category
      # @return [Symbol] backoff strategy (:none, :linear, :exponential)
      def self.backoff_strategy(category)
        policy = retry_policy(category)
        policy[:backoff_strategy] || :none
      end
    end
  end
end
