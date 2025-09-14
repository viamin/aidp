# frozen_string_literal: true

require "csv"
require "fileutils"

module Aidp
  module Storage
    # Simple CSV file storage for tabular data
    class CsvStorage
      def initialize(base_dir = ".aidp")
        @base_dir = base_dir
        ensure_directory_exists
      end

      # Append a row to CSV file
      def append(filename, row_data)
        file_path = get_file_path(filename)
        FileUtils.mkdir_p(File.dirname(file_path))

        # Add timestamp if not present
        row_data["created_at"] ||= Time.now.iso8601

        # Convert all values to strings
        row_data = row_data.transform_values(&:to_s)

        # If file doesn't exist, write headers first
        if !File.exist?(file_path)
          CSV.open(file_path, "w") do |csv|
            csv << row_data.keys
          end
        end

        # Append the row
        CSV.open(file_path, "a") do |csv|
          csv << row_data.values
        end

        {
          filename: filename,
          file_path: file_path,
          row_count: count_rows(filename),
          success: true
        }
      rescue => error
        {
          filename: filename,
          error: error.message,
          success: false
        }
      end

      # Read all rows from CSV file
      def read_all(filename)
        file_path = get_file_path(filename)
        return [] unless File.exist?(file_path)

        rows = []
        CSV.foreach(file_path, headers: true) do |row|
          rows << row.to_h
        end
        rows
      rescue => error
        puts "Error reading #{filename}: #{error.message}" if ENV["AIDP_DEBUG"]
        []
      end

      # Read rows with filtering
      def read_filtered(filename, filters = {})
        all_rows = read_all(filename)
        return all_rows if filters.empty?

        all_rows.select do |row|
          filters.all? { |key, value| row[key.to_s] == value.to_s }
        end
      end

      # Count rows in CSV file
      def count_rows(filename)
        file_path = get_file_path(filename)
        return 0 unless File.exist?(file_path)

        count = 0
        CSV.foreach(file_path) { count += 1 }
        count - 1 # Subtract 1 for header row
      rescue => error
        puts "Error counting rows in #{filename}: #{error.message}" if ENV["AIDP_DEBUG"]
        0
      end

      # Get unique values for a column
      def unique_values(filename, column)
        all_rows = read_all(filename)
        all_rows.map { |row| row[column.to_s] }.compact.uniq
      end

      # Get summary statistics
      def summary(filename)
        file_path = get_file_path(filename)
        return nil unless File.exist?(file_path)

        rows = read_all(filename)
        return nil if rows.empty?

        headers = rows.first.keys
        numeric_columns = headers.select do |col|
          rows.all? { |row| row[col] =~ /^-?\d+\.?\d*$/ }
        end

        summary_data = {
          filename: filename,
          file_path: file_path,
          total_rows: rows.length,
          columns: headers,
          numeric_columns: numeric_columns,
          file_size: File.size(file_path)
        }

        # Add basic stats for numeric columns
        numeric_columns.each do |col|
          values = rows.map { |row| row[col].to_f }
          summary_data["#{col}_stats"] = {
            min: values.min,
            max: values.max,
            avg: values.sum / values.length
          }
        end

        summary_data
      rescue => error
        puts "Error generating summary for #{filename}: #{error.message}" if ENV["AIDP_DEBUG"]
        nil
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

      # List all CSV files
      def list
        return [] unless Dir.exist?(@base_dir)

        Dir.glob(File.join(@base_dir, "**", "*.csv")).map do |file|
          File.basename(file, ".csv")
        end
      end

      private

      def get_file_path(filename)
        # Ensure filename has .csv extension
        filename += ".csv" unless filename.end_with?(".csv")
        File.join(@base_dir, filename)
      end

      def ensure_directory_exists
        FileUtils.mkdir_p(@base_dir) unless Dir.exist?(@base_dir)
      end
    end
  end
end
