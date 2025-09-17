# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Aidp::Harness::StatusDisplay do
  # Helper method to capture stdout
  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
  let(:provider_manager) { instance_double("Aidp::Harness::ProviderManager") }
  let(:metrics_manager) { instance_double("Aidp::Harness::MetricsManager") }
  let(:circuit_breaker_manager) { instance_double("Aidp::Harness::CircuitBreakerManager") }
  let(:status_display) { described_class.new(provider_manager, metrics_manager, circuit_breaker_manager) }

  before do
    # Mock provider manager methods
    allow(provider_manager).to receive(:current_provider).and_return("claude")
    allow(provider_manager).to receive(:current_model).and_return("model1")
    allow(provider_manager).to receive(:get_available_providers).and_return(["claude", "gemini", "cursor"])
    allow(provider_manager).to receive(:get_provider_health_status).and_return({
      "claude" => {status: "healthy", health_score: 0.95}
    })

    # Mock metrics manager methods
    allow(metrics_manager).to receive(:get_realtime_metrics).and_return({
      throughput: 10,
      error_rate: 0.05,
      availability: 0.99
    })

    # Mock circuit breaker manager methods
    allow(circuit_breaker_manager).to receive(:get_all_states).and_return({
      "claude" => {state: :closed, failure_count: 0}
    })

    # Initialize error summary directly
    status_display.instance_variable_set(:@error_summary, {
      error_summary: {total_errors: 2, error_rate: 0.05}
    })
  end

  describe "initialization" do
    it "creates status display successfully" do
      expect(status_display).to be_a(described_class)
    end

    it "initializes with default configuration" do
      config = status_display.instance_variable_get(:@display_config)

      expect(config).to include(
        :mode,
        :update_interval,
        :show_animations,
        :show_colors,
        :show_metrics,
        :show_alerts,
        :max_display_lines,
        :auto_scroll
      )
    end

    it "initializes helper components" do
      expect(status_display.instance_variable_get(:@status_formatter)).to be_a(described_class::StatusFormatter)
      expect(status_display.instance_variable_get(:@metrics_calculator)).to be_a(described_class::MetricsCalculator)
      expect(status_display.instance_variable_get(:@alert_manager)).to be_a(described_class::AlertManager)
      expect(status_display.instance_variable_get(:@display_animator)).to be_a(described_class::DisplayAnimator)
    end
  end

  describe "status updates" do
    it "updates current step" do
      status_display.update_current_step("Test Step")

      expect(status_display.instance_variable_get(:@current_step)).to eq("Test Step")
      expect(status_display.instance_variable_get(:@status_data)[:current_step]).to eq("Test Step")
    end

    it "updates current provider" do
      status_display.update_current_provider("claude")

      expect(status_display.instance_variable_get(:@current_provider)).to eq("claude")
      expect(status_display.instance_variable_get(:@status_data)[:current_provider]).to eq("claude")
    end

    it "updates current model" do
      status_display.update_current_model("claude", "model1")

      expect(status_display.instance_variable_get(:@current_model)).to eq("model1")
      expect(status_display.instance_variable_get(:@status_data)[:current_model]).to eq("model1")
    end

    it "updates token usage" do
      status_display.update_token_usage("claude", "model1", 1000, 500)

      token_usage = status_display.instance_variable_get(:@token_usage)
      expect(token_usage["claude"]["model1"][:used]).to eq(1000)
      expect(token_usage["claude"]["model1"][:remaining]).to eq(500)
    end

    it "updates rate limit status" do
      rate_limit_info = {
        reset_time: Time.now + 3600,
        retry_after: 60,
        quota_remaining: 100,
        quota_limit: 1000
      }

      status_display.update_rate_limit_status("claude", "model1", rate_limit_info)

      rate_limit_status = status_display.instance_variable_get(:@rate_limit_status)
      expect(rate_limit_status["claude"]["model1"][:rate_limited]).to be true
      expect(rate_limit_status["claude"]["model1"][:quota_remaining]).to eq(100)
    end

    it "updates recovery status" do
      status_display.update_recovery_status(:provider_switch, :success, {new_provider: "gemini"})

      recovery_status = status_display.instance_variable_get(:@recovery_status)
      expect(recovery_status[:provider_switch][:status]).to eq(:success)
      expect(recovery_status[:provider_switch][:details][:new_provider]).to eq("gemini")
    end

    it "updates user feedback status" do
      status_display.update_user_feedback_status(:question, :waiting, {question_count: 3})

      user_feedback_status = status_display.instance_variable_get(:@user_feedback_status)
      expect(user_feedback_status[:question][:status]).to eq(:waiting)
      expect(user_feedback_status[:question][:details][:question_count]).to eq(3)
    end

    it "updates work completion status" do
      completion_info = {
        is_complete: false,
        completed_steps: 3,
        total_steps: 5
      }

      status_display.update_work_completion_status(completion_info)

      work_completion_status = status_display.instance_variable_get(:@work_completion_status)
      expect(work_completion_status[:is_complete]).to be false
      expect(work_completion_status[:completed_steps]).to eq(3)
    end

    it "updates performance metrics" do
      metrics = {throughput: 15, error_rate: 0.02}
      status_display.update_performance_metrics(metrics)

      performance_metrics = status_display.instance_variable_get(:@performance_metrics)
      expect(performance_metrics[:throughput]).to eq(15)
      expect(performance_metrics[:error_rate]).to eq(0.02)
    end

    it "updates error summary" do
      error_summary = {total_errors: 5, error_rate: 0.1}
      status_display.update_error_summary(error_summary)

      error_summary_data = status_display.instance_variable_get(:@error_summary)
      expect(error_summary_data[:total_errors]).to eq(5)
      expect(error_summary_data[:error_rate]).to eq(0.1)
    end
  end

  describe "display configuration" do
    it "sets display mode" do
      status_display.set_display_mode(:detailed)

      expect(status_display.instance_variable_get(:@display_mode)).to eq(:detailed)
    end

    it "sets update interval" do
      status_display.set_update_interval(5)

      expect(status_display.instance_variable_get(:@update_interval)).to eq(5)
    end

    it "configures display settings" do
      config = {show_animations: false, show_colors: false}
      status_display.configure_display(config)

      display_config = status_display.instance_variable_get(:@display_config)
      expect(display_config[:show_animations]).to be false
      expect(display_config[:show_colors]).to be false
    end
  end

  describe "status data collection" do
    it "collects status data from managers" do
      status_display.send(:collect_status_data)

      provider_status = status_display.instance_variable_get(:@provider_status)
      expect(provider_status[:current_provider]).to eq("claude")
      expect(provider_status[:available_providers]).to include("claude", "gemini", "cursor")
    end

    it "collects circuit breaker status" do
      status_display.send(:collect_status_data)

      circuit_breaker_status = status_display.instance_variable_get(:@circuit_breaker_status)
      expect(circuit_breaker_status["claude"][:state]).to eq(:closed)
    end

    it "collects metrics data" do
      status_display.send(:collect_status_data)

      performance_metrics = status_display.instance_variable_get(:@performance_metrics)
      expect(performance_metrics[:throughput]).to eq(10)
      expect(performance_metrics[:error_rate]).to eq(0.05)
    end

    it "collects error data" do
      status_display.send(:collect_status_data)

      error_summary = status_display.instance_variable_get(:@error_summary)
      expect(error_summary[:error_summary][:total_errors]).to eq(2)
    end

    it "calculates performance data" do
      status_display.instance_variable_set(:@start_time, Time.now - 60)
      status_display.send(:collect_performance_data)

      performance_metrics = status_display.instance_variable_get(:@performance_metrics)
      expect(performance_metrics[:uptime]).to be > 0
    end
  end

  describe "status display modes" do
    before do
      status_display.instance_variable_set(:@start_time, Time.now - 30)
      status_display.instance_variable_set(:@current_step, "Test Step")
      status_display.instance_variable_set(:@current_provider, "claude")
      status_display.instance_variable_set(:@current_model, "model1")
      status_display.instance_variable_set(:@running, true)
    end

    it "displays compact status" do
      output = capture_stdout do
        status_display.send(:display_compact_status)
      end
      expect(output).to match(/Harness Status/)
    end

    it "displays detailed status" do
      output = capture_stdout do
        status_display.send(:display_detailed_status)
      end
      expect(output).to match(/Harness Status - Detailed/)
    end

    it "displays minimal status" do
      output = capture_stdout do
        status_display.send(:display_minimal_status)
      end
      expect(output).to match(/Test Step/)
    end

    it "displays full status" do
      output = capture_stdout do
        status_display.send(:display_full_status)
      end
      expect(output).to match(/AIDP HARNESS - FULL STATUS REPORT/)
    end
  end

  describe "status information display" do
    before do
      status_display.instance_variable_set(:@start_time, Time.now - 60)
      status_display.instance_variable_set(:@current_step, "Test Step")
      status_display.instance_variable_set(:@current_provider, "claude")
      status_display.instance_variable_set(:@current_model, "model1")
    end

    it "displays basic information" do
      output = capture_stdout do
        status_display.send(:display_basic_info)
      end
      expect(output).to match(/BASIC INFORMATION/)
    end

    it "displays provider information" do
      status_display.instance_variable_set(:@provider_status, {
        available_providers: ["claude", "gemini"],
        provider_health: {"claude" => {status: "healthy", health_score: 0.95}}
      })

      output = capture_stdout do
        status_display.send(:display_provider_info)
      end
      expect(output).to match(/PROVIDER INFORMATION/)
    end

    it "displays performance information" do
      status_display.instance_variable_set(:@performance_metrics, {
        uptime: 60,
        step_duration: 30,
        provider_switch_count: 2,
        error_rate: 0.05
      })

      output = capture_stdout do
        status_display.send(:display_performance_info)
      end
      expect(output).to match(/PERFORMANCE METRICS/)
    end

    it "displays error information" do
      status_display.instance_variable_set(:@error_summary, {
        error_summary: {
          total_errors: 3,
          error_rate: 0.1,
          errors_by_severity: {warning: 2, error: 1},
          errors_by_provider: {"claude" => 2, "gemini" => 1}
        }
      })

      output = capture_stdout do
        status_display.send(:display_error_info)
      end
      expect(output).to match(/ERROR INFORMATION/)
    end

    it "displays circuit breaker information" do
      status_display.instance_variable_set(:@circuit_breaker_status, {
        "claude" => {state: :closed, failure_count: 0},
        "gemini" => {state: :open, failure_count: 5}
      })

      output = capture_stdout do
        status_display.send(:display_circuit_breaker_info)
      end
      expect(output).to match(/CIRCUIT BREAKER STATUS/)
    end

    it "displays token usage information" do
      status_display.instance_variable_set(:@token_usage, {
        "claude" => {
          "model1" => {used: 1000, remaining: 500}
        }
      })

      output = capture_stdout do
        status_display.send(:display_token_usage)
      end
      expect(output).to match(/TOKEN USAGE/)
    end

    it "displays rate limit information" do
      status_display.instance_variable_set(:@rate_limit_status, {
        "claude" => {
          "model1" => {
            rate_limited: true,
            reset_time: Time.now + 3600,
            retry_after: 60,
            quota_remaining: 100,
            quota_limit: 1000
          }
        }
      })

      output = capture_stdout do
        status_display.send(:display_rate_limit_info)
      end
      expect(output).to match(/RATE LIMIT STATUS/)
    end

    it "displays recovery information" do
      status_display.instance_variable_set(:@recovery_status, {
        provider_switch: {status: :success, details: {new_provider: "gemini"}}
      })

      output = capture_stdout do
        status_display.send(:display_recovery_info)
      end
      expect(output).to match(/RECOVERY STATUS/)
    end

    it "displays user feedback information" do
      status_display.instance_variable_set(:@user_feedback_status, {
        question: {status: :waiting, details: {question_count: 3}}
      })

      output = capture_stdout do
        status_display.send(:display_user_feedback_info)
      end
      expect(output).to match(/USER FEEDBACK STATUS/)
    end

    it "displays work completion information" do
      status_display.instance_variable_set(:@work_completion_status, {
        is_complete: false,
        completed_steps: 3,
        total_steps: 5
      })

      output = capture_stdout do
        status_display.send(:display_work_completion_info)
      end
      expect(output).to match(/WORK COMPLETION STATUS/)
    end

    it "displays alerts" do
      alert_manager = status_display.instance_variable_get(:@alert_manager)
      alert_manager.process_alerts([
        {severity: :warning, message: "High error rate", timestamp: Time.now}
      ])

      output = capture_stdout do
        status_display.send(:display_alerts)
      end
      expect(output).to match(/ALERTS/)
    end
  end

  describe "alert checking" do
    it "checks for high error rate alerts" do
      status_display.instance_variable_set(:@performance_metrics, {error_rate: 0.15})

      expect { status_display.send(:check_alerts) }.not_to raise_error
    end

    it "checks for open circuit breaker alerts" do
      status_display.instance_variable_set(:@circuit_breaker_status, {
        "claude" => {state: :open, failure_count: 5}
      })

      expect { status_display.send(:check_alerts) }.not_to raise_error
    end

    it "checks for rate limit alerts" do
      status_display.instance_variable_set(:@rate_limit_status, {
        "claude" => {
          "model1" => {rate_limited: true}
        }
      })

      expect { status_display.send(:check_alerts) }.not_to raise_error
    end
  end

  describe "status data retrieval" do
    before do
      status_display.instance_variable_set(:@start_time, Time.now - 60)
      status_display.instance_variable_set(:@current_step, "Test Step")
      status_display.instance_variable_set(:@current_provider, "claude")
      status_display.instance_variable_set(:@current_model, "model1")
    end

    it "gets basic status" do
      basic_status = status_display.send(:get_basic_status)

      expect(basic_status).to include(
        :duration,
        :current_step,
        :current_provider,
        :current_model,
        :status,
        :start_time,
        :last_update
      )
      expect(basic_status[:current_step]).to eq("Test Step")
      expect(basic_status[:current_provider]).to eq("claude")
    end

    it "gets provider status" do
      provider_status = status_display.send(:get_provider_status)

      expect(provider_status).to be_a(Hash)
    end

    it "gets performance status" do
      performance_status = status_display.send(:get_performance_status)

      expect(performance_status).to be_a(Hash)
    end

    it "gets error status" do
      error_status = status_display.send(:get_error_status)

      expect(error_status).to be_a(Hash)
    end

    it "gets circuit breaker status" do
      circuit_breaker_status = status_display.send(:get_circuit_breaker_status)

      expect(circuit_breaker_status).to be_a(Hash)
    end

    it "gets token status" do
      token_status = status_display.send(:get_token_status)

      expect(token_status).to be_a(Hash)
    end

    it "gets rate limit status" do
      rate_limit_status = status_display.send(:get_rate_limit_status)

      expect(rate_limit_status).to be_a(Hash)
    end

    it "gets recovery status" do
      recovery_status = status_display.send(:get_recovery_status)

      expect(recovery_status).to be_a(Hash)
    end

    it "gets user feedback status" do
      user_feedback_status = status_display.send(:get_user_feedback_status)

      expect(user_feedback_status).to be_a(Hash)
    end

    it "gets work completion status" do
      work_completion_status = status_display.send(:get_work_completion_status)

      expect(work_completion_status).to be_a(Hash)
    end

    it "gets alerts" do
      alerts = status_display.send(:get_alerts)

      expect(alerts).to be_an(Array)
    end
  end

  describe "comprehensive status data" do
    it "gets comprehensive status data" do
      status_data = status_display.get_status_data

      expect(status_data).to include(
        :basic_info,
        :provider_info,
        :performance_info,
        :error_info,
        :circuit_breaker_info,
        :token_info,
        :rate_limit_info,
        :recovery_info,
        :user_feedback_info,
        :work_completion_info,
        :alerts
      )
    end
  end

  describe "status export" do
    it "exports status data in JSON format" do
      json_export = status_display.export_status_data(:json)

      expect(json_export).to be_a(String)
      expect { JSON.parse(json_export) }.not_to raise_error
    end

    it "exports status data in YAML format" do
      yaml_export = status_display.export_status_data(:yaml)

      expect(yaml_export).to be_a(String)
      expect { YAML.safe_load(yaml_export, permitted_classes: [Symbol, Time]) }.not_to raise_error
    end

    it "exports status data in text format" do
      text_export = status_display.export_status_data(:text)

      expect(text_export).to be_a(String)
    end

    it "raises error for unsupported format" do
      expect {
        status_display.export_status_data(:unsupported)
      }.to raise_error(ArgumentError, "Unsupported format: unsupported")
    end
  end

  describe "status display lifecycle" do
    it "starts status updates" do
      expect { status_display.start_status_updates(:compact) }.not_to raise_error

      # Give it a moment to start
      sleep(0.1)

      expect(status_display.instance_variable_get(:@running)).to be true
    end

    it "stops status updates" do
      status_display.start_status_updates(:compact)
      sleep(0.1)

      expect { status_display.stop_status_updates }.not_to raise_error

      expect(status_display.instance_variable_get(:@running)).to be false
    end

    it "cleans up display" do
      expect { status_display.cleanup }.not_to raise_error
    end
  end

  describe "special status displays" do
    it "shows paused status" do
      output = capture_stdout do
        status_display.show_paused_status
      end
      expect(output).to match(/Harness PAUSED/)
    end

    it "shows resumed status" do
      output = capture_stdout do
        status_display.show_resumed_status
      end
      expect(output).to match(/Harness RESUMED/)
    end

    it "shows stopped status" do
      output = capture_stdout do
        status_display.show_stopped_status
      end
      expect(output).to match(/Harness STOPPED/)
    end

    it "shows rate limit wait" do
      reset_time = Time.now + 60
      output = capture_stdout do
        status_display.show_rate_limit_wait(reset_time)
      end
      expect(output).to match(/Rate limit reached/)
    end

    it "updates rate limit countdown", pending: "Rate limit countdown display not fully implemented" do
      output = capture_stdout do
        status_display.update_rate_limit_countdown(30)
      end
      expect(output).to match(/Rate limit - waiting/)
    end

    it "shows completion status" do
      output = capture_stdout do
        status_display.show_completion_status(120, 5, 5)
      end
      expect(output).to match(/Harness COMPLETED/)
    end

    it "shows error status" do
      output = capture_stdout do
        status_display.show_error_status("Test error")
      end
      expect(output).to match(/Harness ERROR/)
    end
  end

  describe "helper classes" do
    describe "StatusFormatter" do
      let(:formatter) { described_class::StatusFormatter.new }

      it "formats status data" do
        status_data = {test: "data"}

        expect(formatter.format_status(status_data, :compact)).to be_a(String)
        expect(formatter.format_status(status_data, :detailed)).to be_a(String)
        expect(formatter.format_status(status_data, :json)).to be_a(String)
      end
    end

    describe "MetricsCalculator" do
      let(:calculator) { described_class::MetricsCalculator.new }

      it "calculates metrics" do
        raw_data = {requests: 100, errors: 5}
        metrics = calculator.calculate_metrics(raw_data)

        expect(metrics).to include(
          :throughput,
          :error_rate,
          :availability,
          :performance_score
        )
      end
    end

    describe "AlertManager" do
      let(:alert_manager) { described_class::AlertManager.new }

      it "processes alerts" do
        alerts = [
          {severity: :warning, message: "Test alert", timestamp: Time.now}
        ]

        expect { alert_manager.process_alerts(alerts) }.not_to raise_error
      end

      it "gets active alerts" do
        alerts = alert_manager.get_active_alerts

        expect(alerts).to be_an(Array)
      end

      it "clears alerts" do
        expect { alert_manager.clear_alerts }.not_to raise_error
      end
    end

    describe "DisplayAnimator" do
      let(:animator) { described_class::DisplayAnimator.new }

      it "animates status" do
        expect(animator.animate_status(:loading)).to be_a(String)
        expect(animator.animate_status(:processing)).to be_a(String)
        expect(animator.animate_status(:waiting)).to be_a(String)
      end
    end
  end

  describe "error handling" do
    it "handles display errors gracefully" do
      allow(status_display).to receive(:collect_status_data).and_raise(StandardError.new("Test error"))

      output = capture_stdout do
        status_display.send(:handle_display_error, StandardError.new("Test error"))
      end
      expect(output).to match(/Display Error/)
    end

    it "handles missing manager methods gracefully", pending: "Error handling for missing methods not fully implemented" do
      allow(provider_manager).to receive(:current_provider).and_raise(NoMethodError)

      expect { status_display.send(:collect_provider_status) }.not_to raise_error
    end
  end

  describe "utility methods" do
    it "formats duration correctly" do
      expect(status_display.send(:format_duration, 0)).to eq("0s")
      expect(status_display.send(:format_duration, 30)).to eq("30s")
      expect(status_display.send(:format_duration, 90)).to eq("1m 30s")
      expect(status_display.send(:format_duration, 3661)).to eq("1h 1m 1s")
    end

    it "formats percentage correctly" do
      expect(status_display.send(:format_percentage, 0)).to eq("0%")
      expect(status_display.send(:format_percentage, 0.05)).to eq("5.0%")
      expect(status_display.send(:format_percentage, 0.123)).to eq("12.3%")
      expect(status_display.send(:format_percentage, nil)).to eq("0%")
    end

    it "clears display" do
      expect { status_display.send(:clear_display) }.not_to raise_error
    end
  end
end
