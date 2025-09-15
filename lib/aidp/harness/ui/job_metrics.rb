# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # Job performance metrics and analytics
      class JobMetrics < Base
        class MetricsError < StandardError; end
        class CalculationError < MetricsError; end
        class AnalyticsError < MetricsError; end

        METRIC_TYPES = {
          duration: :duration,
          throughput: :throughput,
          success_rate: :success_rate,
          error_rate: :error_rate,
          retry_rate: :retry_rate,
          queue_time: :queue_time,
          processing_time: :processing_time
        }.freeze

        def initialize(ui_components = {})
          super()
          @formatter = ui_components[:formatter] || JobMetricsFormatter.new
          @metrics_history = []
          @current_metrics = {}
          @aggregation_window = 300 # 5 minutes
          @metrics_enabled = true
        end

        def record_job_metric(job_id, metric_type, value, metadata = {})
          validate_job_id(job_id)
          validate_metric_type(metric_type)
          validate_metric_value(value)

          metric = create_metric_entry(job_id, metric_type, value, metadata)
          @metrics_history << metric

          update_current_metrics(metric)
          record_metric_event(job_id, metric_type, value)

          metric
        rescue => e
          raise MetricsError, "Failed to record job metric: #{e.message}"
        end

        def calculate_job_duration(job_id, start_time, end_time)
          validate_job_id(job_id)
          validate_time_range(start_time, end_time)

          duration = end_time - start_time
          record_job_metric(job_id, :duration, duration, {
            start_time: start_time,
            end_time: end_time
          })

          duration
        end

        def calculate_throughput(job_ids, time_window = nil)
          validate_job_ids(job_ids)

          time_window ||= @aggregation_window
          end_time = Time.now
          start_time = end_time - time_window

          relevant_jobs = @metrics_history.select do |metric|
            metric[:timestamp].between?(start_time, end_time)
          end

          throughput = relevant_jobs.size.to_f / time_window
          record_metric_event("system", :throughput, throughput)

          throughput
        end

        def calculate_success_rate(job_ids, time_window = nil)
          validate_job_ids(job_ids)

          time_window ||= @aggregation_window
          end_time = Time.now
          start_time = end_time - time_window

          relevant_metrics = @metrics_history.select do |metric|
            metric[:job_id].in?(job_ids) &&
              metric[:timestamp] >= start_time && metric[:timestamp] <= end_time
          end

          return 0.0 if relevant_metrics.empty?

          successful_jobs = relevant_metrics.count { |metric| metric[:metric_type] == :success }
          success_rate = successful_jobs.to_f / relevant_metrics.size

          record_metric_event("system", :success_rate, success_rate)
          success_rate
        end

        def calculate_error_rate(job_ids, time_window = nil)
          validate_job_ids(job_ids)

          time_window ||= @aggregation_window
          end_time = Time.now
          start_time = end_time - time_window

          relevant_metrics = @metrics_history.select do |metric|
            metric[:job_id].in?(job_ids) &&
              metric[:timestamp] >= start_time && metric[:timestamp] <= end_time
          end

          return 0.0 if relevant_metrics.empty?

          error_jobs = relevant_metrics.count { |metric| metric[:metric_type] == :error }
          error_rate = error_jobs.to_f / relevant_metrics.size

          record_metric_event("system", :error_rate, error_rate)
          error_rate
        end

        def calculate_retry_rate(job_ids, time_window = nil)
          validate_job_ids(job_ids)

          time_window ||= @aggregation_window
          end_time = Time.now
          start_time = end_time - time_window

          relevant_metrics = @metrics_history.select do |metric|
            metric[:job_id].in?(job_ids) &&
              metric[:timestamp] >= start_time && metric[:timestamp] <= end_time
          end

          return 0.0 if relevant_metrics.empty?

          retry_jobs = relevant_metrics.count { |metric| metric[:metric_type] == :retry }
          retry_rate = retry_jobs.to_f / relevant_metrics.size

          record_metric_event("system", :retry_rate, retry_rate)
          retry_rate
        end

        def get_job_metrics(job_id)
          validate_job_id(job_id)

          job_metrics = @metrics_history.select { |metric| metric[:job_id] == job_id }
          aggregate_job_metrics(job_metrics)
        end

        def get_system_metrics(time_window = nil)
          time_window ||= @aggregation_window
          end_time = Time.now
          start_time = end_time - time_window

          relevant_metrics = @metrics_history.select do |metric|
            metric[:timestamp].between?(start_time, end_time)
          end

          aggregate_system_metrics(relevant_metrics)
        end

        def get_metrics_summary
          {
            total_metrics: @metrics_history.size,
            metrics_by_type: @metrics_history.map { |metric| metric[:metric_type] }.tally,
            metrics_by_job: @metrics_history.map { |metric| metric[:metric_id] }.tally,
            current_metrics: @current_metrics.dup,
            aggregation_window: @aggregation_window,
            metrics_enabled: @metrics_enabled
          }
        end

        def display_metrics_summary
          summary = get_metrics_summary
          @formatter.display_metrics_summary(summary)
        end

        def display_job_metrics(job_id)
          metrics = get_job_metrics(job_id)
          @formatter.display_job_metrics(job_id, metrics)
        end

        def display_system_metrics(time_window = nil)
          metrics = get_system_metrics(time_window)
          @formatter.display_system_metrics(metrics, time_window)
        end

        def export_metrics(format = :json, file_path = nil)
          validate_export_format(format)

          file_path ||= generate_export_file_path(format)

          case format
          when :json
            export_to_json(file_path)
          when :csv
            export_to_csv(file_path)
          when :yaml
            export_to_yaml(file_path)
          else
            raise MetricsError, "Unsupported export format: #{format}"
          end

          CLI::UI.puts(@formatter.format_export_success(file_path, @metrics_history.size))
          file_path
        rescue => e
          raise MetricsError, "Failed to export metrics: #{e.message}"
        end

        def clear_metrics_history
          @metrics_history.clear
          @current_metrics.clear
          CLI::UI.puts(@formatter.format_metrics_cleared)
        end

        def set_aggregation_window(window_seconds)
          validate_aggregation_window(window_seconds)
          @aggregation_window = window_seconds
          CLI::UI.puts(@formatter.format_aggregation_window_set(window_seconds))
        end

        def enable_metrics
          @metrics_enabled = true
          CLI::UI.puts(@formatter.format_metrics_enabled)
        end

        def disable_metrics
          @metrics_enabled = false
          CLI::UI.puts(@formatter.format_metrics_disabled)
        end

        private

        def validate_job_id(job_id)
          raise MetricsError, "Job ID cannot be empty" if job_id.to_s.strip.empty?
        end

        def validate_metric_type(metric_type)
          unless METRIC_TYPES.key?(metric_type)
            raise MetricsError, "Invalid metric type: #{metric_type}. Must be one of: #{METRIC_TYPES.keys.join(", ")}"
          end
        end

        def validate_metric_value(value)
          raise MetricsError, "Metric value must be numeric" unless value.is_a?(Numeric)
        end

        def validate_time_range(start_time, end_time)
          raise MetricsError, "Start time must be a Time object" unless start_time.is_a?(Time)
          raise MetricsError, "End time must be a Time object" unless end_time.is_a?(Time)
          raise MetricsError, "Start time must be before end time" if start_time > end_time
        end

        def validate_job_ids(job_ids)
          raise MetricsError, "Job IDs must be an array" unless job_ids.is_a?(Array)
        end

        def validate_export_format(format)
          valid_formats = [:json, :csv, :yaml]
          unless valid_formats.include?(format)
            raise MetricsError, "Invalid export format: #{format}. Must be one of: #{valid_formats.join(", ")}"
          end
        end

        def validate_aggregation_window(window_seconds)
          raise MetricsError, "Aggregation window must be positive" unless window_seconds > 0
        end

        def create_metric_entry(job_id, metric_type, value, metadata)
          {
            id: generate_metric_id,
            job_id: job_id,
            metric_type: metric_type,
            value: value,
            timestamp: Time.now,
            metadata: metadata
          }
        end

        def generate_metric_id
          "#{Time.now.to_i}_#{rand(10000)}"
        end

        def update_current_metrics(metric)
          @current_metrics[metric[:metric_type]] = {
            value: metric[:value],
            timestamp: metric[:timestamp],
            job_id: metric[:job_id]
          }
        end

        def record_metric_event(job_id, metric_type, value)
          # Could be extended to log to external systems
        end

        def aggregate_job_metrics(job_metrics)
          return {} if job_metrics.empty?

          {
            total_metrics: job_metrics.size,
            metrics_by_type: job_metrics.map { |metric| metric[:metric_type] }.tally,
            average_duration: calculate_average(job_metrics, :duration),
            total_duration: calculate_sum(job_metrics, :duration),
            min_duration: calculate_min(job_metrics, :duration),
            max_duration: calculate_max(job_metrics, :duration),
            success_count: job_metrics.count { |metric| metric[:metric_type] == :success },
            error_count: job_metrics.count { |metric| metric[:metric_type] == :error },
            retry_count: job_metrics.count { |metric| metric[:metric_type] == :retry }
          }
        end

        def aggregate_system_metrics(metrics)
          return {} if metrics.empty?

          {
            total_metrics: metrics.size,
            time_window: @aggregation_window,
            throughput: calculate_throughput_from_metrics(metrics),
            success_rate: calculate_success_rate_from_metrics(metrics),
            error_rate: calculate_error_rate_from_metrics(metrics),
            retry_rate: calculate_retry_rate_from_metrics(metrics),
            average_duration: calculate_average(metrics, :duration),
            total_duration: calculate_sum(metrics, :duration)
          }
        end

        def calculate_average(metrics, metric_type)
          relevant_metrics = metrics.select { |metric| metric[:metric_type] == metric_type }
          return 0.0 if relevant_metrics.empty?

          relevant_metrics.sum { |metric| metric[:value] } / relevant_metrics.size
        end

        def calculate_sum(metrics, metric_type)
          relevant_metrics = metrics.select { |metric| metric[:metric_type] == metric_type }
          relevant_metrics.sum { |metric| metric[:value] }
        end

        def calculate_min(metrics, metric_type)
          relevant_metrics = metrics.select { |metric| metric[:metric_type] == metric_type }
          return 0.0 if relevant_metrics.empty?

          relevant_metrics.min { |metric| metric[:value] }[:value]
        end

        def calculate_max(metrics, metric_type)
          relevant_metrics = metrics.select { |metric| metric[:metric_type] == metric_type }
          return 0.0 if relevant_metrics.empty?

          relevant_metrics.max { |metric| metric[:value] }[:value]
        end

        def calculate_throughput_from_metrics(metrics)
          metrics.size.to_f / @aggregation_window
        end

        def calculate_success_rate_from_metrics(metrics)
          return 0.0 if metrics.empty?

          success_count = metrics.count { |metric| metric[:metric_type] == :success }
          success_count.to_f / metrics.size
        end

        def calculate_error_rate_from_metrics(metrics)
          return 0.0 if metrics.empty?

          error_count = metrics.count { |metric| metric[:metric_type] == :error }
          error_count.to_f / metrics.size
        end

        def calculate_retry_rate_from_metrics(metrics)
          return 0.0 if metrics.empty?

          retry_count = metrics.count { |metric| metric[:metric_type] == :retry }
          retry_count.to_f / metrics.size
        end

        def generate_export_file_path(format)
          timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
          "job_metrics_#{timestamp}.#{format}"
        end

        def export_to_json(file_path)
          metrics_data = {
            version: "1.0",
            exported_at: Time.now,
            total_metrics: @metrics_history.size,
            metrics: @metrics_history
          }

          File.write(file_path, JSON.pretty_generate(metrics_data))
        end

        def export_to_csv(file_path)
          require "csv"

          CSV.open(file_path, "w") do |csv|
            csv << ["ID", "Job ID", "Metric Type", "Value", "Timestamp", "Metadata"]

            @metrics_history.each do |metric|
              csv << [
                metric[:id],
                metric[:job_id],
                metric[:metric_type],
                metric[:value],
                metric[:timestamp].iso8601,
                metric[:metadata].to_json
              ]
            end
          end
        end

        def export_to_yaml(file_path)
          require "yaml"

          metrics_data = {
            version: "1.0",
            exported_at: Time.now,
            total_metrics: @metrics_history.size,
            metrics: @metrics_history
          }

          File.write(file_path, metrics_data.to_yaml)
        end
      end

      # Formats job metrics display
      class JobMetricsFormatter
        def display_metrics_summary(summary)
          CLI::UI.puts(CLI::UI.fmt("{{bold:{{blue:📊 Job Metrics Summary}}}}"))
          CLI::UI.puts("─" * 50)

          CLI::UI.puts("Total metrics: {{bold:#{summary[:total_metrics]}}}")
          CLI::UI.puts("Aggregation window: {{bold:#{summary[:aggregation_window]}s}}")
          CLI::UI.puts("Metrics enabled: #{summary[:metrics_enabled] ? "Yes" : "No"}")

          if summary[:metrics_by_type].any?
            CLI::UI.puts("\nMetrics by type:")
            summary[:metrics_by_type].each do |type, count|
              CLI::UI.puts("  {{dim:#{type}: #{count}}}")
            end
          end

          if summary[:current_metrics].any?
            CLI::UI.puts("\nCurrent metrics:")
            summary[:current_metrics].each do |type, data|
              CLI::UI.puts("  {{dim:#{type}: #{data[:value]} (#{data[:job_id]})}}")
            end
          end
        end

        def display_job_metrics(job_id, metrics)
          CLI::UI.puts(CLI::UI.fmt("{{bold:{{blue:📊 Job Metrics: #{job_id}}}}}}"))
          CLI::UI.puts("─" * 50)

          CLI::UI.puts("Total metrics: {{bold:#{metrics[:total_metrics]}}}")
          CLI::UI.puts("Average duration: {{bold:#{format_duration(metrics[:average_duration])}}}")
          CLI::UI.puts("Total duration: {{bold:#{format_duration(metrics[:total_duration])}}}")
          CLI::UI.puts("Min duration: {{bold:#{format_duration(metrics[:min_duration])}}}")
          CLI::UI.puts("Max duration: {{bold:#{format_duration(metrics[:max_duration])}}}")
          CLI::UI.puts("Success count: {{green:#{metrics[:success_count]}}}")
          CLI::UI.puts("Error count: {{red:#{metrics[:error_count]}}}")
          CLI::UI.puts("Retry count: {{yellow:#{metrics[:retry_count]}}}")
        end

        def display_system_metrics(metrics, time_window)
          CLI::UI.puts(CLI::UI.fmt("{{bold:{{blue:📊 System Metrics}}}}"))
          CLI::UI.puts("─" * 50)

          CLI::UI.puts("Time window: {{bold:#{time_window || "default"}s}}")
          CLI::UI.puts("Total metrics: {{bold:#{metrics[:total_metrics]}}}")
          CLI::UI.puts("Throughput: {{bold:#{format_throughput(metrics[:throughput])}}}")
          CLI::UI.puts("Success rate: {{green:#{format_percentage(metrics[:success_rate])}}}")
          CLI::UI.puts("Error rate: {{red:#{format_percentage(metrics[:error_rate])}}}")
          CLI::UI.puts("Retry rate: {{yellow:#{format_percentage(metrics[:retry_rate])}}}")
          CLI::UI.puts("Average duration: {{bold:#{format_duration(metrics[:average_duration])}}}")
          CLI::UI.puts("Total duration: {{bold:#{format_duration(metrics[:total_duration])}}}")
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

        def format_export_success(file_path, metric_count)
          CLI::UI.fmt("{{green:✅ Metrics exported to #{file_path} (#{metric_count} metrics)}}")
        end

        def format_metrics_cleared
          CLI::UI.fmt("{{yellow:🗑️ Metrics history cleared}}")
        end

        def format_aggregation_window_set(window_seconds)
          CLI::UI.fmt("{{green:✅ Aggregation window set to #{window_seconds}s}}")
        end

        def format_metrics_enabled
          CLI::UI.fmt("{{green:✅ Metrics collection enabled}}")
        end

        def format_metrics_disabled
          CLI::UI.fmt("{{red:❌ Metrics collection disabled}}")
        end
      end
    end
  end
end
