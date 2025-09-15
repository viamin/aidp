# frozen_string_literal: true

require_relative "base"
require_relative "job_monitor"
require_relative "job_progress_display"
require_relative "job_filter"
require_relative "job_history"
require_relative "job_error_handler"
require_relative "job_metrics"
require_relative "frame_manager"

module Aidp
  module Harness
    module UI
      # Job monitoring dashboard interface
      class JobDashboard < Base
        class DashboardError < StandardError; end
        class DisplayError < DashboardError; end

        def initialize(ui_components = {})
          super()
          @job_monitor = ui_components[:job_monitor] || JobMonitor.new
          @progress_display = ui_components[:progress_display] || JobProgressDisplay.new
          @job_filter = ui_components[:job_filter] || JobFilter.new
          @job_history = ui_components[:job_history] || JobHistory.new
          @error_handler = ui_components[:error_handler] || JobErrorHandler.new
          @job_metrics = ui_components[:job_metrics] || JobMetrics.new
          @frame_manager = ui_components[:frame_manager] || FrameManager.new
          @formatter = ui_components[:formatter] || JobDashboardFormatter.new

          @dashboard_active = false
          @refresh_interval = 2.0
          @refresh_thread = nil
          @current_view = :overview
          @dashboard_state = {}
        end

        def start_dashboard
          return if @dashboard_active

          @dashboard_active = true
          @job_monitor.start_monitoring
          start_dashboard_refresh

          CLI::UI.puts(@formatter.format_dashboard_started)
        rescue => e
          raise DashboardError, "Failed to start dashboard: #{e.message}"
        end

        def stop_dashboard
          return unless @dashboard_active

          @dashboard_active = false
          stop_dashboard_refresh
          @job_monitor.stop_monitoring

          CLI::UI.puts(@formatter.format_dashboard_stopped)
        end

        def display_dashboard(view = :overview)
          validate_view(view)
          @current_view = view

          case view
          when :overview
            display_overview
          when :jobs
            display_jobs_view
          when :metrics
            display_metrics_view
          when :errors
            display_errors_view
          when :history
            display_history_view
          when :settings
            display_settings_view
          else
            display_overview
          end
        end

        def handle_dashboard_input(input)
          return unless @dashboard_active

          case input.downcase
          when "overview", "o"
            display_dashboard(:overview)
          when "jobs", "j"
            display_dashboard(:jobs)
          when "metrics", "m"
            display_dashboard(:metrics)
          when "errors", "e"
            display_dashboard(:errors)
          when "history", "h"
            display_dashboard(:history)
          when "settings", "s"
            display_dashboard(:settings)
          when "help", "?"
            display_help
          when "quit", "q"
            handle_quit
          when "refresh", "r"
            display_dashboard(@current_view)
          else
            CLI::UI.puts(@formatter.format_unknown_command(input))
          end
        end

        def set_refresh_interval(interval_seconds)
          validate_refresh_interval(interval_seconds)
          @refresh_interval = interval_seconds
          CLI::UI.puts(@formatter.format_refresh_interval_set(interval_seconds))
        end

        def get_dashboard_state
          {
            active: @dashboard_active,
            current_view: @current_view,
            refresh_interval: @refresh_interval,
            monitoring_active: @job_monitor.get_monitoring_summary[:monitoring_active]
          }
        end

        private

        def validate_view(view)
          valid_views = [:overview, :jobs, :metrics, :errors, :history, :settings]
          unless valid_views.include?(view)
            raise DisplayError, "Invalid view: #{view}. Must be one of: #{valid_views.join(", ")}"
          end
        end

        def validate_refresh_interval(interval_seconds)
          raise DashboardError, "Refresh interval must be positive" unless interval_seconds > 0
        end

        def start_dashboard_refresh
          @refresh_thread = Thread.new do
            dashboard_refresh_loop
          end
        end

        def stop_dashboard_refresh
          @refresh_thread&.kill
          @refresh_thread = nil
        end

        def dashboard_refresh_loop
          loop do
            break unless @dashboard_active

            begin
              refresh_current_view
              sleep(@refresh_interval)
            rescue => e
              CLI::UI.puts(@formatter.format_refresh_error(e.message))
            end
          end
        end

        def refresh_current_view
          display_dashboard(@current_view)
        end

        def display_overview
          @frame_manager.section("Job Dashboard Overview") do
            display_dashboard_header
            display_quick_stats
            display_recent_activity
            display_dashboard_commands
          end
        end

        def display_jobs_view
          @frame_manager.section("Jobs View") do
            display_jobs_summary
            display_active_jobs
            display_job_filters
          end
        end

        def display_metrics_view
          @frame_manager.section("Metrics View") do
            display_system_metrics
            display_job_metrics
            display_performance_trends
          end
        end

        def display_errors_view
          @frame_manager.section("Errors View") do
            display_error_summary
            display_recent_errors
            display_retry_queue
          end
        end

        def display_history_view
          @frame_manager.section("History View") do
            display_history_summary
            display_recent_history
            display_history_filters
          end
        end

        def display_settings_view
          @frame_manager.section("Settings View") do
            display_dashboard_settings
            display_monitoring_settings
            display_display_settings
          end
        end

        def display_dashboard_header
          CLI::UI.puts(@formatter.format_dashboard_header)
          CLI::UI.puts("Current view: {{bold:#{@current_view.to_s.capitalize}}}")
          CLI::UI.puts("Refresh interval: {{bold:#{@refresh_interval}s}}")
          CLI::UI.puts("Status: #{@dashboard_active ? "Active" : "Inactive"}")
        end

        def display_quick_stats
          monitor_summary = @job_monitor.get_monitoring_summary
          @job_metrics.get_metrics_summary
          error_summary = @error_handler.get_error_summary

          CLI::UI.puts("\n{{bold:Quick Stats:}}")
          CLI::UI.puts("  Total jobs: {{bold:#{monitor_summary[:total_jobs]}}}")
          CLI::UI.puts("  Running jobs: {{blue:#{monitor_summary[:jobs_by_status][:running] || 0}}}")
          CLI::UI.puts("  Completed jobs: {{green:#{monitor_summary[:jobs_by_status][:completed] || 0}}}")
          CLI::UI.puts("  Failed jobs: {{red:#{monitor_summary[:jobs_by_status][:failed] || 0}}}")
          CLI::UI.puts("  Total errors: {{red:#{error_summary[:total_errors]}}}")
          CLI::UI.puts("  Retry queue: {{yellow:#{error_summary[:retry_queue_size]}}}")
        end

        def display_recent_activity
          recent_history = @job_history.get_recent_history(10)

          CLI::UI.puts("\n{{bold:Recent Activity:}}")
          if recent_history.empty?
            CLI::UI.puts("  {{dim:No recent activity}}")
          else
            recent_history.last(5).each do |event|
              CLI::UI.puts("  {{dim:#{event[:timestamp].strftime("%H:%M:%S")}}} #{event[:event_type]} - #{event[:job_id]}")
            end
          end
        end

        def display_dashboard_commands
          CLI::UI.puts("\n{{bold:Dashboard Commands:}}")
          CLI::UI.puts("  {{bold:o}} - Overview")
          CLI::UI.puts("  {{bold:j}} - Jobs view")
          CLI::UI.puts("  {{bold:m}} - Metrics view")
          CLI::UI.puts("  {{bold:e}} - Errors view")
          CLI::UI.puts("  {{bold:h}} - History view")
          CLI::UI.puts("  {{bold:s}} - Settings view")
          CLI::UI.puts("  {{bold:r}} - Refresh current view")
          CLI::UI.puts("  {{bold:?}} - Show help")
          CLI::UI.puts("  {{bold:q}} - Quit dashboard")
        end

        def display_jobs_summary
          monitor_summary = @job_monitor.get_monitoring_summary

          CLI::UI.puts("{{bold:Jobs Summary:}}")
          CLI::UI.puts("  Total jobs: {{bold:#{monitor_summary[:total_jobs]}}}")

          if monitor_summary[:jobs_by_status].any?
            CLI::UI.puts("  Jobs by status:")
            monitor_summary[:jobs_by_status].each do |status, count|
              CLI::UI.puts("    {{dim:#{status}: #{count}}}")
            end
          end
        end

        def display_active_jobs
          all_jobs = @job_monitor.get_all_jobs
          active_jobs = all_jobs.select { |_, job| [:pending, :running, :retrying].include?(job[:status]) }

          CLI::UI.puts("\n{{bold:Active Jobs:}}")
          if active_jobs.empty?
            CLI::UI.puts("  {{dim:No active jobs}}")
          else
            active_jobs.each do |job_id, job|
              CLI::UI.puts("  {{bold:#{job_id}}} - #{@formatter.format_job_status(job[:status])} - #{job[:progress] || 0}%")
            end
          end
        end

        def display_job_filters
          CLI::UI.puts("\n{{bold:Job Filters:}}")
          CLI::UI.puts("  Use the job filter component to filter and sort jobs")
        end

        def display_system_metrics
          system_metrics = @job_metrics.get_system_metrics

          CLI::UI.puts("{{bold:System Metrics:}}")
          CLI::UI.puts("  Throughput: {{bold:#{@formatter.format_throughput(system_metrics[:throughput])}}}")
          CLI::UI.puts("  Success rate: {{green:#{@formatter.format_percentage(system_metrics[:success_rate])}}}")
          CLI::UI.puts("  Error rate: {{red:#{@formatter.format_percentage(system_metrics[:error_rate])}}}")
          CLI::UI.puts("  Retry rate: {{yellow:#{@formatter.format_percentage(system_metrics[:retry_rate])}}}")
          CLI::UI.puts("  Average duration: {{bold:#{@formatter.format_duration(system_metrics[:average_duration])}}}")
        end

        def display_job_metrics
          CLI::UI.puts("\n{{bold:Job Metrics:}}")
          CLI::UI.puts("  Use the job metrics component to view detailed job metrics")
        end

        def display_performance_trends
          CLI::UI.puts("\n{{bold:Performance Trends:}}")
          CLI::UI.puts("  {{dim:Performance trend analysis would be displayed here}}")
        end

        def display_error_summary
          error_summary = @error_handler.get_error_summary

          CLI::UI.puts("{{bold:Error Summary:}}")
          CLI::UI.puts("  Total errors: {{bold:#{error_summary[:total_errors]}}}")
          CLI::UI.puts("  Retry queue size: {{bold:#{error_summary[:retry_queue_size]}}}")
          CLI::UI.puts("  Max retries: {{bold:#{error_summary[:max_retries]}}}")
          CLI::UI.puts("  Retry strategy: {{bold:#{error_summary[:retry_strategy]}}}")
        end

        def display_recent_errors
          CLI::UI.puts("\n{{bold:Recent Errors:}}")
          CLI::UI.puts("  {{dim:Recent error details would be displayed here}}")
        end

        def display_retry_queue
          CLI::UI.puts("\n{{bold:Retry Queue:}}")
          @error_handler.display_retry_queue
        end

        def display_history_summary
          history_summary = @job_history.get_history_summary

          CLI::UI.puts("{{bold:History Summary:}}")
          CLI::UI.puts("  Total events: {{bold:#{history_summary[:total_events]}}}")
          CLI::UI.puts("  Storage path: {{dim:#{history_summary[:storage_path]}}}")
          CLI::UI.puts("  Persistence: #{history_summary[:persistence_enabled] ? "Enabled" : "Disabled"}")
        end

        def display_recent_history
          recent_history = @job_history.get_recent_history(20)

          CLI::UI.puts("\n{{bold:Recent History:}}")
          if recent_history.empty?
            CLI::UI.puts("  {{dim:No recent history}}")
          else
            recent_history.last(10).each do |event|
              CLI::UI.puts("  {{dim:#{event[:timestamp].strftime("%H:%M:%S")}}} #{event[:event_type]} - #{event[:job_id]}")
            end
          end
        end

        def display_history_filters
          CLI::UI.puts("\n{{bold:History Filters:}}")
          CLI::UI.puts("  Use the job history component to filter and search history")
        end

        def display_dashboard_settings
          CLI::UI.puts("{{bold:Dashboard Settings:}}")
          CLI::UI.puts("  Refresh interval: {{bold:#{@refresh_interval}s}}")
          CLI::UI.puts("  Current view: {{bold:#{@current_view}}}")
          CLI::UI.puts("  Dashboard active: #{@dashboard_active ? "Yes" : "No"}")
        end

        def display_monitoring_settings
          monitor_summary = @job_monitor.get_monitoring_summary

          CLI::UI.puts("\n{{bold:Monitoring Settings:}}")
          CLI::UI.puts("  Monitoring active: #{monitor_summary[:monitoring_active] ? "Yes" : "No"}")
        end

        def display_display_settings
          CLI::UI.puts("\n{{bold:Display Settings:}}")
          CLI::UI.puts("  {{dim:Display configuration options would be shown here}}")
        end

        def display_help
          @frame_manager.section("Dashboard Help") do
            CLI::UI.puts("The job dashboard provides real-time monitoring of job execution.")
            CLI::UI.puts("\n{{bold:Available Views:}}")
            CLI::UI.puts("  {{bold:Overview}} - Quick stats and recent activity")
            CLI::UI.puts("  {{bold:Jobs}} - Detailed job information and filtering")
            CLI::UI.puts("  {{bold:Metrics}} - Performance metrics and analytics")
            CLI::UI.puts("  {{bold:Errors}} - Error handling and retry information")
            CLI::UI.puts("  {{bold:History}} - Job history and event tracking")
            CLI::UI.puts("  {{bold:Settings}} - Dashboard configuration")

            CLI::UI.puts("\n{{bold:Commands:}}")
            CLI::UI.puts("  {{bold:o}} - Switch to overview view")
            CLI::UI.puts("  {{bold:j}} - Switch to jobs view")
            CLI::UI.puts("  {{bold:m}} - Switch to metrics view")
            CLI::UI.puts("  {{bold:e}} - Switch to errors view")
            CLI::UI.puts("  {{bold:h}} - Switch to history view")
            CLI::UI.puts("  {{bold:s}} - Switch to settings view")
            CLI::UI.puts("  {{bold:r}} - Refresh current view")
            CLI::UI.puts("  {{bold:q}} - Quit dashboard")
          end
        end

        def handle_quit
          CLI::UI.puts(@formatter.format_quit_confirmation)
          stop_dashboard
        end
      end

      # Formats job dashboard display
      class JobDashboardFormatter
        def format_dashboard_header
          CLI::UI.fmt("{{bold:{{blue:📊 Job Monitoring Dashboard}}}}")
        end

        def format_dashboard_started
          CLI::UI.fmt("{{green:✅ Job dashboard started}}")
        end

        def format_dashboard_stopped
          CLI::UI.fmt("{{red:❌ Job dashboard stopped}}")
        end

        def format_refresh_interval_set(interval_seconds)
          CLI::UI.fmt("{{green:✅ Refresh interval set to #{interval_seconds}s}}")
        end

        def format_refresh_error(error_message)
          CLI::UI.fmt("{{red:❌ Dashboard refresh error: #{error_message}}}")
        end

        def format_unknown_command(command)
          CLI::UI.fmt("{{yellow:⚠️ Unknown command: '#{command}'. Type 'help' for available commands.}}")
        end

        def format_quit_confirmation
          CLI::UI.fmt("{{blue:👋 Quitting job dashboard...}}")
        end

        def format_job_status(status)
          case status
          when :pending
            CLI::UI.fmt("{{yellow:⏳ Pending}}")
          when :running
            CLI::UI.fmt("{{blue:🔄 Running}}")
          when :completed
            CLI::UI.fmt("{{green:✅ Completed}}")
          when :failed
            CLI::UI.fmt("{{red:❌ Failed}}")
          when :cancelled
            CLI::UI.fmt("{{red:🚫 Cancelled}}")
          when :retrying
            CLI::UI.fmt("{{yellow:🔄 Retrying}}")
          else
            CLI::UI.fmt("{{dim:❓ #{status.to_s.capitalize}}}")
          end
        end

        def format_throughput(throughput)
          return "0 jobs/s" if throughput.nil? || throughput == 0

          if throughput < 1
            "#{(throughput * 60).round(2)} jobs/min"
          else
            "#{throughput.round(2)} jobs/s"
          end
        end

        def format_percentage(rate)
          return "0%" if rate.nil? || rate == 0

          "#{(rate * 100).round(1)}%"
        end

        def format_duration(duration_seconds)
          return "0s" if duration_seconds.nil? || duration_seconds == 0

          if duration_seconds < 60
            "#{duration_seconds.round(2)}s"
          elsif duration_seconds < 3600
            "#{(duration_seconds / 60).round(2)}m"
          else
            "#{(duration_seconds / 3600).round(2)}h"
          end
        end
      end
    end
  end
end
