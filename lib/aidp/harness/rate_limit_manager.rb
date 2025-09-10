# frozen_string_literal: true

module Aidp
  module Harness
    # Manages rate limiting, provider rotation, and intelligent retry strategies
    class RateLimitManager
      def initialize(provider_manager, configuration)
        @provider_manager = provider_manager
        @configuration = configuration
        @rate_limit_info = {}
        @rotation_history = []
        @retry_strategies = {}
        @backoff_calculator = BackoffCalculator.new
        @rate_limit_detector = RateLimitDetector.new
        @rotation_strategies = {}
        @quota_tracker = QuotaTracker.new
        @cost_optimizer = CostOptimizer.new
        initialize_retry_strategies
        initialize_rotation_strategies
      end

      # Handle rate limit detection and response
      def handle_rate_limit(provider_name, model_name, response, error = nil)
        # Detect rate limit information
        rate_limit_info = @rate_limit_detector.detect_rate_limit(response, error)

        if rate_limit_info[:is_rate_limited]
          # Record rate limit
          record_rate_limit(provider_name, model_name, rate_limit_info)

          # Calculate rotation strategy
          rotation_strategy = determine_rotation_strategy(provider_name, model_name, rate_limit_info)

          # Execute rotation
          rotation_result = execute_rotation(provider_name, model_name, rotation_strategy, rate_limit_info)

          # Update quota tracking
          @quota_tracker.record_rate_limit(provider_name, model_name, rate_limit_info)

          # Optimize costs if needed
          @cost_optimizer.optimize_for_rate_limit(provider_name, model_name, rate_limit_info)

          rotation_result
        else
          # Not rate limited, clear any existing rate limits
          clear_rate_limit(provider_name, model_name)
          { success: true, action: "continue", provider: provider_name, model: model_name }
        end
      end

      # Get next available provider/model combination
      def get_next_available_combination(current_provider, current_model, context = {})
        # Get rotation strategy based on context
        strategy = get_rotation_strategy_for_context(context)

        case strategy
        when "provider_first"
          get_next_provider_first(current_provider, current_model, context)
        when "model_first"
          get_next_model_first(current_provider, current_model, context)
        when "cost_optimized"
          get_next_cost_optimized(current_provider, current_model, context)
        when "performance_optimized"
          get_next_performance_optimized(current_provider, current_model, context)
        when "quota_aware"
          get_next_quota_aware(current_provider, current_model, context)
        else
          get_next_default(current_provider, current_model, context)
        end
      end

      # Check if provider/model is rate limited
      def is_rate_limited?(provider_name, model_name = nil)
        if model_name
          @provider_manager.is_model_rate_limited?(provider_name, model_name)
        else
          @provider_manager.is_rate_limited?(provider_name)
        end
      end

      # Get rate limit status for all providers/models
      def get_rate_limit_status
        status = {
          providers: {},
          models: {},
          next_reset_times: [],
          rotation_history: @rotation_history.last(10),
          quota_status: @quota_tracker.get_status,
          cost_optimization: @cost_optimizer.get_status
        }

        # Get provider rate limit status
        @provider_manager.configured_providers.each do |provider|
          status[:providers][provider] = {
            rate_limited: @provider_manager.is_rate_limited?(provider),
            reset_time: get_provider_reset_time(provider),
            quota_used: @quota_tracker.get_quota_used(provider),
            quota_limit: @quota_tracker.get_quota_limit(provider)
          }
        end

        # Get model rate limit status
        @provider_manager.configured_providers.each do |provider|
          status[:models][provider] = {}
          @provider_manager.get_provider_models(provider).each do |model|
            status[:models][provider][model] = {
              rate_limited: @provider_manager.is_model_rate_limited?(provider, model),
              reset_time: get_model_reset_time(provider, model),
              quota_used: @quota_tracker.get_quota_used(provider, model),
              quota_limit: @quota_tracker.get_quota_limit(provider, model)
            }
          end
        end

        # Get next reset times
        status[:next_reset_times] = get_all_reset_times

        status
      end

      # Get retry strategy for error type
      def get_retry_strategy(error_type, context = {})
        strategy = @retry_strategies[error_type] || @retry_strategies[:default]

        # Customize strategy based on context
        customized_strategy = strategy.dup
        customized_strategy[:context] = context
        customized_strategy[:backoff_delay] = @backoff_calculator.calculate_delay(
          strategy[:base_delay],
          strategy[:max_delay],
          strategy[:exponential_base],
          context[:retry_count] || 0
        )

        customized_strategy
      end

      # Execute retry with strategy
      def execute_retry(provider_name, model_name, error_type, context = {})
        strategy = get_retry_strategy(error_type, context)

        # Check if we should retry
        return { success: false, action: "no_retry", reason: "max_retries_exceeded" } unless should_retry?(strategy, context)

        # Calculate delay
        delay = strategy[:backoff_delay]

        # Apply jitter if enabled
        delay = apply_jitter(delay, strategy[:jitter]) if strategy[:jitter]

        # Wait for delay
        sleep(delay) if delay > 0

        # Get next available combination
        next_combination = get_next_available_combination(provider_name, model_name, context)

        # Record retry attempt
        record_retry_attempt(provider_name, model_name, error_type, strategy, next_combination)

        next_combination
      end

      # Clear rate limit for provider/model
      def clear_rate_limit(provider_name, model_name = nil)
        if model_name
          @provider_manager.clear_model_rate_limit(provider_name, model_name)
        else
          @provider_manager.clear_rate_limit(provider_name)
        end

        # Update quota tracker
        @quota_tracker.clear_rate_limit(provider_name, model_name)
      end

      # Get rotation statistics
      def get_rotation_statistics
        {
          total_rotations: @rotation_history.size,
          rotations_by_reason: @rotation_history.group_by { |r| r[:reason] }.transform_values(&:size),
          rotations_by_provider: @rotation_history.group_by { |r| r[:from_provider] }.transform_values(&:size),
          average_rotation_time: calculate_average_rotation_time,
          success_rate: calculate_rotation_success_rate,
          cost_impact: @cost_optimizer.get_cost_impact,
          quota_efficiency: @quota_tracker.get_efficiency_metrics
        }
      end

      private

      # Initialize retry strategies
      def initialize_retry_strategies
        @retry_strategies = {
          rate_limit: {
            max_retries: 3,
            base_delay: 1.0,
            max_delay: 300.0, # 5 minutes
            exponential_base: 2.0,
            jitter: true,
            strategy: "exponential_backoff"
          },
          network_error: {
            max_retries: 5,
            base_delay: 0.5,
            max_delay: 60.0,
            exponential_base: 1.5,
            jitter: true,
            strategy: "linear_backoff"
          },
          server_error: {
            max_retries: 3,
            base_delay: 2.0,
            max_delay: 120.0,
            exponential_base: 2.0,
            jitter: true,
            strategy: "exponential_backoff"
          },
          timeout: {
            max_retries: 2,
            base_delay: 5.0,
            max_delay: 30.0,
            exponential_base: 1.5,
            jitter: false,
            strategy: "fixed_delay"
          },
          authentication: {
            max_retries: 1,
            base_delay: 0.0,
            max_delay: 0.0,
            exponential_base: 1.0,
            jitter: false,
            strategy: "immediate_fail"
          },
          default: {
            max_retries: 3,
            base_delay: 1.0,
            max_delay: 60.0,
            exponential_base: 2.0,
            jitter: true,
            strategy: "exponential_backoff"
          }
        }
      end

      # Initialize rotation strategies
      def initialize_rotation_strategies
        @rotation_strategies = {
          provider_first: {
            description: "Try different providers before switching models",
            priority: ["provider", "model"],
            cost_aware: false
          },
          model_first: {
            description: "Try different models before switching providers",
            priority: ["model", "provider"],
            cost_aware: false
          },
          cost_optimized: {
            description: "Optimize for cost while maintaining performance",
            priority: ["cost", "performance"],
            cost_aware: true
          },
          performance_optimized: {
            description: "Optimize for performance regardless of cost",
            priority: ["performance", "cost"],
            cost_aware: false
          },
          quota_aware: {
            description: "Consider quota limits when rotating",
            priority: ["quota", "performance"],
            cost_aware: true
          }
        }
      end

      # Record rate limit
      def record_rate_limit(provider_name, model_name, rate_limit_info)
        if model_name
          @provider_manager.mark_model_rate_limited(provider_name, model_name, rate_limit_info[:reset_time])
        else
          @provider_manager.mark_rate_limited(provider_name, rate_limit_info[:reset_time])
        end

        # Log rate limit
        log_rate_limit(provider_name, model_name, rate_limit_info)
      end

      # Determine rotation strategy
      def determine_rotation_strategy(provider_name, model_name, rate_limit_info)
        # Determine strategy based on rate limit type and context
        case rate_limit_info[:type]
        when "quota_exceeded"
          "quota_aware"
        when "rate_limit"
          if @cost_optimizer.should_optimize_cost?(provider_name, model_name)
            "cost_optimized"
          else
            "performance_optimized"
          end
        when "burst_limit"
          "model_first"
        else
          "provider_first"
        end
      end

      # Execute rotation
      def execute_rotation(provider_name, model_name, strategy, rate_limit_info)
        start_time = Time.now

        case strategy
        when "provider_first"
          result = rotate_provider_first(provider_name, model_name, rate_limit_info)
        when "model_first"
          result = rotate_model_first(provider_name, model_name, rate_limit_info)
        when "cost_optimized"
          result = rotate_cost_optimized(provider_name, model_name, rate_limit_info)
        when "performance_optimized"
          result = rotate_performance_optimized(provider_name, model_name, rate_limit_info)
        when "quota_aware"
          result = rotate_quota_aware(provider_name, model_name, rate_limit_info)
        else
          result = rotate_default(provider_name, model_name, rate_limit_info)
        end

        # Record rotation
        record_rotation(provider_name, model_name, strategy, result, Time.now - start_time)

        result
      end

      # Rotation strategies
      def rotate_provider_first(provider_name, model_name, rate_limit_info)
        # Try switching provider first
        next_provider = @provider_manager.switch_provider("rate_limit", {
          model: model_name,
          rate_limit_info: rate_limit_info
        })

        if next_provider
          {
            success: true,
            action: "provider_switch",
            provider: next_provider,
            model: @provider_manager.get_default_model(next_provider),
            strategy: "provider_first"
          }
        else
          # Try switching model within current provider
          next_model = @provider_manager.switch_model("rate_limit", {
            provider: provider_name,
            rate_limit_info: rate_limit_info
          })

          if next_model
            {
              success: true,
              action: "model_switch",
              provider: provider_name,
              model: next_model,
              strategy: "provider_first"
            }
          else
            {
              success: false,
              action: "no_rotation",
              reason: "no_available_alternatives",
              strategy: "provider_first"
            }
          end
        end
      end

      def rotate_model_first(provider_name, model_name, rate_limit_info)
        # Try switching model first
        next_model = @provider_manager.switch_model("rate_limit", {
          provider: provider_name,
          rate_limit_info: rate_limit_info
        })

        if next_model
          {
            success: true,
            action: "model_switch",
            provider: provider_name,
            model: next_model,
            strategy: "model_first"
          }
        else
          # Try switching provider
          next_provider = @provider_manager.switch_provider("rate_limit", {
            model: model_name,
            rate_limit_info: rate_limit_info
          })

          if next_provider
            {
              success: true,
              action: "provider_switch",
              provider: next_provider,
              model: @provider_manager.get_default_model(next_provider),
              strategy: "model_first"
            }
          else
            {
              success: false,
              action: "no_rotation",
              reason: "no_available_alternatives",
              strategy: "model_first"
            }
          end
        end
      end

      def rotate_cost_optimized(provider_name, model_name, rate_limit_info)
        # Get cost-optimized combination
        combination = @cost_optimizer.get_cost_optimized_combination(provider_name, model_name, rate_limit_info)

        if combination
          # Switch to cost-optimized combination
          if combination[:provider] != provider_name
            @provider_manager.set_current_provider(combination[:provider], "cost_optimization")
          end

          if combination[:model] != model_name
            @provider_manager.set_current_model(combination[:model], "cost_optimization")
          end

          {
            success: true,
            action: "cost_optimized_switch",
            provider: combination[:provider],
            model: combination[:model],
            strategy: "cost_optimized",
            cost_savings: combination[:cost_savings]
          }
        else
          # Fallback to default rotation
          rotate_default(provider_name, model_name, rate_limit_info)
        end
      end

      def rotate_performance_optimized(provider_name, model_name, rate_limit_info)
        # Get performance-optimized combination
        combination = get_performance_optimized_combination(provider_name, model_name, rate_limit_info)

        if combination
          # Switch to performance-optimized combination
          if combination[:provider] != provider_name
            @provider_manager.set_current_provider(combination[:provider], "performance_optimization")
          end

          if combination[:model] != model_name
            @provider_manager.set_current_model(combination[:model], "performance_optimization")
          end

          {
            success: true,
            action: "performance_optimized_switch",
            provider: combination[:provider],
            model: combination[:model],
            strategy: "performance_optimized",
            performance_boost: combination[:performance_boost]
          }
        else
          # Fallback to default rotation
          rotate_default(provider_name, model_name, rate_limit_info)
        end
      end

      def rotate_quota_aware(provider_name, model_name, rate_limit_info)
        # Get quota-aware combination
        combination = @quota_tracker.get_quota_aware_combination(provider_name, model_name, rate_limit_info)

        if combination
          # Switch to quota-aware combination
          if combination[:provider] != provider_name
            @provider_manager.set_current_provider(combination[:provider], "quota_aware")
          end

          if combination[:model] != model_name
            @provider_manager.set_current_model(combination[:model], "quota_aware")
          end

          {
            success: true,
            action: "quota_aware_switch",
            provider: combination[:provider],
            model: combination[:model],
            strategy: "quota_aware",
            quota_remaining: combination[:quota_remaining]
          }
        else
          # Fallback to default rotation
          rotate_default(provider_name, model_name, rate_limit_info)
        end
      end

      def rotate_default(provider_name, model_name, rate_limit_info)
        # Default rotation: try provider first, then model
        rotate_provider_first(provider_name, model_name, rate_limit_info)
      end

      # Get next available combinations
      def get_next_provider_first(current_provider, _current_model, context)
        # Try switching provider first
        next_provider = @provider_manager.switch_provider("rotation", context)

        if next_provider
          {
            success: true,
            action: "provider_switch",
            provider: next_provider,
            model: @provider_manager.get_default_model(next_provider)
          }
        else
          # Try switching model
          next_model = @provider_manager.switch_model("rotation", context)

          if next_model
            {
              success: true,
              action: "model_switch",
              provider: current_provider,
              model: next_model
            }
          else
            {
              success: false,
              action: "no_rotation",
              reason: "no_available_alternatives"
            }
          end
        end
      end

      def get_next_model_first(current_provider, _current_model, context)
        # Try switching model first
        next_model = @provider_manager.switch_model("rotation", context)

        if next_model
          {
            success: true,
            action: "model_switch",
            provider: current_provider,
            model: next_model
          }
        else
          # Try switching provider
          next_provider = @provider_manager.switch_provider("rotation", context)

          if next_provider
            {
              success: true,
              action: "provider_switch",
              provider: next_provider,
              model: @provider_manager.get_default_model(next_provider)
            }
          else
            {
              success: false,
              action: "no_rotation",
              reason: "no_available_alternatives"
            }
          end
        end
      end

      def get_next_cost_optimized(current_provider, current_model, context)
        combination = @cost_optimizer.get_cost_optimized_combination(current_provider, current_model, context)

        if combination
          {
            success: true,
            action: "cost_optimized_switch",
            provider: combination[:provider],
            model: combination[:model],
            cost_savings: combination[:cost_savings]
          }
        else
          get_next_default(current_provider, current_model, context)
        end
      end

      def get_next_performance_optimized(current_provider, current_model, context)
        combination = get_performance_optimized_combination(current_provider, current_model, context)

        if combination
          {
            success: true,
            action: "performance_optimized_switch",
            provider: combination[:provider],
            model: combination[:model],
            performance_boost: combination[:performance_boost]
          }
        else
          get_next_default(current_provider, current_model, context)
        end
      end

      def get_next_quota_aware(current_provider, current_model, context)
        combination = @quota_tracker.get_quota_aware_combination(current_provider, current_model, context)

        if combination
          {
            success: true,
            action: "quota_aware_switch",
            provider: combination[:provider],
            model: combination[:model],
            quota_remaining: combination[:quota_remaining]
          }
        else
          get_next_default(current_provider, current_model, context)
        end
      end

      def get_next_default(current_provider, current_model, context)
        get_next_provider_first(current_provider, current_model, context)
      end

      # Utility methods
      def get_rotation_strategy_for_context(context)
        context[:rotation_strategy] || @configuration.rate_limit_config[:rotation_strategy] || "provider_first"
      end

      def should_retry?(strategy, context)
        retry_count = context[:retry_count] || 0
        retry_count < strategy[:max_retries]
      end

      def apply_jitter(delay, jitter_enabled)
        return delay unless jitter_enabled

        # Add ±25% jitter
        jitter_factor = 0.25
        jitter = delay * jitter_factor * (rand - 0.5) * 2
        delay + jitter
      end

      def record_retry_attempt(provider_name, model_name, error_type, strategy, result)
        @rotation_history << {
          timestamp: Time.now,
          type: "retry",
          from_provider: provider_name,
          from_model: model_name,
          to_provider: result[:provider],
          to_model: result[:model],
          error_type: error_type,
          strategy: strategy[:strategy],
          success: result[:success],
          reason: "retry_attempt"
        }
      end

      def record_rotation(provider_name, model_name, strategy, result, duration)
        @rotation_history << {
          timestamp: Time.now,
          type: "rotation",
          from_provider: provider_name,
          from_model: model_name,
          to_provider: result[:provider],
          to_model: result[:model],
          strategy: strategy,
          success: result[:success],
          duration: duration,
          reason: result[:action]
        }
      end

      def log_rate_limit(provider_name, model_name, rate_limit_info)
        puts "🚫 Rate limit detected: #{provider_name}:#{model_name}"
        puts "   Type: #{rate_limit_info[:type]}"
        puts "   Reset time: #{rate_limit_info[:reset_time]}"
        puts "   Retry after: #{rate_limit_info[:retry_after]}"
      end

      def get_provider_reset_time(provider_name)
        @provider_manager.instance_variable_get(:@rate_limit_info)[provider_name]&.dig(:reset_time)
      end

      def get_model_reset_time(provider_name, model_name)
        model_key = "#{provider_name}:#{model_name}"
        @provider_manager.instance_variable_get(:@model_rate_limit_info)&.dig(model_key, :reset_time)
      end

      def get_all_reset_times
        reset_times = []

        # Provider reset times
        @provider_manager.instance_variable_get(:@rate_limit_info).each do |provider, info|
          reset_times << { provider: provider, reset_time: info[:reset_time] } if info[:reset_time]
        end

        # Model reset times
        @provider_manager.instance_variable_get(:@model_rate_limit_info)&.each do |model_key, info|
          reset_times << { model: model_key, reset_time: info[:reset_time] } if info[:reset_time]
        end

        reset_times.sort_by { |r| r[:reset_time] }
      end

      def calculate_average_rotation_time
        rotations = @rotation_history.select { |r| r[:duration] }
        return 0 if rotations.empty?

        rotations.sum { |r| r[:duration] } / rotations.size
      end

      def calculate_rotation_success_rate
        return 0 if @rotation_history.empty?

        successful_rotations = @rotation_history.count { |r| r[:success] }
        successful_rotations.to_f / @rotation_history.size
      end

      def get_performance_optimized_combination(provider_name, model_name, _context)
        # Get all available combinations
        combinations = get_all_available_combinations(provider_name, model_name)

        # Score combinations by performance
        scored_combinations = combinations.map do |combo|
          score = calculate_performance_score(combo[:provider], combo[:model])
          combo.merge(performance_score: score)
        end

        # Return highest scoring combination
        scored_combinations.max_by { |c| c[:performance_score] }
      end

      def get_all_available_combinations(_current_provider, _current_model)
        combinations = []

        @provider_manager.configured_providers.each do |provider|
          next if @provider_manager.is_rate_limited?(provider)

          @provider_manager.get_provider_models(provider).each do |model|
            next if @provider_manager.is_model_rate_limited?(provider, model)

            combinations << { provider: provider, model: model }
          end
        end

        combinations
      end

      def calculate_performance_score(provider_name, _model_name)
        # Get metrics for provider and model
        provider_metrics = @provider_manager.get_metrics(provider_name)

        # Calculate performance score based on success rate, response time, etc.
        success_rate = provider_metrics[:successful_requests].to_f / [provider_metrics[:total_requests], 1].max
        avg_response_time = provider_metrics[:total_duration] / [provider_metrics[:successful_requests], 1].max

        # Higher score is better
        score = success_rate * 100 - avg_response_time
        score
      end

      # Helper classes
      class BackoffCalculator
        def calculate_delay(base_delay, max_delay, exponential_base, retry_count)
          delay = base_delay * (exponential_base ** retry_count)
          [delay, max_delay].min
        end
      end

      class RateLimitDetector
        def detect_rate_limit(response, error)
          # Detect rate limit from response or error
          if error&.message&.include?("rate limit")
            {
              is_rate_limited: true,
              type: "rate_limit",
              reset_time: calculate_reset_time,
              retry_after: 60
            }
          elsif response&.include?("quota exceeded")
            {
              is_rate_limited: true,
              type: "quota_exceeded",
              reset_time: calculate_quota_reset_time,
              retry_after: 3600
            }
          else
            { is_rate_limited: false }
          end
        end

        private

        def calculate_reset_time
          Time.now + 3600 # 1 hour default
        end

        def calculate_quota_reset_time
          Time.now + 86400 # 24 hours default
        end
      end

      class QuotaTracker
        def initialize
          @quota_usage = {}
          @quota_limits = {}
        end

        def record_rate_limit(provider_name, model_name, _rate_limit_info)
          key = model_name ? "#{provider_name}:#{model_name}" : provider_name
          @quota_usage[key] ||= 0
          @quota_usage[key] += 1
        end

        def clear_rate_limit(provider_name, model_name)
          key = model_name ? "#{provider_name}:#{model_name}" : provider_name
          @quota_usage.delete(key)
        end

        def get_quota_used(provider_name, model_name = nil)
          key = model_name ? "#{provider_name}:#{model_name}" : provider_name
          @quota_usage[key] || 0
        end

        def get_quota_limit(provider_name, model_name = nil)
          key = model_name ? "#{provider_name}:#{model_name}" : provider_name
          @quota_limits[key] || 1000 # Default limit
        end

        def get_quota_aware_combination(current_provider, current_model, context)
          # Find combination with most quota remaining
          # This would be implemented with actual quota checking
          # For now, return a simple fallback
          _ = context # Suppress unused argument warning
          { provider: current_provider, model: current_model, quota_remaining: 1000 }
        end

        def get_status
          {
            quota_usage: @quota_usage.dup,
            quota_limits: @quota_limits.dup
          }
        end

        def get_efficiency_metrics
          {
            total_quota_used: @quota_usage.values.sum,
            average_quota_usage: @quota_usage.values.sum.to_f / [@quota_usage.size, 1].max
          }
        end
      end

      class CostOptimizer
        def initialize
          @cost_models = {}
          @cost_history = {}
        end

        def should_optimize_cost?(_provider_name, _model_name)
          # Determine if cost optimization should be applied
          true # Simplified for now
        end

        def get_cost_optimized_combination(current_provider, current_model, _context)
          # Find most cost-effective combination
          # This would be implemented with actual cost models
          { provider: current_provider, model: current_model, cost_savings: 0.1 }
        end

        def optimize_for_rate_limit(provider_name, model_name, _rate_limit_info)
          # Optimize cost based on rate limit
          # Implementation would track cost optimization based on rate limits
          _ = provider_name
          _ = model_name
        end

        def get_status
          {
            cost_models: @cost_models.dup,
            cost_history: @cost_history.dup
          }
        end

        def get_cost_impact
          {
            total_cost_savings: 0.0,
            cost_optimization_rate: 0.0
          }
        end
      end
    end
  end
end
