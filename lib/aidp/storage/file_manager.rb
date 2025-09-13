# frozen_string_literal: true

require_relative "json_storage"
require_relative "csv_storage"

module Aidp
  module Storage
    # Simple file manager that provides easy access to JSON and CSV storage
    class FileManager
      def initialize(base_dir = ".aidp")
        @base_dir = base_dir
        @json_storage = JsonStorage.new(base_dir)
        @csv_storage = CsvStorage.new(base_dir)
      end

      # JSON operations for structured data
      def store_json(filename, data)
        @json_storage.store(filename, data)
      end

      def load_json(filename)
        @json_storage.load(filename)
      end

      def update_json(filename, data)
        @json_storage.update(filename, data)
      end

      def json_exists?(filename)
        @json_storage.exists?(filename)
      end

      def json_metadata(filename)
        @json_storage.metadata(filename)
      end

      # CSV operations for tabular data
      def append_csv(filename, row_data)
        @csv_storage.append(filename, row_data)
      end

      def read_csv(filename, filters = {})
        if filters.empty?
          @csv_storage.read_all(filename)
        else
          @csv_storage.read_filtered(filename, filters)
        end
      end

      def csv_summary(filename)
        @csv_storage.summary(filename)
      end

      def csv_exists?(filename)
        @csv_storage.exists?(filename)
      end

      # Convenience methods for common data types

      # Analysis results (structured data)
      def store_analysis_result(step_name, data, metadata = {})
        result = {
          step_name: step_name,
          data: data,
          metadata: metadata
        }
        store_json("analysis_results", result)
      end

      def load_analysis_result
        load_json("analysis_results")
      end

      # Embeddings (structured data)
      def store_embeddings(step_name, embeddings_data)
        result = {
          step_name: step_name,
          embeddings_data: embeddings_data
        }
        store_json("embeddings", result)
      end

      def load_embeddings
        load_json("embeddings")
      end

      # Metrics (tabular data)
      def record_metric(step_name, metric_name, value, metadata = {})
        row_data = {
          step_name: step_name,
          metric_name: metric_name,
          value: value,
          recorded_at: Time.now.iso8601
        }.merge(metadata)

        append_csv("metrics", row_data)
      end

      def get_metrics(filters = {})
        read_csv("metrics", filters)
      end

      def get_metrics_summary
        csv_summary("metrics")
      end

      # Step executions (tabular data)
      def record_step_execution(step_name, provider_name, duration, success, metadata = {})
        row_data = {
          step_name: step_name,
          provider_name: provider_name,
          duration: duration,
          success: success,
          created_at: Time.now.iso8601
        }.merge(metadata)

        append_csv("step_executions", row_data)
      end

      def get_step_executions(filters = {})
        read_csv("step_executions", filters)
      end

      def get_step_executions_summary
        csv_summary("step_executions")
      end

      # Provider activities (tabular data)
      def record_provider_activity(provider_name, step_name, start_time, end_time, duration, final_state, stuck_detected = false)
        row_data = {
          provider_name: provider_name,
          step_name: step_name,
          start_time: start_time&.iso8601,
          end_time: end_time&.iso8601,
          duration: duration,
          final_state: final_state,
          stuck_detected: stuck_detected,
          created_at: Time.now.iso8601
        }

        append_csv("provider_activities", row_data)
      end

      def get_provider_activities(filters = {})
        read_csv("provider_activities", filters)
      end

      def get_provider_activities_summary
        csv_summary("provider_activities")
      end

      # Configuration and status (structured data)
      def store_config(config_data)
        store_json("config", config_data)
      end

      def load_config
        load_json("config")
      end

      def store_status(status_data)
        store_json("status", status_data)
      end

      def load_status
        load_json("status")
      end

      # List all files
      def list_json_files
        @json_storage.list
      end

      def list_csv_files
        @csv_storage.list
      end

      def list_all_files
        {
          json_files: list_json_files,
          csv_files: list_csv_files
        }
      end

      # Backup and restore
      def backup_to(destination_dir)
        FileUtils.mkdir_p(destination_dir)
        # Copy contents of base_dir to destination_dir, avoiding recursive copying
        if Dir.exist?(@base_dir)
          Dir.glob(File.join(@base_dir, "*")).each do |item|
            next if File.expand_path(item) == File.expand_path(destination_dir)
            FileUtils.cp_r(item, destination_dir)
          end
        end
        { success: true, backup_location: destination_dir }
      rescue => error
        { success: false, error: error.message }
      end

      def restore_from(source_dir)
        return { success: false, error: "Source directory does not exist" } unless Dir.exist?(source_dir)

        # Clear existing data
        FileUtils.rm_rf(@base_dir) if Dir.exist?(@base_dir)

        # Copy from source
        FileUtils.cp_r(source_dir, @base_dir)
        { success: true, restored_from: source_dir }
      rescue => error
        { success: false, error: error.message }
      end
    end
  end
end
