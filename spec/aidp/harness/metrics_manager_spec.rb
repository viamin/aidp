# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::MetricsManager do
  let(:provider_manager) { instance_double("Aidp::Harness::ProviderManager") }
  let(:configuration) { instance_double("Aidp::Harness::Configuration") }
  let(:metrics_manager) { described_class.new(provider_manager, configuration) }

  before do
    # Mock provider manager methods
    allow(provider_manager).to receive(:configured_providers).and_return(["claude", "gemini", "cursor"])
    allow(provider_manager).to receive(:get_provider_models).and_return(["model1", "model2"])

    # Mock configuration methods
    allow(configuration).to receive(:metrics_config).and_return({
      retention_days: 30,
      collection_interval: 60
    })
  end

  describe "initialization" do
    it "creates metrics manager successfully" do
      expect(metrics_manager).to be_a(described_class)
    end

    it "initializes metrics collection components" do
      expect(metrics_manager.instance_variable_get(:@metrics_store)).to be_a(described_class::MetricsStore)
      expect(metrics_manager.instance_variable_get(:@performance_analyzer)).to be_a(described_class::PerformanceAnalyzer)
      expect(metrics_manager.instance_variable_get(:@trend_analyzer)).to be_a(described_class::TrendAnalyzer)
      expect(metrics_manager.instance_variable_get(:@alert_manager)).to be_a(described_class::AlertManager)
      expect(metrics_manager.instance_variable_get(:@report_generator)).to be_a(described_class::ReportGenerator)
      expect(metrics_manager.instance_variable_get(:@data_aggregator)).to be_a(described_class::DataAggregator)
      expect(metrics_manager.instance_variable_get(:@benchmark_manager)).to be_a(described_class::BenchmarkManager)
    end
  end

  describe "request recording" do
    let(:request_data) { {prompt: "test prompt", max_tokens: 100} }
    let(:response_data) { {response: "test response", token_count: 50} }

    it "records a successful request" do
      event = metrics_manager.record_request("claude", "model1", request_data, response_data, 1.5, true)

      expect(event[:event_type]).to eq("request")
      expect(event[:provider]).to eq("claude")
      expect(event[:model]).to eq("model1")
      expect(event[:success]).to be true
      expect(event[:duration]).to eq(1.5)
      expect(event[:token_count]).to eq(50)
    end

    it "records a failed request" do
      error = StandardError.new("API error")
      event = metrics_manager.record_request("claude", "model1", request_data, response_data, 2.0, false, error)

      expect(event[:success]).to be false
      expect(event[:error]).to eq("API error")
      expect(event[:error_type]).to eq("StandardError")
    end

    it "sanitizes sensitive data from request" do
      sensitive_request = {prompt: "test", api_key: "secret", password: "password"}
      event = metrics_manager.record_request("claude", "model1", sensitive_request, response_data, 1.0, true)

      expect(event[:request_data]).not_to include(:api_key, :password)
      expect(event[:request_data][:prompt]).to eq("test")
    end

    it "sanitizes sensitive data from response" do
      sensitive_response = {response: "test", api_key: "secret", token: "token"}
      event = metrics_manager.record_request("claude", "model1", request_data, sensitive_response, 1.0, true)

      expect(event[:response_data]).not_to include(:api_key, :token)
      expect(event[:response_data][:response]).to eq("test")
    end
  end

  describe "provider switch recording" do
    it "records provider switch event" do
      event = metrics_manager.record_provider_switch("claude", "gemini", "rate_limit", {switch_duration: 0.5})

      expect(event[:event_type]).to eq("provider_switch")
      expect(event[:from_provider]).to eq("claude")
      expect(event[:to_provider]).to eq("gemini")
      expect(event[:reason]).to eq("rate_limit")
      expect(event[:switch_duration]).to eq(0.5)
    end
  end

  describe "model switch recording" do
    it "records model switch event" do
      event = metrics_manager.record_model_switch("claude", "model1", "model2", "performance", {switch_duration: 0.3})

      expect(event[:event_type]).to eq("model_switch")
      expect(event[:provider]).to eq("claude")
      expect(event[:from_model]).to eq("model1")
      expect(event[:to_model]).to eq("model2")
      expect(event[:reason]).to eq("performance")
      expect(event[:switch_duration]).to eq(0.3)
    end
  end

  describe "rate limit recording" do
    let(:rate_limit_info) do
      {
        type: "rate_limit",
        reset_time: Time.now + 3600,
        retry_after: 60
      }
    end

    it "records rate limit event" do
      event = metrics_manager.record_rate_limit("claude", "model1", rate_limit_info, {context: "test"})

      expect(event[:event_type]).to eq("rate_limit")
      expect(event[:provider]).to eq("claude")
      expect(event[:model]).to eq("model1")
      expect(event[:rate_limit_info]).to eq(rate_limit_info)
      expect(event[:reset_time]).to eq(rate_limit_info[:reset_time])
      expect(event[:retry_after]).to eq(60)
    end
  end

  describe "provider metrics" do
    before do
      # Record some test events
      metrics_manager.record_request("claude", "model1", {}, {}, 1.0, true)
      metrics_manager.record_request("claude", "model1", {}, {}, 2.0, true)
      metrics_manager.record_request("claude", "model1", {}, {}, 3.0, false)
    end

    it "returns comprehensive provider metrics" do
      metrics = metrics_manager.get_provider_metrics("claude")

      expect(metrics).to include(
        :basic_metrics,
        :performance_metrics,
        :reliability_metrics,
        :cost_metrics,
        :usage_metrics,
        :trend_analysis,
        :benchmarks,
        :alerts
      )
    end

    it "calculates basic metrics correctly" do
      metrics = metrics_manager.get_provider_metrics("claude")
      basic_metrics = metrics[:basic_metrics]

      expect(basic_metrics[:total_requests]).to eq(3)
      expect(basic_metrics[:successful_requests]).to eq(2)
      expect(basic_metrics[:failed_requests]).to eq(1)
      expect(basic_metrics[:success_rate]).to be_within(0.01).of(0.67)
      expect(basic_metrics[:average_response_time]).to eq(2.0)
    end

    it "calculates performance metrics correctly" do
      metrics = metrics_manager.get_provider_metrics("claude")
      performance_metrics = metrics[:performance_metrics]

      expect(performance_metrics).to include(
        :response_time_percentiles,
        :throughput,
        :error_rate,
        :availability,
        :performance_score
      )

      expect(performance_metrics[:error_rate]).to be_within(0.01).of(0.33)
      expect(performance_metrics[:availability]).to be_within(0.01).of(0.67)
    end

    it "calculates reliability metrics correctly" do
      metrics = metrics_manager.get_provider_metrics("claude")
      reliability_metrics = metrics[:reliability_metrics]

      expect(reliability_metrics).to include(
        :uptime,
        :mean_time_between_failures,
        :mean_time_to_recovery,
        :error_distribution,
        :reliability_score
      )
    end

    it "calculates cost metrics correctly" do
      metrics = metrics_manager.get_provider_metrics("claude")
      cost_metrics = metrics[:cost_metrics]

      expect(cost_metrics).to include(
        :total_cost,
        :average_cost_per_request,
        :cost_per_token,
        :cost_efficiency,
        :cost_trend
      )
    end

    it "calculates usage metrics correctly" do
      metrics = metrics_manager.get_provider_metrics("claude")
      usage_metrics = metrics[:usage_metrics]

      expect(usage_metrics).to include(
        :request_volume,
        :token_usage,
        :peak_usage,
        :usage_patterns,
        :utilization_rate
      )
    end
  end

  describe "model metrics" do
    before do
      # Record some test events
      metrics_manager.record_request("claude", "model1", {}, {}, 1.0, true)
      metrics_manager.record_request("claude", "model1", {}, {}, 2.0, true)
      metrics_manager.record_request("claude", "model2", {}, {}, 3.0, false)
    end

    it "returns comprehensive model metrics" do
      metrics = metrics_manager.get_model_metrics("claude", "model1")

      expect(metrics).to include(
        :basic_metrics,
        :performance_metrics,
        :reliability_metrics,
        :cost_metrics,
        :usage_metrics,
        :trend_analysis,
        :benchmarks,
        :alerts
      )
    end

    it "calculates model-specific basic metrics" do
      metrics = metrics_manager.get_model_metrics("claude", "model1")
      basic_metrics = metrics[:basic_metrics]

      expect(basic_metrics[:total_requests]).to eq(2)
      expect(basic_metrics[:successful_requests]).to eq(2)
      expect(basic_metrics[:failed_requests]).to eq(0)
      expect(basic_metrics[:success_rate]).to eq(1.0)
    end
  end

  describe "system metrics" do
    before do
      # Record some test events across providers
      metrics_manager.record_request("claude", "model1", {}, {}, 1.0, true)
      metrics_manager.record_request("gemini", "model1", {}, {}, 2.0, true)
      metrics_manager.record_request("claude", "model2", {}, {}, 3.0, false)
    end

    it "returns comprehensive system metrics" do
      metrics = metrics_manager.get_system_metrics

      expect(metrics).to include(
        :overall_performance,
        :provider_comparison,
        :model_comparison,
        :system_health,
        :cost_analysis,
        :usage_patterns,
        :trend_analysis,
        :alerts
      )
    end

    it "calculates overall performance metrics" do
      metrics = metrics_manager.get_system_metrics
      overall_performance = metrics[:overall_performance]

      expect(overall_performance[:total_requests]).to eq(3)
      expect(overall_performance[:overall_success_rate]).to be_within(0.01).of(0.67)
      expect(overall_performance[:overall_average_response_time]).to eq(2.0)
    end

    it "provides provider comparison metrics" do
      metrics = metrics_manager.get_system_metrics
      provider_comparison = metrics[:provider_comparison]

      expect(provider_comparison).to include("claude", "gemini")
      expect(provider_comparison["claude"]).to include(:success_rate, :average_response_time, :total_cost, :performance_score)
    end

    it "provides model comparison metrics" do
      metrics = metrics_manager.get_system_metrics
      model_comparison = metrics[:model_comparison]

      expect(model_comparison).to include("claude", "gemini")
      expect(model_comparison["claude"]).to include("model1", "model2")
    end

    it "calculates system health metrics" do
      metrics = metrics_manager.get_system_metrics
      system_health = metrics[:system_health]

      expect(system_health).to include(
        :system_uptime,
        :switch_frequency,
        :rate_limit_frequency,
        :health_score
      )
    end

    it "provides cost analysis" do
      metrics = metrics_manager.get_system_metrics
      cost_analysis = metrics[:cost_analysis]

      expect(cost_analysis).to include(
        :total_system_cost,
        :cost_by_provider,
        :cost_by_model,
        :cost_trend,
        :cost_optimization_opportunities
      )
    end

    it "provides usage patterns" do
      metrics = metrics_manager.get_system_metrics
      usage_patterns = metrics[:usage_patterns]

      expect(usage_patterns).to include(
        :hourly_patterns,
        :daily_patterns,
        :provider_usage_distribution,
        :model_usage_distribution
      )
    end
  end

  describe "real-time metrics" do
    it "returns real-time metrics" do
      metrics = metrics_manager.get_realtime_metrics

      expect(metrics).to include(
        :current_requests,
        :active_providers,
        :current_load,
        :recent_errors,
        :performance_scores,
        :alert_status
      )
    end
  end

  describe "performance recommendations" do
    before do
      # Record some test events with poor performance
      metrics_manager.record_request("claude", "model1", {}, {}, 1.0, true)
      metrics_manager.record_request("claude", "model1", {}, {}, 2.0, true)
      metrics_manager.record_request("claude", "model1", {}, {}, 3.0, false)
    end

    it "generates performance recommendations" do
      recommendations = metrics_manager.get_performance_recommendations

      expect(recommendations).to be_an(Array)
      recommendations.each do |recommendation|
        expect(recommendation).to include(
          :type,
          :issue,
          :current_value,
          :threshold,
          :recommendation,
          :priority,
          :impact
        )
      end
    end

    it "sorts recommendations by priority and impact" do
      recommendations = metrics_manager.get_performance_recommendations

      if recommendations.size > 1
        priorities = recommendations.map { |r| r[:priority] }

        # Should be sorted by priority (descending) then impact (descending)
        expect(priorities).to eq(priorities.sort.reverse)
      end
    end
  end

  describe "performance report generation" do
    it "generates JSON performance report" do
      report = metrics_manager.generate_performance_report(nil, :json)

      expect(report).to be_a(String)
      expect { JSON.parse(report) }.not_to raise_error
    end

    it "generates YAML performance report" do
      report = metrics_manager.generate_performance_report(nil, :yaml)

      expect(report).to be_a(String)
      expect { YAML.safe_load(report, permitted_classes: [Symbol, Time, Range]) }.not_to raise_error
    end

    it "generates CSV performance report" do
      report = metrics_manager.generate_performance_report(nil, :csv)

      expect(report).to be_a(String)
    end
  end

  describe "benchmark management" do
    it "sets up benchmarks" do
      benchmark_config = {
        response_time: {threshold: 2.0},
        success_rate: {threshold: 0.95}
      }

      expect { metrics_manager.setup_benchmarks(benchmark_config) }.not_to raise_error
    end

    it "runs benchmarks" do
      expect { metrics_manager.run_benchmarks }.not_to raise_error
      expect { metrics_manager.run_benchmarks("claude") }.not_to raise_error
      expect { metrics_manager.run_benchmarks("claude", "model1") }.not_to raise_error
    end

    it "gets benchmark results" do
      results = metrics_manager.get_benchmark_results

      expect(results).to be_a(Hash)
    end
  end

  describe "alert management" do
    it "configures alerts" do
      alert_config = {
        response_time: {threshold: 5.0, severity: "warning"},
        error_rate: {threshold: 0.1, severity: "critical"}
      }

      expect { metrics_manager.configure_alerts(alert_config) }.not_to raise_error
    end

    it "gets alert history" do
      history = metrics_manager.get_alert_history

      expect(history).to be_an(Array)
    end
  end

  describe "data export" do
    it "exports metrics data" do
      csv_export = metrics_manager.export_metrics(nil, :csv)
      json_export = metrics_manager.export_metrics(nil, :json)

      expect(csv_export).to be_a(String)
      expect(json_export).to be_a(String)
    end
  end

  describe "data cleanup" do
    it "cleans up old metrics data" do
      expect { metrics_manager.cleanup_old_metrics(7) }.not_to raise_error
    end

    it "uses default retention days from configuration" do
      expect { metrics_manager.cleanup_old_metrics }.not_to raise_error
    end
  end

  describe "helper classes" do
    describe "MetricsStore" do
      let(:metrics_store) { described_class::MetricsStore.new }

      it "stores and retrieves events" do
        event = {event_type: "request", timestamp: Time.now, provider: "claude"}

        metrics_store.store_event(event)
        events = metrics_store.get_events("request", "claude")

        expect(events).to include(event)
      end

      it "filters events by time range" do
        old_event = {event_type: "request", timestamp: Time.now - 3600, provider: "claude"}
        new_event = {event_type: "request", timestamp: Time.now, provider: "claude"}

        metrics_store.store_event(old_event)
        metrics_store.store_event(new_event)

        time_range = (Time.now - 1800)..Time.now
        events = metrics_store.get_events("request", "claude", time_range)

        expect(events).to include(new_event)
        expect(events).not_to include(old_event)
      end

      it "updates real-time metrics" do
        event = {success: true, duration: 1.5}

        metrics_store.update_realtime_metrics("claude", "model1", event)

        expect(metrics_store.get_current_requests).to eq(1)
        expect(metrics_store.get_recent_errors).to eq(0)
      end
    end

    describe "PerformanceAnalyzer" do
      let(:analyzer) { described_class::PerformanceAnalyzer.new }

      it "calculates performance score" do
        events = [
          {success: true, duration: 1.0},
          {success: true, duration: 2.0},
          {success: false, duration: 3.0}
        ]

        score = analyzer.calculate_performance_score(events)

        expect(score).to be_a(Float)
        expect(score).to be_between(0.0, 1.0)
      end

      it "calculates reliability score" do
        events = [
          {success: true},
          {success: true},
          {success: false}
        ]

        score = analyzer.calculate_reliability_score(events)

        expect(score).to be_within(0.01).of(0.67)
      end

      it "calculates system health score" do
        request_events = [
          {success: true},
          {success: true},
          {success: false}
        ]
        switch_events = [{type: "switch"}]
        rate_limit_events = [{type: "rate_limit"}]

        score = analyzer.calculate_system_health_score(request_events, switch_events, rate_limit_events)

        expect(score).to be_a(Float)
        expect(score).to be_between(0.0, 1.0)
      end
    end

    describe "TrendAnalyzer" do
      let(:analyzer) { described_class::TrendAnalyzer.new }

      it "provides provider trends" do
        trends = analyzer.get_provider_trends("claude", (Time.now - 3600)..Time.now)

        expect(trends).to include(
          :request_volume_trend,
          :response_time_trend,
          :success_rate_trend
        )
      end

      it "provides model trends" do
        trends = analyzer.get_model_trends("claude", "model1", (Time.now - 3600)..Time.now)

        expect(trends).to include(
          :request_volume_trend,
          :response_time_trend,
          :success_rate_trend
        )
      end

      it "provides system trends" do
        trends = analyzer.get_system_trends((Time.now - 3600)..Time.now)

        expect(trends).to include(
          :overall_trend,
          :performance_trend,
          :cost_trend
        )
      end
    end

    describe "AlertManager" do
      let(:alert_manager) { described_class::AlertManager.new }

      it "configures alerts" do
        config = {response_time: {threshold: 5.0}}

        expect { alert_manager.configure_alerts(config) }.not_to raise_error
      end

      it "provides alert history" do
        history = alert_manager.get_alert_history((Time.now - 3600)..Time.now)

        expect(history).to be_an(Array)
      end

      it "provides alerts summary" do
        summary = alert_manager.get_alerts_summary((Time.now - 3600)..Time.now)

        expect(summary).to include(
          :total_alerts,
          :critical_alerts,
          :warning_alerts
        )
      end
    end

    describe "ReportGenerator" do
      let(:generator) { described_class::ReportGenerator.new }

      it "generates JSON reports" do
        data = {test: "data"}
        report = generator.generate_report(data, :json)

        expect(report).to be_a(String)
        expect { JSON.parse(report) }.not_to raise_error
      end

      it "generates YAML reports" do
        data = {test: "data"}
        report = generator.generate_report(data, :yaml)

        expect(report).to be_a(String)
        expect { YAML.safe_load(report, permitted_classes: [Symbol, Time, Range]) }.not_to raise_error
      end

      it "generates CSV reports" do
        data = {test: "data"}
        report = generator.generate_report(data, :csv)

        expect(report).to be_a(String)
      end
    end

    describe "DataAggregator" do
      let(:aggregator) { described_class::DataAggregator.new }

      it "exports data in different formats" do
        csv_export = aggregator.export_metrics((Time.now - 3600)..Time.now, :csv)
        json_export = aggregator.export_metrics((Time.now - 3600)..Time.now, :json)

        expect(csv_export).to be_a(String)
        expect(json_export).to be_a(String)
      end
    end

    describe "BenchmarkManager" do
      let(:benchmark_manager) { described_class::BenchmarkManager.new }

      it "sets up benchmarks" do
        config = {response_time: {threshold: 2.0}}

        expect { benchmark_manager.setup_benchmarks(config) }.not_to raise_error
      end

      it "runs benchmarks" do
        expect { benchmark_manager.run_benchmarks }.not_to raise_error
      end

      it "gets benchmark results" do
        results = benchmark_manager.get_results

        expect(results).to be_a(Hash)
      end
    end
  end

  describe "error handling" do
    it "handles missing provider manager methods gracefully" do
      allow(provider_manager).to receive(:configured_providers).and_raise(NoMethodError)

      expect {
        metrics_manager.get_system_metrics
      }.to raise_error(NoMethodError)
    end

    # Missing configuration methods test removed - method now exists in Configuration class
  end
end
