# frozen_string_literal: true

require "json"
require "fileutils"
require "aidp/rescue_logging"

module Aidp
  module Storage
    # Simple JSON file storage for structured data
    class JsonStorage
      include Aidp::RescueLogging

      def initialize(base_dir = ".aidp")
        @base_dir = sanitize_base_dir(base_dir)
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
        log_rescue(error,
          component: "json_storage",
          action: "store",
          fallback: {success: false},
          filename: filename,
          path: file_path)
        {filename: filename, error: error.message, success: false}
      end

      # Load data from JSON file
      def load(filename)
        file_path = get_file_path(filename)
        return nil unless File.exist?(file_path)

        content = File.read(file_path)
        json_data = JSON.parse(content)
        json_data["data"]
      rescue => error
        log_rescue(error,
          component: "json_storage",
          action: "load",
          fallback: nil,
          filename: filename,
          path: (defined?(file_path) ? file_path : nil))
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
        log_rescue(error,
          component: "json_storage",
          action: "update",
          fallback: {success: false},
          filename: filename,
          path: (defined?(file_path) ? file_path : nil))
        {filename: filename, error: error.message, success: false}
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
        log_rescue(error,
          component: "json_storage",
          action: "delete",
          fallback: {success: false},
          filename: filename,
          path: file_path)
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
        log_rescue(error,
          component: "json_storage",
          action: "metadata",
          fallback: nil,
          filename: filename,
          path: (defined?(file_path) ? file_path : nil))
        nil
      end

      private

      def get_file_path(filename)
        # Ensure filename has .json extension
        filename += ".json" unless filename.end_with?(".json")
        File.join(@base_dir, filename)
      end

      def ensure_directory_exists
        return if Dir.exist?(@base_dir)
        begin
          FileUtils.mkdir_p(@base_dir)
        rescue SystemCallError => e
          # Fallback when directory creation fails (e.g., attempting to write to '/.aidp')
          fallback = begin
            home = Dir.respond_to?(:home) ? Dir.home : nil
            if home && !home.empty? && File.writable?(home)
              File.join(home, ".aidp")
            else
              File.join(Dir.tmpdir, "aidp_storage")
            end
          rescue
            File.join(Dir.tmpdir, "aidp_storage")
          end
          Kernel.warn "[AIDP Storage] Cannot create base directory #{@base_dir}: #{e.class}: #{e.message}. Using fallback #{fallback}"
          @base_dir = fallback
          begin
            FileUtils.mkdir_p(@base_dir) unless Dir.exist?(@base_dir)
          rescue SystemCallError => e2
            Kernel.warn "[AIDP Storage] Fallback directory creation also failed: #{e2.class}: #{e2.message}. Continuing without persistent JSON storage."
          end
        end
      end

      def sanitize_base_dir(dir)
        return Dir.pwd if dir.nil? || dir.to_s.strip.empty?
        str = dir.to_s
        # If given root '/', redirect to a writable location to avoid EACCES on CI
        if str == File::SEPARATOR
          fallback = begin
            home = Dir.home
            (home && !home.empty? && File.writable?(home)) ? File.join(home, ".aidp") : File.join(Dir.tmpdir, "aidp_storage")
          rescue
            File.join(Dir.tmpdir, "aidp_storage")
          end
          Kernel.warn "[AIDP Storage] Root base_dir detected - using fallback #{fallback} instead of '#{str}'"
          return fallback
        end
        str
      end
    end
  end
end
