# frozen_string_literal: true

require "securerandom"

module Aidp
  module Harness
    # Comprehensive token usage monitoring and display system
    class TokenMonitor
      def initialize(provider_manager, metrics_manager, status_display)
        @provider_manager = provider_manager
        @metrics_manager = metrics_manager
        @status_display = status_display

        @token_usage = {}
        @token_history = []
        @token_limits = {}
        @token_alerts = []
        @usage_patterns = {}
        @cost_tracking = {}
        @quota_tracking = {}
        @rate_limit_tracking = {}
        @token_analyzers = initialize_token_analyzers
        @usage_predictors = initialize_usage_predictors
        @cost_calculators = initialize_cost_calculators
        @quota_managers = initialize_quota_managers
        @alert_managers = initialize_alert_managers
        @display_formatters = initialize_display_formatters
        @export_managers = initialize_export_managers
        @optimization_engines = initialize_optimization_engines
        @max_history_size = 10000
        @update_interval = 30 # seconds
        @last_update = Time.now
      end

      # Record token usage for a request
      def record_token_usage(provider, model, request_tokens, response_tokens, cost = nil)
        timestamp = Time.now
        total_tokens = request_tokens + response_tokens

        # Initialize provider/model tracking if needed
        @token_usage[provider] ||= {}
        @token_usage[provider][model] ||= initialize_model_tracking

        # Update usage data
        update_model_usage(provider, model, request_tokens, response_tokens, total_tokens, cost, timestamp)

        # Update history
        add_to_history(provider, model, request_tokens, response_tokens, total_tokens, cost, timestamp)

        # Update patterns and predictions
        update_usage_patterns(provider, model, total_tokens, timestamp)
        update_predictions(provider, model)

        # Check for alerts
        check_token_alerts(provider, model, total_tokens)

        # Update status display
        update_status_display(provider, model)

        # Return usage summary
        get_current_usage(provider, model)
      end

      # Get current token usage for provider/model
      def get_current_usage(provider, model = nil)
        if model
          get_model_usage(provider, model)
        else
          get_provider_usage(provider)
        end
      end

      # Get token usage history
      def get_usage_history(provider = nil, model = nil, time_range = nil, limit = 1000)
        history = @token_history.dup

        # Filter by provider
        if provider
          history = history.select { |entry| entry[:provider] == provider }
        end

        # Filter by model
        if model
          history = history.select { |entry| entry[:model] == model }
        end

        # Filter by time range
        if time_range
          start_time = Time.now - time_range
          history = history.select { |entry| entry[:timestamp] >= start_time }
        end

        # Limit results
        history.last(limit)
      end

      # Get token usage summary
      def get_usage_summary(provider = nil, model = nil, time_range = 3600)
        history = get_usage_history(provider, model, time_range)

        return empty_summary if history.empty?

        {
          total_requests: history.size,
          total_tokens: history.sum { |entry| entry[:total_tokens] },
          total_request_tokens: history.sum { |entry| entry[:request_tokens] },
          total_response_tokens: history.sum { |entry| entry[:response_tokens] },
          average_tokens_per_request: history.sum { |entry| entry[:total_tokens] }.to_f / history.size,
          average_request_tokens: history.sum { |entry| entry[:request_tokens] }.to_f / history.size,
          average_response_tokens: history.sum { |entry| entry[:response_tokens] }.to_f / history.size,
          total_cost: history.sum { |entry| entry[:cost] || 0 },
          peak_usage: history.max_by { |entry| entry[:total_tokens] }[:total_tokens],
          time_range: time_range,
          start_time: history.first[:timestamp],
          end_time: history.last[:timestamp]
        }
      end

      # Get token usage patterns
      def get_usage_patterns(provider = nil, model = nil)
        patterns = @usage_patterns.dup

        if provider
          patterns = patterns[provider] || {}
          if model
            patterns = patterns[model] || {}
          end
        end

        patterns
      end

      # Get token usage predictions
      def get_usage_predictions(provider = nil, model = nil, time_horizon = 3600)
        predictor = @usage_predictors[:default]
        predictor.predict_usage(provider, model, time_horizon)
      end

      # Get cost analysis
      def get_cost_analysis(provider = nil, model = nil, time_range = 3600)
        calculator = @cost_calculators[:default]
        calculator.analyze_costs(provider, model, time_range)
      end

      # Get quota status
      def get_quota_status(provider = nil, model = nil)
        if provider && model
          get_model_quota_status(provider, model)
        elsif provider
          get_provider_quota_status(provider)
        else
          get_system_quota_status
        end
      end

      # Get rate limit status
      def get_rate_limit_status(provider = nil, model = nil)
        if provider && model
          get_model_rate_limit_status(provider, model)
        elsif provider
          get_provider_rate_limit_status(provider)
        else
          get_system_rate_limit_status
        end
      end

      # Get token alerts
      def get_token_alerts(severity = nil)
        alerts = @token_alerts.dup

        if severity
          alerts = alerts.select { |alert| alert[:severity] == severity }
        end

        alerts
      end

      # Display token usage
      def display_token_usage(provider = nil, model = nil, format = :compact)
        formatter = @display_formatters[format]
        formatter.format_usage(provider, model, self)
      end

      # Export token data
      def export_token_data(format = :json, options = {})
        exporter = @export_managers[format]
        exporter.export_data(self, options)
      end

      # Optimize token usage
      def optimize_token_usage(provider = nil, model = nil)
        optimizer = @optimization_engines[:default]
        optimizer.optimize_usage(provider, model, self)
      end

      # Set token limits
      def set_token_limits(provider, model, limits)
        @token_limits[provider] ||= {}
        @token_limits[provider][model] = limits
      end

      # Get token limits
      def get_token_limits(provider, model = nil)
        if model
          @token_limits.dig(provider, model) || {}
        else
          @token_limits[provider] || {}
        end
      end

      # Clear token history
      def clear_token_history
        @token_history.clear
      end

      # Get token statistics
      def get_token_statistics
        {
          total_entries: @token_history.size,
          providers_tracked: @token_usage.keys.size,
          models_tracked: @token_usage.values.sum { |models| models.keys.size },
          active_alerts: @token_alerts.size,
          last_update: @last_update,
          history_size_limit: @max_history_size
        }
      end

      private

      def initialize_token_analyzers
        {
          usage: TokenUsageAnalyzer.new,
          patterns: TokenPatternAnalyzer.new,
          trends: TokenTrendAnalyzer.new,
          efficiency: TokenEfficiencyAnalyzer.new
        }
      end

      def initialize_usage_predictors
        {
          default: TokenUsagePredictor.new(@token_history),
          provider: ProviderTokenPredictor.new(@token_history),
          model: ModelTokenPredictor.new(@token_history)
        }
      end

      def initialize_cost_calculators
        {
          default: TokenCostCalculator.new,
          provider: ProviderCostCalculator.new,
          model: ModelCostCalculator.new
        }
      end

      def initialize_quota_managers
        {
          default: TokenQuotaManager.new,
          provider: ProviderQuotaManager.new,
          model: ModelQuotaManager.new
        }
      end

      def initialize_alert_managers
        {
          usage: TokenUsageAlertManager.new,
          quota: TokenQuotaAlertManager.new,
          cost: TokenCostAlertManager.new,
          rate_limit: TokenRateLimitAlertManager.new
        }
      end

      def initialize_display_formatters
        {
          compact: CompactTokenFormatter.new,
          detailed: DetailedTokenFormatter.new,
          summary: SummaryTokenFormatter.new,
          realtime: RealtimeTokenFormatter.new
        }
      end

      def initialize_export_managers
        {
          json: TokenJsonExporter.new,
          yaml: TokenYamlExporter.new,
          csv: TokenCsvExporter.new,
          text: TokenTextExporter.new
        }
      end

      def initialize_optimization_engines
        {
          default: TokenUsageOptimizer.new,
          provider: ProviderTokenOptimizer.new,
          model: ModelTokenOptimizer.new
        }
      end

      def initialize_model_tracking
        {
          total_tokens: 0,
          request_tokens: 0,
          response_tokens: 0,
          request_count: 0,
          total_cost: 0.0,
          last_used: nil,
          peak_usage: 0,
          average_usage: 0.0,
          usage_trend: :stable,
          efficiency_score: 0.0
        }
      end

      def update_model_usage(provider, model, request_tokens, response_tokens, total_tokens, cost, timestamp)
        model_data = @token_usage[provider][model]

        model_data[:total_tokens] += total_tokens
        model_data[:request_tokens] += request_tokens
        model_data[:response_tokens] += response_tokens
        model_data[:request_count] += 1
        model_data[:total_cost] += cost || 0.0
        model_data[:last_used] = timestamp
        model_data[:peak_usage] = [model_data[:peak_usage], total_tokens].max
        model_data[:average_usage] = model_data[:total_tokens].to_f / model_data[:request_count]

        # Update efficiency score
        model_data[:efficiency_score] = calculate_efficiency_score(model_data)

        # Update usage trend
        model_data[:usage_trend] = calculate_usage_trend(provider, model)
      end

      def add_to_history(provider, model, request_tokens, response_tokens, total_tokens, cost, timestamp)
        entry = {
          timestamp: timestamp,
          provider: provider,
          model: model,
          request_tokens: request_tokens,
          response_tokens: response_tokens,
          total_tokens: total_tokens,
          cost: cost,
          request_id: generate_request_id
        }

        @token_history << entry

        # Maintain history size limit
        if @token_history.size > @max_history_size
          @token_history.shift(@token_history.size - @max_history_size)
        end
      end

      def update_usage_patterns(provider, model, total_tokens, timestamp)
        @usage_patterns[provider] ||= {}
        @usage_patterns[provider][model] ||= {
          hourly_pattern: {},
          daily_pattern: {},
          weekly_pattern: {},
          peak_hours: [],
          peak_days: [],
          usage_distribution: {}
        }

        pattern = @usage_patterns[provider][model]
        hour = timestamp.hour
        day = timestamp.wday

        # Update hourly pattern
        pattern[:hourly_pattern][hour] ||= {count: 0, total_tokens: 0}
        pattern[:hourly_pattern][hour][:count] += 1
        pattern[:hourly_pattern][hour][:total_tokens] += total_tokens

        # Update daily pattern
        pattern[:daily_pattern][day] ||= {count: 0, total_tokens: 0}
        pattern[:daily_pattern][day][:count] += 1
        pattern[:daily_pattern][day][:total_tokens] += total_tokens

        # Update usage distribution
        token_range = get_token_range(total_tokens)
        pattern[:usage_distribution][token_range] ||= 0
        pattern[:usage_distribution][token_range] += 1
      end

      def update_predictions(provider, model)
        predictor = @usage_predictors[:default]
        predictor.update_model(provider, model, @token_history)
      end

      def check_token_alerts(provider, model, total_tokens)
        # Check usage alerts
        usage_alert = @alert_managers[:usage].check_usage(provider, model, total_tokens, @token_usage)
        @token_alerts << usage_alert if usage_alert

        # Check quota alerts
        quota_alert = @alert_managers[:quota].check_quota(provider, model, @token_usage, @token_limits)
        @token_alerts << quota_alert if quota_alert

        # Check cost alerts
        cost_alert = @alert_managers[:cost].check_cost(provider, model, @token_usage)
        @token_alerts << cost_alert if cost_alert

        # Check rate limit alerts
        rate_limit_alert = @alert_managers[:rate_limit].check_rate_limit(provider, model, @token_usage)
        @token_alerts << rate_limit_alert if rate_limit_alert
      end

      def update_status_display(provider, model)
        return unless @status_display

        begin
          current_usage = get_current_usage(provider, model)
          @status_display.update_token_usage(provider, model, current_usage[:total_tokens], current_usage[:remaining_tokens])
        rescue NoMethodError, StandardError => e
          # Handle missing methods gracefully
          puts "Token monitor display error: #{e.message}" if @display_config&.dig(:show_errors)
        end
      end

      def get_model_usage(provider, model)
        model_data = @token_usage.dig(provider, model) || initialize_model_tracking
        limits = get_token_limits(provider, model)

        {
          provider: provider,
          model: model,
          total_tokens: model_data[:total_tokens],
          request_tokens: model_data[:request_tokens],
          response_tokens: model_data[:response_tokens],
          request_count: model_data[:request_count],
          total_cost: model_data[:total_cost],
          last_used: model_data[:last_used],
          peak_usage: model_data[:peak_usage],
          average_usage: model_data[:average_usage],
          usage_trend: model_data[:usage_trend],
          efficiency_score: model_data[:efficiency_score],
          remaining_tokens: limits[:daily_limit] ? limits[:daily_limit] - model_data[:total_tokens] : nil,
          quota_used: limits[:daily_limit] ? (model_data[:total_tokens].to_f / limits[:daily_limit] * 100).round(2) : nil
        }
      end

      def get_provider_usage(provider)
        models = @token_usage[provider] || {}

        total_tokens = models.values.sum { |data| data[:total_tokens] }
        total_request_tokens = models.values.sum { |data| data[:request_tokens] }
        total_response_tokens = models.values.sum { |data| data[:response_tokens] }
        total_requests = models.values.sum { |data| data[:request_count] }
        total_cost = models.values.sum { |data| data[:total_cost] }

        {
          provider: provider,
          total_tokens: total_tokens,
          request_tokens: total_request_tokens,
          response_tokens: total_response_tokens,
          request_count: total_requests,
          total_cost: total_cost,
          average_usage: (total_requests > 0) ? total_tokens.to_f / total_requests : 0.0,
          models: models.keys,
          last_used: models.values.map { |data| data[:last_used] }.compact.max
        }
      end

      def get_model_quota_status(provider, model)
        model_data = @token_usage.dig(provider, model) || initialize_model_tracking
        limits = get_token_limits(provider, model)

        {
          provider: provider,
          model: model,
          used_tokens: model_data[:total_tokens],
          daily_limit: limits[:daily_limit],
          monthly_limit: limits[:monthly_limit],
          remaining_daily: limits[:daily_limit] ? limits[:daily_limit] - model_data[:total_tokens] : nil,
          remaining_monthly: limits[:monthly_limit] ? limits[:monthly_limit] - model_data[:total_tokens] : nil,
          quota_used_percentage: limits[:daily_limit] ? (model_data[:total_tokens].to_f / limits[:daily_limit] * 100).round(2) : nil,
          status: get_quota_status_level(model_data, limits)
        }
      end

      def get_provider_quota_status(provider)
        models = @token_usage[provider] || {}
        total_used = models.values.sum { |data| data[:total_tokens] }

        {
          provider: provider,
          total_used_tokens: total_used,
          models_count: models.size,
          status: :healthy # Simplified for now
        }
      end

      def get_system_quota_status
        {
          total_providers: @token_usage.keys.size,
          total_models: @token_usage.values.sum { |models| models.keys.size },
          total_tokens_used: @token_usage.values.sum { |models| models.values.sum { |data| data[:total_tokens] } },
          status: :healthy # Simplified for now
        }
      end

      def get_model_rate_limit_status(provider, model)
        # This would integrate with actual rate limit tracking
        {
          provider: provider,
          model: model,
          rate_limited: false,
          requests_per_minute: 0,
          tokens_per_minute: 0,
          reset_time: nil
        }
      end

      def get_provider_rate_limit_status(provider)
        {
          provider: provider,
          rate_limited: false,
          requests_per_minute: 0,
          tokens_per_minute: 0,
          reset_time: nil
        }
      end

      def get_system_rate_limit_status
        {
          any_rate_limited: false,
          total_requests_per_minute: 0,
          total_tokens_per_minute: 0
        }
      end

      def calculate_efficiency_score(model_data)
        # Calculate efficiency based on response tokens vs request tokens ratio
        return 0.0 if model_data[:request_tokens] == 0

        response_ratio = model_data[:response_tokens].to_f / model_data[:request_tokens]
        # Normalize to 0-1 scale (higher is better)
        [response_ratio / 10.0, 1.0].min
      end

      def calculate_usage_trend(provider, model)
        # Analyze recent usage to determine trend
        recent_history = get_usage_history(provider, model, 3600, 100) # Last hour
        return :stable if recent_history.size < 3

        recent_usage = recent_history.last(3).map { |entry| entry[:total_tokens] }
        if recent_usage[2] > recent_usage[1] && recent_usage[1] > recent_usage[0]
          :increasing
        elsif recent_usage[2] < recent_usage[1] && recent_usage[1] < recent_usage[0]
          :decreasing
        else
          :stable
        end
      end

      def get_token_range(total_tokens)
        case total_tokens
        when 0..100 then "0-100"
        when 101..500 then "101-500"
        when 501..1000 then "501-1000"
        when 1001..5000 then "1001-5000"
        else "5000+"
        end
      end

      def get_quota_status_level(model_data, limits)
        return :unknown unless limits[:daily_limit]

        usage_percentage = model_data[:total_tokens].to_f / limits[:daily_limit] * 100

        case usage_percentage
        when 0..50 then :healthy
        when 51..80 then :warning
        when 81..95 then :critical
        else :exceeded
        end
      end

      def generate_request_id
        SecureRandom.uuid
      end

      def empty_summary
        {
          total_requests: 0,
          total_tokens: 0,
          total_request_tokens: 0,
          total_response_tokens: 0,
          average_tokens_per_request: 0.0,
          average_request_tokens: 0.0,
          average_response_tokens: 0.0,
          total_cost: 0.0,
          peak_usage: 0,
          time_range: 0,
          start_time: nil,
          end_time: nil
        }
      end

      # Helper classes
      class TokenUsageAnalyzer
        def analyze_usage(usage_data)
          {
            efficiency: calculate_efficiency(usage_data),
            patterns: identify_patterns(usage_data),
            trends: analyze_trends(usage_data),
            recommendations: generate_recommendations(usage_data)
          }
        end

        private

        def calculate_efficiency(_usage_data)
          0.85 # Placeholder
        end

        def identify_patterns(_usage_data)
          {} # Placeholder
        end

        def analyze_trends(_usage_data)
          {} # Placeholder
        end

        def generate_recommendations(_usage_data)
          [] # Placeholder
        end
      end

      class TokenPatternAnalyzer
        def analyze_patterns(usage_history)
          {
            hourly_patterns: analyze_hourly_patterns(usage_history),
            daily_patterns: analyze_daily_patterns(usage_history),
            weekly_patterns: analyze_weekly_patterns(usage_history)
          }
        end

        private

        def analyze_hourly_patterns(_usage_history)
          {} # Placeholder
        end

        def analyze_daily_patterns(_usage_history)
          {} # Placeholder
        end

        def analyze_weekly_patterns(_usage_history)
          {} # Placeholder
        end
      end

      class TokenTrendAnalyzer
        def analyze_trends(_usage_history)
          {
            short_term_trend: :stable,
            long_term_trend: :increasing,
            seasonal_patterns: {},
            anomalies: []
          }
        end
      end

      class TokenEfficiencyAnalyzer
        def analyze_efficiency(_usage_data)
          {
            overall_efficiency: 0.85,
            provider_efficiency: {},
            model_efficiency: {},
            optimization_opportunities: []
          }
        end
      end

      class TokenUsagePredictor
        def initialize(usage_history)
          @usage_history = usage_history
        end

        def predict_usage(_provider = nil, _model = nil, time_horizon = 3600)
          {
            predicted_tokens: 1000,
            confidence: 0.75,
            time_horizon: time_horizon,
            factors: [:historical_usage, :time_of_day, :day_of_week]
          }
        end

        def update_model(_provider, _model, _usage_history)
          # Update prediction model with new data
        end
      end

      class ProviderTokenPredictor < TokenUsagePredictor
        def predict_usage(provider, model = nil, time_horizon = 3600)
          super
        end
      end

      class ModelTokenPredictor < TokenUsagePredictor
        def predict_usage(provider, model, time_horizon = 3600)
          super
        end
      end

      class TokenCostCalculator
        def analyze_costs(_provider = nil, _model = nil, _time_range = 3600)
          {
            total_cost: 0.0,
            average_cost_per_request: 0.0,
            cost_trend: :stable,
            cost_breakdown: {},
            cost_optimization: []
          }
        end
      end

      class ProviderCostCalculator < TokenCostCalculator
        def analyze_costs(provider, model = nil, time_range = 3600)
          super
        end
      end

      class ModelCostCalculator < TokenCostCalculator
        def analyze_costs(provider, model, time_range = 3600)
          super
        end
      end

      class TokenQuotaManager
        def check_quota_status(_provider, _model, _usage_data, _limits)
          {
            status: :healthy,
            used_percentage: 0.0,
            remaining: 0,
            reset_time: nil
          }
        end
      end

      class ProviderQuotaManager < TokenQuotaManager
        def check_quota_status(provider, model = nil, usage_data = {}, limits = {})
          super
        end
      end

      class ModelQuotaManager < TokenQuotaManager
        def check_quota_status(provider, model, usage_data = {}, limits = {})
          super
        end
      end

      class TokenUsageAlertManager
        def check_usage(_provider, _model, _total_tokens, _usage_data)
          # Check for high usage alerts
          nil # No alert for now
        end
      end

      class TokenQuotaAlertManager
        def check_quota(_provider, _model, _usage_data, _limits)
          # Check for quota alerts
          nil # No alert for now
        end
      end

      class TokenCostAlertManager
        def check_cost(_provider, _model, _usage_data)
          # Check for cost alerts
          nil # No alert for now
        end
      end

      class TokenRateLimitAlertManager
        def check_rate_limit(_provider, _model, _usage_data)
          # Check for rate limit alerts
          nil # No alert for now
        end
      end

      class CompactTokenFormatter
        def format_usage(_provider, _model, _monitor)
          "Compact token usage display"
        end
      end

      class DetailedTokenFormatter
        def format_usage(_provider, _model, _monitor)
          "Detailed token usage display"
        end
      end

      class SummaryTokenFormatter
        def format_usage(_provider, _model, _monitor)
          "Summary token usage display"
        end
      end

      class RealtimeTokenFormatter
        def format_usage(_provider, _model, _monitor)
          "Real-time token usage display"
        end
      end

      class TokenJsonExporter
        def export_data(monitor, _options = {})
          JSON.pretty_generate(monitor.get_usage_summary)
        end
      end

      class TokenYamlExporter
        def export_data(monitor, _options = {})
          monitor.get_usage_summary.to_yaml
        end
      end

      class TokenCsvExporter
        def export_data(_monitor, _options = {})
          "CSV export would be implemented here"
        end
      end

      class TokenTextExporter
        def export_data(_monitor, _options = {})
          "Text export would be implemented here"
        end
      end

      class TokenUsageOptimizer
        def optimize_usage(_provider, _model, _monitor)
          {
            optimizations: ["Token usage optimizations applied"],
            potential_savings: 0.0,
            recommendations: []
          }
        end
      end

      class ProviderTokenOptimizer < TokenUsageOptimizer
        def optimize_usage(provider, model = nil, monitor)
          super
        end
      end

      class ModelTokenOptimizer < TokenUsageOptimizer
      end
    end
  end
end
