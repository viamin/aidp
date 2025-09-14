# frozen_string_literal: true

require "json"
require "fileutils"

module Aidp
  module Storage
    # Simple JSON file storage for structured data
    class JsonStorage
      def initialize(base_dir = ".aidp")
        @base_dir = base_dir
        ensure_directory_exists
      end

      # Store data as JSON file
      def store(filename, data)
        file_path = get_file_path(filename)
        FileUtils.mkdir_p(File.dirname(file_path))

        json_data = {
          "data" => data,
          "created_at" => Time.now.iso8601,
          "updated_at" => Time.now.iso8601
        }

        File.write(file_path, JSON.pretty_generate(json_data))

        {
          filename: filename,
          file_path: file_path,
          stored_at: Time.now,
          success: true
        }
      rescue => error
        {
          filename: filename,
          error: error.message,
          success: false
        }
      end

      # Load data from JSON file
      def load(filename)
        file_path = get_file_path(filename)
        return nil unless File.exist?(file_path)

        content = File.read(file_path)
        json_data = JSON.parse(content)
        json_data["data"]
      rescue => error
        puts "Error loading #{filename}: #{error.message}" if ENV["AIDP_DEBUG"]
        nil
      end

      # Update existing data
      def update(filename, data)
        existing = load(filename)
        return store(filename, data) unless existing

        file_path = get_file_path(filename)
        json_data = JSON.parse(File.read(file_path))

        json_data["data"] = data
        json_data["updated_at"] = Time.now.iso8601

        File.write(file_path, JSON.pretty_generate(json_data))

        {
          filename: filename,
          file_path: file_path,
          updated_at: Time.now,
          success: true
        }
      rescue => error
        {
          filename: filename,
          error: error.message,
          success: false
        }
      end

      # Check if file exists
      def exists?(filename)
        File.exist?(get_file_path(filename))
      end

      # Delete file
      def delete(filename)
        file_path = get_file_path(filename)
        return {success: true, message: "File does not exist"} unless File.exist?(file_path)

        File.delete(file_path)
        {success: true, message: "File deleted"}
      rescue => error
        {success: false, error: error.message}
      end

      # List all JSON files
      def list
        return [] unless Dir.exist?(@base_dir)

        Dir.glob(File.join(@base_dir, "**", "*.json")).map do |file|
          File.basename(file, ".json")
        end
      end

      # Get file metadata
      def metadata(filename)
        file_path = get_file_path(filename)
        return nil unless File.exist?(file_path)

        content = File.read(file_path)
        json_data = JSON.parse(content)

        {
          filename: filename,
          file_path: file_path,
          created_at: json_data["created_at"],
          updated_at: json_data["updated_at"],
          size: File.size(file_path)
        }
      rescue => error
        puts "Error getting metadata for #{filename}: #{error.message}" if ENV["AIDP_DEBUG"]
        nil
      end

      private

      def get_file_path(filename)
        # Ensure filename has .json extension
        filename += ".json" unless filename.end_with?(".json")
        File.join(@base_dir, filename)
      end

      def ensure_directory_exists
        FileUtils.mkdir_p(@base_dir) unless Dir.exist?(@base_dir)
      end
    end
  end
end
