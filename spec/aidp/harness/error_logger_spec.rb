# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ErrorLogger do
  let(:configuration) { instance_double("Aidp::Harness::Configuration") }
  let(:metrics_manager) { instance_double("Aidp::Harness::MetricsManager") }
  let(:error_logger) { described_class.new(configuration, metrics_manager) }

  before do
    # Mock configuration methods
    allow(configuration).to receive(:logging_config).and_return({
      log_level: :info,
      retention_days: 30
    })

    # Mock metrics manager methods
    allow(metrics_manager).to receive(:record_error_event)
    allow(metrics_manager).to receive(:record_recovery_event)
    allow(metrics_manager).to receive(:record_switch_event)
    allow(metrics_manager).to receive(:record_retry_event)
    allow(metrics_manager).to receive(:record_circuit_breaker_event)
  end

  describe "initialization" do
    it "creates error logger successfully" do
      expect(error_logger).to be_a(described_class)
    end

    it "initializes logging components" do
      expect(error_logger.instance_variable_get(:@log_storage)).to be_a(described_class::LogStorage)
      expect(error_logger.instance_variable_get(:@recovery_tracker)).to be_a(described_class::RecoveryTracker)
      expect(error_logger.instance_variable_get(:@error_analyzer)).to be_a(described_class::ErrorAnalyzer)
      expect(error_logger.instance_variable_get(:@alert_manager)).to be_a(described_class::AlertManager)
      expect(error_logger.instance_variable_get(:@log_formatter)).to be_a(described_class::LogFormatter)
      expect(error_logger.instance_variable_get(:@log_rotator)).to be_a(described_class::LogRotator)
      expect(error_logger.instance_variable_get(:@log_compressor)).to be_a(described_class::LogCompressor)
      expect(error_logger.instance_variable_get(:@log_archiver)).to be_a(described_class::LogArchiver)
    end

    it "initializes logging configuration" do
      config = error_logger.instance_variable_get(:@logging_config)

      expect(config).to include(
        :log_level,
        :log_format,
        :retention_days,
        :max_log_size,
        :compression_enabled,
        :archiving_enabled,
        :alert_thresholds
      )
    end
  end

  describe "error logging" do
    let(:context) { {provider: "claude", model: "model1", session_id: "session123"} }

    it "logs network timeout errors" do
      error = Timeout::Error.new("Connection timeout")

      entry = error_logger.log_error(error, context)

      expect(entry).to include(:id, :type, :timestamp, :error, :context, :severity, :category)
      expect(entry[:type]).to eq(:error)
      expect(entry[:severity]).to eq(:warning)
      expect(entry[:category]).to eq(:timeout)
      expect(entry[:error][:class]).to eq("Timeout::Error")
      expect(entry[:error][:message]).to eq("Connection timeout")
    end

    it "logs rate limit errors" do
      error = Net::HTTPError.new("429 Too Many Requests", nil)
      response = double("response")
      allow(response).to receive(:code).and_return("429")
      allow(error).to receive(:response).and_return(response)

      entry = error_logger.log_error(error, context)

      expect(entry[:severity]).to eq(:warning)
      expect(entry[:category]).to eq(:rate_limit)
    end

    it "logs server errors" do
      error = Net::HTTPError.new("500 Internal Server Error", nil)
      response = double("response")
      allow(response).to receive(:code).and_return("500")
      allow(error).to receive(:response).and_return(response)

      entry = error_logger.log_error(error, context)

      expect(entry[:severity]).to eq(:error)
      expect(entry[:category]).to eq(:server_error)
    end

    it "logs authentication errors" do
      error = Net::HTTPError.new("401 Unauthorized", nil)
      response = double("response")
      allow(response).to receive(:code).and_return("401")
      allow(error).to receive(:response).and_return(response)

      entry = error_logger.log_error(error, context)

      expect(entry[:severity]).to eq(:info)
      expect(entry[:category]).to eq(:authentication)
    end

    it "logs network connection errors" do
      error = SocketError.new("Connection refused")

      entry = error_logger.log_error(error, context)

      expect(entry[:severity]).to eq(:error)
      expect(entry[:category]).to eq(:network_error)
    end

    it "logs application errors" do
      error = StandardError.new("Application error")

      entry = error_logger.log_error(error, context)

      expect(entry[:severity]).to eq(:error)
      expect(entry[:category]).to eq(:application_error)
    end

    it "sanitizes sensitive context data" do
      sensitive_context = context.merge({
        api_key: "secret_key",
        password: "secret_password",
        token: "secret_token"
      })

      error = StandardError.new("Test error")
      entry = error_logger.log_error(error, sensitive_context)

      expect(entry[:context]).not_to include(:api_key, :password, :token)
      expect(entry[:context][:provider]).to eq("claude")
    end

    it "records error in metrics manager" do
      error = StandardError.new("Test error")

      expect(metrics_manager).to receive(:record_error_event).with(anything)

      error_logger.log_error(error, context)
    end

    it "generates unique log IDs" do
      error = StandardError.new("Test error")

      entry1 = error_logger.log_error(error, context)
      entry2 = error_logger.log_error(error, context)

      expect(entry1[:id]).not_to eq(entry2[:id])
    end
  end

  describe "recovery action logging" do
    let(:action_details) { {success: true, duration: 2.5, new_provider: "gemini"} }
    let(:context) { {provider: "claude", model: "model1", session_id: "session123"} }

    it "logs recovery actions" do
      entry = error_logger.log_recovery_action(:provider_switch, action_details, context)

      expect(entry).to include(:id, :type, :timestamp, :action_type, :action_details, :context, :success)
      expect(entry[:type]).to eq(:recovery)
      expect(entry[:action_type]).to eq(:provider_switch)
      expect(entry[:success]).to be true
      expect(entry[:duration]).to eq(2.5)
    end

    it "logs failed recovery actions" do
      failed_details = action_details.merge(success: false, error: "No available providers")

      entry = error_logger.log_recovery_action(:provider_switch, failed_details, context)

      expect(entry[:success]).to be false
    end

    it "records recovery in metrics manager" do
      expect(metrics_manager).to receive(:record_recovery_event).with(anything)

      error_logger.log_recovery_action(:provider_switch, action_details, context)
    end
  end

  describe "switch logging" do
    let(:context) { {session_id: "session123", duration: 0.5} }

    it "logs provider switches" do
      entry = error_logger.log_provider_switch("claude", "gemini", "rate_limit", context)

      expect(entry).to include(:id, :type, :timestamp, :switch_type, :from, :to, :reason, :success)
      expect(entry[:type]).to eq(:switch)
      expect(entry[:switch_type]).to eq(:provider_switch)
      expect(entry[:from]).to eq("claude")
      expect(entry[:to]).to eq("gemini")
      expect(entry[:reason]).to eq("rate_limit")
    end

    it "logs model switches" do
      entry = error_logger.log_model_switch("claude", "model1", "model2", "timeout", context)

      expect(entry[:switch_type]).to eq(:model_switch)
      expect(entry[:from]).to eq("model1")
      expect(entry[:to]).to eq("model2")
      expect(entry[:reason]).to eq("timeout")
    end

    it "records switch in metrics manager" do
      expect(metrics_manager).to receive(:record_switch_event).with(anything)

      error_logger.log_provider_switch("claude", "gemini", "rate_limit", context)
    end
  end

  describe "retry logging" do
    let(:context) { {provider: "claude", model: "model1", session_id: "session123"} }

    it "logs retry attempts" do
      entry = error_logger.log_retry_attempt(:network_error, 2, 1.5, context)

      expect(entry).to include(:id, :type, :timestamp, :error_type, :attempt_number, :delay, :success)
      expect(entry[:type]).to eq(:retry)
      expect(entry[:error_type]).to eq(:network_error)
      expect(entry[:attempt_number]).to eq(2)
      expect(entry[:delay]).to eq(1.5)
    end

    it "logs successful retries" do
      success_context = context.merge(success: true)

      entry = error_logger.log_retry_attempt(:timeout, 1, 0.5, success_context)

      expect(entry[:success]).to be true
    end

    it "records retry in metrics manager" do
      expect(metrics_manager).to receive(:record_retry_event).with(anything)

      error_logger.log_retry_attempt(:network_error, 1, 1.0, context)
    end
  end

  describe "circuit breaker logging" do
    let(:context) { {session_id: "session123", failure_count: 5} }

    it "logs circuit breaker events" do
      entry = error_logger.log_circuit_breaker_event("claude", "model1", :opened, "high_failure_rate", context)

      expect(entry).to include(:id, :type, :timestamp, :provider, :model, :event_type, :reason)
      expect(entry[:type]).to eq(:circuit_breaker)
      expect(entry[:provider]).to eq("claude")
      expect(entry[:model]).to eq("model1")
      expect(entry[:event_type]).to eq(:opened)
      expect(entry[:reason]).to eq("high_failure_rate")
    end

    it "logs circuit breaker closure" do
      entry = error_logger.log_circuit_breaker_event("claude", "model1", :closed, "recovery_successful", context)

      expect(entry[:event_type]).to eq(:closed)
      expect(entry[:reason]).to eq("recovery_successful")
    end

    it "records circuit breaker event in metrics manager" do
      expect(metrics_manager).to receive(:record_circuit_breaker_event).with(anything)

      error_logger.log_circuit_breaker_event("claude", "model1", :opened, "high_failure_rate", context)
    end
  end

  describe "log retrieval with filtering" do
    before do
      # Add some test logs
      error_logger.log_error(StandardError.new("Error 1"), {provider: "claude", model: "model1"})
      error_logger.log_error(StandardError.new("Error 2"), {provider: "gemini", model: "model1"})
      error_logger.log_recovery_action(:provider_switch, {success: true}, {provider: "claude"})
    end

    it "gets error logs without filters" do
      errors = error_logger.get_error_logs

      expect(errors.size).to eq(2)
      expect(errors.map { |e| e[:error][:message] }).to include("Error 1", "Error 2")
    end

    it "gets error logs with provider filter" do
      errors = error_logger.get_error_logs({provider: "claude"})

      expect(errors.size).to eq(1)
      expect(errors.first[:provider]).to eq("claude")
    end

    it "gets error logs with time range filter" do
      time_range = (Time.now - 1)..Time.now
      errors = error_logger.get_error_logs({time_range: time_range})

      expect(errors.size).to eq(2)
    end

    it "gets recovery logs" do
      recoveries = error_logger.get_recovery_logs

      expect(recoveries.size).to eq(1)
      expect(recoveries.first[:action_type]).to eq(:provider_switch)
    end

    it "gets switch logs" do
      error_logger.log_provider_switch("claude", "gemini", "rate_limit", {})

      switches = error_logger.get_switch_logs

      expect(switches.size).to eq(1)
      expect(switches.first[:switch_type]).to eq(:provider_switch)
    end

    it "gets retry logs" do
      error_logger.log_retry_attempt(:network_error, 1, 1.0, {})

      retries = error_logger.get_retry_logs

      expect(retries.size).to eq(1)
      expect(retries.first[:error_type]).to eq(:network_error)
    end

    it "gets circuit breaker logs" do
      error_logger.log_circuit_breaker_event("claude", "model1", :opened, "high_failure_rate", {})

      circuit_breakers = error_logger.get_circuit_breaker_logs

      expect(circuit_breakers.size).to eq(1)
      expect(circuit_breakers.first[:event_type]).to eq(:opened)
    end
  end

  describe "log summary" do
    before do
      # Add some test logs
      error_logger.log_error(StandardError.new("Error 1"), {provider: "claude", model: "model1"})
      error_logger.log_error(Timeout::Error.new("Timeout"), {provider: "gemini", model: "model1"})
      error_logger.log_recovery_action(:provider_switch, {success: true, duration: 2.0}, {})
      error_logger.log_provider_switch("claude", "gemini", "rate_limit", {duration: 0.5})
      error_logger.log_retry_attempt(:network_error, 1, 1.0, {success: true})
      error_logger.log_circuit_breaker_event("claude", "model1", :opened, "high_failure_rate", {})
    end

    it "gets comprehensive log summary" do
      summary = error_logger.get_log_summary

      expect(summary).to include(
        :error_summary,
        :recovery_summary,
        :switch_summary,
        :retry_summary,
        :circuit_breaker_summary,
        :error_patterns,
        :recovery_effectiveness,
        :alert_summary
      )
    end

    it "provides error summary with statistics" do
      summary = error_logger.get_log_summary
      error_summary = summary[:error_summary]

      expect(error_summary[:total_errors]).to eq(2)
      expect(error_summary[:errors_by_provider]).to include("claude" => 1, "gemini" => 1)
      expect(error_summary[:errors_by_severity]).to include(error: 1, warning: 1)
    end

    it "provides recovery summary with statistics" do
      summary = error_logger.get_log_summary
      recovery_summary = summary[:recovery_summary]

      expect(recovery_summary[:total_recoveries]).to eq(1)
      expect(recovery_summary[:successful_recoveries]).to eq(1)
      expect(recovery_summary[:failed_recoveries]).to eq(0)
      expect(recovery_summary[:recovery_success_rate]).to eq(1.0)
    end

    it "provides switch summary with statistics" do
      summary = error_logger.get_log_summary
      switch_summary = summary[:switch_summary]

      expect(switch_summary[:total_switches]).to eq(1)
      expect(switch_summary[:provider_switches]).to eq(1)
      expect(switch_summary[:model_switches]).to eq(0)
    end

    it "provides retry summary with statistics" do
      summary = error_logger.get_log_summary
      retry_summary = summary[:retry_summary]

      expect(retry_summary[:total_retries]).to eq(1)
      expect(retry_summary[:successful_retries]).to eq(1)
      expect(retry_summary[:failed_retries]).to eq(0)
      expect(retry_summary[:retry_success_rate]).to eq(1.0)
    end

    it "provides circuit breaker summary with statistics" do
      summary = error_logger.get_log_summary
      circuit_breaker_summary = summary[:circuit_breaker_summary]

      expect(circuit_breaker_summary[:total_events]).to eq(1)
      expect(circuit_breaker_summary[:events_by_type]).to include(opened: 1)
    end
  end

  describe "log export" do
    before do
      # Add some test logs
      error_logger.log_error(StandardError.new("Test error"), {provider: "claude"})
      error_logger.log_recovery_action(:provider_switch, {success: true}, {})
    end

    it "exports logs in JSON format" do
      json_export = error_logger.export_logs(:json)

      expect(json_export).to be_a(String)
      expect { JSON.parse(json_export) }.not_to raise_error

      parsed = JSON.parse(json_export)
      expect(parsed).to include("errors", "recoveries", "switches", "retries", "circuit_breakers")
    end

    it "exports logs in YAML format" do
      yaml_export = error_logger.export_logs(:yaml)

      expect(yaml_export).to be_a(String)
      expect { YAML.safe_load(yaml_export, permitted_classes: [Symbol, Time]) }.not_to raise_error
    end

    it "exports logs in CSV format" do
      csv_export = error_logger.export_logs(:csv)

      expect(csv_export).to be_a(String)
    end

    it "exports logs in text format" do
      text_export = error_logger.export_logs(:text)

      expect(text_export).to be_a(String)
    end

    it "raises error for unsupported format" do
      expect {
        error_logger.export_logs(:unsupported)
      }.to raise_error(ArgumentError, "Unsupported export format: unsupported")
    end
  end

  describe "log management" do
    it "rotates logs" do
      expect { error_logger.rotate_logs }.not_to raise_error
    end

    it "compresses logs" do
      expect { error_logger.compress_logs }.not_to raise_error
    end

    it "archives logs" do
      expect { error_logger.archive_logs }.not_to raise_error
    end

    it "clears old logs with default retention" do
      expect { error_logger.clear_old_logs }.not_to raise_error
    end

    it "clears old logs with custom retention" do
      expect { error_logger.clear_old_logs(7) }.not_to raise_error
    end
  end

  describe "logging configuration" do
    it "configures logging settings" do
      config = {
        log_level: :debug,
        retention_days: 14,
        compression_enabled: false
      }

      expect { error_logger.configure_logging(config) }.not_to raise_error
    end
  end

  describe "error patterns and analysis" do
    it "gets error patterns" do
      patterns = error_logger.get_error_patterns

      expect(patterns).to include(
        :most_common_errors,
        :error_trends,
        :peak_error_times,
        :error_correlation
      )
    end

    it "gets recovery effectiveness" do
      effectiveness = error_logger.get_recovery_effectiveness

      expect(effectiveness).to include(
        :success_rate,
        :average_recovery_time,
        :most_effective_strategy,
        :least_effective_strategy
      )
    end

    it "gets alert summary" do
      summary = error_logger.get_alert_summary

      expect(summary).to include(
        :total_alerts,
        :critical_alerts,
        :warning_alerts,
        :recent_alerts
      )
    end
  end

  describe "helper classes" do
    describe "LogStorage" do
      let(:log_storage) { described_class::LogStorage.new }

      it "stores and retrieves errors" do
        error_entry = {id: "1", type: :error, timestamp: Time.now}

        log_storage.store_error(error_entry)
        errors = log_storage.get_errors

        expect(errors).to include(error_entry)
      end

      it "filters logs by time range" do
        old_entry = {id: "1", type: :error, timestamp: Time.now - 3600}
        new_entry = {id: "2", type: :error, timestamp: Time.now}

        log_storage.store_error(old_entry)
        log_storage.store_error(new_entry)

        time_range = (Time.now - 1800)..Time.now
        filtered = log_storage.get_errors({time_range: time_range})

        expect(filtered).to include(new_entry)
        expect(filtered).not_to include(old_entry)
      end

      it "filters logs by provider" do
        claude_entry = {id: "1", type: :error, provider: "claude"}
        gemini_entry = {id: "2", type: :error, provider: "gemini"}

        log_storage.store_error(claude_entry)
        log_storage.store_error(gemini_entry)

        filtered = log_storage.get_errors({provider: "claude"})

        expect(filtered).to include(claude_entry)
        expect(filtered).not_to include(gemini_entry)
      end

      it "clears old logs" do
        old_entry = {id: "1", type: :error, timestamp: Time.now - 3600}
        new_entry = {id: "2", type: :error, timestamp: Time.now}

        log_storage.store_error(old_entry)
        log_storage.store_error(new_entry)

        log_storage.clear_old_logs(0.02) # ~30 minutes (0.02 days)

        errors = log_storage.get_errors
        expect(errors).to include(new_entry)
        expect(errors).not_to include(old_entry)
      end
    end

    describe "RecoveryTracker" do
      let(:tracker) { described_class::RecoveryTracker.new }

      it "tracks recovery metrics" do
        recovery_entry = {action_type: :provider_switch, success: true, duration: 2.0}

        expect { tracker.track_recovery(recovery_entry) }.not_to raise_error
      end

      it "provides recovery effectiveness metrics" do
        effectiveness = tracker.get_recovery_effectiveness

        expect(effectiveness).to include(
          :success_rate,
          :average_recovery_time,
          :most_effective_strategy,
          :least_effective_strategy
        )
      end
    end

    describe "ErrorAnalyzer" do
      let(:analyzer) { described_class::ErrorAnalyzer.new }

      it "analyzes error patterns" do
        error_entry = {category: :timeout, severity: :warning}

        expect { analyzer.analyze_error(error_entry) }.not_to raise_error
      end

      it "provides error pattern analysis" do
        patterns = analyzer.get_error_patterns

        expect(patterns).to include(
          :most_common_errors,
          :error_trends,
          :peak_error_times,
          :error_correlation
        )
      end
    end

    describe "AlertManager" do
      let(:alert_manager) { described_class::AlertManager.new }

      it "checks error alerts" do
        error_entry = {severity: :error, category: :server_error}

        expect { alert_manager.check_error_alerts(error_entry) }.not_to raise_error
      end

      it "provides alert summary" do
        summary = alert_manager.get_alert_summary

        expect(summary).to include(
          :total_alerts,
          :critical_alerts,
          :warning_alerts,
          :recent_alerts
        )
      end
    end
  end

  describe "error handling" do
    it "handles missing configuration methods gracefully" do
      allow(configuration).to receive(:logging_config).and_raise(NoMethodError)

      expect {
        described_class.new(configuration)
      }.to raise_error(NoMethodError)
    end

    it "handles missing metrics manager methods gracefully" do
      allow(metrics_manager).to receive(:record_error_event).and_raise(NoMethodError)

      error = StandardError.new("Test error")

      expect {
        error_logger.log_error(error, {})
      }.to raise_error(NoMethodError)
    end
  end
end
