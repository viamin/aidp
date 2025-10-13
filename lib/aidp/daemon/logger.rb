# frozen_string_literal: true

require "logger"
require "fileutils"

module Aidp
  module Daemon
    # Structured logger for daemon background operations
    # Writes to .aidp/logs/ with rotation and structured formatting
    class DaemonLogger
      LOG_DIR = ".aidp/logs"
      CURRENT_LOG = "#{LOG_DIR}/current.log"
      MAX_LOG_SIZE = 10 * 1024 * 1024 # 10MB
      MAX_LOG_FILES = 5

      attr_reader :logger

      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
        @log_dir = File.join(@project_dir, LOG_DIR)
        @current_log = File.join(@project_dir, CURRENT_LOG)
        ensure_log_dir
        @logger = create_logger
      end

      # Log structured event
      def log_event(level, event_type, message, **metadata)
        structured = {
          timestamp: Time.now.iso8601,
          level: level.to_s.upcase,
          event: event_type,
          message: message
        }.merge(metadata)

        @logger.send(level, format_log_entry(structured))
      end

      # Convenience methods
      def info(event_type, message, **metadata)
        log_event(:info, event_type, message, **metadata)
      end

      def warn(event_type, message, **metadata)
        log_event(:warn, event_type, message, **metadata)
      end

      def error(event_type, message, **metadata)
        log_event(:error, event_type, message, **metadata)
      end

      def debug(event_type, message, **metadata)
        log_event(:debug, event_type, message, **metadata)
      end

      # Log work loop iteration
      def log_iteration(step_name, iteration, status, **metadata)
        log_event(
          :info,
          "work_loop_iteration",
          "Iteration #{iteration} for #{step_name}: #{status}",
          step: step_name,
          iteration: iteration,
          status: status,
          **metadata
        )
      end

      # Log daemon lifecycle event
      def log_lifecycle(event, **metadata)
        log_event(:info, "daemon_lifecycle", event, **metadata)
      end

      # Log watch mode event
      def log_watch(event, **metadata)
        log_event(:info, "watch_mode", event, **metadata)
      end

      # Get recent log entries (for replay on attach)
      def recent_entries(count: 50)
        return [] unless File.exist?(@current_log)

        lines = File.readlines(@current_log).last(count)
        lines.map { |line| parse_log_entry(line) }.compact
      rescue => e
        [{error: "Failed to read log: #{e.message}"}]
      end

      # Get activity summary (for attach replay)
      def activity_summary(since: Time.now - 3600)
        entries = recent_entries(count: 1000)
        entries = entries.select { |e| e[:timestamp] && Time.parse(e[:timestamp]) >= since }

        {
          total_events: entries.size,
          by_event_type: entries.group_by { |e| e[:event] }.transform_values(&:size),
          by_level: entries.group_by { |e| e[:level] }.transform_values(&:size),
          recent: entries.last(10)
        }
      rescue => e
        {error: "Failed to generate summary: #{e.message}"}
      end

      private

      def ensure_log_dir
        FileUtils.mkdir_p(@log_dir) unless Dir.exist?(@log_dir)
      end

      def create_logger
        logger = Logger.new(
          @current_log,
          MAX_LOG_FILES,
          MAX_LOG_SIZE
        )
        logger.level = Logger::INFO
        logger.formatter = proc do |severity, datetime, progname, msg|
          "#{msg}\n"
        end
        logger
      end

      def format_log_entry(data)
        # JSON-like format for easy parsing
        parts = [
          "[#{data[:timestamp]}]",
          data[:level],
          data[:event],
          "-",
          data[:message]
        ]

        # Add metadata
        metadata = data.except(:timestamp, :level, :event, :message)
        unless metadata.empty?
          metadata_str = metadata.map { |k, v| "#{k}=#{v}" }.join(" ")
          parts << "|" << metadata_str
        end

        parts.join(" ")
      end

      def parse_log_entry(line)
        # Parse structured log format
        return nil if line.strip.empty?

        parts = line.match(/\[([^\]]+)\]\s+(\w+)\s+(\w+)\s+-\s+([^|]+)(?:\s+\|\s+(.+))?/)
        return {raw: line} unless parts

        entry = {
          timestamp: parts[1],
          level: parts[2],
          event: parts[3],
          message: parts[4].strip
        }

        # Parse metadata if present
        parts[5]&.split&.each do |pair|
          key, value = pair.split("=", 2)
          entry[key.to_sym] = value if key && value
        end

        entry
      rescue => e
        {raw: line, parse_error: e.message}
      end
    end
  end
end
