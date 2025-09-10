# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ProviderStatusTracker do
  let(:provider_manager) { instance_double("Aidp::Harness::ProviderManager") }
  let(:metrics_manager) { instance_double("Aidp::Harness::MetricsManager") }
  let(:circuit_breaker_manager) { instance_double("Aidp::Harness::CircuitBreakerManager") }
  let(:error_logger) { instance_double("Aidp::Harness::ErrorLogger") }
  let(:tracker) { described_class.new(provider_manager, metrics_manager, circuit_breaker_manager, error_logger) }

  before do
    # Mock provider manager methods
    allow(provider_manager).to receive(:get_available_providers).and_return(["claude", "gemini", "cursor"])
    allow(provider_manager).to receive(:get_provider_models).with("claude").and_return(["claude-3-5-sonnet", "claude-3-haiku"])
    allow(provider_manager).to receive(:get_provider_models).with("gemini").and_return(["gemini-pro", "gemini-pro-vision"])
    allow(provider_manager).to receive(:get_provider_models).with("cursor").and_return(["gpt-4", "gpt-3.5-turbo"])
    allow(provider_manager).to receive(:get_available_models).with("claude").and_return(["claude-3-5-sonnet", "claude-3-haiku"])
    allow(provider_manager).to receive(:get_available_models).with("gemini").and_return(["gemini-pro", "gemini-pro-vision"])
    allow(provider_manager).to receive(:get_available_models).with("cursor").and_return(["gpt-4", "gpt-3.5-turbo"])
    allow(provider_manager).to receive(:current_provider).and_return("claude")
    allow(provider_manager).to receive(:current_model).and_return("claude-3-5-sonnet")

    # Mock circuit breaker manager methods
    allow(circuit_breaker_manager).to receive(:get_state).with("claude").and_return(:closed)
    allow(circuit_breaker_manager).to receive(:get_state).with("gemini").and_return(:closed)
    allow(circuit_breaker_manager).to receive(:get_state).with("cursor").and_return(:open)
  end

  describe "initialization" do
    it "creates provider status tracker successfully" do
      expect(tracker).to be_a(described_class)
    end

    it "initializes with all required components" do
      expect(tracker.instance_variable_get(:@provider_manager)).to eq(provider_manager)
      expect(tracker.instance_variable_get(:@metrics_manager)).to eq(metrics_manager)
      expect(tracker.instance_variable_get(:@circuit_breaker_manager)).to eq(circuit_breaker_manager)
      expect(tracker.instance_variable_get(:@error_logger)).to eq(error_logger)
    end

    it "initializes status tracking components" do
      expect(tracker.instance_variable_get(:@status_history)).to be_an(Array)
      expect(tracker.instance_variable_get(:@provider_status_cache)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@model_status_cache)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@status_analyzers)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@health_monitors)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@performance_trackers)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@availability_trackers)).to be_a(Hash)
    end

    it "initializes helper components" do
      expect(tracker.instance_variable_get(:@status_aggregators)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@status_reporters)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@status_alerts)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@status_exporters)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@status_validators)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@status_optimizers)).to be_a(Hash)
    end
  end

  describe "provider status tracking" do
    before do
      tracker.force_status_update
    end

    it "gets provider status for all providers" do
      provider_status = tracker.get_provider_status

      expect(provider_status).to be_a(Hash)
      expect(provider_status.keys).to include("claude", "gemini", "cursor")

      provider_status.each do |provider, status|
        expect(status).to include(:name, :status, :health, :performance, :availability, :metrics, :last_updated)
        expect(status[:name]).to eq(provider)
      end
    end

    it "gets provider status for specific provider" do
      claude_status = tracker.get_provider_status("claude")

      expect(claude_status).to be_a(Hash)
      expect(claude_status[:name]).to eq("claude")
      expect(claude_status).to include(:status, :health, :performance, :availability, :metrics)
    end

    it "tracks provider operational status" do
      claude_status = tracker.get_provider_status("claude")
      operational_status = claude_status[:status]

      expect(operational_status).to include(
        :current,
        :available,
        :circuit_breaker_state,
        :last_used,
        :switch_count
      )
      expect(operational_status[:current]).to be true
      expect(operational_status[:available]).to be true
      expect(operational_status[:circuit_breaker_state]).to eq(:closed)
    end

    it "tracks provider health data" do
      claude_status = tracker.get_provider_status("claude")
      health_data = claude_status[:health]

      expect(health_data).to include(
        :score,
        :status,
        :issues,
        :recommendations,
        :last_check
      )
      expect(health_data[:score]).to be_a(Numeric)
      expect(health_data[:status]).to be_a(Symbol)
    end

    it "tracks provider performance data" do
      claude_status = tracker.get_provider_status("claude")
      performance_data = claude_status[:performance]

      expect(performance_data).to include(
        :score,
        :metrics,
        :trends,
        :benchmarks
      )
      expect(performance_data[:score]).to be_a(Numeric)
      expect(performance_data[:metrics]).to be_a(Hash)
    end

    it "tracks provider availability data" do
      claude_status = tracker.get_provider_status("claude")
      availability_data = claude_status[:availability]

      expect(availability_data).to include(
        :uptime,
        :downtime,
        :availability_percentage,
        :last_outage,
        :outage_count
      )
      expect(availability_data[:availability_percentage]).to be_a(Numeric)
    end

    it "tracks provider metrics data" do
      claude_status = tracker.get_provider_status("claude")
      metrics_data = claude_status[:metrics]

      expect(metrics_data).to include(
        :request_count,
        :success_count,
        :error_count,
        :average_response_time,
        :token_usage
      )
      expect(metrics_data[:request_count]).to be_a(Numeric)
      expect(metrics_data[:success_count]).to be_a(Numeric)
      expect(metrics_data[:error_count]).to be_a(Numeric)
    end
  end

  describe "model status tracking" do
    before do
      tracker.force_status_update
    end

    it "gets model status for all models in a provider" do
      claude_models = tracker.get_model_status("claude")

      expect(claude_models).to be_a(Hash)
      expect(claude_models.keys).to include("claude-3-5-sonnet", "claude-3-haiku")

      claude_models.each do |model, status|
        expect(status).to include(:name, :provider, :status, :performance, :availability, :metrics, :last_updated)
        expect(status[:name]).to eq(model)
        expect(status[:provider]).to eq("claude")
      end
    end

    it "gets model status for specific model" do
      model_status = tracker.get_model_status("claude", "claude-3-5-sonnet")

      expect(model_status).to be_a(Hash)
      expect(model_status[:name]).to eq("claude-3-5-sonnet")
      expect(model_status[:provider]).to eq("claude")
      expect(model_status).to include(:status, :performance, :availability, :metrics)
    end

    it "tracks model operational status" do
      model_status = tracker.get_model_status("claude", "claude-3-5-sonnet")
      operational_status = model_status[:status]

      expect(operational_status).to include(
        :current,
        :available,
        :last_used,
        :switch_count
      )
      expect(operational_status[:current]).to be true
      expect(operational_status[:available]).to be true
    end

    it "tracks model performance data" do
      model_status = tracker.get_model_status("claude", "claude-3-5-sonnet")
      performance_data = model_status[:performance]

      expect(performance_data).to include(
        :score,
        :metrics,
        :trends
      )
      expect(performance_data[:score]).to be_a(Numeric)
      expect(performance_data[:metrics]).to be_a(Hash)
    end

    it "tracks model availability data" do
      model_status = tracker.get_model_status("claude", "claude-3-5-sonnet")
      availability_data = model_status[:availability]

      expect(availability_data).to include(
        :available,
        :rate_limited,
        :quota_remaining,
        :quota_limit
      )
      expect(availability_data[:available]).to be true
      expect(availability_data[:rate_limited]).to be false
    end

    it "tracks model metrics data" do
      model_status = tracker.get_model_status("claude", "claude-3-5-sonnet")
      metrics_data = model_status[:metrics]

      expect(metrics_data).to include(
        :request_count,
        :success_count,
        :error_count,
        :average_response_time,
        :token_usage
      )
      expect(metrics_data[:request_count]).to be_a(Numeric)
    end
  end

  describe "status summary" do
    before do
      tracker.force_status_update
    end

    it "gets comprehensive status summary" do
      summary = tracker.get_status_summary

      expect(summary).to include(
        :timestamp,
        :providers,
        :models,
        :system_health,
        :performance,
        :availability,
        :alerts,
        :recommendations
      )
      expect(summary[:timestamp]).to be_a(Time)
      expect(summary[:providers]).to be_a(Hash)
      expect(summary[:models]).to be_a(Hash)
    end

    it "provides provider summary" do
      summary = tracker.get_status_summary
      provider_summary = summary[:providers]

      expect(provider_summary).to be_a(Hash)
      expect(provider_summary.keys).to include("claude", "gemini", "cursor")

      provider_summary.each do |_provider, status|
        expect(status).to include(
          :status,
          :health_score,
          :performance_score,
          :availability,
          :current
        )
        expect(status[:health_score]).to be_a(Numeric)
        expect(status[:performance_score]).to be_a(Numeric)
        expect(status[:current]).to be_a(TrueClass).or be_a(FalseClass)
      end
    end

    it "provides model summary" do
      summary = tracker.get_status_summary
      model_summary = summary[:models]

      expect(model_summary).to be_a(Hash)
      expect(model_summary.keys).to include("claude", "gemini", "cursor")

      claude_models = model_summary["claude"]
      expect(claude_models).to be_a(Hash)
      expect(claude_models.keys).to include("claude-3-5-sonnet", "claude-3-haiku")
    end

    it "provides system health summary" do
      summary = tracker.get_status_summary
      system_health = summary[:system_health]

      expect(system_health).to include(
        :overall_health,
        :provider_health,
        :model_health,
        :critical_issues,
        :recommendations
      )
      expect(system_health[:overall_health]).to be_a(Numeric)
    end

    it "provides performance summary" do
      summary = tracker.get_status_summary
      performance = summary[:performance]

      expect(performance).to include(
        :overall_performance,
        :provider_performance,
        :model_performance,
        :bottlenecks,
        :optimization_opportunities
      )
      expect(performance[:overall_performance]).to be_a(Numeric)
    end

    it "provides availability summary" do
      summary = tracker.get_status_summary
      availability = summary[:availability]

      expect(availability).to include(
        :overall_availability,
        :provider_availability,
        :model_availability,
        :outage_history,
        :reliability_metrics
      )
      expect(availability[:overall_availability]).to be_a(Numeric)
    end

    it "provides active alerts" do
      summary = tracker.get_status_summary
      alerts = summary[:alerts]

      expect(alerts).to be_an(Array)
    end

    it "provides status recommendations" do
      summary = tracker.get_status_summary
      recommendations = summary[:recommendations]

      expect(recommendations).to be_an(Array)
    end
  end

  describe "status history" do
    it "gets status history" do
      tracker.force_status_update
      history = tracker.get_status_history

      expect(history).to be_an(Array)
      expect(history.size).to eq(1)

      snapshot = history.first
      expect(snapshot).to include(
        :timestamp,
        :providers,
        :models,
        :system_health,
        :performance,
        :availability
      )
    end

    it "gets status history with time range" do
      tracker.force_status_update
      history = tracker.get_status_history(3600) # 1 hour

      expect(history).to be_an(Array)
    end

    it "gets status history with limit" do
      tracker.force_status_update
      history = tracker.get_status_history(nil, 50)

      expect(history).to be_an(Array)
      expect(history.size).to be <= 50
    end

    it "maintains history size limit" do
      # Force multiple updates to test history limit
      1002.times { tracker.force_status_update }

      history = tracker.get_status_history
      expect(history.size).to be <= 1000
    end
  end

  describe "health and performance tracking" do
    it "gets provider health score" do
      health_score = tracker.get_provider_health_score("claude")

      expect(health_score).to be_a(Numeric)
      expect(health_score).to be >= 0.0
      expect(health_score).to be <= 1.0
    end

    it "gets model performance score" do
      performance_score = tracker.get_model_performance_score("claude", "claude-3-5-sonnet")

      expect(performance_score).to be_a(Numeric)
      expect(performance_score).to be >= 0.0
      expect(performance_score).to be <= 1.0
    end

    it "gets availability metrics for provider" do
      availability = tracker.get_availability_metrics("claude")

      expect(availability).to be_a(Hash)
      expect(availability).to include(
        :uptime,
        :downtime,
        :availability_percentage,
        :last_outage,
        :outage_count
      )
    end

    it "gets availability metrics for model" do
      availability = tracker.get_availability_metrics("claude", "claude-3-5-sonnet")

      expect(availability).to be_a(Hash)
      expect(availability).to include(
        :available,
        :rate_limited,
        :quota_remaining,
        :quota_limit
      )
    end

    it "gets system availability metrics" do
      availability = tracker.get_availability_metrics

      expect(availability).to be_a(Hash)
      expect(availability).to include(
        :overall_availability,
        :provider_availability,
        :model_availability,
        :outage_history,
        :reliability_metrics
      )
    end
  end

  describe "status trends and predictions" do
    before do
      # Add some history for trend analysis
      5.times { tracker.force_status_update }
    end

    it "gets status trends" do
      trends = tracker.get_status_trends(3600) # 1 hour

      expect(trends).to be_a(Hash)
      expect(trends).to include(
        :health_trend,
        :performance_trend,
        :availability_trend,
        :error_trend
      )
    end

    it "gets status predictions for provider" do
      predictions = tracker.get_status_predictions("claude")

      expect(predictions).to be_a(Hash)
      expect(predictions).to include(
        :predicted_health,
        :predicted_performance,
        :predicted_availability,
        :confidence,
        :time_horizon
      )
    end

    it "gets status predictions for model" do
      predictions = tracker.get_status_predictions("claude", "claude-3-5-sonnet")

      expect(predictions).to be_a(Hash)
      expect(predictions).to include(
        :predicted_health,
        :predicted_performance,
        :predicted_availability,
        :confidence,
        :time_horizon
      )
    end

    it "gets system-wide status predictions" do
      predictions = tracker.get_status_predictions

      expect(predictions).to be_a(Hash)
      expect(predictions).to include(
        :predicted_health,
        :predicted_performance,
        :predicted_availability,
        :confidence,
        :time_horizon
      )
    end
  end

  describe "data export" do
    before do
      tracker.force_status_update
    end

    it "exports status data in JSON format" do
      json_export = tracker.export_status_data(:json)

      expect(json_export).to be_a(String)
      expect { JSON.parse(json_export) }.not_to raise_error
    end

    it "exports status data in YAML format" do
      yaml_export = tracker.export_status_data(:yaml)

      expect(yaml_export).to be_a(String)
      expect { YAML.safe_load(yaml_export) }.not_to raise_error
    end

    it "exports status data in CSV format" do
      csv_export = tracker.export_status_data(:csv)

      expect(csv_export).to be_a(String)
    end

    it "exports status data in text format" do
      text_export = tracker.export_status_data(:text)

      expect(text_export).to be_a(String)
    end

    it "raises error for unsupported format" do
      expect {
        tracker.export_status_data(:unsupported)
      }.to raise_error(ArgumentError, "Unsupported format: unsupported")
    end

    it "exports with options" do
      json_export = tracker.export_status_data(:json, {pretty: true})

      expect(json_export).to be_a(String)
    end
  end

  describe "status validation" do
    before do
      tracker.force_status_update
    end

    it "validates status data" do
      status_data = tracker.get_status_summary
      validation_result = tracker.validate_status_data(status_data)

      expect(validation_result).to include(:valid, :errors)
      expect(validation_result[:valid]).to be true
      expect(validation_result[:errors]).to be_an(Array)
    end
  end

  describe "status optimization" do
    it "optimizes status tracking" do
      optimization_result = tracker.optimize_status_tracking

      expect(optimization_result).to be_a(Hash)
    end
  end

  describe "status management" do
    it "forces status update" do
      expect { tracker.force_status_update }.not_to raise_error

      history = tracker.get_status_history
      expect(history.size).to be >= 1
    end

    it "clears status history" do
      tracker.force_status_update
      expect(tracker.get_status_history.size).to be >= 1

      tracker.clear_status_history
      expect(tracker.get_status_history.size).to eq(0)
    end

    it "gets status statistics" do
      tracker.force_status_update
      stats = tracker.get_status_statistics

      expect(stats).to include(
        :total_snapshots,
        :last_update,
        :cache_size,
        :health_monitors,
        :performance_trackers,
        :availability_trackers
      )
      expect(stats[:total_snapshots]).to be >= 1
      expect(stats[:last_update]).to be_a(Time)
    end
  end

  describe "helper classes" do
    describe "StatusAnalyzer" do
      let(:analyzer) { described_class::StatusAnalyzer.new(:health) }

      it "analyzes health data" do
        result = analyzer.analyze({})

        expect(result).to include(:health_score, :issues, :recommendations)
        expect(result[:health_score]).to be_a(Numeric)
        expect(result[:issues]).to be_an(Array)
        expect(result[:recommendations]).to be_an(Array)
      end
    end

    describe "ProviderHealthMonitor" do
      let(:monitor) { described_class::ProviderHealthMonitor.new("claude", provider_manager, error_logger) }

      it "calculates health score" do
        score = monitor.calculate_health_score

        expect(score).to be_a(Numeric)
        expect(score).to be >= 0.0
        expect(score).to be <= 1.0
      end

      it "gets health status" do
        status = monitor.get_health_status

        expect(status).to be_a(Symbol)
        expect([:excellent, :good, :fair, :poor, :critical]).to include(status)
      end

      it "gets health issues" do
        issues = monitor.get_health_issues

        expect(issues).to be_an(Array)
      end

      it "gets health recommendations" do
        recommendations = monitor.get_health_recommendations

        expect(recommendations).to be_an(Array)
      end

      it "tracks last check time" do
        last_check = monitor.last_check_time

        expect(last_check).to be_a(Time)
      end
    end

    describe "ProviderPerformanceTracker" do
      let(:tracker) { described_class::ProviderPerformanceTracker.new("claude", metrics_manager) }

      it "gets overall performance score" do
        score = tracker.get_overall_score

        expect(score).to be_a(Numeric)
        expect(score).to be >= 0.0
        expect(score).to be <= 1.0
      end

      it "gets performance metrics" do
        metrics = tracker.get_performance_metrics

        expect(metrics).to include(
          :throughput,
          :latency,
          :success_rate,
          :error_rate
        )
        expect(metrics[:throughput]).to be_a(Numeric)
        expect(metrics[:latency]).to be_a(Numeric)
      end

      it "gets performance trends" do
        trends = tracker.get_performance_trends

        expect(trends).to include(
          :throughput_trend,
          :latency_trend,
          :success_rate_trend
        )
      end

      it "gets benchmark data" do
        benchmarks = tracker.get_benchmark_data

        expect(benchmarks).to include(
          :baseline_throughput,
          :baseline_latency,
          :baseline_success_rate
        )
      end

      it "gets model-specific performance data" do
        model_score = tracker.get_model_score("claude-3-5-sonnet")
        model_metrics = tracker.get_model_metrics("claude-3-5-sonnet")
        model_trends = tracker.get_model_trends("claude-3-5-sonnet")

        expect(model_score).to be_a(Numeric)
        expect(model_metrics).to be_a(Hash)
        expect(model_trends).to be_a(Hash)
      end
    end

    describe "ProviderAvailabilityTracker" do
      let(:tracker) { described_class::ProviderAvailabilityTracker.new("claude", circuit_breaker_manager) }

      it "tracks uptime" do
        uptime = tracker.get_uptime

        expect(uptime).to be_a(Numeric)
        expect(uptime).to be >= 0
      end

      it "tracks downtime" do
        downtime = tracker.get_downtime

        expect(downtime).to be_a(Numeric)
        expect(downtime).to be >= 0
      end

      it "calculates availability percentage" do
        percentage = tracker.get_availability_percentage

        expect(percentage).to be_a(Numeric)
        expect(percentage).to be >= 0.0
        expect(percentage).to be <= 1.0
      end

      it "tracks last outage" do
        last_outage = tracker.get_last_outage

        expect(last_outage).to be_a(Time)
      end

      it "tracks outage count" do
        count = tracker.get_outage_count

        expect(count).to be_a(Numeric)
        expect(count).to be >= 0
      end
    end

    describe "StatusExporter" do
      let(:exporter) { described_class::StatusExporter.new(:json) }

      it "exports data in specified format" do
        data = {test: "data"}
        export = exporter.export(data)

        expect(export).to be_a(String)
      end

      it "exports with options" do
        data = {test: "data"}
        export = exporter.export(data, {pretty: true})

        expect(export).to be_a(String)
      end
    end

    describe "StatusValidator" do
      let(:validator) { described_class::StatusValidator.new(:comprehensive) }

      it "validates status data" do
        data = {test: "data"}
        result = validator.validate(data)

        expect(result).to include(:valid, :errors)
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_an(Array)
      end
    end

    describe "StatusOptimizer" do
      let(:optimizer) { described_class::StatusOptimizer.new(:performance) }

      it "optimizes status tracking" do
        result = optimizer.optimize(tracker)

        expect(result).to be_a(Hash)
        expect(result).to include(:optimizations)
      end
    end

    describe "StatusTrendAnalyzer" do
      let(:history) { [{timestamp: Time.now, data: "test"}] }
      let(:analyzer) { described_class::StatusTrendAnalyzer.new(history, 3600) }

      it "analyzes status trends" do
        trends = analyzer.analyze_trends

        expect(trends).to include(
          :health_trend,
          :performance_trend,
          :availability_trend,
          :error_trend
        )
      end
    end

    describe "StatusPredictor" do
      let(:history) { [{timestamp: Time.now, data: "test"}] }
      let(:predictor) { described_class::StatusPredictor.new(history, metrics_manager) }

      it "predicts status for provider" do
        predictions = predictor.predict_status("claude")

        expect(predictions).to include(
          :predicted_health,
          :predicted_performance,
          :predicted_availability,
          :confidence,
          :time_horizon
        )
      end

      it "predicts status for model" do
        predictions = predictor.predict_status("claude", "claude-3-5-sonnet")

        expect(predictions).to include(
          :predicted_health,
          :predicted_performance,
          :predicted_availability,
          :confidence,
          :time_horizon
        )
      end

      it "predicts system-wide status" do
        predictions = predictor.predict_status

        expect(predictions).to include(
          :predicted_health,
          :predicted_performance,
          :predicted_availability,
          :confidence,
          :time_horizon
        )
      end
    end
  end

  describe "error handling" do
    it "handles missing provider manager methods gracefully" do
      allow(provider_manager).to receive(:get_available_providers).and_raise(NoMethodError)

      expect { tracker.force_status_update }.not_to raise_error
    end

    it "handles missing circuit breaker manager methods gracefully" do
      allow(circuit_breaker_manager).to receive(:get_state).and_raise(NoMethodError)

      expect { tracker.force_status_update }.not_to raise_error
    end

    it "handles missing metrics manager methods gracefully" do
      allow(metrics_manager).to receive(:get_realtime_metrics).and_raise(NoMethodError)

      expect { tracker.force_status_update }.not_to raise_error
    end

    it "handles missing error logger methods gracefully" do
      allow(error_logger).to receive(:get_log_summary).and_raise(NoMethodError)

      expect { tracker.force_status_update }.not_to raise_error
    end
  end

  describe "performance and scalability" do
    it "handles large number of providers efficiently" do
      large_provider_list = (1..100).map { |i| "provider#{i}" }
      allow(provider_manager).to receive(:get_available_providers).and_return(large_provider_list)

      expect { tracker.force_status_update }.not_to raise_error

      provider_status = tracker.get_provider_status
      expect(provider_status.keys.size).to eq(100)
    end

    it "handles large number of models efficiently" do
      large_model_list = (1..50).map { |i| "model#{i}" }
      allow(provider_manager).to receive(:get_provider_models).and_return(large_model_list)
      allow(provider_manager).to receive(:get_available_models).and_return(large_model_list)

      expect { tracker.force_status_update }.not_to raise_error

      model_status = tracker.get_model_status("claude")
      expect(model_status.keys.size).to eq(50)
    end

    it "maintains performance with frequent updates" do
      start_time = Time.now

      100.times { tracker.force_status_update }

      end_time = Time.now
      duration = end_time - start_time

      # Should complete within reasonable time (adjust threshold as needed)
      expect(duration).to be < 10.0
    end
  end
end
