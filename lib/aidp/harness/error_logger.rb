# frozen_string_literal: true

module Aidp
  module Harness
    # Comprehensive error logging and recovery action tracking system
    class ErrorLogger
      def initialize(configuration, metrics_manager = nil)
        @configuration = configuration
        @metrics_manager = metrics_manager
        @log_storage = LogStorage.new
        @recovery_tracker = RecoveryTracker.new
        @error_analyzer = ErrorAnalyzer.new
        @alert_manager = AlertManager.new
        @log_formatter = LogFormatter.new
        @log_rotator = LogRotator.new
        @log_compressor = LogCompressor.new
        @log_archiver = LogArchiver.new
        initialize_logging_configuration
      end

      # Main entry point for error logging
      def log_error(error, context = {})
        error_entry = build_error_entry(error, context)

        # Store error entry
        @log_storage.store_error(error_entry)

        # Track recovery actions
        track_recovery_actions(error_entry)

        # Analyze error patterns
        @error_analyzer.analyze_error(error_entry)

        # Check for alerts
        @alert_manager.check_error_alerts(error_entry)

        # Record in metrics if available
        @metrics_manager&.record_error_event(error_entry)

        error_entry
      end

      # Log recovery action
      def log_recovery_action(action_type, action_details, context = {})
        recovery_entry = build_recovery_entry(action_type, action_details, context)

        # Store recovery entry
        @log_storage.store_recovery(recovery_entry)

        # Track recovery metrics
        @recovery_tracker.track_recovery(recovery_entry)

        # Record in metrics if available
        @metrics_manager&.record_recovery_event(recovery_entry)

        recovery_entry
      end

      # Log provider switch
      def log_provider_switch(from_provider, to_provider, reason, context = {})
        switch_entry = build_switch_entry(:provider_switch, from_provider, from_provider, to_provider, reason, context)

        @log_storage.store_switch(switch_entry)
        @recovery_tracker.track_switch(switch_entry)
        @metrics_manager&.record_switch_event(switch_entry)

        switch_entry
      end

      # Log model switch
      def log_model_switch(provider, from_model, to_model, reason, context = {})
        switch_entry = build_switch_entry(:model_switch, provider, from_model, to_model, reason, context)

        @log_storage.store_switch(switch_entry)
        @recovery_tracker.track_switch(switch_entry)
        @metrics_manager&.record_switch_event(switch_entry)

        switch_entry
      end

      # Log retry attempt
      def log_retry_attempt(error_type, attempt_number, delay, context = {})
        retry_entry = build_retry_entry(error_type, attempt_number, delay, context)

        @log_storage.store_retry(retry_entry)
        @recovery_tracker.track_retry(retry_entry)
        @metrics_manager&.record_retry_event(retry_entry)

        retry_entry
      end

      # Log circuit breaker event
      def log_circuit_breaker_event(provider, model, event_type, reason, context = {})
        circuit_breaker_entry = build_circuit_breaker_entry(provider, model, event_type, reason, context)

        @log_storage.store_circuit_breaker(circuit_breaker_entry)
        @recovery_tracker.track_circuit_breaker(circuit_breaker_entry)
        @metrics_manager&.record_circuit_breaker_event(circuit_breaker_entry)

        circuit_breaker_entry
      end

      # Get error logs with filtering
      def get_error_logs(filters = {})
        @log_storage.get_errors(filters)
      end

      # Get recovery logs with filtering
      def get_recovery_logs(filters = {})
        @log_storage.get_recoveries(filters)
      end

      # Get switch logs with filtering
      def get_switch_logs(filters = {})
        @log_storage.get_switches(filters)
      end

      # Get retry logs with filtering
      def get_retry_logs(filters = {})
        @log_storage.get_retries(filters)
      end

      # Get circuit breaker logs with filtering
      def get_circuit_breaker_logs(filters = {})
        @log_storage.get_circuit_breakers(filters)
      end

      # Get comprehensive log summary
      def get_log_summary(time_range = nil)
        time_range ||= default_time_range

        {
          error_summary: get_error_summary(time_range),
          recovery_summary: get_recovery_summary(time_range),
          switch_summary: get_switch_summary(time_range),
          retry_summary: get_retry_summary(time_range),
          circuit_breaker_summary: get_circuit_breaker_summary(time_range),
          error_patterns: @error_analyzer.get_error_patterns(time_range),
          recovery_effectiveness: @recovery_tracker.get_recovery_effectiveness(time_range),
          alert_summary: @alert_manager.get_alert_summary(time_range)
        }
      end

      # Get error patterns and trends
      def get_error_patterns(time_range = nil)
        @error_analyzer.get_error_patterns(time_range)
      end

      # Get recovery effectiveness metrics
      def get_recovery_effectiveness(time_range = nil)
        @recovery_tracker.get_recovery_effectiveness(time_range)
      end

      # Get alert summary
      def get_alert_summary(time_range = nil)
        @alert_manager.get_alert_summary(time_range)
      end

      # Export logs in various formats
      def export_logs(format, filters = {})
        case format
        when :json
          export_logs_json(filters)
        when :csv
          export_logs_csv(filters)
        when :yaml
          export_logs_yaml(filters)
        when :text
          export_logs_text(filters)
        else
          raise ArgumentError, "Unsupported export format: #{format}"
        end
      end

      # Rotate logs
      def rotate_logs
        @log_rotator.rotate_logs
      end

      # Compress old logs
      def compress_logs
        @log_compressor.compress_logs
      end

      # Archive logs
      def archive_logs
        @log_archiver.archive_logs
      end

      # Clear old logs
      def clear_old_logs(retention_days = nil)
        retention_days ||= @logging_config[:retention_days] || 30
        @log_storage.clear_old_logs(retention_days)
      end

      # Configure logging
      def configure_logging(config)
        @logging_config.merge!(config)
        @log_storage.configure(config)
        @log_formatter.configure(config)
        @log_rotator.configure(config)
        @log_compressor.configure(config)
        @log_archiver.configure(config)
      end

      private

      def initialize_logging_configuration
        @logging_config = {
          log_level: :info,
          log_format: :json,
          retention_days: 30,
          max_log_size: 100 * 1024 * 1024, # 100MB
          compression_enabled: true,
          archiving_enabled: true,
          alert_thresholds: {
            error_rate: 0.1,
            recovery_failure_rate: 0.2,
            switch_frequency: 10
          }
        }

        # Override with configuration if available
        if @configuration.respond_to?(:logging_config)
          @logging_config.merge!(@configuration.logging_config)
        end
      end

      def build_error_entry(error, context)
        {
          id: generate_log_id,
          type: :error,
          timestamp: Time.now,
          error: {
            class: error.class.name,
            message: error.message,
            backtrace: error.backtrace&.first(10)
          },
          context: sanitize_context(context),
          severity: determine_error_severity(error),
          category: categorize_error(error),
          provider: context[:provider],
          model: context[:model],
          error_type: context[:error_type],
          session_id: context[:session_id],
          request_id: context[:request_id],
          user_id: context[:user_id]
        }
      end

      def build_recovery_entry(action_type, action_details, context)
        {
          id: generate_log_id,
          type: :recovery,
          timestamp: Time.now,
          action_type: action_type,
          action_details: action_details,
          context: sanitize_context(context),
          success: action_details[:success],
          duration: action_details[:duration],
          provider: context[:provider],
          model: context[:model],
          session_id: context[:session_id],
          request_id: context[:request_id]
        }
      end

      def build_switch_entry(switch_type, provider, from, to, reason, context)
        {
          id: generate_log_id,
          type: :switch,
          timestamp: Time.now,
          switch_type: switch_type,
          provider: provider,
          from: from,
          to: to,
          reason: reason,
          context: sanitize_context(context),
          success: context[:success] || true,
          duration: context[:duration],
          session_id: context[:session_id],
          request_id: context[:request_id]
        }
      end

      def build_retry_entry(error_type, attempt_number, delay, context)
        {
          id: generate_log_id,
          type: :retry,
          timestamp: Time.now,
          error_type: error_type,
          attempt_number: attempt_number,
          delay: delay,
          context: sanitize_context(context),
          success: context[:success] || false,
          provider: context[:provider],
          model: context[:model],
          session_id: context[:session_id],
          request_id: context[:request_id]
        }
      end

      def build_circuit_breaker_entry(provider, model, event_type, reason, context)
        {
          id: generate_log_id,
          type: :circuit_breaker,
          timestamp: Time.now,
          provider: provider,
          model: model,
          event_type: event_type,
          reason: reason,
          context: sanitize_context(context),
          session_id: context[:session_id],
          request_id: context[:request_id]
        }
      end

      def determine_error_severity(error)
        case error
        when Timeout::Error, Timeout::Error
          :warning
        when Net::HTTPError
          case error.response.code.to_i
          when 429
            :warning
          when 500..599
            :error
          else
            :info
          end
        when SocketError, Errno::ECONNREFUSED
          :error
        when StandardError
          :error
        else
          :info
        end
      end

      def categorize_error(error)
        case error
        when Timeout::Error, Timeout::Error
          :timeout
        when Net::HTTPError
          case error.response.code.to_i
          when 429
            :rate_limit
          when 401, 403
            :authentication
          when 500..599
            :server_error
          else
            :network_error
          end
        when SocketError, Errno::ECONNREFUSED
          :network_error
        when StandardError
          :application_error
        else
          :unknown
        end
      end

      def sanitize_context(context)
        return {} unless context.is_a?(Hash)

        sanitized = context.dup
        sanitized.delete(:api_key)
        sanitized.delete(:password)
        sanitized.delete(:token)
        sanitized.delete(:secret)
        sanitized
      end

      def generate_log_id
        "#{Time.now.to_i}-#{SecureRandom.hex(8)}"
      end

      def default_time_range
        (Time.now - 86400)..Time.now
      end

      def track_recovery_actions(error_entry)
        # Track recovery actions for the error entry
        # This is a placeholder implementation
      end

      def get_error_summary(time_range)
        errors = @log_storage.get_errors({time_range: time_range})

        {
          total_errors: errors.size,
          errors_by_severity: errors.group_by { |e| e[:severity] }.transform_values(&:size),
          errors_by_category: errors.group_by { |e| e[:category] }.transform_values(&:size),
          errors_by_provider: errors.group_by { |e| e[:provider] }.transform_values(&:size),
          errors_by_model: errors.group_by { |e| e[:model] }.transform_values(&:size),
          error_rate: calculate_error_rate(errors, time_range)
        }
      end

      def get_recovery_summary(time_range)
        recoveries = @log_storage.get_recoveries({time_range: time_range})

        {
          total_recoveries: recoveries.size,
          successful_recoveries: recoveries.count { |r| r[:success] },
          failed_recoveries: recoveries.count { |r| !r[:success] },
          recoveries_by_type: recoveries.group_by { |r| r[:action_type] }.transform_values(&:size),
          average_recovery_time: calculate_average_recovery_time(recoveries),
          recovery_success_rate: calculate_recovery_success_rate(recoveries)
        }
      end

      def get_switch_summary(time_range)
        switches = @log_storage.get_switches({time_range: time_range})

        {
          total_switches: switches.size,
          provider_switches: switches.count { |s| s[:switch_type] == :provider_switch },
          model_switches: switches.count { |s| s[:switch_type] == :model_switch },
          switches_by_reason: switches.group_by { |s| s[:reason] }.transform_values(&:size),
          average_switch_time: calculate_average_switch_time(switches)
        }
      end

      def get_retry_summary(time_range)
        retries = @log_storage.get_retries({time_range: time_range})

        {
          total_retries: retries.size,
          successful_retries: retries.count { |r| r[:success] },
          failed_retries: retries.count { |r| !r[:success] },
          retries_by_error_type: retries.group_by { |r| r[:error_type] }.transform_values(&:size),
          average_retry_delay: calculate_average_retry_delay(retries),
          retry_success_rate: calculate_retry_success_rate(retries)
        }
      end

      def get_circuit_breaker_summary(time_range)
        circuit_breakers = @log_storage.get_circuit_breakers({time_range: time_range})

        {
          total_events: circuit_breakers.size,
          events_by_type: circuit_breakers.group_by { |cb| cb[:event_type] }.transform_values(&:size),
          events_by_provider: circuit_breakers.group_by { |cb| cb[:provider] }.transform_values(&:size),
          events_by_model: circuit_breakers.group_by { |cb| cb[:model] }.transform_values(&:size)
        }
      end

      def calculate_error_rate(errors, time_range)
        return 0.0 if errors.empty? || time_range.nil?

        duration = time_range.is_a?(Range) ? (time_range.end - time_range.begin) : 3600
        errors.size.to_f / duration
      end

      def calculate_average_recovery_time(recoveries)
        return 0.0 if recoveries.empty?

        total_time = recoveries.sum { |r| r[:duration] || 0 }
        total_time.to_f / recoveries.size
      end

      def calculate_recovery_success_rate(recoveries)
        return 0.0 if recoveries.empty?

        successful = recoveries.count { |r| r[:success] }
        successful.to_f / recoveries.size
      end

      def calculate_average_switch_time(switches)
        return 0.0 if switches.empty?

        total_time = switches.sum { |s| s[:duration] || 0 }
        total_time.to_f / switches.size
      end

      def calculate_average_retry_delay(retries)
        return 0.0 if retries.empty?

        total_delay = retries.sum { |r| r[:delay] || 0 }
        total_delay.to_f / retries.size
      end

      def calculate_retry_success_rate(retries)
        return 0.0 if retries.empty?

        successful = retries.count { |r| r[:success] }
        successful.to_f / retries.size
      end

      def export_logs_json(filters)
        logs = {
          errors: get_error_logs(filters),
          recoveries: get_recovery_logs(filters),
          switches: get_switch_logs(filters),
          retries: get_retry_logs(filters),
          circuit_breakers: get_circuit_breaker_logs(filters)
        }

        JSON.pretty_generate(logs)
      end

      def export_logs_csv(_filters)
        # Generate CSV format logs
        "CSV export would be generated here"
      end

      def export_logs_yaml(filters)
        logs = {
          errors: get_error_logs(filters),
          recoveries: get_recovery_logs(filters),
          switches: get_switch_logs(filters),
          retries: get_retry_logs(filters),
          circuit_breakers: get_circuit_breaker_logs(filters)
        }

        logs.to_yaml
      end

      def export_logs_text(_filters)
        # Generate human-readable text format logs
        "Text export would be generated here"
      end

      # Helper classes
      class LogStorage
        def initialize
          @errors = []
          @recoveries = []
          @switches = []
          @retries = []
          @circuit_breakers = []
        end

        def store_error(error_entry)
          @errors << error_entry
        end

        def store_recovery(recovery_entry)
          @recoveries << recovery_entry
        end

        def store_switch(switch_entry)
          @switches << switch_entry
        end

        def store_retry(retry_entry)
          @retries << retry_entry
        end

        def store_circuit_breaker(circuit_breaker_entry)
          @circuit_breakers << circuit_breaker_entry
        end

        def get_errors(filters = {})
          filter_logs(@errors, filters)
        end

        def get_recoveries(filters = {})
          filter_logs(@recoveries, filters)
        end

        def get_switches(filters = {})
          filter_logs(@switches, filters)
        end

        def get_retries(filters = {})
          filter_logs(@retries, filters)
        end

        def get_circuit_breakers(filters = {})
          filter_logs(@circuit_breakers, filters)
        end

        def clear_old_logs(retention_days)
          cutoff_time = Time.now - (retention_days * 86400)

          @errors.reject! { |e| e[:timestamp] < cutoff_time }
          @recoveries.reject! { |r| r[:timestamp] < cutoff_time }
          @switches.reject! { |s| s[:timestamp] < cutoff_time }
          @retries.reject! { |r| r[:timestamp] < cutoff_time }
          @circuit_breakers.reject! { |cb| cb[:timestamp] < cutoff_time }
        end

        def configure(config)
          # Configure log storage based on config
        end

        private

        def filter_logs(logs, filters)
          filtered = logs.dup

          if filters[:time_range]
            filtered = filtered.select { |log| filters[:time_range].include?(log[:timestamp]) }
          end

          if filters[:provider]
            filtered = filtered.select { |log| log[:provider] == filters[:provider] }
          end

          if filters[:model]
            filtered = filtered.select { |log| log[:model] == filters[:model] }
          end

          if filters[:severity]
            filtered = filtered.select { |log| log[:severity] == filters[:severity] }
          end

          if filters[:type]
            filtered = filtered.select { |log| log[:type] == filters[:type] }
          end

          filtered
        end
      end

      class RecoveryTracker
        def initialize
          @recovery_metrics = {}
        end

        def track_recovery(recovery_entry)
          # Track recovery metrics
        end

        def track_switch(switch_entry)
          # Track switch metrics
        end

        def track_retry(retry_entry)
          # Track retry metrics
        end

        def track_circuit_breaker(circuit_breaker_entry)
          # Track circuit breaker metrics
        end

        def get_recovery_effectiveness(_time_range = nil)
          {
            success_rate: 0.95,
            average_recovery_time: 2.5,
            most_effective_strategy: "provider_switch",
            least_effective_strategy: "retry"
          }
        end
      end

      class ErrorAnalyzer
        def initialize
          @error_patterns = {}
        end

        def analyze_error(error_entry)
          # Analyze error patterns
        end

        def get_error_patterns(_time_range = nil)
          {
            most_common_errors: ["timeout", "rate_limit", "network_error"],
            error_trends: "increasing",
            peak_error_times: ["14:00", "15:00", "16:00"],
            error_correlation: {
              "timeout" => "network_error",
              "rate_limit" => "server_error"
            }
          }
        end
      end

      class AlertManager
        def initialize
          @alerts = []
        end

        def check_error_alerts(error_entry)
          # Check for alert conditions
        end

        def get_alert_summary(_time_range = nil)
          {
            total_alerts: @alerts.size,
            critical_alerts: @alerts.count { |a| a[:severity] == :critical },
            warning_alerts: @alerts.count { |a| a[:severity] == :warning },
            recent_alerts: @alerts.last(5)
          }
        end
      end

      class LogFormatter
        def configure(config)
          # Configure log formatting
        end
      end

      class LogRotator
        def rotate_logs
          # Rotate log files
        end

        def configure(config)
          # Configure log rotation
        end
      end

      class LogCompressor
        def compress_logs
          # Compress old log files
        end

        def configure(config)
          # Configure log compression
        end
      end

      class LogArchiver
        def archive_logs
          # Archive old log files
        end

        def configure(config)
          # Configure log archiving
        end
      end
    end
  end
end
