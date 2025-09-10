# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::RateLimitDisplay do
  let(:provider_manager) { instance_double("Aidp::Harness::ProviderManager") }
  let(:status_display) { instance_double("Aidp::Harness::StatusDisplay") }
  let(:rate_limit_manager) { instance_double("Aidp::Harness::RateLimitManager") }
  let(:display) { described_class.new(provider_manager, status_display, rate_limit_manager) }

  before do
    allow(status_display).to receive(:update_rate_limit_status)
  end

  describe "initialization" do
    it "creates rate limit display successfully" do
      expect(display).to be_a(described_class)
    end

    it "initializes with all required components" do
      expect(display.instance_variable_get(:@provider_manager)).to eq(provider_manager)
      expect(display.instance_variable_get(:@status_display)).to eq(status_display)
      expect(display.instance_variable_get(:@rate_limit_manager)).to eq(rate_limit_manager)
    end

    it "initializes rate limit tracking data structures" do
      expect(display.instance_variable_get(:@rate_limits)).to be_a(Hash)
      expect(display.instance_variable_get(:@countdown_timers)).to be_a(Hash)
      expect(display.instance_variable_get(:@rate_limit_history)).to be_an(Array)
      expect(display.instance_variable_get(:@display_config)).to be_a(Hash)
    end

    it "initializes helper components" do
      expect(display.instance_variable_get(:@display_formatters)).to be_a(Hash)
      expect(display.instance_variable_get(:@countdown_managers)).to be_a(Hash)
      expect(display.instance_variable_get(:@status_managers)).to be_a(Hash)
      expect(display.instance_variable_get(:@alert_managers)).to be_a(Hash)
      expect(display.instance_variable_get(:@export_managers)).to be_a(Hash)
      expect(display.instance_variable_get(:@optimization_engines)).to be_a(Hash)
    end

    it "sets configuration defaults" do
      config = display.instance_variable_get(:@display_config)
      expect(config[:update_interval]).to eq(1)
      expect(config[:show_countdown]).to be true
      expect(config[:show_provider_info]).to be true
      expect(config[:show_model_info]).to be true
      expect(config[:show_quota_info]).to be true
      expect(config[:show_retry_info]).to be true
      expect(config[:show_switch_info]).to be true
      expect(config[:compact_mode]).to be false
      expect(config[:color_enabled]).to be true
      expect(config[:sound_enabled]).to be false
    end

    it "sets other defaults" do
      expect(display.instance_variable_get(:@max_history_size)).to eq(1000)
      expect(display.instance_variable_get(:@last_update)).to be_a(Time)
      expect(display.instance_variable_get(:@display_thread)).to be_nil
      expect(display.instance_variable_get(:@display_running)).to be false
    end
  end

  describe "display management" do
    it "starts display successfully" do
      display_info = display.start_display

      expect(display_info).to include(
        :status,
        :update_interval,
        :features
      )
      expect(display_info[:status]).to eq(:started)
      expect(display_info[:update_interval]).to eq(1)
      expect(display_info[:features]).to be_a(Hash)
      expect(display.instance_variable_get(:@display_running)).to be true
    end

    it "stops display successfully" do
      display.start_display

      stop_info = display.stop_display

      expect(stop_info).to include(
        :status,
        :display_duration
      )
      expect(stop_info[:status]).to eq(:stopped)
      expect(stop_info[:display_duration]).to be_a(Numeric)
      expect(display.instance_variable_get(:@display_running)).to be false
    end

    it "prevents starting display when already running" do
      display.start_display

      display_info = display.start_display

      expect(display_info[:status]).to eq(:started) # Should return existing status
    end

    it "prevents stopping display when not running" do
      stop_info = display.stop_display

      expect(stop_info[:status]).to eq(:stopped)
    end
  end

  describe "rate limit tracking" do
    it "updates rate limit information" do
      rate_limit_info = {
        rate_limited: true,
        limit_type: :requests_per_minute,
        current_count: 50,
        limit: 60,
        reset_time: Time.now + 300,
        quota_used: 1000,
        quota_limit: 10000
      }

      result = display.update_rate_limit("claude", "claude-3-5-sonnet", rate_limit_info)

      expect(result).to include(
        :provider,
        :model,
        :rate_limited,
        :limit_type,
        :current_count,
        :limit,
        :reset_time,
        :quota_used,
        :quota_limit,
        :status,
        :countdown,
        :usage_percentage,
        :time_until_reset,
        :estimated_reset_time
      )
      expect(result[:provider]).to eq("claude")
      expect(result[:model]).to eq("claude-3-5-sonnet")
      expect(result[:rate_limited]).to be true
      expect(result[:limit_type]).to eq(:requests_per_minute)
      expect(result[:current_count]).to eq(50)
      expect(result[:limit]).to eq(60)
      expect(result[:quota_used]).to eq(1000)
      expect(result[:quota_limit]).to eq(10000)
      expect(result[:status]).to eq(:rate_limited)
      expect(result[:usage_percentage]).to eq(83.33)
    end

    it "handles rate limit information without rate limiting" do
      rate_limit_info = {
        rate_limited: false,
        limit_type: :requests_per_minute,
        current_count: 10,
        limit: 60,
        quota_used: 1000,
        quota_limit: 10000
      }

      result = display.update_rate_limit("claude", "claude-3-5-sonnet", rate_limit_info)

      expect(result[:rate_limited]).to be false
      expect(result[:status]).to eq(:available)
      expect(result[:usage_percentage]).to eq(16.67)
    end

    it "handles rate limit information with retry_after" do
      rate_limit_info = {
        rate_limited: true,
        limit_type: :requests_per_minute,
        current_count: 60,
        limit: 60,
        retry_after: 300,
        quota_used: 1000,
        quota_limit: 10000
      }

      result = display.update_rate_limit("claude", "claude-3-5-sonnet", rate_limit_info)

      expect(result[:rate_limited]).to be true
      expect(result[:retry_after]).to eq(300)
      expect(result[:status]).to eq(:rate_limited)
    end

    it "determines status based on quota usage" do
      # Test critical status (>= 90%)
      rate_limit_info = {
        rate_limited: false,
        quota_used: 9500,
        quota_limit: 10000
      }

      result = display.update_rate_limit("claude", "claude-3-5-sonnet", rate_limit_info)
      expect(result[:status]).to eq(:critical)

      # Test warning status (>= 75%)
      rate_limit_info = {
        rate_limited: false,
        quota_used: 8000,
        quota_limit: 10000
      }

      result = display.update_rate_limit("claude", "claude-3-5-sonnet", rate_limit_info)
      expect(result[:status]).to eq(:warning)

      # Test available status (< 75%)
      rate_limit_info = {
        rate_limited: false,
        quota_used: 5000,
        quota_limit: 10000
      }

      result = display.update_rate_limit("claude", "claude-3-5-sonnet", rate_limit_info)
      expect(result[:status]).to eq(:available)
    end
  end

  describe "rate limit information retrieval" do
    before do
      display.update_rate_limit("claude", "claude-3-5-sonnet", {
        rate_limited: true,
        limit_type: :requests_per_minute,
        current_count: 50,
        limit: 60,
        reset_time: Time.now + 300,
        quota_used: 1000,
        quota_limit: 10000
      })
    end

    it "gets rate limit information for specific provider and model" do
      result = display.get_rate_limit_info("claude", "claude-3-5-sonnet")

      expect(result).to include(
        :provider,
        :model,
        :rate_limited,
        :limit_type,
        :current_count,
        :limit,
        :status,
        :countdown,
        :usage_percentage,
        :time_until_reset,
        :estimated_reset_time
      )
      expect(result[:provider]).to eq("claude")
      expect(result[:model]).to eq("claude-3-5-sonnet")
    end

    it "returns nil for non-existent provider and model" do
      result = display.get_rate_limit_info("nonexistent", "nonexistent")

      expect(result).to be_nil
    end

    it "gets all rate limit information" do
      result = display.get_all_rate_limits

      expect(result).to be_a(Hash)
      expect(result.keys).to include("claude:claude-3-5-sonnet")
      expect(result["claude:claude-3-5-sonnet"]).to include(
        :provider,
        :model,
        :rate_limited,
        :status
      )
    end
  end

  describe "rate limit summary" do
    before do
      display.update_rate_limit("claude", "claude-3-5-sonnet", {
        rate_limited: true,
        quota_used: 1000,
        quota_limit: 10000
      })
      display.update_rate_limit("gemini", "gemini-pro", {
        rate_limited: false,
        quota_used: 8000,
        quota_limit: 10000
      })
    end

    it "gets rate limit status summary" do
      summary = display.get_rate_limit_summary

      expect(summary).to include(
        :total_providers,
        :total_models,
        :rate_limited_count,
        :active_countdowns,
        :overall_status,
        :critical_limits,
        :upcoming_resets,
        :quota_status,
        :last_update
      )
      expect(summary[:total_providers]).to eq(2)
      expect(summary[:total_models]).to eq(2)
      expect(summary[:rate_limited_count]).to eq(1)
      expect(summary[:active_countdowns]).to eq(1)
      expect(summary[:overall_status]).to be_a(Symbol)
      expect(summary[:critical_limits]).to be_a(Hash)
      expect(summary[:upcoming_resets]).to be_a(Hash)
      expect(summary[:quota_status]).to be_a(Hash)
    end
  end

  describe "countdown management" do
    before do
      display.update_rate_limit("claude", "claude-3-5-sonnet", {
        rate_limited: true,
        reset_time: Time.now + 300
      })
    end

    it "gets countdown information" do
      countdown = display.get_countdown_info("claude:claude-3-5-sonnet")

      expect(countdown).to include(
        :start_time,
        :end_time,
        :duration,
        :remaining_time,
        :progress,
        :status,
        :alerts_sent
      )
      expect(countdown[:start_time]).to be_a(Time)
      expect(countdown[:end_time]).to be_a(Time)
      expect(countdown[:duration]).to be_a(Numeric)
      expect(countdown[:remaining_time]).to be_a(Numeric)
      expect(countdown[:progress]).to be_a(Numeric)
      expect(countdown[:status]).to eq(:active)
      expect(countdown[:alerts_sent]).to be_an(Array)
    end

    it "returns nil for non-existent countdown" do
      countdown = display.get_countdown_info("nonexistent:nonexistent")

      expect(countdown).to be_nil
    end
  end

  describe "rate limit history" do
    before do
      display.update_rate_limit("claude", "claude-3-5-sonnet", {
        rate_limited: true,
        current_count: 50,
        limit: 60
      })
      display.update_rate_limit("claude", "claude-3-5-sonnet", {
        rate_limited: false,
        current_count: 10,
        limit: 60
      })
    end

    it "gets rate limit history for all providers and models" do
      history = display.get_rate_limit_history

      expect(history).to be_an(Array)
      expect(history.size).to eq(2)

      history.each do |entry|
        expect(entry).to include(
          :timestamp,
          :provider,
          :model,
          :rate_limited,
          :limit_type,
          :current_count,
          :limit,
          :quota_used,
          :quota_limit
        )
        expect(entry[:timestamp]).to be_a(Time)
        expect(entry[:provider]).to eq("claude")
        expect(entry[:model]).to eq("claude-3-5-sonnet")
      end
    end

    it "gets rate limit history filtered by provider" do
      history = display.get_rate_limit_history("claude")

      expect(history.size).to eq(2)
      expect(history.all? { |entry| entry[:provider] == "claude" }).to be true
    end

    it "gets rate limit history filtered by model" do
      history = display.get_rate_limit_history("claude", "claude-3-5-sonnet")

      expect(history.size).to eq(2)
      expect(history.all? { |entry| entry[:provider] == "claude" && entry[:model] == "claude-3-5-sonnet" }).to be true
    end

    it "gets rate limit history with limit" do
      history = display.get_rate_limit_history(nil, nil, 1)

      expect(history.size).to eq(1)
    end

    it "maintains history size limit" do
      # Force multiple entries to test history limit
      1002.times do |i|
        display.update_rate_limit("claude", "claude-3-5-sonnet", {
          rate_limited: i.even?,
          current_count: i,
          limit: 100
        })
      end

      history = display.get_rate_limit_history
      expect(history.size).to be <= 1000
    end

    it "clears rate limit history" do
      expect(display.get_rate_limit_history.size).to be >= 1

      display.clear_rate_limit_history
      expect(display.get_rate_limit_history.size).to eq(0)
    end
  end

  describe "display formatting" do
    before do
      display.update_rate_limit("claude", "claude-3-5-sonnet", {
        rate_limited: true,
        limit_type: :requests_per_minute,
        current_count: 50,
        limit: 60,
        reset_time: Time.now + 300,
        quota_used: 1000,
        quota_limit: 10000
      })
    end

    it "displays rate limits in compact format" do
      result = display.display_rate_limits(:compact, "claude", "claude-3-5-sonnet")

      expect(result).to be_a(String)
      expect(result).to include("Rate limited")
    end

    it "displays rate limits in detailed format" do
      result = display.display_rate_limits(:detailed, "claude", "claude-3-5-sonnet")

      expect(result).to be_a(String)
      expect(result).to include("Provider:")
      expect(result).to include("Model:")
      expect(result).to include("Status:")
    end

    it "displays rate limits in realtime format" do
      result = display.display_rate_limits(:realtime, "claude", "claude-3-5-sonnet")

      expect(result).to be_a(String)
      expect(result).to include("🔴")
    end

    it "displays rate limits in summary format" do
      result = display.display_rate_limits(:summary, "claude", "claude-3-5-sonnet")

      expect(result).to be_a(String)
      expect(result).to include("claude:claude-3-5-sonnet")
    end

    it "displays rate limits in JSON format" do
      result = display.display_rate_limits(:json, "claude", "claude-3-5-sonnet")

      expect(result).to be_a(String)
      expect { JSON.parse(result) }.not_to raise_error
    end

    it "displays all rate limits" do
      result = display.display_rate_limits(:compact)

      expect(result).to be_a(String)
      expect(result).to include("Rate Limit Status:")
    end
  end

  describe "data export" do
    before do
      display.update_rate_limit("claude", "claude-3-5-sonnet", {
        rate_limited: true,
        current_count: 50,
        limit: 60
      })
    end

    it "exports rate limit data in JSON format" do
      export = display.export_rate_limit_data(:json)

      expect(export).to be_a(String)
      expect { JSON.parse(export) }.not_to raise_error
    end

    it "exports rate limit data in YAML format" do
      export = display.export_rate_limit_data(:yaml)

      expect(export).to be_a(String)
      expect { YAML.safe_load(export) }.not_to raise_error
    end

    it "exports rate limit data in CSV format" do
      export = display.export_rate_limit_data(:csv)

      expect(export).to be_a(String)
    end

    it "exports rate limit data in text format" do
      export = display.export_rate_limit_data(:text)

      expect(export).to be_a(String)
    end

    it "exports rate limit data with options" do
      export = display.export_rate_limit_data(:json, { pretty: true })

      expect(export).to be_a(String)
    end
  end

  describe "display configuration" do
    it "configures display settings" do
      settings = {
        update_interval: 2,
        show_countdown: false,
        compact_mode: true,
        color_enabled: false
      }

      result = display.configure_display(settings)

      expect(result).to include(
        :status,
        :settings
      )
      expect(result[:status]).to eq(:configured)
      expect(result[:settings]).to include(settings)
    end

    it "gets display configuration" do
      config = display.get_display_config

      expect(config).to be_a(Hash)
      expect(config).to include(
        :update_interval,
        :show_countdown,
        :show_provider_info,
        :show_model_info,
        :show_quota_info,
        :show_retry_info,
        :show_switch_info,
        :compact_mode,
        :color_enabled,
        :sound_enabled
      )
    end

    it "gets enabled features" do
      features = display.get_enabled_features

      expect(features).to include(
        :countdown,
        :provider_info,
        :model_info,
        :quota_info,
        :retry_info,
        :switch_info,
        :compact_mode,
        :color_enabled,
        :sound_enabled
      )
      expect(features[:countdown]).to be true
      expect(features[:provider_info]).to be true
      expect(features[:model_info]).to be true
      expect(features[:quota_info]).to be true
      expect(features[:retry_info]).to be true
      expect(features[:switch_info]).to be true
      expect(features[:compact_mode]).to be false
      expect(features[:color_enabled]).to be true
      expect(features[:sound_enabled]).to be false
    end
  end

  describe "rate limit statistics" do
    before do
      display.update_rate_limit("claude", "claude-3-5-sonnet", {
        rate_limited: true,
        current_count: 50,
        limit: 60
      })
      display.update_rate_limit("gemini", "gemini-pro", {
        rate_limited: false,
        current_count: 10,
        limit: 60
      })
    end

    it "gets rate limit statistics" do
      stats = display.get_rate_limit_statistics

      expect(stats).to include(
        :total_entries,
        :providers_tracked,
        :models_tracked,
        :active_countdowns,
        :rate_limited_count,
        :last_update,
        :history_size_limit,
        :display_running
      )
      expect(stats[:total_entries]).to be >= 2
      expect(stats[:providers_tracked]).to eq(2)
      expect(stats[:models_tracked]).to eq(2)
      expect(stats[:active_countdowns]).to eq(1)
      expect(stats[:rate_limited_count]).to eq(1)
      expect(stats[:last_update]).to be_a(Time)
      expect(stats[:history_size_limit]).to eq(1000)
      expect(stats[:display_running]).to be false
    end
  end

  describe "helper classes" do
    describe "CompactRateLimitFormatter" do
      let(:formatter) { described_class::CompactRateLimitFormatter.new }

      it "formats single rate limit in compact format" do
        rate_limit_info = {
          rate_limited: true,
          time_until_reset: 300
        }

        result = formatter.format_single_rate_limit(rate_limit_info, {})

        expect(result).to be_a(String)
        expect(result).to include("Rate limited")
        expect(result).to include("300s remaining")
      end

      it "formats single rate limit when not rate limited" do
        rate_limit_info = {
          rate_limited: false,
          usage_percentage: 50.0
        }

        result = formatter.format_single_rate_limit(rate_limit_info, {})

        expect(result).to be_a(String)
        expect(result).to include("Available")
        expect(result).to include("50% used")
      end

      it "formats all rate limits in compact format" do
        all_limits = {
          "claude:claude-3-5-sonnet" => {
            rate_limited: true,
            time_until_reset: 300
          }
        }

        result = formatter.format_all_rate_limits(all_limits, {})

        expect(result).to be_a(String)
        expect(result).to include("Rate Limit Status:")
        expect(result).to include("claude:claude-3-5-sonnet")
      end

      it "handles no rate limit information" do
        result = formatter.format_single_rate_limit(nil, {})

        expect(result).to eq("No rate limit information available")
      end
    end

    describe "DetailedRateLimitFormatter" do
      let(:formatter) { described_class::DetailedRateLimitFormatter.new }

      it "formats single rate limit in detailed format" do
        rate_limit_info = {
          provider: "claude",
          model: "claude-3-5-sonnet",
          status: :rate_limited,
          rate_limited: true,
          limit_type: :requests_per_minute,
          current_count: 50,
          limit: 60,
          usage_percentage: 83.33,
          reset_time: Time.now + 300,
          time_until_reset: 300,
          quota_used: 1000,
          quota_limit: 10000
        }

        result = formatter.format_single_rate_limit(rate_limit_info, {})

        expect(result).to be_a(String)
        expect(result).to include("Provider: claude")
        expect(result).to include("Model: claude-3-5-sonnet")
        expect(result).to include("Status: rate_limited")
        expect(result).to include("Rate Limited: true")
        expect(result).to include("Limit Type: requests_per_minute")
        expect(result).to include("Current Count: 50")
        expect(result).to include("Limit: 60")
        expect(result).to include("Usage: 83.33%")
        expect(result).to include("Reset Time:")
        expect(result).to include("Time Until Reset: 300s")
        expect(result).to include("Quota Used: 1000")
        expect(result).to include("Quota Limit: 10000")
      end

      it "formats all rate limits in detailed format" do
        all_limits = {
          "claude:claude-3-5-sonnet" => {
            provider: "claude",
            model: "claude-3-5-sonnet",
            status: :rate_limited
          }
        }

        result = formatter.format_all_rate_limits(all_limits, {})

        expect(result).to be_a(String)
        expect(result).to include("Detailed Rate Limit Status:")
        expect(result).to include("Provider: claude")
        expect(result).to include("Model: claude-3-5-sonnet")
        expect(result).to include("---")
      end
    end

    describe "RealtimeRateLimitFormatter" do
      let(:formatter) { described_class::RealtimeRateLimitFormatter.new }

      it "formats single rate limit in realtime format" do
        rate_limit_info = {
          rate_limited: true,
          time_until_reset: 300
        }

        result = formatter.format_single_rate_limit(rate_limit_info, {})

        expect(result).to be_a(String)
        expect(result).to include("🔴")
        expect(result).to include("Rate Limited")
        expect(result).to include("300s")
      end

      it "formats single rate limit when not rate limited" do
        rate_limit_info = {
          rate_limited: false,
          usage_percentage: 50.0
        }

        result = formatter.format_single_rate_limit(rate_limit_info, {})

        expect(result).to be_a(String)
        expect(result).to include("🟢")
        expect(result).to include("Available")
        expect(result).to include("50% used")
      end

      it "formats all rate limits in realtime format" do
        all_limits = {
          "claude:claude-3-5-sonnet" => {
            rate_limited: true,
            time_until_reset: 300
          }
        }

        result = formatter.format_all_rate_limits(all_limits, {})

        expect(result).to be_a(String)
        expect(result).to include("🔄 Real-time Rate Limit Status:")
        expect(result).to include("🔴")
      end
    end

    describe "SummaryRateLimitFormatter" do
      let(:formatter) { described_class::SummaryRateLimitFormatter.new }

      it "formats single rate limit in summary format" do
        rate_limit_info = {
          provider: "claude",
          model: "claude-3-5-sonnet",
          rate_limited: true,
          time_until_reset: 300
        }

        result = formatter.format_single_rate_limit(rate_limit_info, {})

        expect(result).to be_a(String)
        expect(result).to include("claude:claude-3-5-sonnet")
        expect(result).to include("Rate Limited")
        expect(result).to include("300s")
      end

      it "formats all rate limits in summary format" do
        all_limits = {
          "claude:claude-3-5-sonnet" => {
            provider: "claude",
            model: "claude-3-5-sonnet",
            rate_limited: true,
            time_until_reset: 300
          }
        }

        result = formatter.format_all_rate_limits(all_limits, {})

        expect(result).to be_a(String)
        expect(result).to include("Rate Limit Summary:")
        expect(result).to include("claude:claude-3-5-sonnet")
      end
    end

    describe "JsonRateLimitFormatter" do
      let(:formatter) { described_class::JsonRateLimitFormatter.new }

      it "formats single rate limit in JSON format" do
        rate_limit_info = {
          provider: "claude",
          model: "claude-3-5-sonnet",
          rate_limited: true
        }

        result = formatter.format_single_rate_limit(rate_limit_info, {})

        expect(result).to be_a(String)
        expect { JSON.parse(result) }.not_to raise_error
        parsed = JSON.parse(result)
        expect(parsed["provider"]).to eq("claude")
        expect(parsed["model"]).to eq("claude-3-5-sonnet")
        expect(parsed["rate_limited"]).to be true
      end

      it "formats all rate limits in JSON format" do
        all_limits = {
          "claude:claude-3-5-sonnet" => {
            provider: "claude",
            model: "claude-3-5-sonnet",
            rate_limited: true
          }
        }

        result = formatter.format_all_rate_limits(all_limits, {})

        expect(result).to be_a(String)
        expect { JSON.parse(result) }.not_to raise_error
      end
    end

    describe "CountdownManager" do
      let(:manager) { described_class::CountdownManager.new }

      it "manages countdown" do
        timer_info = {
          start_time: Time.now,
          end_time: Time.now + 300
        }

        result = manager.manage_countdown(timer_info)

        expect(result).to include(
          :status,
          :progress,
          :remaining_time
        )
        expect(result[:status]).to eq(:active)
        expect(result[:progress]).to eq(0.0)
        expect(result[:remaining_time]).to eq(0)
      end
    end

    describe "StatusManager" do
      let(:manager) { described_class::StatusManager.new }

      it "manages status" do
        rate_limit_info = {
          rate_limited: true,
          status: :rate_limited
        }

        result = manager.manage_status(rate_limit_info)

        expect(result).to include(
          :status,
          :priority,
          :actions
        )
        expect(result[:status]).to eq(:available)
        expect(result[:priority]).to eq(:normal)
        expect(result[:actions]).to be_an(Array)
      end
    end

    describe "AlertManagers" do
      let(:countdown_alert) { described_class::CountdownAlertManager.new }
      let(:quota_alert) { described_class::QuotaAlertManager.new }
      let(:reset_alert) { described_class::ResetAlertManager.new }
      let(:critical_alert) { described_class::CriticalAlertManager.new }

      it "checks countdown alerts" do
        result = countdown_alert.check_alerts({}, {})

        expect(result).to be_an(Array)
      end

      it "checks quota alerts" do
        result = quota_alert.check_alerts({}, {})

        expect(result).to be_an(Array)
      end

      it "checks reset alerts" do
        result = reset_alert.check_alerts({}, {})

        expect(result).to be_an(Array)
      end

      it "checks critical alerts" do
        result = critical_alert.check_alerts({}, {})

        expect(result).to be_an(Array)
      end
    end

    describe "ExportManagers" do
      let(:json_exporter) { described_class::RateLimitJsonExporter.new }
      let(:yaml_exporter) { described_class::RateLimitYamlExporter.new }
      let(:csv_exporter) { described_class::RateLimitCsvExporter.new }
      let(:text_exporter) { described_class::RateLimitTextExporter.new }

      it "exports data in JSON format" do
        result = json_exporter.export_data(display)

        expect(result).to be_a(String)
        expect { JSON.parse(result) }.not_to raise_error
      end

      it "exports data in YAML format" do
        result = yaml_exporter.export_data(display)

        expect(result).to be_a(String)
        expect { YAML.safe_load(result) }.not_to raise_error
      end

      it "exports data in CSV format" do
        result = csv_exporter.export_data(display)

        expect(result).to be_a(String)
        expect(result).to eq("CSV export would be implemented here")
      end

      it "exports data in text format" do
        result = text_exporter.export_data(display)

        expect(result).to be_a(String)
        expect(result).to eq("Text export would be implemented here")
      end
    end

    describe "Optimizers" do
      let(:optimizer) { described_class::RateLimitOptimizer.new }
      let(:display_optimizer) { described_class::DisplayOptimizer.new }
      let(:performance_optimizer) { described_class::PerformanceOptimizer.new }

      it "optimizes rate limit display" do
        result = optimizer.optimize_display(display)

        expect(result).to include(
          :optimizations,
          :recommendations
        )
        expect(result[:optimizations]).to be_an(Array)
        expect(result[:recommendations]).to be_an(Array)
      end

      it "optimizes display" do
        result = display_optimizer.optimize_display(display)

        expect(result).to include(
          :optimizations,
          :recommendations,
          :display_optimizations
        )
        expect(result[:display_optimizations]).to be_an(Array)
      end

      it "optimizes performance" do
        result = performance_optimizer.optimize_display(display)

        expect(result).to include(
          :optimizations,
          :recommendations,
          :performance_optimizations
        )
        expect(result[:performance_optimizations]).to be_an(Array)
      end
    end
  end

  describe "error handling" do
    it "handles missing status display methods gracefully" do
      allow(status_display).to receive(:update_rate_limit_status).and_raise(NoMethodError)

      expect { display.update_rate_limit("claude", "claude-3-5-sonnet", {}) }.not_to raise_error
    end

    it "handles invalid rate limit information gracefully" do
      result = display.update_rate_limit("claude", "claude-3-5-sonnet", nil)

      expect(result).to be_a(Hash)
    end

    it "handles negative values gracefully" do
      rate_limit_info = {
        current_count: -10,
        limit: -60,
        quota_used: -1000,
        quota_limit: -10000
      }

      result = display.update_rate_limit("claude", "claude-3-5-sonnet", rate_limit_info)

      expect(result[:current_count]).to eq(-10)
      expect(result[:limit]).to eq(-60)
      expect(result[:quota_used]).to eq(-1000)
      expect(result[:quota_limit]).to eq(-10000)
    end
  end

  describe "performance and scalability" do
    it "handles large number of rate limit updates efficiently" do
      start_time = Time.now

      1000.times do |i|
        display.update_rate_limit("claude", "claude-3-5-sonnet", {
          rate_limited: i.even?,
          current_count: i,
          limit: 100
        })
      end

      end_time = Time.now
      duration = end_time - start_time

      # Should complete within reasonable time (adjust threshold as needed)
      expect(duration).to be < 5.0
    end

    it "handles multiple providers and models efficiently" do
      providers = ["claude", "gemini", "cursor", "openai"]
      models = ["model1", "model2", "model3", "model4", "model5"]

      start_time = Time.now

      providers.each do |provider|
        models.each do |model|
          display.update_rate_limit(provider, model, {
            rate_limited: false,
            current_count: 10,
            limit: 100
          })
        end
      end

      end_time = Time.now
      duration = end_time - start_time

      # Should complete within reasonable time (adjust threshold as needed)
      expect(duration).to be < 2.0

      stats = display.get_rate_limit_statistics
      expect(stats[:providers_tracked]).to eq(4)
      expect(stats[:models_tracked]).to eq(20)
    end

    it "maintains performance with frequent updates" do
      display.start_display

      start_time = Time.now

      100.times do |i|
        display.update_rate_limit("claude", "claude-3-5-sonnet", {
          rate_limited: i.even?,
          current_count: i,
          limit: 100
        })
        sleep(0.001) # Small delay to simulate real usage
      end

      end_time = Time.now
      duration = end_time - start_time

      # Should complete within reasonable time (adjust threshold as needed)
      expect(duration).to be < 3.0

      display.stop_display
    end
  end
end
