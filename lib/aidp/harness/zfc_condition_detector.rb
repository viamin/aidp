# frozen_string_literal: true

require_relative "condition_detector"
require_relative "ai_decision_engine"

module Aidp
  module Harness
    # ZFC-enabled wrapper for ConditionDetector
    #
    # Delegates semantic analysis to AI when ZFC is enabled, falls back to
    # legacy pattern matching when disabled or on AI failure.
    #
    # @example Basic usage
    #   detector = ZfcConditionDetector.new(config, provider_factory)
    #   if detector.is_rate_limited?(result)
    #     # Handle rate limit
    #   end
    #
    # @see docs/ZFC_COMPLIANCE_ASSESSMENT.md
    # @see docs/ZFC_IMPLEMENTATION_PLAN.md
    class ZfcConditionDetector
      attr_reader :config, :legacy_detector, :ai_engine, :stats

      # Initialize ZFC condition detector
      #
      # @param config [Configuration, ConfigManager] AIDP configuration
      # @param provider_factory [ProviderFactory, nil] Optional factory for creating providers
      def initialize(config, provider_factory: nil)
        @config = config
        @legacy_detector = ConditionDetector.new

        # Create ProviderFactory if not provided and ZFC is enabled
        # Note: ConfigManager doesn't have zfc_enabled?, so we check respond_to? first
        if provider_factory.nil? && config.respond_to?(:zfc_enabled?) && config.zfc_enabled?
          require_relative "provider_factory"
          provider_factory = ProviderFactory.new
        end

        @ai_engine = AIDecisionEngine.new(config, provider_factory: provider_factory)

        # Statistics for A/B testing
        @stats = {
          zfc_calls: 0,
          legacy_calls: 0,
          zfc_fallbacks: 0,
          agreements: 0,
          disagreements: 0,
          zfc_total_cost: 0.0
        }
      end

      # Check if result indicates rate limiting
      #
      # @param result [Hash] AI response or error
      # @param provider [String, nil] Provider name for context
      # @return [Boolean] true if rate limited
      def is_rate_limited?(result, provider = nil)
        detect_condition(:is_rate_limited?, result, provider: provider) do |ai_result|
          ai_result[:condition] == "rate_limit" &&
            ai_result[:confidence] >= confidence_threshold(:condition_detection)
        end
      end

      # Check if result needs user feedback
      #
      # @param result [Hash] AI response
      # @return [Boolean] true if user feedback needed
      def needs_user_feedback?(result)
        detect_condition(:needs_user_feedback?, result, provider: nil) do |ai_result|
          ai_result[:condition] == "user_feedback_needed" &&
            ai_result[:confidence] >= confidence_threshold(:condition_detection)
        end
      end

      # Check if work is complete
      #
      # @param result [Hash] AI response
      # @param progress [Hash, nil] Progress context
      # @return [Boolean] true if work complete
      def is_work_complete?(result, progress = nil)
        return false unless result

        if zfc_enabled?(:completion_detection)
          begin
            # Build context for AI decision
            context = {
              response: result_to_text(result),
              task_description: progress&.dig(:task) || "general task"
            }

            # Ask AI if work is complete
            ai_result = @ai_engine.decide(:completion_detection,
              context: context,
              tier: zfc_tier(:completion_detection),
              cache_ttl: zfc_cache_ttl(:completion_detection))

            record_zfc_call(:completion_detection, ai_result)

            # A/B test if enabled
            if ab_testing_enabled?
              legacy_result = @legacy_detector.is_work_complete?(result, progress)
              compare_results(:is_work_complete, ai_result[:complete], legacy_result)
            end

            ai_result[:complete] &&
              ai_result[:confidence] >= confidence_threshold(:completion_detection)
          rescue => e
            Aidp.log_error("zfc_condition_detector", "ZFC completion detection failed, falling back to legacy", {
              error: e.message,
              error_class: e.class.name
            })
            record_fallback(:completion_detection)
            @legacy_detector.is_work_complete?(result, progress)
          end
        else
          @stats[:legacy_calls] += 1
          @legacy_detector.is_work_complete?(result, progress)
        end
      end

      # Extract questions from result (delegates to legacy for now)
      #
      # @param result [Hash] AI response
      # @return [Array<Hash>] List of questions
      def extract_questions(result)
        @legacy_detector.extract_questions(result)
      end

      # Extract rate limit info (delegates to legacy for now)
      #
      # @param result [Hash] AI response or error
      # @param provider [String, nil] Provider name
      # @return [Hash] Rate limit information
      def extract_rate_limit_info(result, provider = nil)
        @legacy_detector.extract_rate_limit_info(result, provider)
      end

      # Classify error using AI or legacy pattern matching
      #
      # @param error [Exception, StandardError] Error to classify
      # @param context [Hash] Additional context (provider, model, etc.)
      # @return [Hash] Classification with error_type, retryable, recommended_action
      def classify_error(error, context = {})
        return @legacy_detector.classify_error(error) unless zfc_enabled?(:error_classification)

        begin
          # Build context for AI decision
          error_context = {
            error_message: error_to_text(error),
            context: context.to_s
          }

          # Ask AI to classify error
          ai_result = @ai_engine.decide(:error_classification,
            context: error_context,
            tier: zfc_tier(:error_classification),
            cache_ttl: zfc_cache_ttl(:error_classification))

          record_zfc_call(:error_classification, ai_result)

          # A/B test if enabled
          if ab_testing_enabled?
            legacy_result = @legacy_detector.classify_error(error)
            compare_error_results(ai_result, legacy_result)
          end

          # Only use AI result if confidence is high enough
          if ai_result[:confidence] >= confidence_threshold(:error_classification)
            # Convert AI result to legacy format
            {
              error: error,
              error_type: ai_result[:error_type].to_sym,
              retryable: ai_result[:retryable],
              recommended_action: ai_result[:recommended_action].to_sym,
              confidence: ai_result[:confidence],
              reasoning: ai_result[:reasoning],
              timestamp: Time.now,
              context: context,
              message: error&.message || "Unknown error"
            }
          else
            @legacy_detector.classify_error(error)
          end
        rescue => e
          Aidp.log_error("zfc_condition_detector", "ZFC error classification failed, falling back to legacy", {
            error: e.message,
            error_class: e.class.name,
            original_error: error&.class&.name
          })
          record_fallback(:error_classification)
          @legacy_detector.classify_error(error)
        end
      end

      # Get statistics summary
      #
      # @return [Hash] Statistics including accuracy, cost, performance
      def statistics
        total_calls = @stats[:zfc_calls] + @stats[:legacy_calls]
        return @stats.merge(total_calls: 0, accuracy: nil) if total_calls.zero?

        comparisons = @stats[:agreements] + @stats[:disagreements]
        accuracy = comparisons.zero? ? nil : (@stats[:agreements].to_f / comparisons * 100).round(2)

        @stats.merge(
          total_calls: total_calls,
          zfc_percentage: (@stats[:zfc_calls].to_f / total_calls * 100).round(2),
          accuracy: accuracy,
          fallback_rate: (@stats[:zfc_fallbacks].to_f / [@stats[:zfc_calls], 1].max * 100).round(2)
        )
      end

      private

      # Generic condition detection with ZFC/legacy fallback
      def detect_condition(method_name, result, provider: nil)
        return false unless result

        if zfc_enabled?(:condition_detection)
          begin
            # Build context for AI decision
            context = {
              response: result_to_text(result)
            }
            context[:provider] = provider if provider

            # Ask AI to classify condition
            ai_result = @ai_engine.decide(:condition_detection,
              context: context,
              tier: zfc_tier(:condition_detection),
              cache_ttl: zfc_cache_ttl(:condition_detection))

            record_zfc_call(:condition_detection, ai_result)

            # Convert AI result to boolean using provided block
            zfc_decision = yield(ai_result)

            # A/B test if enabled
            if ab_testing_enabled?
              # Call legacy method with appropriate arguments
              legacy_decision = call_legacy_method(method_name, result, provider)
              compare_results(method_name, zfc_decision, legacy_decision)
            end

            zfc_decision
          rescue => e
            Aidp.log_error("zfc_condition_detector", "ZFC condition detection failed, falling back to legacy", {
              error: e.message,
              error_class: e.class.name,
              method: method_name
            })
            record_fallback(:condition_detection)
            call_legacy_method(method_name, result, provider)
          end
        else
          @stats[:legacy_calls] += 1
          call_legacy_method(method_name, result, provider)
        end
      end

      # Call legacy method with appropriate arguments based on method signature
      def call_legacy_method(method_name, result, provider)
        case method_name
        when :is_rate_limited?
          @legacy_detector.send(method_name, result, provider)
        when :needs_user_feedback?
          @legacy_detector.send(method_name, result)
        else
          @legacy_detector.send(method_name, result, provider)
        end
      end

      # Convert result to text for AI analysis
      def result_to_text(result)
        case result
        when String
          result
        when Hash
          # Try common keys - match what ConditionDetector uses
          result[:output] || result[:content] || result[:message] || result[:error] || result[:response] || result.to_s
        else
          result.to_s
        end
      end

      # Convert error to text for AI analysis
      def error_to_text(error)
        return "Unknown error" unless error

        message = error.message || error.to_s
        error_class = error.class.name

        # Include error class and message
        text = "#{error_class}: #{message}"

        # Add backtrace context if available
        if error.backtrace && !error.backtrace.empty?
          text += "\nLocation: #{error.backtrace.first}"
        end

        text
      end

      # Check if ZFC is enabled for decision type
      def zfc_enabled?(decision_type)
        return false unless @config.respond_to?(:zfc_decision_enabled?)
        @config.zfc_decision_enabled?(decision_type)
      end

      # Get tier for ZFC decision type
      def zfc_tier(decision_type)
        return "mini" unless @config.respond_to?(:zfc_decision_tier)
        @config.zfc_decision_tier(decision_type)
      end

      # Get cache TTL for decision type
      def zfc_cache_ttl(decision_type)
        return nil unless @config.respond_to?(:zfc_decision_cache_ttl)
        @config.zfc_decision_cache_ttl(decision_type)
      end

      # Get confidence threshold for decision type
      def confidence_threshold(decision_type)
        return 0.7 unless @config.respond_to?(:zfc_decision_confidence_threshold)
        @config.zfc_decision_confidence_threshold(decision_type)
      end

      # Check if A/B testing is enabled
      def ab_testing_enabled?
        return false unless @config.respond_to?(:zfc_ab_testing_enabled?)
        @config.zfc_ab_testing_enabled?
      end

      # Record ZFC call for statistics
      def record_zfc_call(decision_type, ai_result)
        @stats[:zfc_calls] += 1

        # Estimate cost (very rough)
        # Mini tier: ~$0.15/MTok input, $0.75/MTok output
        # Assume ~500 tokens input, ~100 tokens output per decision
        estimated_cost = (500 * 0.15 / 1_000_000) + (100 * 0.75 / 1_000_000)
        @stats[:zfc_total_cost] += estimated_cost
      end

      # Record fallback to legacy
      def record_fallback(decision_type)
        @stats[:zfc_fallbacks] += 1
      end

      # Compare ZFC vs legacy results for A/B testing
      def compare_results(method_name, zfc_result, legacy_result)
        if zfc_result == legacy_result
          @stats[:agreements] += 1
        else
          @stats[:disagreements] += 1

          # Log comparisons if configured (only available in Configuration, not ConfigManager)
          if @config.respond_to?(:zfc_ab_testing_config) &&
              @config.zfc_ab_testing_config[:log_comparisons]
            Aidp.log_debug("zfc_ab_testing", "ZFC vs Legacy disagreement", {
              method: method_name,
              zfc_result: zfc_result,
              legacy_result: legacy_result
            })
          end
        end
      end

      # Compare ZFC vs legacy error classification results
      def compare_error_results(ai_result, legacy_result)
        # Extract comparable fields
        ai_error_type = ai_result[:error_type].to_sym
        legacy_error_type = legacy_result[:error_type]

        if ai_error_type == legacy_error_type
          @stats[:agreements] += 1
        else
          @stats[:disagreements] += 1

          # Log comparisons if configured
          if @config.respond_to?(:zfc_ab_testing_config) &&
              @config.zfc_ab_testing_config[:log_comparisons]
            Aidp.log_debug("zfc_ab_testing", "Error classification disagreement", {
              ai_error_type: ai_error_type,
              legacy_error_type: legacy_error_type,
              ai_retryable: ai_result[:retryable],
              ai_action: ai_result[:recommended_action],
              ai_confidence: ai_result[:confidence]
            })
          end
        end
      end
    end
  end
end
