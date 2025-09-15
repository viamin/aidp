# frozen_string_literal: true

require_relative "base"
require "fileutils"

module Aidp
  module Harness
    module UI
      # Job history tracking and persistence
      class JobHistory < Base
        class HistoryError < StandardError; end
        class PersistenceError < HistoryError; end
        class RetrievalError < HistoryError; end

        def initialize(ui_components = {})
          super()
          @formatter = ui_components[:formatter] || JobHistoryFormatter.new
          @storage_path = ui_components[:storage_path] || ".aidp/job_history"
          @max_history_size = ui_components[:max_history_size] || 1000
          @history = []
          @persistence_enabled = true

          ensure_storage_directory
          load_history_from_storage
        end

        def record_job_event(job_id, event_type, event_data = {})
          validate_job_id(job_id)
          validate_event_type(event_type)

          event = create_history_event(job_id, event_type, event_data)
          @history << event

          # Maintain history size limit
          trim_history_if_needed

          # Persist to storage
          persist_history if @persistence_enabled

          event
        rescue => e
          raise HistoryError, "Failed to record job event: #{e.message}"
        end

        def get_job_history(job_id)
          validate_job_id(job_id)

          @history.select { |event| event[:job_id] == job_id }
        end

        def get_history_by_event_type(event_type)
          validate_event_type(event_type)

          @history.select { |event| event[:event_type] == event_type }
        end

        def get_history_by_date_range(start_date, end_date)
          validate_date_range(start_date, end_date)

          @history.select do |event|
            event_date = event[:timestamp]
            event_date.between?(start_date, end_date)
          end
        end

        def get_recent_history(limit = 50)
          validate_limit(limit)

          @history.last(limit)
        end

        def search_history(search_criteria)
          validate_search_criteria(search_criteria)

          results = @history.dup

          search_criteria.each do |criteria, value|
            results = apply_search_criteria(results, criteria, value)
          end

          results
        end

        def export_history(format = :json, file_path = nil)
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
            raise PersistenceError, "Unsupported export format: #{format}"
          end

          CLI::UI.puts(@formatter.format_export_success(file_path, @history.size))
          file_path
        rescue => e
          raise PersistenceError, "Failed to export history: #{e.message}"
        end

        def import_history(file_path, format = :json)
          validate_file_path(file_path)
          validate_import_format(format)

          case format
          when :json
            import_from_json(file_path)
          when :csv
            import_from_csv(file_path)
          when :yaml
            import_from_yaml(file_path)
          else
            raise PersistenceError, "Unsupported import format: #{format}"
          end

          CLI::UI.puts(@formatter.format_import_success(file_path, @history.size))
        rescue => e
          raise PersistenceError, "Failed to import history: #{e.message}"
        end

        def clear_history
          @history.clear
          persist_history if @persistence_enabled
          CLI::UI.puts(@formatter.format_history_cleared)
        end

        def get_history_summary
          {
            total_events: @history.size,
            events_by_type: @history.map { |event| event[:event_type] }.tally,
            events_by_job: @history.map { |event| event[:job_id] }.tally,
            date_range: get_date_range,
            storage_path: @storage_path,
            persistence_enabled: @persistence_enabled
          }
        end

        def display_history_summary
          summary = get_history_summary
          @formatter.display_history_summary(summary)
        end

        def display_job_timeline(job_id)
          job_history = get_job_history(job_id)

          if job_history.empty?
            CLI::UI.puts(@formatter.format_no_job_history(job_id))
            return
          end

          @formatter.display_job_timeline(job_id, job_history)
        end

        def enable_persistence
          @persistence_enabled = true
          persist_history
          CLI::UI.puts(@formatter.format_persistence_enabled)
        end

        def disable_persistence
          @persistence_enabled = false
          CLI::UI.puts(@formatter.format_persistence_disabled)
        end

        private

        def validate_job_id(job_id)
          raise HistoryError, "Job ID cannot be empty" if job_id.to_s.strip.empty?
        end

        def validate_event_type(event_type)
          raise HistoryError, "Event type cannot be empty" if event_type.to_s.strip.empty?
        end

        def validate_date_range(start_date, end_date)
          raise HistoryError, "Start date must be a Time object" unless start_date.is_a?(Time)
          raise HistoryError, "End date must be a Time object" unless end_date.is_a?(Time)
          raise HistoryError, "Start date must be before end date" if start_date > end_date
        end

        def validate_limit(limit)
          raise HistoryError, "Limit must be a positive integer" unless limit.is_a?(Integer) && limit > 0
        end

        def validate_search_criteria(search_criteria)
          raise HistoryError, "Search criteria must be a hash" unless search_criteria.is_a?(Hash)
        end

        def validate_export_format(format)
          valid_formats = [:json, :csv, :yaml]
          unless valid_formats.include?(format)
            raise PersistenceError, "Invalid export format: #{format}. Must be one of: #{valid_formats.join(", ")}"
          end
        end

        def validate_import_format(format)
          valid_formats = [:json, :csv, :yaml]
          unless valid_formats.include?(format)
            raise PersistenceError, "Invalid import format: #{format}. Must be one of: #{valid_formats.join(", ")}"
          end
        end

        def validate_file_path(file_path)
          raise PersistenceError, "File path cannot be empty" if file_path.to_s.strip.empty?
        end

        def create_history_event(job_id, event_type, event_data)
          {
            id: generate_event_id,
            job_id: job_id,
            event_type: event_type,
            timestamp: Time.now,
            data: event_data,
            metadata: {
              version: "1.0",
              source: "job_history"
            }
          }
        end

        def generate_event_id
          "#{Time.now.to_i}_#{rand(10000)}"
        end

        def trim_history_if_needed
          if @history.size > @max_history_size
            @history = @history.last(@max_history_size)
          end
        end

        def ensure_storage_directory
          FileUtils.mkdir_p(File.dirname(@storage_path))
        end

        def load_history_from_storage
          return unless File.exist?(@storage_path)

          begin
            history_data = JSON.parse(File.read(@storage_path), symbolize_names: true)
            @history = history_data[:events] || []
          rescue => e
            CLI::UI.puts(@formatter.format_load_error(e.message))
            @history = []
          end
        end

        def persist_history
          return unless @persistence_enabled

          history_data = {
            version: "1.0",
            last_updated: Time.now,
            events: @history
          }

          File.write(@storage_path, JSON.pretty_generate(history_data))
        rescue => e
          CLI::UI.puts(@formatter.format_persistence_error(e.message))
        end

        def generate_export_file_path(format)
          timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
          "job_history_#{timestamp}.#{format}"
        end

        def export_to_json(file_path)
          history_data = {
            version: "1.0",
            exported_at: Time.now,
            total_events: @history.size,
            events: @history
          }

          File.write(file_path, JSON.pretty_generate(history_data))
        end

        def export_to_csv(file_path)
          require "csv"

          CSV.open(file_path, "w") do |csv|
            csv << ["ID", "Job ID", "Event Type", "Timestamp", "Data"]

            @history.each do |event|
              csv << [
                event[:id],
                event[:job_id],
                event[:event_type],
                event[:timestamp].iso8601,
                event[:data].to_json
              ]
            end
          end
        end

        def export_to_yaml(file_path)
          require "yaml"

          history_data = {
            version: "1.0",
            exported_at: Time.now,
            total_events: @history.size,
            events: @history
          }

          File.write(file_path, history_data.to_yaml)
        end

        def import_from_json(file_path)
          history_data = JSON.parse(File.read(file_path), symbolize_names: true)
          imported_events = history_data[:events] || []

          @history.concat(imported_events)
          trim_history_if_needed
          persist_history if @persistence_enabled
        end

        def import_from_csv(file_path)
          require "csv"

          CSV.foreach(file_path, headers: true) do |row|
            event = {
              id: row["ID"],
              job_id: row["Job ID"],
              event_type: row["Event Type"],
              timestamp: Time.parse(row["Timestamp"]),
              data: JSON.parse(row["Data"], symbolize_names: true),
              metadata: {version: "1.0", source: "imported"}
            }

            @history << event
          end

          trim_history_if_needed
          persist_history if @persistence_enabled
        end

        def import_from_yaml(file_path)
          require "yaml"

          history_data = YAML.load_file(file_path)
          imported_events = history_data[:events] || []

          @history.concat(imported_events)
          trim_history_if_needed
          persist_history if @persistence_enabled
        end

        def apply_search_criteria(events, criteria, value)
          case criteria
          when :job_id
            events.select { |event| event[:job_id] == value }
          when :event_type
            events.select { |event| event[:event_type] == value }
          when :date_range
            start_date, end_date = value[:start], value[:end]
            events.select do |event|
              event[:timestamp].between?(start_date, end_date)
            end
          when :data_contains
            events.select do |event|
              event[:data].to_s.downcase.include?(value.downcase)
            end
          else
            events
          end
        end

        def get_date_range
          return {start: nil, end: nil} if @history.empty?

          timestamps = @history.map { |event| event[:timestamp] }
          {start: timestamps.min, end: timestamps.max}
        end
      end

      # Formats job history display
      class JobHistoryFormatter
        def display_history_summary(summary)
          CLI::UI.puts(CLI::UI.fmt("{{bold:{{blue:📊 Job History Summary}}}}"))
          CLI::UI.puts("─" * 50)

          CLI::UI.puts("Total events: {{bold:#{summary[:total_events]}}}")
          CLI::UI.puts("Storage path: {{dim:#{summary[:storage_path]}}}")
          CLI::UI.puts("Persistence: #{summary[:persistence_enabled] ? "Enabled" : "Disabled"}")

          if summary[:date_range][:start]
            CLI::UI.puts("Date range: {{dim:#{summary[:date_range][:start]} to #{summary[:date_range][:end]}}}")
          end

          if summary[:events_by_type].any?
            CLI::UI.puts("\nEvents by type:")
            summary[:events_by_type].each do |type, count|
              CLI::UI.puts("  {{dim:#{type}: #{count}}}")
            end
          end

          if summary[:events_by_job].any?
            CLI::UI.puts("\nEvents by job:")
            summary[:events_by_job].each do |job_id, count|
              CLI::UI.puts("  {{dim:#{job_id}: #{count}}}")
            end
          end
        end

        def display_job_timeline(job_id, job_history)
          CLI::UI.puts(CLI::UI.fmt("{{bold:{{blue:📅 Job Timeline: #{job_id}}}}}}"))
          CLI::UI.puts("─" * 50)

          job_history.each do |event|
            CLI::UI.puts(format_timeline_event(event))
          end
        end

        def format_timeline_event(event)
          timestamp = event[:timestamp].strftime("%H:%M:%S")
          event_type = event[:event_type]
          data = event[:data]

          case event_type
          when :registered
            CLI::UI.fmt("{{green:✅ #{timestamp}}} Job registered")
          when :status_changed
            from_status = data[:from]
            to_status = data[:to]
            CLI::UI.fmt("{{blue:🔄 #{timestamp}}} Status: #{from_status} → #{to_status}")
          when :progress_updated
            progress = data[:progress]
            CLI::UI.fmt("{{yellow:📊 #{timestamp}}} Progress: #{progress}%")
          when :error_occurred
            error = data[:error]
            CLI::UI.fmt("{{red:❌ #{timestamp}}} Error: #{error}")
          when :completed
            CLI::UI.fmt("{{green:✅ #{timestamp}}} Job completed")
          when :cancelled
            CLI::UI.fmt("{{red:🚫 #{timestamp}}} Job cancelled")
          else
            CLI::UI.fmt("{{dim:❓ #{timestamp}}} #{event_type}: #{data}")
          end
        end

        def format_export_success(file_path, event_count)
          CLI::UI.fmt("{{green:✅ History exported to #{file_path} (#{event_count} events)}}")
        end

        def format_import_success(file_path, event_count)
          CLI::UI.fmt("{{green:✅ History imported from #{file_path} (#{event_count} events)}}")
        end

        def format_history_cleared
          CLI::UI.fmt("{{yellow:🗑️ Job history cleared}}")
        end

        def format_no_job_history(job_id)
          CLI::UI.fmt("{{dim:No history found for job: #{job_id}}}")
        end

        def format_persistence_enabled
          CLI::UI.fmt("{{green:✅ History persistence enabled}}")
        end

        def format_persistence_disabled
          CLI::UI.fmt("{{red:❌ History persistence disabled}}")
        end

        def format_load_error(error_message)
          CLI::UI.fmt("{{red:❌ Failed to load history: #{error_message}}}")
        end

        def format_persistence_error(error_message)
          CLI::UI.fmt("{{red:❌ Failed to persist history: #{error_message}}}")
        end
      end
    end
  end
end
