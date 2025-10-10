# frozen_string_literal: true

require "json"
require "fileutils"

module Aidp
  module Analyze
    class JsonFileStorage
      def initialize(project_dir = Dir.pwd, storage_dir = ".aidp/json")
        @project_dir = project_dir
        @storage_dir = File.join(project_dir, storage_dir)
        ensure_storage_directory
      end

      # Store data in a JSON file
      def store_data(filename, data)
        file_path = file_path(filename)

        # Ensure directory exists
        FileUtils.mkdir_p(File.dirname(file_path))

        # Write data as pretty JSON
        File.write(file_path, JSON.pretty_generate(data))

        {
          filename: filename,
          file_path: file_path,
          stored_at: Time.now,
          success: true
        }
      end

      # Retrieve data from a JSON file
      def data(filename)
        file_path = file_path(filename)

        return nil unless File.exist?(file_path)

        begin
          JSON.parse(File.read(file_path))
        rescue JSON::ParserError => e
          raise "Invalid JSON in file #{filename}: #{e.message}"
        end
      end

      # Check if a JSON file exists
      def data_exists?(filename)
        File.exist?(file_path(filename))
      end

      # Delete a JSON file
      def delete_data(filename)
        file_path = file_path(filename)

        if File.exist?(file_path)
          File.delete(file_path)
          {
            filename: filename,
            deleted: true,
            deleted_at: Time.now
          }
        else
          {
            filename: filename,
            deleted: false,
            message: "File does not exist"
          }
        end
      end

      # List all JSON files in the storage directory
      def list_files
        return [] unless Dir.exist?(@storage_dir)

        Dir.glob(File.join(@storage_dir, "**", "*.json")).map do |file_path|
          relative_path = file_path.sub("#{@storage_dir}/", "")
          {
            filename: relative_path,
            file_path: file_path,
            size: File.size(file_path),
            modified_at: File.mtime(file_path)
          }
        end
      end

      # Store project configuration
      def store_project_config(config_data)
        store_data("project_config.json", config_data)
      end

      # Get project configuration
      def project_config
        data("project_config.json")
      end

      # Store runtime status
      def store_runtime_status(status_data)
        store_data("runtime_status.json", status_data)
      end

      # Get runtime status
      def runtime_status
        data("runtime_status.json")
      end

      # Store simple metrics
      def store_simple_metrics(metrics_data)
        store_data("simple_metrics.json", metrics_data)
      end

      # Get simple metrics
      def simple_metrics
        data("simple_metrics.json")
      end

      # Store analysis session data
      def store_analysis_session(session_id, session_data)
        store_data("sessions/#{session_id}.json", session_data)
      end

      # Get analysis session data
      def analysis_session(session_id)
        data("sessions/#{session_id}.json")
      end

      # List analysis sessions
      def list_analysis_sessions
        sessions_dir = File.join(@storage_dir, "sessions")
        return [] unless Dir.exist?(sessions_dir)

        Dir.glob(File.join(sessions_dir, "*.json")).map do |file_path|
          session_id = File.basename(file_path, ".json")
          {
            session_id: session_id,
            file_path: file_path,
            size: File.size(file_path),
            modified_at: File.mtime(file_path)
          }
        end
      end

      # Store user preferences
      def store_user_preferences(preferences_data)
        store_data("user_preferences.json", preferences_data)
      end

      # Get user preferences
      def user_preferences
        data("user_preferences.json")
      end

      # Store cache data
      def store_cache(cache_key, cache_data, ttl_seconds = nil)
        cache_data_with_ttl = {
          data: cache_data,
          cached_at: Time.now.iso8601,
          ttl_seconds: ttl_seconds
        }

        store_data("cache/#{cache_key}.json", cache_data_with_ttl)
      end

      # Get cache data (respects TTL)
      def cache(cache_key)
        cache_file_data = data("cache/#{cache_key}.json")
        return nil unless cache_file_data

        # Check TTL if specified
        if cache_file_data["ttl_seconds"]
          cached_at = Time.parse(cache_file_data["cached_at"])
          if Time.now - cached_at > cache_file_data["ttl_seconds"]
            # Cache expired, delete it
            delete_data("cache/#{cache_key}.json")
            return nil
          end
        end

        cache_file_data["data"]
      end

      # Clear expired cache entries
      def clear_expired_cache
        cache_dir = File.join(@storage_dir, "cache")
        return 0 unless Dir.exist?(cache_dir)

        cleared_count = 0
        Dir.glob(File.join(cache_dir, "*.json")).each do |file_path|
          cache_data = JSON.parse(File.read(file_path))
          if cache_data["ttl_seconds"] && cache_data["cached_at"]
            cached_at = Time.parse(cache_data["cached_at"])
            if Time.now - cached_at > cache_data["ttl_seconds"]
              File.delete(file_path)
              cleared_count += 1
            end
          end
        rescue JSON::ParserError
          # Invalid JSON, delete the file
          File.delete(file_path)
          cleared_count += 1
        end

        cleared_count
      end

      # Get storage statistics
      def storage_statistics
        files = list_files

        {
          total_files: files.length,
          total_size: files.sum { |f| f[:size] },
          storage_directory: @storage_dir,
          oldest_file: files.min_by { |f| f[:modified_at] }&.dig(:modified_at),
          newest_file: files.max_by { |f| f[:modified_at] }&.dig(:modified_at),
          file_types: files.group_by { |f| File.extname(f[:filename]) }.transform_values(&:count)
        }
      end

      # Export all data to a single JSON file
      def export_all_data(export_filename = "aidp_data_export.json")
        export_data = {
          "exported_at" => Time.now.iso8601,
          "storage_directory" => @storage_dir,
          "files" => {}
        }

        files = list_files
        files.each do |file_info|
          data = data(file_info[:filename])
          export_data["files"][file_info[:filename]] = {
            "data" => data,
            "metadata" => {
              "size" => file_info[:size],
              "modified_at" => file_info[:modified_at]
            }
          }
        end

        export_path = File.join(@storage_dir, export_filename)
        File.write(export_path, JSON.pretty_generate(export_data))

        {
          export_filename: export_filename,
          export_path: export_path,
          files_exported: files.length,
          exported_at: Time.now
        }
      end

      # Import data from an exported JSON file
      def import_data(import_filename)
        import_path = file_path(import_filename)

        unless File.exist?(import_path)
          raise "Import file does not exist: #{import_filename}"
        end

        begin
          import_data = JSON.parse(File.read(import_path))
        rescue JSON::ParserError => e
          raise "Invalid JSON in import file: #{e.message}"
        end

        unless import_data["files"]
          raise "Invalid import file format: missing 'files' key"
        end

        imported_count = 0
        import_data["files"].each do |filename, file_data|
          store_data(filename, file_data["data"])
          imported_count += 1
        end

        {
          imported_count: imported_count,
          imported_at: Time.now,
          success: true
        }
      end

      private

      def file_path(filename)
        File.join(@storage_dir, filename)
      end

      def ensure_storage_directory
        FileUtils.mkdir_p(@storage_dir)
      end
    end
  end
end
