# frozen_string_literal: true

module Aidp
  module Harness
    # Manages performance tracking, metrics collection, and analytics for providers and models
    class MetricsManager
      def initialize(provider_manager, configuration)
        @provider_manager = provider_manager
        @configuration = configuration
        @metrics_store = MetricsStore.new
        @performance_analyzer = PerformanceAnalyzer.new
        @trend_analyzer = TrendAnalyzer.new
        @alert_manager = AlertManager.new
        @report_generator = ReportGenerator.new
        @data_aggregator = DataAggregator.new
        @benchmark_manager = BenchmarkManager.new
        initialize_metrics_collection
      end

      # Record a request/response event
      def record_request(provider_name, model_name, request_data, response_data, duration, success, error = nil)
        event = build_request_event(provider_name, model_name, request_data, response_data, duration, success, error)

        # Store the event
        @metrics_store.store_event(event)

        # Update real-time metrics
        update_realtime_metrics(provider_name, model_name, event)

        # Check for alerts
        check_alerts(provider_name, model_name, event)

        # Update performance analysis
        @performance_analyzer.analyze_event(event)

        # Update trend analysis
        @trend_analyzer.analyze_event(event)

        event
      end

      # Record a provider switch event
      def record_provider_switch(from_provider, to_provider, reason, context = {})
        event = build_switch_event(from_provider, to_provider, reason, context)

        @metrics_store.store_event(event)
        update_switch_metrics(from_provider, to_provider, event)

        event
      end

      # Record a model switch event
      def record_model_switch(provider_name, from_model, to_model, reason, context = {})
        event = build_model_switch_event(provider_name, from_model, to_model, reason, context)

        @metrics_store.store_event(event)
        update_model_switch_metrics(provider_name, from_model, to_model, event)

        event
      end

      # Record an error event
      def record_error(provider_name, model_name, error_info)
        event = build_error_event(provider_name, model_name, error_info)

        @metrics_store.store_event(event)
        update_error_metrics(provider_name, model_name, event)

        event
      end

      # Record an error event (for ErrorLogger compatibility)
      def record_error_event(error_entry)
        event = build_error_event_from_entry(error_entry)

        @metrics_store.store_event(event)
        update_error_metrics(event[:provider], event[:model], event)

        event
      end

      # Record a recovery event
      def record_recovery_event(recovery_entry)
        event = build_recovery_event_from_entry(recovery_entry)

        @metrics_store.store_event(event)
        update_recovery_metrics(event[:provider], event[:model], event)

        event
      end

      # Record a switch event
      def record_switch_event(switch_entry)
        event = build_switch_event_from_entry(switch_entry)

        @metrics_store.store_event(event)
        update_switch_metrics(event[:from_provider], event[:to_provider], event)

        event
      end

      # Record a retry event
      def record_retry_event(retry_entry)
        event = build_retry_event_from_entry(retry_entry)

        @metrics_store.store_event(event)
        update_retry_metrics(event[:provider], event[:model], event)

        event
      end

      # Record a circuit breaker event
      def record_circuit_breaker_event(circuit_breaker_entry)
        event = build_circuit_breaker_event_from_entry(circuit_breaker_entry)

        @metrics_store.store_event(event)
        update_circuit_breaker_metrics(event[:provider], event[:model], event)

        event
      end

      # Record a fallback attempt
      def record_fallback_attempt(fallback_info)
        event = build_fallback_event_from_info(fallback_info)

        @metrics_store.store_event(event)
        update_fallback_metrics(event[:provider], event[:model], event)

        event
      end

      # Record a rate limit event
      def record_rate_limit(provider_name, model_name, rate_limit_info, context = {})
        event = build_rate_limit_event(provider_name, model_name, rate_limit_info, context)

        @metrics_store.store_event(event)
        update_rate_limit_metrics(provider_name, model_name, event)

        event
      end

      def record_circuit_breaker_success(provider_name, model_name, state)
        event = {
          type: :circuit_breaker_success,
          provider: provider_name,
          model: model_name,
          state: state,
          timestamp: Time.now
        }
        @metrics_store.store_event(event)
        event
      end

      def record_circuit_breaker_failure(provider_name, model_name, state, error)
        event = {
          type: :circuit_breaker_failure,
          provider: provider_name,
          model: model_name,
          state: state,
          error: error&.message,
          timestamp: Time.now
        }
        @metrics_store.store_event(event)
        event
      end

      # Get comprehensive metrics for a provider
      def get_provider_metrics(provider_name, time_range = nil)
        time_range ||= default_time_range

        {
          basic_metrics: get_basic_provider_metrics(provider_name, time_range),
          performance_metrics: get_performance_metrics(provider_name, time_range),
          reliability_metrics: get_reliability_metrics(provider_name, time_range),
          cost_metrics: get_cost_metrics(provider_name, time_range),
          usage_metrics: get_usage_metrics(provider_name, time_range),
          trend_analysis: @trend_analyzer.get_provider_trends(provider_name, time_range),
          benchmarks: @benchmark_manager.get_provider_benchmarks(provider_name, time_range),
          alerts: @alert_manager.get_provider_alerts(provider_name, time_range)
        }
      end

      # Get comprehensive metrics for a model
      def get_model_metrics(provider_name, model_name, time_range = nil)
        time_range ||= default_time_range

        {
          basic_metrics: get_basic_model_metrics(provider_name, model_name, time_range),
          performance_metrics: get_performance_metrics(provider_name, model_name, time_range),
          reliability_metrics: get_reliability_metrics(provider_name, model_name, time_range),
          cost_metrics: get_cost_metrics(provider_name, model_name, time_range),
          usage_metrics: get_usage_metrics(provider_name, model_name, time_range),
          trend_analysis: @trend_analyzer.get_model_trends(provider_name, model_name, time_range),
          benchmarks: @benchmark_manager.get_model_benchmarks(provider_name, model_name, time_range),
          alerts: @alert_manager.get_model_alerts(provider_name, model_name, time_range)
        }
      end

      # Get overall system metrics
      def get_system_metrics(time_range = nil)
        time_range ||= default_time_range

        {
          overall_performance: get_overall_performance_metrics(time_range),
          provider_comparison: get_provider_comparison_metrics(time_range),
          model_comparison: get_model_comparison_metrics(time_range),
          system_health: get_system_health_metrics(time_range),
          cost_analysis: get_system_cost_analysis(time_range),
          usage_patterns: get_usage_patterns(time_range),
          trend_analysis: @trend_analyzer.get_system_trends(time_range),
          alerts: @alert_manager.get_system_alerts(time_range)
        }
      end

      # Get real-time metrics
      def get_realtime_metrics
        {
          current_requests: @metrics_store.get_current_requests,
          active_providers: @metrics_store.get_active_providers,
          current_load: @metrics_store.get_current_load,
          recent_errors: @metrics_store.get_recent_errors,
          performance_scores: @performance_analyzer.get_current_scores,
          alert_status: @alert_manager.get_current_alerts
        }
      end

      # Generate performance report
      def generate_performance_report(time_range = nil, format = :json)
        time_range ||= default_time_range

        report_data = {
          report_metadata: {
            generated_at: Time.now,
            time_range: time_range,
            format: format
          },
          system_metrics: get_system_metrics(time_range),
          provider_metrics: get_all_provider_metrics(time_range),
          model_metrics: get_all_model_metrics(time_range),
          recommendations: generate_recommendations(time_range),
          alerts_summary: @alert_manager.get_alerts_summary(time_range)
        }

        @report_generator.generate_report(report_data, format)
      end

      # Get performance recommendations
      def get_performance_recommendations(time_range = nil)
        time_range ||= default_time_range

        recommendations = []

        # Analyze provider performance
        provider_metrics = get_all_provider_metrics(time_range)
        recommendations.concat(analyze_provider_recommendations(provider_metrics))

        # Analyze model performance
        model_metrics = get_all_model_metrics(time_range)
        recommendations.concat(analyze_model_recommendations(model_metrics))

        # Analyze system performance
        system_metrics = get_system_metrics(time_range)
        recommendations.concat(analyze_system_recommendations(system_metrics))

        # Sort by priority and impact
        recommendations.sort_by { |r| [-r[:priority], -r[:impact]] }
      end

      # Set up performance benchmarks
      def setup_benchmarks(benchmark_config)
        @benchmark_manager.setup_benchmarks(benchmark_config)
      end

      # Run performance benchmarks
      def run_benchmarks(provider_name = nil, model_name = nil)
        @benchmark_manager.run_benchmarks(provider_name, model_name)
      end

      # Get benchmark results
      def get_benchmark_results(provider_name = nil, model_name = nil)
        @benchmark_manager.get_results(provider_name, model_name)
      end

      # Configure alerts
      def configure_alerts(alert_config)
        @alert_manager.configure_alerts(alert_config)
      end

      # Get alert history
      def get_alert_history(time_range = nil)
        time_range ||= default_time_range
        @alert_manager.get_alert_history(time_range)
      end

      # Export metrics data
      def export_metrics(time_range = nil, format = :csv)
        time_range ||= default_time_range
        @data_aggregator.export_metrics(time_range, format)
      end

      # Clean up old metrics data
      def cleanup_old_metrics(retention_days = nil)
        retention_days ||= @configuration.metrics_config[:retention_days] || 30
        @metrics_store.cleanup_old_data(retention_days)
      end

      private

      def initialize_metrics_collection
        # Skip background threads in test environment
        return if defined?(RSpec) && RSpec.current_example

        # Set up periodic metrics collection using Async
        require "async"
        Async do |task|
          task.async do
            loop do
              collect_system_metrics
              interval = @configuration.metrics_config[:collection_interval] || 60
              if ENV['RACK_ENV'] == 'test' || defined?(RSpec)
                sleep(interval)
              else
                Async::Task.current.sleep(interval)
              end
            end
          end
        end

        # Set up periodic cleanup using Async
        Async do |task|
          task.async do
            loop do
              cleanup_old_metrics
              if ENV['RACK_ENV'] == 'test' || defined?(RSpec)
                sleep(3600) # Run cleanup every hour
              else
                Async::Task.current.sleep(3600) # Run cleanup every hour
              end
            end
          end
        end
      end

      def build_request_event(provider_name, model_name, request_data, response_data, duration, success, error)
        {
          event_type: "request",
          timestamp: Time.now,
          provider: provider_name,
          model: model_name,
          request_data: sanitize_request_data(request_data),
          response_data: sanitize_response_data(response_data),
          duration: duration,
          success: success,
          error: error&.message,
          error_type: error&.class&.name,
          request_size: calculate_request_size(request_data),
          response_size: calculate_response_size(response_data),
          token_count: extract_token_count(response_data),
          cost: calculate_cost(provider_name, model_name, request_data, response_data)
        }
      end

      def build_switch_event(from_provider, to_provider, reason, context)
        {
          event_type: "provider_switch",
          timestamp: Time.now,
          from_provider: from_provider,
          to_provider: to_provider,
          reason: reason,
          context: context,
          switch_duration: context[:switch_duration] || 0
        }
      end

      def build_model_switch_event(provider_name, from_model, to_model, reason, context)
        {
          event_type: "model_switch",
          timestamp: Time.now,
          provider: provider_name,
          from_model: from_model,
          to_model: to_model,
          reason: reason,
          context: context,
          switch_duration: context[:switch_duration] || 0
        }
      end

      def build_rate_limit_event(provider_name, model_name, rate_limit_info, context)
        {
          event_type: "rate_limit",
          timestamp: Time.now,
          provider: provider_name,
          model: model_name,
          rate_limit_info: rate_limit_info,
          context: context,
          reset_time: rate_limit_info[:reset_time],
          retry_after: rate_limit_info[:retry_after]
        }
      end

      def build_error_event(provider_name, model_name, error_info)
        {
          event_type: "error",
          timestamp: Time.now,
          provider: provider_name,
          model: model_name,
          error_info: error_info,
          error_type: error_info[:error_type],
          error_message: error_info[:message],
          success: false
        }
      end

      def build_error_event_from_entry(error_entry)
        {
          event_type: "error",
          timestamp: error_entry[:timestamp] || Time.now,
          provider: error_entry[:provider] || "unknown",
          model: error_entry[:model] || "unknown",
          error_info: error_entry,
          error_type: error_entry[:category] || error_entry[:error_type] || "unknown",
          error_message: error_entry[:message] || "Unknown error",
          success: false
        }
      end

      def build_recovery_event_from_entry(recovery_entry)
        {
          event_type: "recovery",
          timestamp: recovery_entry[:timestamp] || Time.now,
          provider: recovery_entry[:provider] || "unknown",
          model: recovery_entry[:model] || "unknown",
          recovery_info: recovery_entry,
          action_type: recovery_entry[:action_type] || "unknown",
          success: recovery_entry[:success] || false
        }
      end

      def build_switch_event_from_entry(switch_entry)
        {
          event_type: "switch",
          timestamp: switch_entry[:timestamp] || Time.now,
          from_provider: switch_entry[:from_provider] || "unknown",
          to_provider: switch_entry[:to_provider] || "unknown",
          switch_info: switch_entry,
          switch_type: switch_entry[:switch_type] || "unknown",
          success: switch_entry[:success] || false
        }
      end

      def build_retry_event_from_entry(retry_entry)
        {
          event_type: "retry",
          timestamp: retry_entry[:timestamp] || Time.now,
          provider: retry_entry[:provider] || "unknown",
          model: retry_entry[:model] || "unknown",
          retry_info: retry_entry,
          retry_count: retry_entry[:retry_count] || 0,
          success: retry_entry[:success] || false
        }
      end

      def build_circuit_breaker_event_from_entry(circuit_breaker_entry)
        {
          event_type: "circuit_breaker",
          timestamp: circuit_breaker_entry[:timestamp] || Time.now,
          provider: circuit_breaker_entry[:provider] || "unknown",
          model: circuit_breaker_entry[:model] || "unknown",
          circuit_breaker_info: circuit_breaker_entry,
          state: circuit_breaker_entry[:state] || "unknown",
          success: circuit_breaker_entry[:success] || false
        }
      end

      def build_fallback_event_from_info(fallback_info)
        {
          event_type: "fallback",
          timestamp: fallback_info[:timestamp] || Time.now,
          provider: fallback_info[:provider] || "unknown",
          model: fallback_info[:model] || "unknown",
          fallback_info: fallback_info,
          error_type: fallback_info[:error_type] || "unknown",
          retry_count: fallback_info[:retry_count] || 0,
          success: fallback_info[:success] || false
        }
      end

      def update_realtime_metrics(provider_name, model_name, event)
        @metrics_store.update_realtime_metrics(provider_name, model_name, event)
      end

      def update_switch_metrics(from_provider, to_provider, event)
        @metrics_store.update_switch_metrics(from_provider, to_provider, event)
      end

      def update_model_switch_metrics(provider_name, from_model, to_model, event)
        @metrics_store.update_model_switch_metrics(provider_name, from_model, to_model, event)
      end

      def update_rate_limit_metrics(provider_name, model_name, event)
        @metrics_store.update_rate_limit_metrics(provider_name, model_name, event)
      end

      def update_error_metrics(provider_name, model_name, event)
        @metrics_store.update_realtime_metrics(provider_name, model_name, event)
      end

      def update_recovery_metrics(provider_name, model_name, event)
        @metrics_store.update_realtime_metrics(provider_name, model_name, event)
      end

      def update_retry_metrics(provider_name, model_name, event)
        @metrics_store.update_realtime_metrics(provider_name, model_name, event)
      end

      def update_circuit_breaker_metrics(provider_name, model_name, event)
        @metrics_store.update_realtime_metrics(provider_name, model_name, event)
      end

      def update_fallback_metrics(provider_name, model_name, event)
        @metrics_store.update_realtime_metrics(provider_name, model_name, event)
      end

      def get_basic_provider_metrics(provider_name, time_range)
        events = @metrics_store.get_events("request", provider_name, time_range)

        {
          total_requests: events.size,
          successful_requests: events.count { |e| e[:success] },
          failed_requests: events.count { |e| !e[:success] },
          success_rate: calculate_success_rate(events),
          average_response_time: calculate_average_response_time(events),
          total_duration: events.sum { |e| e[:duration] },
          total_tokens: events.sum { |e| e[:token_count] || 0 },
          total_cost: events.sum { |e| e[:cost] || 0 }
        }
      end

      def get_basic_model_metrics(provider_name, model_name, time_range)
        events = @metrics_store.get_events("request", provider_name, time_range, model_name)

        {
          total_requests: events.size,
          successful_requests: events.count { |e| e[:success] },
          failed_requests: events.count { |e| !e[:success] },
          success_rate: calculate_success_rate(events),
          average_response_time: calculate_average_response_time(events),
          total_duration: events.sum { |e| e[:duration] },
          total_tokens: events.sum { |e| e[:token_count] || 0 },
          total_cost: events.sum { |e| e[:cost] || 0 }
        }
      end

      def get_performance_metrics(provider_name, model_name_or_time_range = nil, time_range = nil)
        if model_name_or_time_range.is_a?(Hash) || model_name_or_time_range.is_a?(Range)
          # Called with provider_name, time_range
          time_range = model_name_or_time_range
          model_name = nil
        else
          # Called with provider_name, model_name, time_range
          model_name = model_name_or_time_range
          time_range ||= default_time_range
        end

        events = @metrics_store.get_events("request", provider_name, time_range, model_name)

        {
          response_time_percentiles: calculate_response_time_percentiles(events),
          throughput: calculate_throughput(events, time_range),
          error_rate: calculate_error_rate(events),
          availability: calculate_availability(events, time_range),
          performance_score: @performance_analyzer.calculate_performance_score(events)
        }
      end

      def get_reliability_metrics(provider_name, model_name_or_time_range = nil, time_range = nil)
        if model_name_or_time_range.is_a?(Hash) || model_name_or_time_range.is_a?(Range)
          time_range = model_name_or_time_range
          model_name = nil
        else
          model_name = model_name_or_time_range
          time_range ||= default_time_range
        end

        events = @metrics_store.get_events("request", provider_name, time_range, model_name)

        {
          uptime: calculate_uptime(events, time_range),
          mean_time_between_failures: calculate_mtbf(events),
          mean_time_to_recovery: calculate_mttr(events),
          error_distribution: calculate_error_distribution(events),
          reliability_score: @performance_analyzer.calculate_reliability_score(events)
        }
      end

      def get_cost_metrics(provider_name, model_name_or_time_range = nil, time_range = nil)
        if model_name_or_time_range.is_a?(Hash) || model_name_or_time_range.is_a?(Range)
          time_range = model_name_or_time_range
          model_name = nil
        else
          model_name = model_name_or_time_range
          time_range ||= default_time_range
        end

        events = @metrics_store.get_events("request", provider_name, time_range, model_name)

        {
          total_cost: events.sum { |e| e[:cost] || 0 },
          average_cost_per_request: calculate_average_cost_per_request(events),
          cost_per_token: calculate_cost_per_token(events),
          cost_efficiency: calculate_cost_efficiency(events),
          cost_trend: @trend_analyzer.calculate_cost_trend(events)
        }
      end

      def get_usage_metrics(provider_name, model_name_or_time_range = nil, time_range = nil)
        if model_name_or_time_range.is_a?(Hash) || model_name_or_time_range.is_a?(Range)
          time_range = model_name_or_time_range
          model_name = nil
        else
          model_name = model_name_or_time_range
          time_range ||= default_time_range
        end

        events = @metrics_store.get_events("request", provider_name, time_range, model_name)

        {
          request_volume: events.size,
          token_usage: events.sum { |e| e[:token_count] || 0 },
          peak_usage: calculate_peak_usage(events, time_range),
          usage_patterns: calculate_usage_patterns(events, time_range),
          utilization_rate: calculate_utilization_rate(events, time_range)
        }
      end

      def get_all_provider_metrics(time_range)
        providers = @provider_manager.configured_providers
        providers.map { |provider| [provider, get_provider_metrics(provider, time_range)] }.to_h
      end

      def get_all_model_metrics(time_range)
        metrics = {}

        @provider_manager.configured_providers.each do |provider|
          models = @provider_manager.get_provider_models(provider)
          metrics[provider] = {}

          models.each do |model|
            metrics[provider][model] = get_model_metrics(provider, model, time_range)
          end
        end

        metrics
      end

      def get_overall_performance_metrics(time_range)
        all_events = @metrics_store.get_all_events("request", time_range)

        {
          total_requests: all_events.size,
          overall_success_rate: calculate_success_rate(all_events),
          overall_average_response_time: calculate_average_response_time(all_events),
          overall_throughput: calculate_throughput(all_events, time_range),
          overall_error_rate: calculate_error_rate(all_events),
          system_availability: calculate_availability(all_events, time_range)
        }
      end

      def get_provider_comparison_metrics(time_range)
        providers = @provider_manager.configured_providers
        comparison = {}

        providers.each do |provider|
          metrics = get_provider_metrics(provider, time_range)
          comparison[provider] = {
            success_rate: metrics[:basic_metrics][:success_rate],
            average_response_time: metrics[:basic_metrics][:average_response_time],
            total_cost: metrics[:basic_metrics][:total_cost],
            performance_score: metrics[:performance_metrics][:performance_score]
          }
        end

        comparison
      end

      def get_model_comparison_metrics(time_range)
        comparison = {}

        @provider_manager.configured_providers.each do |provider|
          models = @provider_manager.get_provider_models(provider)
          comparison[provider] = {}

          models.each do |model|
            metrics = get_model_metrics(provider, model, time_range)
            comparison[provider][model] = {
              success_rate: metrics[:basic_metrics][:success_rate],
              average_response_time: metrics[:basic_metrics][:average_response_time],
              total_cost: metrics[:basic_metrics][:total_cost],
              performance_score: metrics[:performance_metrics][:performance_score]
            }
          end
        end

        comparison
      end

      def get_system_health_metrics(time_range)
        all_events = @metrics_store.get_all_events("request", time_range)
        switch_events = @metrics_store.get_all_events("provider_switch", time_range)
        rate_limit_events = @metrics_store.get_all_events("rate_limit", time_range)

        {
          system_uptime: calculate_system_uptime(all_events, time_range),
          switch_frequency: switch_events.size,
          rate_limit_frequency: rate_limit_events.size,
          health_score: @performance_analyzer.calculate_system_health_score(all_events, switch_events, rate_limit_events)
        }
      end

      def get_system_cost_analysis(time_range)
        all_events = @metrics_store.get_all_events("request", time_range)

        {
          total_system_cost: all_events.sum { |e| e[:cost] || 0 },
          cost_by_provider: calculate_cost_by_provider(all_events),
          cost_by_model: calculate_cost_by_model(all_events),
          cost_trend: @trend_analyzer.calculate_cost_trend(all_events),
          cost_optimization_opportunities: identify_cost_optimization_opportunities(all_events)
        }
      end

      def get_usage_patterns(time_range)
        all_events = @metrics_store.get_all_events("request", time_range)

        {
          hourly_patterns: calculate_hourly_patterns(all_events),
          daily_patterns: calculate_daily_patterns(all_events),
          provider_usage_distribution: calculate_provider_usage_distribution(all_events),
          model_usage_distribution: calculate_model_usage_distribution(all_events)
        }
      end

      def collect_system_metrics
        # Collect system-level metrics
        system_metrics = {
          timestamp: Time.now,
          active_providers: @provider_manager.configured_providers.size,
          current_load: @metrics_store.get_current_load,
          memory_usage: get_memory_usage,
          cpu_usage: get_cpu_usage
        }

        @metrics_store.store_system_metrics(system_metrics)
      end

      def check_alerts(provider_name, model_name, event)
        @alert_manager.check_alerts(provider_name, model_name, event)
      end

      def generate_recommendations(time_range)
        get_performance_recommendations(time_range)
      end

      def analyze_provider_recommendations(provider_metrics)
        recommendations = []

        provider_metrics.each do |provider, metrics|
          # Check for low success rate
          if metrics[:basic_metrics][:success_rate] < 0.95
            recommendations << {
              type: "provider_performance",
              provider: provider,
              issue: "Low success rate",
              current_value: metrics[:basic_metrics][:success_rate],
              threshold: 0.95,
              recommendation: "Consider switching to a more reliable provider",
              priority: 1,
              impact: "high"
            }
          end

          # Check for high response time
          if metrics[:basic_metrics][:average_response_time] > 30.0
            recommendations << {
              type: "provider_performance",
              provider: provider,
              issue: "High response time",
              current_value: metrics[:basic_metrics][:average_response_time],
              threshold: 30.0,
              recommendation: "Consider using a faster model or provider",
              priority: 2,
              impact: "medium"
            }
          end
        end

        recommendations
      end

      def analyze_model_recommendations(model_metrics)
        recommendations = []

        model_metrics.each do |provider, models|
          models.each do |model, metrics|
            # Check for cost efficiency
            if metrics[:cost_metrics][:cost_efficiency] < 0.8
              recommendations << {
                type: "model_cost",
                provider: provider,
                model: model,
                issue: "Low cost efficiency",
                current_value: metrics[:cost_metrics][:cost_efficiency],
                threshold: 0.8,
                recommendation: "Consider switching to a more cost-effective model",
                priority: 2,
                impact: "medium"
              }
            end
          end
        end

        recommendations
      end

      def analyze_system_recommendations(system_metrics)
        recommendations = []

        # Check system health
        if system_metrics[:system_health][:health_score] < 0.9
          recommendations << {
            type: "system_health",
            issue: "System health below threshold",
            current_value: system_metrics[:system_health][:health_score],
            threshold: 0.9,
            recommendation: "Review provider configurations and consider load balancing",
            priority: 1,
            impact: "high"
          }
        end

        recommendations
      end

      # Utility methods for calculations
      def calculate_success_rate(events)
        return 0.0 if events.empty?

        successful_events = events.count { |e| e[:success] }
        successful_events.to_f / events.size
      end

      def calculate_average_response_time(events)
        return 0.0 if events.empty?

        total_duration = events.sum { |e| e[:duration] }
        total_duration.to_f / events.size
      end

      def calculate_response_time_percentiles(events)
        return {} if events.empty?

        response_times = events.map { |e| e[:duration] }.sort

        {
          p50: percentile(response_times, 0.5),
          p90: percentile(response_times, 0.9),
          p95: percentile(response_times, 0.95),
          p99: percentile(response_times, 0.99)
        }
      end

      def calculate_throughput(events, time_range)
        return 0.0 if events.empty? || time_range.nil?

        duration = time_range.is_a?(Range) ? (time_range.end - time_range.begin) : 3600
        events.size.to_f / duration
      end

      def calculate_error_rate(events)
        return 0.0 if events.empty?

        failed_events = events.count { |e| !e[:success] }
        failed_events.to_f / events.size
      end

      def calculate_availability(events, _time_range)
        return 1.0 if events.empty?

        successful_events = events.count { |e| e[:success] }
        successful_events.to_f / events.size
      end

      def calculate_uptime(events, _time_range)
        return 1.0 if events.empty?

        # Calculate uptime based on successful requests
        successful_events = events.count { |e| e[:success] }
        successful_events.to_f / events.size
      end

      def calculate_mtbf(events)
        return Float::INFINITY if events.empty?

        failed_events = events.select { |e| !e[:success] }
        return Float::INFINITY if failed_events.size < 2

        # Calculate mean time between failures
        failure_intervals = []
        failed_events.each_cons(2) do |event1, event2|
          interval = event2[:timestamp] - event1[:timestamp]
          failure_intervals << interval
        end

        failure_intervals.sum / failure_intervals.size
      end

      def calculate_mttr(events)
        return 0.0 if events.empty?

        # Calculate mean time to recovery
        # This is a simplified calculation - in practice, you'd track recovery times
        0.0
      end

      def calculate_error_distribution(events)
        return {} if events.empty?

        error_types = events.select { |e| !e[:success] }.group_by { |e| e[:error_type] }
        error_types.transform_values(&:size)
      end

      def calculate_average_cost_per_request(events)
        return 0.0 if events.empty?

        total_cost = events.sum { |e| e[:cost] || 0 }
        total_cost / events.size
      end

      def calculate_cost_per_token(events)
        return 0.0 if events.empty?

        total_cost = events.sum { |e| e[:cost] || 0 }
        total_tokens = events.sum { |e| e[:token_count] || 0 }

        return 0.0 if total_tokens == 0

        total_cost / total_tokens
      end

      def calculate_cost_efficiency(events)
        return 0.0 if events.empty?

        # Calculate cost efficiency based on success rate and cost
        success_rate = calculate_success_rate(events)
        average_cost = calculate_average_cost_per_request(events)

        # Higher success rate and lower cost = higher efficiency
        success_rate / (1.0 + average_cost)
      end

      def calculate_peak_usage(events, _time_range)
        return 0 if events.empty?

        # Calculate peak usage in requests per hour
        hourly_usage = events.group_by { |e| e[:timestamp].hour }
        hourly_usage.values.map(&:size).max || 0
      end

      def calculate_usage_patterns(events, _time_range)
        return {} if events.empty?

        {
          hourly: events.group_by { |e| e[:timestamp].hour }.transform_values(&:size),
          daily: events.group_by { |e| e[:timestamp].wday }.transform_values(&:size)
        }
      end

      def calculate_utilization_rate(events, time_range)
        return 0.0 if events.empty? || time_range.nil?

        # Calculate utilization rate based on expected capacity
        expected_capacity = 1000 # This would come from configuration
        actual_usage = events.size

        [actual_usage.to_f / expected_capacity, 1.0].min
      end

      def calculate_system_uptime(events, _time_range)
        return 1.0 if events.empty?

        # Calculate system uptime based on successful requests
        successful_events = events.count { |e| e[:success] }
        successful_events.to_f / events.size
      end

      def calculate_cost_by_provider(events)
        events.group_by { |e| e[:provider] }.transform_values do |provider_events|
          provider_events.sum { |e| e[:cost] || 0 }
        end
      end

      def calculate_cost_by_model(events)
        events.group_by { |e| "#{e[:provider]}:#{e[:model]}" }.transform_values do |model_events|
          model_events.sum { |e| e[:cost] || 0 }
        end
      end

      def calculate_hourly_patterns(events)
        events.group_by { |e| e[:timestamp].hour }.transform_values(&:size)
      end

      def calculate_daily_patterns(events)
        events.group_by { |e| e[:timestamp].wday }.transform_values(&:size)
      end

      def calculate_provider_usage_distribution(events)
        total_events = events.size
        return {} if total_events == 0

        events.group_by { |e| e[:provider] }.transform_values do |provider_events|
          provider_events.size.to_f / total_events
        end
      end

      def calculate_model_usage_distribution(events)
        total_events = events.size
        return {} if total_events == 0

        events.group_by { |e| "#{e[:provider]}:#{e[:model]}" }.transform_values do |model_events|
          model_events.size.to_f / total_events
        end
      end

      def identify_cost_optimization_opportunities(events)
        opportunities = []

        # Find high-cost, low-performance combinations
        events.group_by { |e| "#{e[:provider]}:#{e[:model]}" }.each do |combination, model_events|
          success_rate = calculate_success_rate(model_events)
          average_cost = calculate_average_cost_per_request(model_events)

          if success_rate < 0.9 && average_cost > 0.1
            opportunities << {
              combination: combination,
              issue: "High cost, low performance",
              success_rate: success_rate,
              average_cost: average_cost,
              recommendation: "Consider switching to a more cost-effective alternative"
            }
          end
        end

        opportunities
      end

      def percentile(sorted_array, percentile)
        return 0.0 if sorted_array.empty?

        index = (percentile * (sorted_array.size - 1)).round
        sorted_array[index]
      end

      def default_time_range
        # Default to last 24 hours
        (Time.now - 86400)..Time.now
      end

      def sanitize_request_data(request_data)
        # Remove sensitive information from request data
        return {} unless request_data.is_a?(Hash)

        request_data.dup.tap do |data|
          data.delete(:api_key)
          data.delete(:password)
          data.delete(:token)
        end
      end

      def sanitize_response_data(response_data)
        # Remove sensitive information from response data
        return {} unless response_data.is_a?(Hash)

        response_data.dup.tap do |data|
          data.delete(:api_key)
          data.delete(:password)
          data.delete(:token)
        end
      end

      def calculate_request_size(request_data)
        return 0 unless request_data

        if request_data.is_a?(String)
          request_data.bytesize
        elsif request_data.is_a?(Hash)
          request_data.to_json.bytesize
        else
          0
        end
      end

      def calculate_response_size(response_data)
        return 0 unless response_data

        if response_data.is_a?(String)
          response_data.bytesize
        elsif response_data.is_a?(Hash)
          response_data.to_json.bytesize
        else
          0
        end
      end

      def extract_token_count(response_data)
        return 0 unless response_data.is_a?(Hash)

        response_data[:token_count] || response_data[:tokens] || 0
      end

      def calculate_cost(_provider_name, _model_name, _request_data, _response_data)
        # This would integrate with actual cost calculation
        # For now, return a placeholder
        0.01
      end

      def get_memory_usage
        # This would integrate with system monitoring
        0.0
      end

      def get_cpu_usage
        # This would integrate with system monitoring
        0.0
      end

      # Helper classes
      class MetricsStore
        def initialize
          @events = []
          @realtime_metrics = {}
          @system_metrics = []
        end

        def store_event(event)
          @events << event
        end

        def store_system_metrics(metrics)
          @system_metrics << metrics
        end

        def get_events(event_type, provider = nil, time_range = nil, model = nil)
          events = @events.select { |e| e[:event_type] == event_type }

          events = events.select { |e| e[:provider] == provider } if provider
          events = events.select { |e| e[:model] == model } if model
          events = events.select { |e| time_range.include?(e[:timestamp]) } if time_range

          events
        end

        def get_all_events(event_type, time_range = nil)
          events = @events.select { |e| e[:event_type] == event_type }
          events = events.select { |e| time_range.include?(e[:timestamp]) } if time_range
          events
        end

        def update_realtime_metrics(provider_name, model_name, event)
          key = "#{provider_name}:#{model_name}"
          @realtime_metrics[key] ||= {requests: 0, errors: 0, total_duration: 0}

          @realtime_metrics[key][:requests] += 1
          @realtime_metrics[key][:errors] += 1 unless event[:success]
          @realtime_metrics[key][:total_duration] += event[:duration]
        end

        def update_switch_metrics(from_provider, to_provider, event)
          # Update switch metrics
        end

        def update_model_switch_metrics(provider_name, from_model, to_model, event)
          # Update model switch metrics
        end

        def update_rate_limit_metrics(provider_name, model_name, event)
          # Update rate limit metrics
        end

        def get_current_requests
          @realtime_metrics.values.sum { |m| m[:requests] }
        end

        def get_active_providers
          @realtime_metrics.keys.map { |k| k.split(":").first }.uniq
        end

        def get_current_load
          @realtime_metrics.values.sum { |m| m[:requests] }
        end

        def get_recent_errors
          @realtime_metrics.values.sum { |m| m[:errors] }
        end

        def cleanup_old_data(retention_days)
          cutoff_time = Time.now - (retention_days * 86400)
          @events.reject! { |e| e[:timestamp] < cutoff_time }
          @system_metrics.reject! { |m| m[:timestamp] < cutoff_time }
        end
      end

      class PerformanceAnalyzer
        def initialize
          @performance_scores = {}
        end

        def analyze_event(event)
          # Analyze event for performance insights
        end

        def calculate_performance_score(events)
          return 0.0 if events.empty?

          success_rate = events.count { |e| e[:success] }.to_f / events.size
          avg_response_time = events.sum { |e| e[:duration] } / events.size

          # Higher success rate and lower response time = higher score
          success_rate * (1.0 / (1.0 + avg_response_time / 10.0))
        end

        def calculate_reliability_score(events)
          return 0.0 if events.empty?

          events.count { |e| e[:success] }.to_f / events.size
        end

        def calculate_system_health_score(request_events, switch_events, rate_limit_events)
          return 0.0 if request_events.empty?

          success_rate = request_events.count { |e| e[:success] }.to_f / request_events.size
          switch_penalty = switch_events.size * 0.01
          rate_limit_penalty = rate_limit_events.size * 0.02

          [success_rate - switch_penalty - rate_limit_penalty, 0.0].max
        end

        def get_current_scores
          @performance_scores
        end
      end

      class TrendAnalyzer
        def initialize
          @trends = {}
        end

        def analyze_event(event)
          # Analyze event for trends
        end

        def get_provider_trends(_provider_name, _time_range)
          {
            request_volume_trend: "stable",
            response_time_trend: "stable",
            success_rate_trend: "stable"
          }
        end

        def get_model_trends(_provider_name, _model_name, _time_range)
          {
            request_volume_trend: "stable",
            response_time_trend: "stable",
            success_rate_trend: "stable"
          }
        end

        def get_system_trends(_time_range)
          {
            overall_trend: "stable",
            performance_trend: "stable",
            cost_trend: "stable"
          }
        end

        def calculate_cost_trend(_events)
          "stable"
        end
      end

      class AlertManager
        def initialize
          @alerts = []
          @alert_config = {}
        end

        def configure_alerts(alert_config)
          @alert_config = alert_config
        end

        def check_alerts(provider_name, model_name, event)
          # Check for alert conditions
        end

        def get_provider_alerts(provider_name, time_range)
          @alerts.select { |a| a[:provider] == provider_name && time_range.include?(a[:timestamp]) }
        end

        def get_model_alerts(provider_name, model_name, time_range)
          @alerts.select { |a| a[:provider] == provider_name && a[:model] == model_name && time_range.include?(a[:timestamp]) }
        end

        def get_system_alerts(time_range)
          @alerts.select { |a| time_range.include?(a[:timestamp]) }
        end

        def get_current_alerts
          @alerts.select { |a| a[:timestamp] > Time.now - 3600 }
        end

        def get_alerts_summary(time_range)
          {
            total_alerts: @alerts.count { |a| time_range.include?(a[:timestamp]) },
            critical_alerts: @alerts.count { |a| time_range.include?(a[:timestamp]) && a[:severity] == "critical" },
            warning_alerts: @alerts.count { |a| time_range.include?(a[:timestamp]) && a[:severity] == "warning" }
          }
        end

        def get_alert_history(time_range)
          @alerts.select { |a| time_range.include?(a[:timestamp]) }
        end
      end

      class ReportGenerator
        def generate_report(report_data, format)
          case format
          when :json
            sanitize_for_json(report_data).to_json
          when :yaml
            report_data.to_yaml
          when :csv
            generate_csv_report(report_data)
          else
            report_data.to_s
          end
        end

        def sanitize_for_json(data)
          case data
          when Hash
            data.transform_values { |v| sanitize_for_json(v) }
          when Array
            data.map { |v| sanitize_for_json(v) }
          when Float
            if data.infinite?
              data > 0 ? "Infinity" : "-Infinity"
            elsif data.nan?
              "NaN"
            else
              data
            end
          else
            data
          end
        end

        private

        def generate_csv_report(_report_data)
          # Generate CSV format report
          "CSV report would be generated here"
        end
      end

      class DataAggregator
        def export_metrics(_time_range, format)
          case format
          when :csv
            "CSV export would be generated here"
          when :json
            "JSON export would be generated here"
          else
            "Export in #{format} format would be generated here"
          end
        end
      end

      class BenchmarkManager
        def initialize
          @benchmarks = {}
          @benchmark_results = {}
        end

        def setup_benchmarks(benchmark_config)
          @benchmarks = benchmark_config
        end

        def run_benchmarks(_provider_name = nil, _model_name = nil)
          # Run benchmarks
        end

        def get_results(_provider_name = nil, _model_name = nil)
          @benchmark_results
        end

        def get_provider_benchmarks(_provider_name, _time_range)
          {}
        end

        def get_model_benchmarks(_provider_name, _model_name, _time_range)
          {}
        end
      end
    end
  end
end
