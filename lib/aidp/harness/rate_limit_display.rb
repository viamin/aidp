# frozen_string_literal: true

module Aidp
  module Harness
    # Comprehensive rate limit countdown and status display system
    class RateLimitDisplay
      def initialize(provider_manager, status_display, rate_limit_manager)
        @provider_manager = provider_manager
        @status_display = status_display
        @rate_limit_manager = rate_limit_manager

        @rate_limits = {}
        @countdown_timers = {}
        @rate_limit_history = []
        @display_config = {
          update_interval: 1, # seconds
          show_countdown: true,
          show_provider_info: true,
          show_model_info: true,
          show_quota_info: true,
          show_retry_info: true,
          show_switch_info: true,
          compact_mode: false,
          color_enabled: true,
          sound_enabled: false
        }
        @display_formatters = initialize_display_formatters
        @countdown_managers = initialize_countdown_managers
        @status_managers = initialize_status_managers
        @alert_managers = initialize_alert_managers
        @export_managers = initialize_export_managers
        @optimization_engines = initialize_optimization_engines
        @max_history_size = 1000
        @last_update = Time.now
        @display_thread = nil
        @display_running = false
      end

      # Start rate limit display
      def start_display
        return if @display_running

        @display_running = true
        @start_time = Time.now
        @display_thread = Thread.new { display_loop }

        {
          status: :started,
          update_interval: @display_config[:update_interval],
          features: get_enabled_features
        }
      end

      # Stop rate limit display
      def stop_display
        return unless @display_running

        @display_running = false
        @display_thread&.join(2) # Wait up to 2 seconds for thread to finish

        {
          status: :stopped,
          display_duration: calculate_display_duration
        }
      end

      # Update rate limit information
      def update_rate_limit(provider, model, rate_limit_info)
        key = "#{provider}:#{model}"

        @rate_limits[key] = {
          provider: provider,
          model: model,
          rate_limited: rate_limit_info[:rate_limited] || false,
          limit_type: rate_limit_info[:limit_type] || :requests_per_minute,
          current_count: rate_limit_info[:current_count] || 0,
          limit: rate_limit_info[:limit] || 0,
          reset_time: rate_limit_info[:reset_time],
          retry_after: rate_limit_info[:retry_after],
          quota_used: rate_limit_info[:quota_used] || 0,
          quota_limit: rate_limit_info[:quota_limit] || 0,
          window_start: rate_limit_info[:window_start] || Time.now,
          window_duration: rate_limit_info[:window_duration] || 60,
          last_updated: Time.now,
          status: determine_rate_limit_status(rate_limit_info)
        }

        # Initialize countdown timer if rate limited
        if @rate_limits[key][:rate_limited]
          initialize_countdown_timer(key, rate_limit_info)
        end

        # Add to history
        add_to_history(key, rate_limit_info)

        # Update status display
        update_status_display

        # Return updated rate limit info
        get_rate_limit_info(provider, model)
      end

      # Get rate limit information
      def get_rate_limit_info(provider, model)
        key = "#{provider}:#{model}"
        rate_limit = @rate_limits[key]

        return nil unless rate_limit

        {
          provider: rate_limit[:provider],
          model: rate_limit[:model],
          rate_limited: rate_limit[:rate_limited],
          limit_type: rate_limit[:limit_type],
          current_count: rate_limit[:current_count],
          limit: rate_limit[:limit],
          reset_time: rate_limit[:reset_time],
          retry_after: rate_limit[:retry_after],
          quota_used: rate_limit[:quota_used],
          quota_limit: rate_limit[:quota_limit],
          window_start: rate_limit[:window_start],
          window_duration: rate_limit[:window_duration],
          last_updated: rate_limit[:last_updated],
          status: rate_limit[:status],
          countdown: get_countdown_info(key),
          usage_percentage: calculate_usage_percentage(rate_limit),
          time_until_reset: calculate_time_until_reset(rate_limit),
          estimated_reset_time: estimate_reset_time(rate_limit)
        }
      end

      # Get all rate limit information
      def get_all_rate_limits
        @rate_limits.transform_values do |rate_limit|
          get_rate_limit_info(rate_limit[:provider], rate_limit[:model])
        end
      end

      # Get rate limit status summary
      def get_rate_limit_summary
        {
          total_providers: @rate_limits.keys.map { |k| k.split(':').first }.uniq.size,
          total_models: @rate_limits.size,
          rate_limited_count: @rate_limits.values.count { |rl| rl[:rate_limited] },
          active_countdowns: @countdown_timers.size,
          overall_status: determine_overall_status,
          critical_limits: get_critical_limits,
          upcoming_resets: get_upcoming_resets,
          quota_status: get_quota_status_summary,
          last_update: @last_update
        }
      end

      # Display rate limit information
      def display_rate_limits(format = :compact, provider = nil, model = nil)
        formatter = @display_formatters[format]

        if provider && model
          rate_limit_info = get_rate_limit_info(provider, model)
          formatter.format_single_rate_limit(rate_limit_info, @display_config)
        else
          all_limits = get_all_rate_limits
          formatter.format_all_rate_limits(all_limits, @display_config)
        end
      end

      # Get countdown information
      def get_countdown_info(key)
        timer = @countdown_timers[key]
        return nil unless timer

        {
          start_time: timer[:start_time],
          end_time: timer[:end_time],
          duration: timer[:duration],
          remaining_time: calculate_remaining_time(timer),
          progress: calculate_countdown_progress(timer),
          status: timer[:status],
          alerts_sent: timer[:alerts_sent] || []
        }
      end

      # Get rate limit history
      def get_rate_limit_history(provider = nil, model = nil, limit = 100)
        history = @rate_limit_history.dup

        # Filter by provider
        if provider
          history = history.select { |entry| entry[:provider] == provider }
        end

        # Filter by model
        if model
          history = history.select { |entry| entry[:model] == model }
        end

        # Limit results
        history.last(limit)
      end

      # Export rate limit data
      def export_rate_limit_data(format = :json, options = {})
        exporter = @export_managers[format]
        exporter.export_data(self, options)
      end

      # Configure display settings
      def configure_display(settings)
        @display_config.merge!(settings)

        {
          status: :configured,
          settings: @display_config
        }
      end

      # Get display configuration
      def get_display_config
        @display_config.dup
      end

      # Get enabled features
      def get_enabled_features
        {
          countdown: @display_config[:show_countdown],
          provider_info: @display_config[:show_provider_info],
          model_info: @display_config[:show_model_info],
          quota_info: @display_config[:show_quota_info],
          retry_info: @display_config[:show_retry_info],
          switch_info: @display_config[:show_switch_info],
          compact_mode: @display_config[:compact_mode],
          color_enabled: @display_config[:color_enabled],
          sound_enabled: @display_config[:sound_enabled]
        }
      end

      # Clear rate limit history
      def clear_rate_limit_history
        @rate_limit_history.clear
      end

      # Get rate limit statistics
      def get_rate_limit_statistics
        {
          total_entries: @rate_limit_history.size,
          providers_tracked: @rate_limits.keys.map { |k| k.split(':').first }.uniq.size,
          models_tracked: @rate_limits.size,
          active_countdowns: @countdown_timers.size,
          rate_limited_count: @rate_limits.values.count { |rl| rl[:rate_limited] },
          last_update: @last_update,
          history_size_limit: @max_history_size,
          display_running: @display_running
        }
      end

      private

      def initialize_display_formatters
        {
          compact: CompactRateLimitFormatter.new,
          detailed: DetailedRateLimitFormatter.new,
          realtime: RealtimeRateLimitFormatter.new,
          summary: SummaryRateLimitFormatter.new,
          json: JsonRateLimitFormatter.new
        }
      end

      def initialize_countdown_managers
        {
          default: CountdownManager.new,
          provider: ProviderCountdownManager.new,
          model: ModelCountdownManager.new
        }
      end

      def initialize_status_managers
        {
          default: StatusManager.new,
          provider: ProviderStatusManager.new,
          model: ModelStatusManager.new
        }
      end

      def initialize_alert_managers
        {
          countdown: CountdownAlertManager.new,
          quota: QuotaAlertManager.new,
          reset: ResetAlertManager.new,
          critical: CriticalAlertManager.new
        }
      end

      def initialize_export_managers
        {
          json: RateLimitJsonExporter.new,
          yaml: RateLimitYamlExporter.new,
          csv: RateLimitCsvExporter.new,
          text: RateLimitTextExporter.new
        }
      end

      def initialize_optimization_engines
        {
          default: RateLimitOptimizer.new,
          display: DisplayOptimizer.new,
          performance: PerformanceOptimizer.new
        }
      end

      def display_loop
        while @display_running
          begin
            update_display
            sleep(@display_config[:update_interval])
          rescue => e
            # Log error but continue display loop
            puts "Rate limit display error: #{e.message}"
            sleep(1)
          end
        end
      end

      def update_display
        @last_update = Time.now

        # Update countdown timers
        update_countdown_timers

        # Update status display
        update_status_display

        # Check for alerts
        check_alerts
      end

      def update_countdown_timers
        @countdown_timers.each do |key, timer|
          if timer[:end_time] && Time.now >= timer[:end_time]
            # Countdown finished
            timer[:status] = :completed
            handle_countdown_completion(key)
          else
            # Update countdown progress
            timer[:progress] = calculate_countdown_progress(timer)
            timer[:remaining_time] = calculate_remaining_time(timer)
          end
        end
      end

      def update_status_display
        return unless @status_display

        # Update status display with current rate limit information
        summary = get_rate_limit_summary
        @status_display.update_rate_limit_status(summary)
      end

      def check_alerts
        @alert_managers.each do |_type, alert_manager|
          alerts = alert_manager.check_alerts(@rate_limits, @countdown_timers)
          alerts.each { |alert| handle_alert(alert) }
        end
      end

      def handle_alert(alert)
        # Handle different types of alerts
        case alert[:type]
        when :countdown_warning
          handle_countdown_warning(alert)
        when :quota_warning
          handle_quota_warning(alert)
        when :reset_notification
          handle_reset_notification(alert)
        when :critical_limit
          handle_critical_limit(alert)
        end
      end

      def handle_countdown_warning(alert)
        # Handle countdown warning alerts
        puts "Rate limit countdown warning: #{alert[:message]}" if @display_config[:show_countdown]
      end

      def handle_quota_warning(alert)
        # Handle quota warning alerts
        puts "Quota warning: #{alert[:message]}" if @display_config[:show_quota_info]
      end

      def handle_reset_notification(alert)
        # Handle reset notification alerts
        puts "Rate limit reset: #{alert[:message]}" if @display_config[:show_retry_info]
      end

      def handle_critical_limit(alert)
        # Handle critical limit alerts
        puts "Critical rate limit: #{alert[:message]}"
      end

      def initialize_countdown_timer(key, rate_limit_info)
        reset_time = rate_limit_info[:reset_time]
        retry_after = rate_limit_info[:retry_after]

        end_time = if reset_time
                     reset_time
                   elsif retry_after
                     Time.now + retry_after
                   else
                     Time.now + 60 # Default 1 minute
                   end

        @countdown_timers[key] = {
          start_time: Time.now,
          end_time: end_time,
          duration: end_time - Time.now,
          progress: 0.0,
          remaining_time: end_time - Time.now,
          status: :active,
          alerts_sent: []
        }
      end

      def handle_countdown_completion(key)
        # Handle countdown completion
        _provider, _model = key.split(':')

        # Remove from countdown timers
        @countdown_timers.delete(key)

        # Update rate limit status
        if @rate_limits[key]
          @rate_limits[key][:rate_limited] = false
          @rate_limits[key][:status] = :available
        end

        # Notify status display
        update_status_display
      end

      def add_to_history(key, rate_limit_info)
        provider, model = key.split(':')

        entry = {
          timestamp: Time.now,
          provider: provider,
          model: model,
          rate_limited: rate_limit_info[:rate_limited] || false,
          limit_type: rate_limit_info[:limit_type] || :requests_per_minute,
          current_count: rate_limit_info[:current_count] || 0,
          limit: rate_limit_info[:limit] || 0,
          reset_time: rate_limit_info[:reset_time],
          retry_after: rate_limit_info[:retry_after],
          quota_used: rate_limit_info[:quota_used] || 0,
          quota_limit: rate_limit_info[:quota_limit] || 0
        }

        @rate_limit_history << entry

        # Maintain history size limit
        if @rate_limit_history.size > @max_history_size
          @rate_limit_history.shift(@rate_limit_history.size - @max_history_size)
        end
      end

      def determine_rate_limit_status(rate_limit_info)
        if rate_limit_info[:rate_limited]
          :rate_limited
        elsif rate_limit_info[:quota_used] && rate_limit_info[:quota_limit]
          usage_percentage = (rate_limit_info[:quota_used].to_f / rate_limit_info[:quota_limit] * 100)
          if usage_percentage >= 90
            :critical
          elsif usage_percentage >= 75
            :warning
          else
            :available
          end
        else
          :available
        end
      end

      def determine_overall_status
        if @rate_limits.values.any? { |rl| rl[:status] == :critical }
          :critical
        elsif @rate_limits.values.any? { |rl| rl[:status] == :warning }
          :warning
        elsif @rate_limits.values.any? { |rl| rl[:rate_limited] }
          :rate_limited
        else
          :available
        end
      end

      def get_critical_limits
        @rate_limits.select { |_key, rate_limit| rate_limit[:status] == :critical }
      end

      def get_upcoming_resets
        @rate_limits.select { |_key, rate_limit| rate_limit[:reset_time] && rate_limit[:reset_time] > Time.now }
                   .sort_by { |_key, rate_limit| rate_limit[:reset_time] }
      end

      def get_quota_status_summary
        quota_info = {}

        @rate_limits.each do |key, rate_limit|
          if rate_limit[:quota_used] && rate_limit[:quota_limit]
            usage_percentage = (rate_limit[:quota_used].to_f / rate_limit[:quota_limit] * 100)
            quota_info[key] = {
              used: rate_limit[:quota_used],
              limit: rate_limit[:quota_limit],
              percentage: usage_percentage,
              status: usage_percentage >= 90 ? :critical : usage_percentage >= 75 ? :warning : :available
            }
          end
        end

        quota_info
      end

      def calculate_usage_percentage(rate_limit)
        return 0.0 unless rate_limit[:limit] > 0

        (rate_limit[:current_count].to_f / rate_limit[:limit] * 100).round(2)
      end

      def calculate_time_until_reset(rate_limit)
        return nil unless rate_limit[:reset_time]

        remaining = rate_limit[:reset_time] - Time.now
        [remaining, 0].max
      end

      def estimate_reset_time(rate_limit)
        return nil unless rate_limit[:reset_time]

        rate_limit[:reset_time]
      end

      def calculate_remaining_time(timer)
        return 0 unless timer[:end_time]

        remaining = timer[:end_time] - Time.now
        [remaining, 0].max
      end

      def calculate_countdown_progress(timer)
        return 1.0 unless timer[:duration] && timer[:duration] > 0

        elapsed = Time.now - timer[:start_time]
        progress = elapsed / timer[:duration]
        [progress, 1.0].min
      end

      def calculate_display_duration
        return 0 unless @display_thread && @start_time

        Time.now - @start_time
      end

      # Helper classes
      class CompactRateLimitFormatter
        def format_single_rate_limit(rate_limit_info, _config)
          return "No rate limit information available" unless rate_limit_info

          if rate_limit_info[:rate_limited]
            remaining = rate_limit_info[:time_until_reset]
            "Rate limited: #{remaining ? "#{remaining.to_i}s remaining" : 'Unknown'}"
          else
            usage = rate_limit_info[:usage_percentage]
            "Available: #{usage ? "#{usage}% used" : 'No usage data'}"
          end
        end

        def format_all_rate_limits(all_limits, _config)
          return "No rate limit information available" if all_limits.empty?

          lines = ["Rate Limit Status:"]
          all_limits.each do |_key, rate_limit|
            lines << "  #{rate_limit[:provider]}:#{rate_limit[:model]}: #{format_single_rate_limit(rate_limit, {})}"
          end
          lines.join("\n")
        end
      end

      class DetailedRateLimitFormatter
        def format_single_rate_limit(rate_limit_info, _config)
          return "No rate limit information available" unless rate_limit_info

          lines = [
            "Provider: #{rate_limit_info[:provider]}",
            "Model: #{rate_limit_info[:model]}",
            "Status: #{rate_limit_info[:status]}",
            "Rate Limited: #{rate_limit_info[:rate_limited]}",
            "Limit Type: #{rate_limit_info[:limit_type]}",
            "Current Count: #{rate_limit_info[:current_count]}",
            "Limit: #{rate_limit_info[:limit]}",
            "Usage: #{rate_limit_info[:usage_percentage]}%"
          ]

          if rate_limit_info[:rate_limited]
            lines << "Reset Time: #{rate_limit_info[:reset_time]}"
            lines << "Time Until Reset: #{rate_limit_info[:time_until_reset]}s"
          end

          if rate_limit_info[:quota_used] && rate_limit_info[:quota_limit]
            lines << "Quota Used: #{rate_limit_info[:quota_used]}"
            lines << "Quota Limit: #{rate_limit_info[:quota_limit]}"
          end

          lines.join("\n")
        end

        def format_all_rate_limits(all_limits, _config)
          return "No rate limit information available" if all_limits.empty?

          lines = ["Detailed Rate Limit Status:"]
          all_limits.each do |_key, rate_limit|
            lines << format_single_rate_limit(rate_limit, {})
            lines << "---"
          end
          lines.join("\n")
        end
      end

      class RealtimeRateLimitFormatter
        def format_single_rate_limit(rate_limit_info, _config)
          return "No rate limit information available" unless rate_limit_info

          if rate_limit_info[:rate_limited]
            remaining = rate_limit_info[:time_until_reset]
            "🔴 Rate Limited: #{remaining ? "#{remaining.to_i}s" : 'Unknown'} remaining"
          else
            usage = rate_limit_info[:usage_percentage]
            status_icon = usage && usage >= 75 ? "🟡" : "🟢"
            "#{status_icon} Available: #{usage ? "#{usage}% used" : 'No usage data'}"
          end
        end

        def format_all_rate_limits(all_limits, _config)
          return "No rate limit information available" if all_limits.empty?

          lines = ["🔄 Real-time Rate Limit Status:"]
          all_limits.each do |_key, rate_limit|
            lines << "  #{format_single_rate_limit(rate_limit, {})}"
          end
          lines.join("\n")
        end
      end

      class SummaryRateLimitFormatter
        def format_single_rate_limit(rate_limit_info, _config)
          return "No rate limit information available" unless rate_limit_info

          summary = "#{rate_limit_info[:provider]}:#{rate_limit_info[:model]}"

          if rate_limit_info[:rate_limited]
            remaining = rate_limit_info[:time_until_reset]
            summary += " - Rate Limited (#{remaining ? "#{remaining.to_i}s" : 'Unknown'} remaining)"
          else
            usage = rate_limit_info[:usage_percentage]
            summary += " - Available"
            summary += " (#{usage}% used)" if usage
          end

          summary
        end

        def format_all_rate_limits(all_limits, _config)
          return "No rate limit information available" if all_limits.empty?

          lines = ["Rate Limit Summary:"]
          all_limits.each do |_key, rate_limit|
            lines << "  #{format_single_rate_limit(rate_limit, {})}"
          end
          lines.join("\n")
        end
      end

      class JsonRateLimitFormatter
        def format_single_rate_limit(rate_limit_info, _config)
          return "{}" unless rate_limit_info

          JSON.pretty_generate(rate_limit_info)
        end

        def format_all_rate_limits(all_limits, _config)
          JSON.pretty_generate(all_limits)
        end
      end

      class CountdownManager
        def manage_countdown(_timer_info)
          {
            status: :active,
            progress: 0.0,
            remaining_time: 0
          }
        end
      end

      class ProviderCountdownManager < CountdownManager
        def manage_countdown(timer_info)
          super.merge({
            provider: timer_info[:provider],
            provider_status: :active
          })
        end
      end

      class ModelCountdownManager < CountdownManager
        def manage_countdown(timer_info)
          super.merge({
            model: timer_info[:model],
            model_status: :active
          })
        end
      end

      class StatusManager
        def manage_status(_rate_limit_info)
          {
            status: :available,
            priority: :normal,
            actions: []
          }
        end
      end

      class ProviderStatusManager < StatusManager
        def manage_status(rate_limit_info)
          super.merge({
            provider: rate_limit_info[:provider],
            provider_actions: []
          })
        end
      end

      class ModelStatusManager < StatusManager
        def manage_status(rate_limit_info)
          super.merge({
            model: rate_limit_info[:model],
            model_actions: []
          })
        end
      end

      class CountdownAlertManager
        def check_alerts(_rate_limits, _countdown_timers)
          [] # No alerts for now
        end
      end

      class QuotaAlertManager
        def check_alerts(_rate_limits, _countdown_timers)
          [] # No alerts for now
        end
      end

      class ResetAlertManager
        def check_alerts(_rate_limits, _countdown_timers)
          [] # No alerts for now
        end
      end

      class CriticalAlertManager
        def check_alerts(_rate_limits, _countdown_timers)
          [] # No alerts for now
        end
      end

      class RateLimitJsonExporter
        def export_data(display, _options = {})
          JSON.pretty_generate(display.get_all_rate_limits)
        end
      end

      class RateLimitYamlExporter
        def export_data(display, _options = {})
          display.get_all_rate_limits.to_yaml
        end
      end

      class RateLimitCsvExporter
        def export_data(_display, _options = {})
          "CSV export would be implemented here"
        end
      end

      class RateLimitTextExporter
        def export_data(_display, _options = {})
          "Text export would be implemented here"
        end
      end

      class RateLimitOptimizer
        def optimize_display(_display)
          {
            optimizations: ["Rate limit display optimizations applied"],
            recommendations: []
          }
        end
      end

      class DisplayOptimizer < RateLimitOptimizer
        def optimize_display(display)
          super.merge({
            display_optimizations: []
          })
        end
      end

      class PerformanceOptimizer < RateLimitOptimizer
        def optimize_display(display)
          super.merge({
            performance_optimizations: []
          })
        end
      end
    end
  end
end
