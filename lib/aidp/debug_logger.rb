# frozen_string_literal: true

require "fileutils"
require "json"
require "pastel"

module Aidp
  # Debug logger that outputs to both console and a single log file
  class DebugLogger
    LOG_LEVELS = {
      debug: 0,
      info: 1,
      warn: 2,
      error: 3
    }.freeze

    def initialize(log_dir: nil)
      @log_dir = log_dir || default_log_dir
      @log_file = nil
      @run_started = false
      ensure_log_directory
      log_run_banner
    end

    def log(message, level: :info, data: nil)
      timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S.%3N")
      level_str = level.to_s.upcase.ljust(5)

      # Format message with timestamp and level
      formatted_message = "[#{timestamp}] #{level_str} #{message}"

      # Add data if present
      if data && !data.empty?
        data_str = format_data(data)
        formatted_message += "\n#{data_str}" if data_str
      end

      # Output to console
      output_to_console(formatted_message, level)

      # Output to log file
      output_to_file(formatted_message, level, data)
    end

    def close
      @log_file&.close
      @log_file = nil
    end

    private

    def default_log_dir
      File.join(Dir.pwd, ".aidp", "debug_logs")
    end

    def ensure_log_directory
      FileUtils.mkdir_p(@log_dir) unless Dir.exist?(@log_dir)
    end

    def log_file_path
      @log_file_path ||= File.join(@log_dir, "aidp_debug.log")
    end

    def get_log_file
      return @log_file if @log_file && !@log_file.closed?

      @log_file = File.open(log_file_path, "a")
      @log_file
    end

    def log_run_banner
      return if @run_started
      @run_started = true

      timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S.%3N")
      command_line = build_command_line

      banner = <<~BANNER

        ================================================================================
        AIDP DEBUG SESSION STARTED
        ================================================================================
        Timestamp: #{timestamp}
        Command: #{command_line}
        Working Directory: #{Dir.pwd}
        Debug Level: #{ENV["DEBUG"] || "0"}
        ================================================================================
      BANNER

      # Write banner to log file
      file = get_log_file
      file.puts banner
      file.flush

      # Also output to console if debug is enabled
      if ENV["DEBUG"] && ENV["DEBUG"].to_i > 0
        puts "\e[36m#{banner}\e[0m"  # Cyan color
      end
    end

    def build_command_line
      # Get the command line arguments
      cmd_parts = []

      # Add the main command (aidp)
      cmd_parts << "aidp"

      # Add any arguments from ARGV
      if defined?(ARGV) && !ARGV.empty?
        cmd_parts.concat(ARGV)
      end

      # Add environment variables that affect behavior
      env_vars = []
      env_vars << "DEBUG=#{ENV["DEBUG"]}" if ENV["DEBUG"]
      env_vars << "AIDP_CONFIG=#{ENV["AIDP_CONFIG"]}" if ENV["AIDP_CONFIG"]

      if env_vars.any?
        cmd_parts << "(" + env_vars.join(" ") + ")"
      end

      cmd_parts.join(" ")
    end

    def output_to_console(message, level)
      case level
      when :error
        warn message
      when :warn
        puts "\e[33m#{message}\e[0m"  # Yellow
      when :info
        puts "\e[36m#{message}\e[0m"   # Cyan
      when :debug
        puts "\e[90m#{message}\e[0m"   # Gray
      else
        puts message
      end
    end

    def output_to_file(message, level, data)
      file = get_log_file
      file.puts message

      # Add structured data if present
      if data && !data.empty?
        structured_data = {
          timestamp: Time.now.strftime("%Y-%m-%dT%H:%M:%S.%3N%z"),
          level: level.to_s,
          message: message,
          data: data
        }
        file.puts "DATA: #{JSON.generate(structured_data)}"
      end

      file.flush
    end

    def format_data(data)
      return nil if data.nil? || data.empty?

      case data
      when Hash
        format_hash_data(data)
      when Array
        format_array_data(data)
      when String
        (data.length > 200) ? "#{data[0..200]}..." : data
      else
        data.to_s
      end
    end

    def format_hash_data(hash)
      lines = []
      hash.each do |key, value|
        lines << if value.is_a?(String) && value.length > 100
          "  #{key}: #{value[0..100]}..."
        elsif value.is_a?(Hash) || value.is_a?(Array)
          "  #{key}: #{JSON.pretty_generate(value).gsub("\n", "\n    ")}"
        else
          "  #{key}: #{value}"
        end
      end
      lines.join("\n")
    end

    def format_array_data(array)
      if array.length > 10
        "#{array.first(5).join(", ")}... (#{array.length} total items)"
      else
        array.join(", ")
      end
    end
  end
end
