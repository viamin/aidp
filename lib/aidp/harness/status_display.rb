# frozen_string_literal: true

require "tty-prompt"
require "tty-cursor"

module Aidp
  module Harness
    # Real-time status updates and monitoring interface
    class StatusDisplay
      include Aidp::MessageDisplay

      def initialize(provider_manager = nil, metrics_manager = nil, circuit_breaker_manager = nil, error_logger = nil, prompt: TTY::Prompt.new)
        @provider_manager = provider_manager
        @metrics_manager = metrics_manager
        @circuit_breaker_manager = circuit_breaker_manager
        @error_logger = error_logger
        @prompt = prompt
        @cursor = TTY::Cursor

        @start_time = nil
        @current_step = nil
        @current_provider = nil
        @current_model = nil
        @status_thread = nil
        @running = false
        @display_mode = :compact
        @update_interval = 2
        @last_update = Time.now
        @status_data = {}
        @performance_metrics = {}
        @error_summary = {}
        @provider_status = {}
        @model_status = {}
        @circuit_breaker_status = {}
        @token_usage = {}
        @rate_limit_status = {}
        @recovery_status = {}
        @user_feedback_status = {}
        @work_completion_status = {}
        @configuration = {}
        @display_config = initialize_display_config
        @status_formatter = StatusFormatter.new
        @metrics_calculator = MetricsCalculator.new
        @alert_manager = AlertManager.new
        @display_animator = DisplayAnimator.new
      end

      # Start real-time status updates
      def start_status_updates(display_mode = :compact)
        return if @running

        @running = true
        @start_time = Time.now
        @display_mode = display_mode
        @last_update = Time.now

        unless ENV["RACK_ENV"] == "test" || defined?(RSpec)
          require "concurrent"
          @status_future = Concurrent::Future.execute do
            while @running
              begin
                collect_status_data
                display_status
                check_alerts
                sleep(@update_interval)
              rescue => e
                handle_display_error(e)
              end
            end
          end
        end
      end

      # Stop status updates
      def stop_status_updates
        @running = false
        @status_future&.wait(5)
        clear_display
      end

      # Update current step
      def update_current_step(step_name)
        @current_step = step_name
        @status_data[:current_step] = step_name
        @status_data[:step_start_time] = Time.now
      end

      # Update current provider
      def update_current_provider(provider_name)
        @current_provider = provider_name
        @status_data[:current_provider] = provider_name
        @status_data[:provider_switch_time] = Time.now
      end

      # Update current model
      def update_current_model(_provider_name, model_name)
        @current_model = model_name
        @status_data[:current_model] = model_name
        @status_data[:model_switch_time] = Time.now
      end

      # Update token usage
      def update_token_usage(provider, model, tokens_used, tokens_remaining = nil)
        @token_usage[provider] ||= {}
        @token_usage[provider][model] = {
          used: tokens_used,
          remaining: tokens_remaining,
          last_updated: Time.now
        }
      end

      # Update rate limit status
      def update_rate_limit_status(provider, model, rate_limit_info)
        @rate_limit_status[provider] ||= {}
        @rate_limit_status[provider][model] = {
          rate_limited: true,
          reset_time: rate_limit_info[:reset_time],
          retry_after: rate_limit_info[:retry_after],
          quota_remaining: rate_limit_info[:quota_remaining],
          quota_limit: rate_limit_info[:quota_limit],
          last_updated: Time.now
        }
      end

      # Update recovery status
      def update_recovery_status(recovery_type, status, details = {})
        @recovery_status[recovery_type] = {
          status: status,
          details: details,
          last_updated: Time.now
        }
      end

      # Update user feedback status
      def update_user_feedback_status(feedback_type, status, details = {})
        @user_feedback_status[feedback_type] = {
          status: status,
          details: details,
          last_updated: Time.now
        }
      end

      # Update work completion status
      def update_work_completion_status(completion_info)
        @work_completion_status = completion_info.merge(last_updated: Time.now)
      end

      # Update performance metrics
      def update_performance_metrics(metrics)
        @performance_metrics.merge!(metrics)
        @performance_metrics[:last_updated] = Time.now
      end

      # Update error summary
      def update_error_summary(error_summary)
        @error_summary.merge!(error_summary)
        @error_summary[:last_updated] = Time.now
      end

      # Set display mode
      def display_mode(mode)
        @display_mode = mode
        @display_config[:mode] = mode
      end

      # Set update interval
      def update_interval(interval)
        @update_interval = interval
        @display_config[:update_interval] = interval
      end

      # Configure display settings
      def configure_display(config)
        @display_config.merge!(config)
      end

      # Show paused status
      def show_paused_status
        clear_display
        display_message("\n⏸️  Harness PAUSED", type: :warning)
        display_message("   Press 'r' to resume, 's' to stop", type: :info)
        display_message("   Current step: #{@current_step}", type: :info) if @current_step
        display_message("   Current provider: #{@current_provider}", type: :info) if @current_provider
        display_message("   Current model: #{@current_model}", type: :info) if @current_model
        display_message("   Duration: #{format_duration(Time.now - @start_time)}", type: :info) if @start_time
      end

      # Show resumed status
      def show_resumed_status
        clear_display
        display_message("\n▶️  Harness RESUMED", type: :success)
        display_message("   Continuing execution...", type: :info)
      end

      # Show stopped status
      def show_stopped_status
        clear_display
        display_message("\n⏹️  Harness STOPPED", type: :error)
        display_message("   Execution terminated by user", type: :info)
      end

      # Show rate limit wait
      def show_rate_limit_wait(reset_time)
        clear_display
        remaining = reset_time - Time.now
        display_message("\n🚫 Rate limit reached", type: :error)
        display_message("   Waiting for reset at #{reset_time.strftime("%H:%M:%S")}", type: :info)
        display_message("   Remaining: #{format_duration(remaining)}", type: :info)
        display_message("   Press Ctrl+C to cancel", type: :info)
      end

      # Update rate limit countdown
      def update_rate_limit_countdown(remaining_seconds)
        clear_display
        display_message("\n🚫 Rate limit - waiting...", type: :warning)
        display_message("   Resets in: #{format_duration(remaining_seconds)}", type: :info)
        display_message("   Press Ctrl+C to cancel", type: :info)
      end

      # Show completion status
      def show_completion_status(duration, steps_completed, total_steps)
        clear_display
        display_message("\n✅ Harness COMPLETED", type: :success)
        display_message("   Duration: #{format_duration(duration)}", type: :info)
        display_message("   Steps completed: #{steps_completed}/#{total_steps}", type: :info)
        display_message("   All workflows finished successfully!", type: :success)
      end

      # Show error status
      def show_error_status(error_message)
        clear_display
        display_message("\n❌ Harness ERROR", type: :error)
        display_message("   Error: #{error_message}", type: :error)
        display_message("   Check logs for details", type: :info)
      end

      # Cleanup display
      def cleanup
        stop_status_updates
        clear_display
      end

      # Get comprehensive status data
      def status_data
        {
          basic_info: basic_status,
          provider_info: provider_status,
          performance_info: performance_status,
          error_info: error_status,
          circuit_breaker_info: circuit_breaker_status,
          token_info: token_status,
          rate_limit_info: rate_limit_status,
          recovery_info: recovery_status,
          user_feedback_info: user_feedback_status,
          work_completion_info: work_completion_status,
          alerts: alerts
        }
      end

      # Export status data
      def export_status_data(format = :json)
        case format
        when :json
          JSON.pretty_generate(status_data)
        when :yaml
          status_data.to_yaml
        when :text
          format_status_as_text
        else
          raise ArgumentError, "Unsupported format: #{format}"
        end
      end

      private

      def initialize_display_config
        {
          mode: :compact,
          update_interval: 2,
          show_animations: true,
          show_colors: true,
          show_metrics: true,
          show_alerts: true,
          max_display_lines: 20,
          auto_scroll: true
        }
      end

      def collect_status_data
        @last_update = Time.now

        # Collect data from various managers
        collect_provider_status
        collect_circuit_breaker_status
        collect_metrics_data
        collect_error_data
        collect_performance_data
      end

      def collect_provider_status
        return unless @provider_manager
        begin
          @provider_status = {
            current_provider: safe_manager_call(@provider_manager, :current_provider),
            current_model: safe_manager_call(@provider_manager, :current_model),
            available_providers: safe_manager_call(@provider_manager, :available_providers) || [],
            provider_health: safe_manager_call(@provider_manager, :provider_health_status) || {}
          }
        rescue => e
          # Log minimal info without breaking display; keep previous provider_status if available
          @provider_status ||= {}
          @provider_status[:error] = "provider_status_error: #{e.class}"
        end
      end

      def safe_manager_call(manager, method)
        return nil unless manager.respond_to?(method, true)
        manager.public_send(method)
      rescue NoMethodError
        nil
      end

      def collect_circuit_breaker_status
        return unless @circuit_breaker_manager

        @circuit_breaker_status = @circuit_breaker_manager.all_states
      end

      def collect_metrics_data
        return unless @metrics_manager

        @performance_metrics = @metrics_manager.realtime_metrics
      end

      def collect_error_data
        return unless @error_logger

        @error_summary = @error_logger.get_log_summary
      end

      def collect_performance_data
        # Calculate performance metrics
        @performance_metrics[:uptime] = @start_time ? Time.now - @start_time : 0
        @performance_metrics[:step_duration] = calculate_step_duration
        @performance_metrics[:provider_switch_count] = count_provider_switches
        @performance_metrics[:error_rate] = calculate_error_rate
      end

      def display_status
        return unless @running

        clear_display

        case @display_mode
        when :compact
          display_compact_status
        when :detailed
          display_detailed_status
        when :minimal
          display_minimal_status
        when :full
          display_full_status
        else
          display_compact_status
        end
      end

      def display_compact_status
        duration = @start_time ? Time.now - @start_time : 0

        display_message("\n🔄 Harness Status", type: :info)
        display_message("   Duration: #{format_duration(duration)}", type: :info)
        display_message("   Step: #{@current_step || "Starting..."}", type: :info)
        display_message("   Provider: #{@current_provider || "Initializing..."}", type: :info)
        display_message("   Model: #{@current_model || "N/A"}", type: :info)
        display_message("   Status: Running", type: :info)

        # Show key metrics
        if @performance_metrics[:error_rate] && @performance_metrics[:error_rate] > 0
          display_message("   Error Rate: #{format_percentage(@performance_metrics[:error_rate])}", type: :warning)
        end

        if @token_usage[@current_provider] && @token_usage[@current_provider][@current_model]
          tokens = @token_usage[@current_provider][@current_model]
          display_message("   Tokens: #{tokens[:used]} used", type: :info)
          display_message("   Remaining: #{tokens[:remaining]}", type: :info) if tokens[:remaining]
        end

        display_message("   Press Ctrl+C to stop", type: :info)
      end

      def display_detailed_status
        duration = @start_time ? Time.now - @start_time : 0

        display_message("\n🔄 Harness Status - Detailed", type: :info)
        display_message("   Duration: #{format_duration(duration)}", type: :info)
        display_message("   Current Step: #{@current_step || "Starting..."}", type: :info)
        display_message("   Provider: #{@current_provider || "Initializing..."}", type: :info)
        display_message("   Model: #{@current_model || "N/A"}", type: :info)
        display_message("   Status: Running", type: :info)

        # Provider information
        if @provider_status[:available_providers]
          display_message("   Available Providers: #{@provider_status[:available_providers].join(", ")}", type: :info)
        end

        # Circuit breaker status
        if @circuit_breaker_status.any?
          open_circuits = @circuit_breaker_status.select { |_, status| status[:state] == :open }
          if open_circuits.any?
            display_message("   Open Circuit Breakers: #{open_circuits.keys.join(", ")}", type: :warning)
          end
        end

        # Token usage
        display_token_usage

        # Error summary
        if @error_summary[:error_summary] && @error_summary[:error_summary][:total_errors] > 0
          display_message("   Errors: #{@error_summary[:error_summary][:total_errors]} total", type: :warning)
        end

        display_message("   Press Ctrl+C to stop", type: :info)
      end

      def display_minimal_status
        duration = @start_time ? Time.now - @start_time : 0
        display_message("\r🔄 #{@current_step || "Starting"} | #{@current_provider || "Init"} | #{format_duration(duration)}", type: :info)
      end

      def display_full_status
        clear_display
        display_message("\n" + "=" * 80, type: :info)
        display_message("🔄 AIDP HARNESS - FULL STATUS REPORT", type: :highlight)
        display_message("=" * 80, type: :info)

        display_basic_info
        display_provider_info
        display_performance_info
        display_error_info
        display_circuit_breaker_info
        display_token_info
        display_rate_limit_info
        display_recovery_info
        display_user_feedback_info
        display_work_completion_info
        display_alerts

        display_message("=" * 80, type: :info)
        display_message("Press Ctrl+C to stop | Last updated: #{Time.now.strftime("%H:%M:%S")}", type: :muted)
      end

      def display_basic_info
        duration = @start_time ? Time.now - @start_time : 0

        display_message("\n📊 BASIC INFORMATION", type: :info)
        display_message("   Duration: #{format_duration(duration)}", type: :info)
        display_message("   Current Step: #{@current_step || "Starting..."}", type: :info)
        display_message("   Provider: #{@current_provider || "Initializing..."}", type: :info)
        display_message("   Model: #{@current_model || "N/A"}", type: :info)
        display_message("   Status: Running", type: :info)
        display_message("   Update Interval: #{@update_interval}s", type: :info)
      end

      def display_provider_info
        return unless @provider_status.any?

        display_message("\n🔌 PROVIDER INFORMATION", type: :info)
        if @provider_status[:available_providers]
          display_message("   Available Providers: #{@provider_status[:available_providers].join(", ")}", type: :info)
        end
        if @provider_status[:provider_health]
          display_message("   Provider Health:", type: :info)
          @provider_status[:provider_health].each do |provider, health|
            display_message("     #{provider}: #{health[:status]} (#{format_percentage(health[:health_score])})", type: :info)
          end
        end
      end

      def display_token_info
        return unless @token_usage.any?

        display_message("\n🎫 TOKEN USAGE", type: :info)
        @token_usage.each do |provider, models|
          display_message("   #{provider}:", type: :info)
          models.each do |model, usage|
            display_message("     #{model}: #{usage[:used]} used, #{usage[:remaining]} remaining", type: :info)
          end
        end
      end

      def display_performance_info
        return unless @performance_metrics.any?

        display_message("\n⚡ PERFORMANCE METRICS", type: :info)
        display_message("   Uptime: #{format_duration(@performance_metrics[:uptime] || 0)}", type: :info)
        display_message("   Step Duration: #{format_duration(@performance_metrics[:step_duration] || 0)}", type: :info)
        display_message("   Provider Switches: #{@performance_metrics[:provider_switch_count] || 0}", type: :info)
        display_message("   Error Rate: #{format_percentage(@performance_metrics[:error_rate] || 0)}", type: :info)

        if @performance_metrics[:throughput]
          display_message("   Throughput: #{@performance_metrics[:throughput]} requests/min", type: :info)
        end
      end

      def display_error_info
        return unless @error_summary[:error_summary]

        error_summary = @error_summary[:error_summary]
        return if error_summary[:total_errors] == 0

        display_message("\n❌ ERROR INFORMATION", type: :error)
        display_message("   Total Errors: #{error_summary[:total_errors]}", type: :error)
        display_message("   Error Rate: #{format_percentage(error_summary[:error_rate] || 0)}", type: :error)

        if error_summary[:errors_by_severity].respond_to?(:any?) && error_summary[:errors_by_severity].any?
          display_message("   By Severity:", type: :info)
          error_summary[:errors_by_severity].each do |severity, count|
            display_message("     #{severity}: #{count}", type: :info)
          end
        end

        if error_summary[:errors_by_provider].respond_to?(:any?) && error_summary[:errors_by_provider].any?
          display_message("   By Provider:", type: :info)
          error_summary[:errors_by_provider].each do |provider, count|
            display_message("     #{provider}: #{count}", type: :info)
          end
        end
      end

      def display_circuit_breaker_info
        return unless @circuit_breaker_status.any?

        display_message("\n🔒 CIRCUIT BREAKER STATUS", type: :info)
        @circuit_breaker_status.each do |key, status|
          state_icons = {closed: "🟢", open: "🔴", half_open: "🟡"}
          state_icon = state_icons[status[:state]] || "⚪"
          display_message("   #{state_icon} #{key}: #{status[:state]} (failures: #{status[:failure_count]})", type: :info)
        end
      end

      def display_token_usage
        return unless @token_usage.any?

        display_message("\n🎫 TOKEN USAGE", type: :info)
        @token_usage.each do |provider, models|
          display_message("   #{provider}:", type: :info)
          models.each do |model, usage|
            display_message("     #{model}: #{usage[:used]} used", type: :info)
            display_message("       Remaining: #{usage[:remaining]}", type: :info) if usage[:remaining]
          end
        end
      end

      def display_rate_limit_info
        return unless @rate_limit_status.any?

        display_message("\n🚫 RATE LIMIT STATUS", type: :warning)
        @rate_limit_status.each do |provider, models|
          models.each do |model, status|
            if status[:rate_limited]
              display_message("   #{provider}:#{model}: Rate Limited", type: :warning)
              display_message("     Reset Time: #{status[:reset_time]&.strftime("%H:%M:%S")}", type: :info)
              display_message("     Retry After: #{status[:retry_after]}s", type: :info)
              display_message("     Quota: #{status[:quota_remaining]}/#{status[:quota_limit]}", type: :info) if status[:quota_remaining]
            end
          end
        end
      end

      def display_recovery_info
        return unless @recovery_status.any?

        display_message("\n🔄 RECOVERY STATUS", type: :info)
        @recovery_status.each do |type, status|
          display_message("   #{type}: #{status[:status]}", type: :info)
          if status[:details].any?
            status[:details].each do |key, value|
              display_message("     #{key}: #{value}", type: :info)
            end
          end
        end
      end

      def display_user_feedback_info
        return unless @user_feedback_status.any?

        display_message("\n💬 USER FEEDBACK STATUS", type: :info)
        @user_feedback_status.each do |type, status|
          display_message("   #{type}: #{status[:status]}", type: :info)
          if status[:details].any?
            status[:details].each do |key, value|
              display_message("     #{key}: #{value}", type: :info)
            end
          end
        end
      end

      def display_work_completion_info
        return unless @work_completion_status.any?

        display_message("\n✅ WORK COMPLETION STATUS", type: :info)
        if @work_completion_status[:is_complete]
          display_message("   Status: Complete", type: :success)
        else
          display_message("   Status: In Progress", type: :info)
        end
        display_message("   Steps Completed: #{@work_completion_status[:completed_steps]}/#{@work_completion_status[:total_steps]}", type: :info)
      end

      def display_alerts
        return unless alerts.any?

        display_message("\n🚨 ALERTS", type: :warning)
        alerts.each do |alert|
          severity_icons = {critical: "🔴", warning: "🟡", info: "🔵"}
          severity_icon = severity_icons[alert[:severity]] || "⚪"
          display_message("   #{severity_icon} #{alert[:message]}", type: :warning)
        end
      end

      def check_alerts
        # Check for various alert conditions
        alerts = []

        # Check error rate
        if @performance_metrics[:error_rate] && @performance_metrics[:error_rate] > 0.1
          alerts << {
            severity: :warning,
            message: "High error rate: #{format_percentage(@performance_metrics[:error_rate])}",
            timestamp: Time.now
          }
        end

        # Check circuit breakers
        if @circuit_breaker_status.any?
          open_circuits = @circuit_breaker_status.select { |_, status| status[:state] == :open }
          if open_circuits.any?
            alerts << {
              severity: :warning,
              message: "Open circuit breakers: #{open_circuits.keys.join(", ")}",
              timestamp: Time.now
            }
          end
        end

        # Check rate limits
        if @rate_limit_status.any?
          rate_limited = @rate_limit_status.any? { |_, models| models.any? { |_, status| status[:rate_limited] } }
          if rate_limited
            alerts << {
              severity: :info,
              message: "Rate limits active",
              timestamp: Time.now
            }
          end
        end

        @alert_manager.process_alerts(alerts) if alerts.any?
      end

      def handle_display_error(error)
        display_message("\n❌ Display Error: #{error.message}", type: :error)
        display_message("   Continuing with status updates...", type: :info)
      end

      def basic_status
        {
          duration: @start_time ? Time.now - @start_time : 0,
          current_step: @current_step,
          current_provider: @current_provider,
          current_model: @current_model,
          status: @running ? :running : :stopped,
          start_time: @start_time,
          last_update: @last_update
        }
      end

      attr_reader :provider_status

      def performance_status
        @performance_metrics
      end

      def error_status
        @error_summary
      end

      attr_reader :circuit_breaker_status

      def token_status
        @token_usage
      end

      attr_reader :rate_limit_status

      attr_reader :recovery_status

      attr_reader :user_feedback_status

      attr_reader :work_completion_status

      def alerts
        @alert_manager.active_alerts
      end

      def calculate_step_duration
        return 0 unless @status_data[:step_start_time]
        Time.now - @status_data[:step_start_time]
      end

      def count_provider_switches
        @status_data[:provider_switch_count] || 0
      end

      def calculate_error_rate
        return 0 unless @error_summary[:error_summary]
        @error_summary[:error_summary][:error_rate] || 0
      end

      def format_status_as_text
        # Generate human-readable text format
        "Status report would be generated here"
      end

      def clear_display
        # Clear the current line using TTY::Cursor
        print_to_stderr(@cursor.clear_line, @cursor.column(1))
      end

      # Helper method to print to stderr with flush
      def print_to_stderr(*parts)
        parts.each { |part| $stderr.print part }
        $stderr.flush
      end

      def format_duration(seconds)
        return "0s" if seconds <= 0

        hours = (seconds / 3600).to_i
        minutes = ((seconds % 3600) / 60).to_i
        secs = (seconds % 60).to_i

        parts = []
        parts << "#{hours}h" if hours > 0
        parts << "#{minutes}m" if minutes > 0
        parts << "#{secs}s" if secs > 0 || parts.empty?

        parts.join(" ")
      end

      def format_percentage(value)
        return "0%" if value.nil? || value == 0
        "#{(value * 100).round(1)}%"
      end

      # Helper classes
      class StatusFormatter
        def initialize
          @formatters = {}
        end

        def format_status(status_data, format_type)
          case format_type
          when :compact
            format_compact_status(status_data)
          when :detailed
            format_detailed_status(status_data)
          when :json
            JSON.pretty_generate(status_data)
          else
            status_data.to_s
          end
        end

        private

        def format_compact_status(_status_data)
          "Compact status format"
        end

        def format_detailed_status(_status_data)
          "Detailed status format"
        end
      end

      class MetricsCalculator
        def initialize
          @calculators = {}
        end

        def calculate_metrics(raw_data)
          {
            throughput: calculate_throughput(raw_data),
            error_rate: calculate_error_rate(raw_data),
            availability: calculate_availability(raw_data),
            performance_score: calculate_performance_score(raw_data)
          }
        end

        private

        def calculate_throughput(_data)
          # Calculate requests per minute
          0
        end

        def calculate_error_rate(_data)
          # Calculate error rate
          0.0
        end

        def calculate_availability(_data)
          # Calculate availability percentage
          1.0
        end

        def calculate_performance_score(_data)
          # Calculate overall performance score
          0.95
        end
      end

      class AlertManager
        def initialize
          @alerts = []
          @alert_history = []
        end

        def process_alerts(alerts)
          alerts.each do |alert|
            @alerts << alert
            @alert_history << alert
          end
        end

        def active_alerts
          @alerts
        end

        def clear_alerts
          @alerts.clear
        end
      end

      class DisplayAnimator
        def initialize
          @animations = {}
        end

        def animate_status(status_type)
          case status_type
          when :loading
            animate_loading
          when :processing
            animate_processing
          when :waiting
            animate_waiting
          else
            ""
          end
        end

        private

        def animate_loading
          "Loading..."
        end

        def animate_processing
          "Processing..."
        end

        def animate_waiting
          "Waiting..."
        end
      end
    end
  end
end
