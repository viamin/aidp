# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::TokenMonitor do
  let(:provider_manager) { instance_double("Aidp::Harness::ProviderManager") }
  let(:metrics_manager) { instance_double("Aidp::Harness::MetricsManager") }
  let(:status_display) { instance_double("Aidp::Harness::StatusDisplay") }
  let(:monitor) { described_class.new(provider_manager, metrics_manager, status_display) }

  before do
    allow(status_display).to receive(:update_token_usage)
  end

  describe "initialization" do
    it "creates token monitor successfully" do
      expect(monitor).to be_a(described_class)
    end

    it "initializes with all required components" do
      expect(monitor.instance_variable_get(:@provider_manager)).to eq(provider_manager)
      expect(monitor.instance_variable_get(:@metrics_manager)).to eq(metrics_manager)
      expect(monitor.instance_variable_get(:@status_display)).to eq(status_display)
    end

    it "initializes token tracking data structures" do
      expect(monitor.instance_variable_get(:@token_usage)).to be_a(Hash)
      expect(monitor.instance_variable_get(:@token_history)).to be_an(Array)
      expect(monitor.instance_variable_get(:@token_limits)).to be_a(Hash)
      expect(monitor.instance_variable_get(:@token_alerts)).to be_an(Array)
      expect(monitor.instance_variable_get(:@usage_patterns)).to be_a(Hash)
      expect(monitor.instance_variable_get(:@cost_tracking)).to be_a(Hash)
      expect(monitor.instance_variable_get(:@quota_tracking)).to be_a(Hash)
      expect(monitor.instance_variable_get(:@rate_limit_tracking)).to be_a(Hash)
    end

    it "initializes helper components" do
      expect(monitor.instance_variable_get(:@token_analyzers)).to be_a(Hash)
      expect(monitor.instance_variable_get(:@usage_predictors)).to be_a(Hash)
      expect(monitor.instance_variable_get(:@cost_calculators)).to be_a(Hash)
      expect(monitor.instance_variable_get(:@quota_managers)).to be_a(Hash)
      expect(monitor.instance_variable_get(:@alert_managers)).to be_a(Hash)
      expect(monitor.instance_variable_get(:@display_formatters)).to be_a(Hash)
      expect(monitor.instance_variable_get(:@export_managers)).to be_a(Hash)
      expect(monitor.instance_variable_get(:@optimization_engines)).to be_a(Hash)
    end

    it "sets configuration defaults" do
      expect(monitor.instance_variable_get(:@max_history_size)).to eq(10000)
      expect(monitor.instance_variable_get(:@update_interval)).to eq(30)
      expect(monitor.instance_variable_get(:@last_update)).to be_a(Time)
    end
  end

  describe "token usage recording" do
    it "records token usage for a request" do
      usage = monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)

      expect(usage).to include(
        :provider,
        :model,
        :total_tokens,
        :request_tokens,
        :response_tokens,
        :request_count,
        :total_cost,
        :last_used,
        :peak_usage,
        :average_usage,
        :usage_trend,
        :efficiency_score
      )
      expect(usage[:provider]).to eq("claude")
      expect(usage[:model]).to eq("claude-3-5-sonnet")
      expect(usage[:total_tokens]).to eq(300)
      expect(usage[:request_tokens]).to eq(100)
      expect(usage[:response_tokens]).to eq(200)
      expect(usage[:request_count]).to eq(1)
      expect(usage[:total_cost]).to eq(0.01)
      expect(usage[:peak_usage]).to eq(300)
      expect(usage[:average_usage]).to eq(300.0)
    end

    it "accumulates token usage across multiple requests" do
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
      usage = monitor.record_token_usage("claude", "claude-3-5-sonnet", 150, 250, 0.015)

      expect(usage[:total_tokens]).to eq(700) # 300 + 400
      expect(usage[:request_tokens]).to eq(250) # 100 + 150
      expect(usage[:response_tokens]).to eq(450) # 200 + 250
      expect(usage[:request_count]).to eq(2)
      expect(usage[:total_cost]).to eq(0.025) # 0.01 + 0.015
      expect(usage[:peak_usage]).to eq(400) # Max of 300 and 400
      expect(usage[:average_usage]).to eq(350.0) # 700 / 2
    end

    it "tracks different providers and models separately" do
      claude_usage = monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
      gemini_usage = monitor.record_token_usage("gemini", "gemini-pro", 150, 250, 0.015)

      expect(claude_usage[:provider]).to eq("claude")
      expect(claude_usage[:model]).to eq("claude-3-5-sonnet")
      expect(claude_usage[:total_tokens]).to eq(300)

      expect(gemini_usage[:provider]).to eq("gemini")
      expect(gemini_usage[:model]).to eq("gemini-pro")
      expect(gemini_usage[:total_tokens]).to eq(400)
    end

    it "updates status display when recording usage" do
      expect(status_display).to receive(:update_token_usage).with("claude", "claude-3-5-sonnet", 300, nil)

      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
    end

    it "handles nil cost gracefully" do
      usage = monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, nil)

      expect(usage[:total_cost]).to eq(0.0)
    end
  end

  describe "current usage retrieval" do
    before do
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
      monitor.record_token_usage("claude", "claude-3-haiku", 150, 250, 0.015)
      monitor.record_token_usage("gemini", "gemini-pro", 200, 300, 0.02)
    end

    it "gets current usage for specific model" do
      usage = monitor.get_current_usage("claude", "claude-3-5-sonnet")

      expect(usage[:provider]).to eq("claude")
      expect(usage[:model]).to eq("claude-3-5-sonnet")
      expect(usage[:total_tokens]).to eq(300)
      expect(usage[:request_count]).to eq(1)
    end

    it "gets current usage for provider (all models)" do
      usage = monitor.get_current_usage("claude")

      expect(usage[:provider]).to eq("claude")
      expect(usage[:total_tokens]).to eq(700) # 300 + 400
      expect(usage[:request_tokens]).to eq(250) # 100 + 150
      expect(usage[:response_tokens]).to eq(450) # 200 + 250
      expect(usage[:request_count]).to eq(2)
      expect(usage[:total_cost]).to eq(0.025)
      expect(usage[:models]).to include("claude-3-5-sonnet", "claude-3-haiku")
    end

    it "returns empty data for non-existent provider/model" do
      usage = monitor.get_current_usage("nonexistent", "nonexistent")

      expect(usage[:total_tokens]).to eq(0)
      expect(usage[:request_count]).to eq(0)
      expect(usage[:total_cost]).to eq(0.0)
    end
  end

  describe "usage history" do
    before do
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 150, 250, 0.015)
      monitor.record_token_usage("gemini", "gemini-pro", 200, 300, 0.02)
    end

    it "gets usage history for all providers and models" do
      history = monitor.get_usage_history

      expect(history).to be_an(Array)
      expect(history.size).to eq(3)

      history.each do |entry|
        expect(entry).to include(
          :timestamp,
          :provider,
          :model,
          :request_tokens,
          :response_tokens,
          :total_tokens,
          :cost,
          :request_id
        )
        expect(entry[:timestamp]).to be_a(Time)
        expect(entry[:request_id]).to be_a(String)
      end
    end

    it "gets usage history filtered by provider" do
      history = monitor.get_usage_history("claude")

      expect(history.size).to eq(2)
      expect(history.all? { |entry| entry[:provider] == "claude" }).to be true
    end

    it "gets usage history filtered by model" do
      history = monitor.get_usage_history("claude", "claude-3-5-sonnet")

      expect(history.size).to eq(2)
      expect(history.all? { |entry| entry[:provider] == "claude" && entry[:model] == "claude-3-5-sonnet" }).to be true
    end

    it "gets usage history filtered by time range" do
      # Wait a bit to ensure time difference
      sleep(0.1)
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)

      history = monitor.get_usage_history(nil, nil, 0.05) # Last 0.05 seconds

      expect(history.size).to eq(1)
      expect(history.first[:provider]).to eq("claude")
    end

    it "limits history results" do
      history = monitor.get_usage_history(nil, nil, nil, 2)

      expect(history.size).to eq(2)
    end

    it "maintains history size limit" do
      # Force multiple entries to test history limit
      10002.times { monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01) }

      history = monitor.get_usage_history
      expect(history.size).to be <= 10000
    end
  end

  describe "usage summary" do
    before do
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 150, 250, 0.015)
      monitor.record_token_usage("gemini", "gemini-pro", 200, 300, 0.02)
    end

    it "gets usage summary for all providers and models" do
      summary = monitor.get_usage_summary

      expect(summary).to include(
        :total_requests,
        :total_tokens,
        :total_request_tokens,
        :total_response_tokens,
        :average_tokens_per_request,
        :average_request_tokens,
        :average_response_tokens,
        :total_cost,
        :peak_usage,
        :time_range,
        :start_time,
        :end_time
      )
      expect(summary[:total_requests]).to eq(3)
      expect(summary[:total_tokens]).to eq(1200) # 300 + 400 + 500
      expect(summary[:total_cost]).to eq(0.045) # 0.01 + 0.015 + 0.02
      expect(summary[:peak_usage]).to eq(500)
    end

    it "gets usage summary filtered by provider" do
      summary = monitor.get_usage_summary("claude")

      expect(summary[:total_requests]).to eq(2)
      expect(summary[:total_tokens]).to eq(700) # 300 + 400
      expect(summary[:total_cost]).to eq(0.025) # 0.01 + 0.015
    end

    it "gets usage summary filtered by model" do
      summary = monitor.get_usage_summary("claude", "claude-3-5-sonnet")

      expect(summary[:total_requests]).to eq(2)
      expect(summary[:total_tokens]).to eq(700) # 300 + 400
      expect(summary[:total_cost]).to eq(0.025) # 0.01 + 0.015
    end

    it "gets usage summary filtered by time range" do
      # Wait a bit to ensure time difference
      sleep(0.1)
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)

      summary = monitor.get_usage_summary(nil, nil, 0.05) # Last 0.05 seconds

      expect(summary[:total_requests]).to eq(1)
      expect(summary[:total_tokens]).to eq(300)
    end

    it "returns empty summary for no data" do
      empty_monitor = described_class.new(provider_manager, metrics_manager, status_display)
      summary = empty_monitor.get_usage_summary

      expect(summary[:total_requests]).to eq(0)
      expect(summary[:total_tokens]).to eq(0)
      expect(summary[:total_cost]).to eq(0.0)
      expect(summary[:peak_usage]).to eq(0)
    end
  end

  describe "usage patterns" do
    before do
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
    end

    it "gets usage patterns for all providers and models" do
      patterns = monitor.get_usage_patterns

      expect(patterns).to be_a(Hash)
      expect(patterns["claude"]).to be_a(Hash)
      expect(patterns["claude"]["claude-3-5-sonnet"]).to include(
        :hourly_pattern,
        :daily_pattern,
        :weekly_pattern,
        :peak_hours,
        :peak_days,
        :usage_distribution
      )
    end

    it "gets usage patterns filtered by provider" do
      patterns = monitor.get_usage_patterns("claude")

      expect(patterns).to be_a(Hash)
      expect(patterns.keys).to include("claude-3-5-sonnet")
    end

    it "gets usage patterns filtered by model" do
      patterns = monitor.get_usage_patterns("claude", "claude-3-5-sonnet")

      expect(patterns).to include(
        :hourly_pattern,
        :daily_pattern,
        :weekly_pattern,
        :peak_hours,
        :peak_days,
        :usage_distribution
      )
    end
  end

  describe "usage predictions" do
    before do
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
    end

    it "gets usage predictions for all providers and models" do
      predictions = monitor.get_usage_predictions

      expect(predictions).to include(
        :predicted_tokens,
        :confidence,
        :time_horizon,
        :factors
      )
      expect(predictions[:predicted_tokens]).to be_a(Numeric)
      expect(predictions[:confidence]).to be_a(Numeric)
      expect(predictions[:time_horizon]).to eq(3600)
    end

    it "gets usage predictions filtered by provider" do
      predictions = monitor.get_usage_predictions("claude")

      expect(predictions).to include(
        :predicted_tokens,
        :confidence,
        :time_horizon,
        :factors
      )
    end

    it "gets usage predictions filtered by model" do
      predictions = monitor.get_usage_predictions("claude", "claude-3-5-sonnet")

      expect(predictions).to include(
        :predicted_tokens,
        :confidence,
        :time_horizon,
        :factors
      )
    end

    it "gets usage predictions with custom time horizon" do
      predictions = monitor.get_usage_predictions("claude", "claude-3-5-sonnet", 7200)

      expect(predictions[:time_horizon]).to eq(7200)
    end
  end

  describe "cost analysis" do
    before do
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
    end

    it "gets cost analysis for all providers and models" do
      analysis = monitor.get_cost_analysis

      expect(analysis).to include(
        :total_cost,
        :average_cost_per_request,
        :cost_trend,
        :cost_breakdown,
        :cost_optimization
      )
    end

    it "gets cost analysis filtered by provider" do
      analysis = monitor.get_cost_analysis("claude")

      expect(analysis).to include(
        :total_cost,
        :average_cost_per_request,
        :cost_trend,
        :cost_breakdown,
        :cost_optimization
      )
    end

    it "gets cost analysis filtered by model" do
      analysis = monitor.get_cost_analysis("claude", "claude-3-5-sonnet")

      expect(analysis).to include(
        :total_cost,
        :average_cost_per_request,
        :cost_trend,
        :cost_breakdown,
        :cost_optimization
      )
    end

    it "gets cost analysis with custom time range" do
      analysis = monitor.get_cost_analysis("claude", "claude-3-5-sonnet", 7200)

      expect(analysis).to include(
        :total_cost,
        :average_cost_per_request,
        :cost_trend,
        :cost_breakdown,
        :cost_optimization
      )
    end
  end

  describe "quota status" do
    before do
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
      monitor.set_token_limits("claude", "claude-3-5-sonnet", {daily_limit: 10000, monthly_limit: 100000})
    end

    it "gets quota status for specific model" do
      status = monitor.get_quota_status("claude", "claude-3-5-sonnet")

      expect(status).to include(
        :provider,
        :model,
        :used_tokens,
        :daily_limit,
        :monthly_limit,
        :remaining_daily,
        :remaining_monthly,
        :quota_used_percentage,
        :status
      )
      expect(status[:provider]).to eq("claude")
      expect(status[:model]).to eq("claude-3-5-sonnet")
      expect(status[:used_tokens]).to eq(300)
      expect(status[:daily_limit]).to eq(10000)
      expect(status[:remaining_daily]).to eq(9700)
      expect(status[:quota_used_percentage]).to eq(3.0)
    end

    it "gets quota status for provider" do
      status = monitor.get_quota_status("claude")

      expect(status).to include(
        :provider,
        :total_used_tokens,
        :models_count,
        :status
      )
      expect(status[:provider]).to eq("claude")
      expect(status[:total_used_tokens]).to eq(300)
      expect(status[:models_count]).to eq(1)
    end

    it "gets system quota status" do
      status = monitor.get_quota_status

      expect(status).to include(
        :total_providers,
        :total_models,
        :total_tokens_used,
        :status
      )
      expect(status[:total_providers]).to eq(1)
      expect(status[:total_models]).to eq(1)
      expect(status[:total_tokens_used]).to eq(300)
    end
  end

  describe "rate limit status" do
    before do
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
    end

    it "gets rate limit status for specific model" do
      status = monitor.get_rate_limit_status("claude", "claude-3-5-sonnet")

      expect(status).to include(
        :provider,
        :model,
        :rate_limited,
        :requests_per_minute,
        :tokens_per_minute,
        :reset_time
      )
      expect(status[:provider]).to eq("claude")
      expect(status[:model]).to eq("claude-3-5-sonnet")
      expect(status[:rate_limited]).to be false
    end

    it "gets rate limit status for provider" do
      status = monitor.get_rate_limit_status("claude")

      expect(status).to include(
        :provider,
        :rate_limited,
        :requests_per_minute,
        :tokens_per_minute,
        :reset_time
      )
      expect(status[:provider]).to eq("claude")
      expect(status[:rate_limited]).to be false
    end

    it "gets system rate limit status" do
      status = monitor.get_rate_limit_status

      expect(status).to include(
        :any_rate_limited,
        :total_requests_per_minute,
        :total_tokens_per_minute
      )
      expect(status[:any_rate_limited]).to be false
    end
  end

  describe "token alerts" do
    it "gets all token alerts" do
      alerts = monitor.get_token_alerts

      expect(alerts).to be_an(Array)
    end

    it "gets token alerts filtered by severity" do
      alerts = monitor.get_token_alerts(:warning)

      expect(alerts).to be_an(Array)
    end
  end

  describe "display formatting" do
    before do
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
    end

    it "displays token usage in compact format" do
      display = monitor.display_token_usage("claude", "claude-3-5-sonnet", :compact)

      expect(display).to be_a(String)
    end

    it "displays token usage in detailed format" do
      display = monitor.display_token_usage("claude", "claude-3-5-sonnet", :detailed)

      expect(display).to be_a(String)
    end

    it "displays token usage in summary format" do
      display = monitor.display_token_usage("claude", "claude-3-5-sonnet", :summary)

      expect(display).to be_a(String)
    end

    it "displays token usage in realtime format" do
      display = monitor.display_token_usage("claude", "claude-3-5-sonnet", :realtime)

      expect(display).to be_a(String)
    end
  end

  describe "data export" do
    before do
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
    end

    it "exports token data in JSON format" do
      export = monitor.export_token_data(:json)

      expect(export).to be_a(String)
      expect { JSON.parse(export) }.not_to raise_error
    end

    it "exports token data in YAML format" do
      export = monitor.export_token_data(:yaml)

      expect(export).to be_a(String)
      expect { YAML.safe_load(export) }.not_to raise_error
    end

    it "exports token data in CSV format" do
      export = monitor.export_token_data(:csv)

      expect(export).to be_a(String)
    end

    it "exports token data in text format" do
      export = monitor.export_token_data(:text)

      expect(export).to be_a(String)
    end

    it "exports token data with options" do
      export = monitor.export_token_data(:json, {pretty: true})

      expect(export).to be_a(String)
    end
  end

  describe "token optimization" do
    before do
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
    end

    it "optimizes token usage for all providers and models" do
      optimization = monitor.optimize_token_usage

      expect(optimization).to include(
        :optimizations,
        :potential_savings,
        :recommendations
      )
    end

    it "optimizes token usage for specific provider" do
      optimization = monitor.optimize_token_usage("claude")

      expect(optimization).to include(
        :optimizations,
        :potential_savings,
        :recommendations
      )
    end

    it "optimizes token usage for specific model" do
      optimization = monitor.optimize_token_usage("claude", "claude-3-5-sonnet")

      expect(optimization).to include(
        :optimizations,
        :potential_savings,
        :recommendations
      )
    end
  end

  describe "token limits management" do
    it "sets token limits for provider and model" do
      limits = {daily_limit: 10000, monthly_limit: 100000}
      monitor.set_token_limits("claude", "claude-3-5-sonnet", limits)

      retrieved_limits = monitor.get_token_limits("claude", "claude-3-5-sonnet")
      expect(retrieved_limits).to eq(limits)
    end

    it "gets token limits for provider" do
      limits = {daily_limit: 10000, monthly_limit: 100000}
      monitor.set_token_limits("claude", "claude-3-5-sonnet", limits)

      provider_limits = monitor.get_token_limits("claude")
      expect(provider_limits).to include("claude-3-5-sonnet" => limits)
    end

    it "returns empty hash for non-existent limits" do
      limits = monitor.get_token_limits("nonexistent", "nonexistent")
      expect(limits).to eq({})
    end
  end

  describe "token history management" do
    before do
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
    end

    it "clears token history" do
      expect(monitor.get_usage_history.size).to be >= 1

      monitor.clear_token_history
      expect(monitor.get_usage_history.size).to eq(0)
    end
  end

  describe "token statistics" do
    before do
      monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)
      monitor.record_token_usage("gemini", "gemini-pro", 150, 250, 0.015)
    end

    it "gets token statistics" do
      stats = monitor.get_token_statistics

      expect(stats).to include(
        :total_entries,
        :providers_tracked,
        :models_tracked,
        :active_alerts,
        :last_update,
        :history_size_limit
      )
      expect(stats[:total_entries]).to be >= 2
      expect(stats[:providers_tracked]).to eq(2)
      expect(stats[:models_tracked]).to eq(2)
      expect(stats[:active_alerts]).to eq(0)
      expect(stats[:last_update]).to be_a(Time)
      expect(stats[:history_size_limit]).to eq(10000)
    end
  end

  describe "helper classes" do
    describe "TokenUsageAnalyzer" do
      let(:analyzer) { described_class::TokenUsageAnalyzer.new }

      it "analyzes usage data" do
        result = analyzer.analyze_usage({})

        expect(result).to include(
          :efficiency,
          :patterns,
          :trends,
          :recommendations
        )
        expect(result[:efficiency]).to be_a(Numeric)
        expect(result[:patterns]).to be_a(Hash)
        expect(result[:trends]).to be_a(Hash)
        expect(result[:recommendations]).to be_an(Array)
      end
    end

    describe "TokenPatternAnalyzer" do
      let(:analyzer) { described_class::TokenPatternAnalyzer.new }

      it "analyzes usage patterns" do
        result = analyzer.analyze_patterns([])

        expect(result).to include(
          :hourly_patterns,
          :daily_patterns,
          :weekly_patterns
        )
        expect(result[:hourly_patterns]).to be_a(Hash)
        expect(result[:daily_patterns]).to be_a(Hash)
        expect(result[:weekly_patterns]).to be_a(Hash)
      end
    end

    describe "TokenTrendAnalyzer" do
      let(:analyzer) { described_class::TokenTrendAnalyzer.new }

      it "analyzes usage trends" do
        result = analyzer.analyze_trends([])

        expect(result).to include(
          :short_term_trend,
          :long_term_trend,
          :seasonal_patterns,
          :anomalies
        )
        expect(result[:short_term_trend]).to be_a(Symbol)
        expect(result[:long_term_trend]).to be_a(Symbol)
        expect(result[:seasonal_patterns]).to be_a(Hash)
        expect(result[:anomalies]).to be_an(Array)
      end
    end

    describe "TokenEfficiencyAnalyzer" do
      let(:analyzer) { described_class::TokenEfficiencyAnalyzer.new }

      it "analyzes usage efficiency" do
        result = analyzer.analyze_efficiency({})

        expect(result).to include(
          :overall_efficiency,
          :provider_efficiency,
          :model_efficiency,
          :optimization_opportunities
        )
        expect(result[:overall_efficiency]).to be_a(Numeric)
        expect(result[:provider_efficiency]).to be_a(Hash)
        expect(result[:model_efficiency]).to be_a(Hash)
        expect(result[:optimization_opportunities]).to be_an(Array)
      end
    end

    describe "TokenUsagePredictor" do
      let(:predictor) { described_class::TokenUsagePredictor.new([]) }

      it "predicts usage" do
        result = predictor.predict_usage

        expect(result).to include(
          :predicted_tokens,
          :confidence,
          :time_horizon,
          :factors
        )
        expect(result[:predicted_tokens]).to be_a(Numeric)
        expect(result[:confidence]).to be_a(Numeric)
        expect(result[:time_horizon]).to eq(3600)
        expect(result[:factors]).to be_an(Array)
      end

      it "updates prediction model" do
        expect { predictor.update_model("claude", "claude-3-5-sonnet", []) }.not_to raise_error
      end
    end

    describe "TokenCostCalculator" do
      let(:calculator) { described_class::TokenCostCalculator.new }

      it "analyzes costs" do
        result = calculator.analyze_costs

        expect(result).to include(
          :total_cost,
          :average_cost_per_request,
          :cost_trend,
          :cost_breakdown,
          :cost_optimization
        )
        expect(result[:total_cost]).to be_a(Numeric)
        expect(result[:average_cost_per_request]).to be_a(Numeric)
        expect(result[:cost_trend]).to be_a(Symbol)
        expect(result[:cost_breakdown]).to be_a(Hash)
        expect(result[:cost_optimization]).to be_an(Array)
      end
    end

    describe "TokenQuotaManager" do
      let(:manager) { described_class::TokenQuotaManager.new }

      it "checks quota status" do
        result = manager.check_quota_status("claude", "claude-3-5-sonnet", {}, {})

        expect(result).to include(
          :status,
          :used_percentage,
          :remaining,
          :reset_time
        )
        expect(result[:status]).to be_a(Symbol)
        expect(result[:used_percentage]).to be_a(Numeric)
        expect(result[:remaining]).to be_a(Numeric)
      end
    end

    describe "TokenUsageAlertManager" do
      let(:manager) { described_class::TokenUsageAlertManager.new }

      it "checks usage alerts" do
        result = manager.check_usage("claude", "claude-3-5-sonnet", 300, {})

        expect(result).to be_nil # No alert for now
      end
    end

    describe "TokenQuotaAlertManager" do
      let(:manager) { described_class::TokenQuotaAlertManager.new }

      it "checks quota alerts" do
        result = manager.check_quota("claude", "claude-3-5-sonnet", {}, {})

        expect(result).to be_nil # No alert for now
      end
    end

    describe "TokenCostAlertManager" do
      let(:manager) { described_class::TokenCostAlertManager.new }

      it "checks cost alerts" do
        result = manager.check_cost("claude", "claude-3-5-sonnet", {})

        expect(result).to be_nil # No alert for now
      end
    end

    describe "TokenRateLimitAlertManager" do
      let(:manager) { described_class::TokenRateLimitAlertManager.new }

      it "checks rate limit alerts" do
        result = manager.check_rate_limit("claude", "claude-3-5-sonnet", {})

        expect(result).to be_nil # No alert for now
      end
    end

    describe "TokenDisplayFormatters" do
      let(:compact_formatter) { described_class::CompactTokenFormatter.new }
      let(:detailed_formatter) { described_class::DetailedTokenFormatter.new }
      let(:summary_formatter) { described_class::SummaryTokenFormatter.new }
      let(:realtime_formatter) { described_class::RealtimeTokenFormatter.new }

      it "formats usage in compact format" do
        result = compact_formatter.format_usage("claude", "claude-3-5-sonnet", monitor)

        expect(result).to be_a(String)
        expect(result).to eq("Compact token usage display")
      end

      it "formats usage in detailed format" do
        result = detailed_formatter.format_usage("claude", "claude-3-5-sonnet", monitor)

        expect(result).to be_a(String)
        expect(result).to eq("Detailed token usage display")
      end

      it "formats usage in summary format" do
        result = summary_formatter.format_usage("claude", "claude-3-5-sonnet", monitor)

        expect(result).to be_a(String)
        expect(result).to eq("Summary token usage display")
      end

      it "formats usage in realtime format" do
        result = realtime_formatter.format_usage("claude", "claude-3-5-sonnet", monitor)

        expect(result).to be_a(String)
        expect(result).to eq("Real-time token usage display")
      end
    end

    describe "TokenExportManagers" do
      let(:json_exporter) { described_class::TokenJsonExporter.new }
      let(:yaml_exporter) { described_class::TokenYamlExporter.new }
      let(:csv_exporter) { described_class::TokenCsvExporter.new }
      let(:text_exporter) { described_class::TokenTextExporter.new }

      it "exports data in JSON format" do
        result = json_exporter.export_data(monitor)

        expect(result).to be_a(String)
        expect { JSON.parse(result) }.not_to raise_error
      end

      it "exports data in YAML format" do
        result = yaml_exporter.export_data(monitor)

        expect(result).to be_a(String)
        expect { YAML.safe_load(result) }.not_to raise_error
      end

      it "exports data in CSV format" do
        result = csv_exporter.export_data(monitor)

        expect(result).to be_a(String)
        expect(result).to eq("CSV export would be implemented here")
      end

      it "exports data in text format" do
        result = text_exporter.export_data(monitor)

        expect(result).to be_a(String)
        expect(result).to eq("Text export would be implemented here")
      end
    end

    describe "TokenUsageOptimizer" do
      let(:optimizer) { described_class::TokenUsageOptimizer.new }

      it "optimizes usage" do
        result = optimizer.optimize_usage("claude", "claude-3-5-sonnet", monitor)

        expect(result).to include(
          :optimizations,
          :potential_savings,
          :recommendations
        )
        expect(result[:optimizations]).to be_an(Array)
        expect(result[:potential_savings]).to be_a(Numeric)
        expect(result[:recommendations]).to be_an(Array)
      end
    end
  end

  describe "error handling" do
    it "handles missing status display methods gracefully" do
      allow(status_display).to receive(:update_token_usage).and_raise(NoMethodError)

      expect { monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01) }.not_to raise_error
    end

    it "handles invalid provider/model gracefully" do
      usage = monitor.record_token_usage(nil, nil, 100, 200, 0.01)

      expect(usage).to be_a(Hash)
    end

    it "handles negative token values gracefully" do
      usage = monitor.record_token_usage("claude", "claude-3-5-sonnet", -100, -200, -0.01)

      expect(usage[:total_tokens]).to eq(-300)
    end
  end

  describe "performance and scalability" do
    it "handles large number of requests efficiently" do
      start_time = Time.now

      1000.times { monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01) }

      end_time = Time.now
      duration = end_time - start_time

      # Should complete within reasonable time (adjust threshold as needed)
      expect(duration).to be < 5.0
    end

    it "handles multiple providers and models efficiently" do
      providers = ["claude", "gemini", "cursor", "openai"]
      models = ["model1", "model2", "model3", "model4", "model5"]

      providers.each do |provider|
        models.each do |model|
          monitor.record_token_usage(provider, model, 100, 200, 0.01)
        end
      end

      stats = monitor.get_token_statistics
      expect(stats[:providers_tracked]).to eq(4)
      expect(stats[:models_tracked]).to eq(20)
    end

    it "maintains performance with frequent updates" do
      start_time = Time.now

      100.times { monitor.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01) }

      end_time = Time.now
      duration = end_time - start_time

      # Should complete within reasonable time (adjust threshold as needed)
      expect(duration).to be < 2.0
    end
  end
end
