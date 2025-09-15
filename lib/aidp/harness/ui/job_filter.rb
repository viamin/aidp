# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # Job filtering and sorting functionality
      class JobFilter < Base
        class FilterError < StandardError; end
        class InvalidFilterError < FilterError; end
        class InvalidSortError < FilterError; end

        FILTER_CRITERIA = {
          status: [:pending, :running, :completed, :failed, :cancelled, :retrying],
          priority: [:low, :normal, :high, :urgent],
          date_range: :date_range,
          progress_range: :progress_range,
          retry_count: :retry_count,
          error_contains: :error_contains
        }.freeze

        SORT_OPTIONS = {
          created_at: :created_at,
          last_updated: :last_updated,
          status: :status,
          priority: :priority,
          progress: :progress,
          retry_count: :retry_count
        }.freeze

        SORT_ORDERS = {
          asc: :asc,
          desc: :desc
        }.freeze

        def initialize(ui_components = {})
          super()
          @formatter = ui_components[:formatter] || JobFilterFormatter.new
          @active_filters = {}
          @sort_options = { field: :created_at, order: :desc }
          @filter_history = []
        end

        def apply_filter(jobs, filter_criteria)
          validate_jobs(jobs)
          validate_filter_criteria(filter_criteria)

          filtered_jobs = jobs.dup

          filter_criteria.each do |criteria, value|
            filtered_jobs = apply_single_filter(filtered_jobs, criteria, value)
          end

          record_filter_event(filter_criteria, filtered_jobs.size)
          filtered_jobs
        rescue StandardError => e
          raise FilterError, "Failed to apply filter: #{e.message}"
        end

        def sort_jobs(jobs, sort_field = nil, sort_order = nil)
          validate_jobs(jobs)

          sort_field ||= @sort_options[:field]
          sort_order ||= @sort_options[:order]

          validate_sort_field(sort_field)
          validate_sort_order(sort_order)

          sorted_jobs = jobs.sort do |a, b|
            a_value = extract_sort_value(a[1], sort_field)
            b_value = extract_sort_value(b[1], sort_field)

            comparison = compare_values(a_value, b_value)
            sort_order == :desc ? -comparison : comparison
          end

          record_sort_event(sort_field, sort_order, sorted_jobs.size)
          sorted_jobs
        rescue StandardError => e
          raise FilterError, "Failed to sort jobs: #{e.message}"
        end

        def filter_and_sort(jobs, filter_criteria = {}, sort_field = nil, sort_order = nil)
          validate_jobs(jobs)

          # Apply filters first
          filtered_jobs = filter_criteria.any? ? apply_filter(jobs, filter_criteria) : jobs

          # Then sort
          sorted_jobs = sort_jobs(filtered_jobs, sort_field, sort_order)

          sorted_jobs
        end

        def set_default_sort(field, order)
          validate_sort_field(field)
          validate_sort_order(order)

          @sort_options = { field: field, order: order }
          CLI::UI.puts(@formatter.format_default_sort_set(field, order))
        end

        def get_active_filters
          @active_filters.dup
        end

        def clear_filters
          @active_filters.clear
          CLI::UI.puts(@formatter.format_filters_cleared)
        end

        def get_filter_summary
          {
            active_filters: @active_filters.size,
            default_sort: @sort_options,
            total_filter_events: @filter_history.size,
            last_filter: @filter_history.last
          }
        end

        def display_filter_options
          @formatter.display_filter_options
        end

        def display_sort_options
          @formatter.display_sort_options
        end

        private

        def validate_jobs(jobs)
          raise FilterError, "Jobs must be a hash" unless jobs.is_a?(Hash)
        end

        def validate_filter_criteria(filter_criteria)
          raise FilterError, "Filter criteria must be a hash" unless filter_criteria.is_a?(Hash)
        end

        def validate_sort_field(sort_field)
          unless SORT_OPTIONS.key?(sort_field)
            raise InvalidSortError, "Invalid sort field: #{sort_field}. Must be one of: #{SORT_OPTIONS.keys.join(', ')}"
          end
        end

        def validate_sort_order(sort_order)
          unless SORT_ORDERS.key?(sort_order)
            raise InvalidSortError, "Invalid sort order: #{sort_order}. Must be one of: #{SORT_ORDERS.keys.join(', ')}"
          end
        end

        def apply_single_filter(jobs, criteria, value)
          case criteria
          when :status
            filter_by_status(jobs, value)
          when :priority
            filter_by_priority(jobs, value)
          when :date_range
            filter_by_date_range(jobs, value)
          when :progress_range
            filter_by_progress_range(jobs, value)
          when :retry_count
            filter_by_retry_count(jobs, value)
          when :error_contains
            filter_by_error_contains(jobs, value)
          else
            raise InvalidFilterError, "Unknown filter criteria: #{criteria}"
          end
        end

        def filter_by_status(jobs, status)
          if status.is_a?(Array)
            jobs.select { |_, job| status.include?(job[:status]) }
          else
            jobs.select { |_, job| job[:status] == status }
          end
        end

        def filter_by_priority(jobs, priority)
          if priority.is_a?(Array)
            jobs.select { |_, job| priority.include?(job[:priority]) }
          else
            jobs.select { |_, job| job[:priority] == priority }
          end
        end

        def filter_by_date_range(jobs, date_range)
          start_date = date_range[:start]
          end_date = date_range[:end]

          jobs.select do |_, job|
            job_date = job[:created_at]
            (start_date.nil? || job_date >= start_date) &&
            (end_date.nil? || job_date <= end_date)
          end
        end

        def filter_by_progress_range(jobs, progress_range)
          min_progress = progress_range[:min] || 0
          max_progress = progress_range[:max] || 100

          jobs.select do |_, job|
            progress = job[:progress] || 0
            progress >= min_progress && progress <= max_progress
          end
        end

        def filter_by_retry_count(jobs, retry_count)
          if retry_count.is_a?(Hash)
            min_retries = retry_count[:min] || 0
            max_retries = retry_count[:max] || Float::INFINITY

            jobs.select do |_, job|
              count = job[:retry_count] || 0
              count >= min_retries && count <= max_retries
            end
          else
            jobs.select { |_, job| (job[:retry_count] || 0) == retry_count }
          end
        end

        def filter_by_error_contains(jobs, error_text)
          jobs.select do |_, job|
            error_message = job[:error_message]
            error_message && error_message.downcase.include?(error_text.downcase)
          end
        end

        def extract_sort_value(job, sort_field)
          case sort_field
          when :created_at
            job[:created_at]
          when :last_updated
            job[:last_updated]
          when :status
            job[:status].to_s
          when :priority
            priority_order(job[:priority])
          when :progress
            job[:progress] || 0
          when :retry_count
            job[:retry_count] || 0
          else
            job[sort_field]
          end
        end

        def priority_order(priority)
          case priority
          when :urgent then 4
          when :high then 3
          when :normal then 2
          when :low then 1
          else 0
          end
        end

        def compare_values(a_value, b_value)
          case a_value
          when Time
            a_value <=> b_value
          when Numeric
            a_value <=> b_value
          when String
            a_value <=> b_value
          else
            a_value.to_s <=> b_value.to_s
          end
        end

        def record_filter_event(filter_criteria, result_count)
          @filter_history << {
            filter_criteria: filter_criteria.dup,
            result_count: result_count,
            timestamp: Time.now
          }
        end

        def record_sort_event(sort_field, sort_order, result_count)
          @filter_history << {
            sort_field: sort_field,
            sort_order: sort_order,
            result_count: result_count,
            timestamp: Time.now
          }
        end
      end

      # Formats job filter display
      class JobFilterFormatter
        def display_filter_options
          CLI::UI.puts(CLI::UI.fmt("{{bold:{{blue:🔍 Job Filter Options}}}}"))
          CLI::UI.puts("─" * 50)

          CLI::UI.puts("\n{{bold:Available Filters:}}")
          CLI::UI.puts("  {{bold:status}} - Filter by job status")
          CLI::UI.puts("    Values: pending, running, completed, failed, cancelled, retrying")
          CLI::UI.puts("  {{bold:priority}} - Filter by job priority")
          CLI::UI.puts("    Values: low, normal, high, urgent")
          CLI::UI.puts("  {{bold:date_range}} - Filter by date range")
          CLI::UI.puts("    Format: { start: Time, end: Time }")
          CLI::UI.puts("  {{bold:progress_range}} - Filter by progress range")
          CLI::UI.puts("    Format: { min: 0, max: 100 }")
          CLI::UI.puts("  {{bold:retry_count}} - Filter by retry count")
          CLI::UI.puts("    Format: { min: 0, max: 10 } or single number")
          CLI::UI.puts("  {{bold:error_contains}} - Filter by error message content")
          CLI::UI.puts("    Format: string")
        end

        def display_sort_options
          CLI::UI.puts(CLI::UI.fmt("{{bold:{{blue:📊 Job Sort Options}}}}"))
          CLI::UI.puts("─" * 50)

          CLI::UI.puts("\n{{bold:Available Sort Fields:}}")
          CLI::UI.puts("  {{bold:created_at}} - Sort by creation time")
          CLI::UI.puts("  {{bold:last_updated}} - Sort by last update time")
          CLI::UI.puts("  {{bold:status}} - Sort by job status")
          CLI::UI.puts("  {{bold:priority}} - Sort by job priority")
          CLI::UI.puts("  {{bold:progress}} - Sort by progress percentage")
          CLI::UI.puts("  {{bold:retry_count}} - Sort by retry count")

          CLI::UI.puts("\n{{bold:Sort Orders:}}")
          CLI::UI.puts("  {{bold:asc}} - Ascending order")
          CLI::UI.puts("  {{bold:desc}} - Descending order (default)")
        end

        def format_default_sort_set(field, order)
          CLI::UI.fmt("{{green:✅ Default sort set to: #{field} #{order}}}")
        end

        def format_filters_cleared
          CLI::UI.fmt("{{yellow:🗑️ All filters cleared}}")
        end

        def format_filter_applied(criteria, result_count)
          CLI::UI.fmt("{{blue:🔍 Filter applied: #{criteria.keys.join(', ')} (#{result_count} results)}}")
        end

        def format_sort_applied(field, order, result_count)
          CLI::UI.fmt("{{blue:📊 Sort applied: #{field} #{order} (#{result_count} results)}}")
        end

        def format_filter_summary(summary)
          CLI::UI.fmt("{{bold:{{blue:📊 Filter Summary}}}}")
          CLI::UI.fmt("Active filters: {{bold:#{summary[:active_filters]}}}")
          CLI::UI.fmt("Default sort: {{bold:#{summary[:default_sort][:field]} #{summary[:default_sort][:order]}}}")
          CLI::UI.fmt("Total filter events: {{dim:#{summary[:total_filter_events]}}}")
        end

        def format_filter_criteria(criteria)
          criteria.map do |key, value|
            case value
            when Array
              "#{key}: [#{value.join(', ')}]"
            when Hash
              "#{key}: #{value}"
            else
              "#{key}: #{value}"
            end
          end.join(", ")
        end
      end
    end
  end
end
