# frozen_string_literal: true

require "logger"
require "json"
require "fileutils"
require "pathname"

module Aidp
  # Unified structured logger for all AIDP operations
  # Supports:
  # - Multiple log levels (info, error, debug)
  # - Text and JSONL formats
  # - Automatic rotation
  # - Redaction of secrets
  # - Consistent file layout in .aidp/logs/
  #
  # Usage:
  #   Aidp.setup_logger(project_dir, config)
  #   Aidp.logger.info("component", "message", key: "value")
  class Logger
    # Custom log device that suppresses IOError exceptions for closed streams.
    # This prevents "log shifting failed. closed stream" errors during test cleanup.
    class SafeLogDevice < ::Logger::LogDevice
      private

      # Override handle_write_errors to suppress warnings for closed stream errors.
      # Ruby's Logger::LogDevice calls warn() when write operations fail, which
      # produces "log shifting failed. closed stream" messages during test cleanup.
      def handle_write_errors(mesg)
        yield
      rescue *@reraise_write_errors
        raise
      rescue IOError => e
        # Silently ignore closed stream errors - these are expected during
        # test cleanup when loggers are finalized after streams are closed
        return if e.message.include?("closed stream")
        warn("log #{mesg} failed. #{e}")
      rescue => e
        warn("log #{mesg} failed. #{e}")
      end
    end
    LEVELS = {
      debug: ::Logger::DEBUG,
      info: ::Logger::INFO,
      warn: ::Logger::WARN,
      error: ::Logger::ERROR
    }.freeze

    LOG_DIR = ".aidp/logs"
    INFO_LOG = "#{LOG_DIR}/aidp.log"

    DEFAULT_MAX_SIZE = 10 * 1024 * 1024 # 10MB
    DEFAULT_MAX_FILES = 5

    attr_reader :level, :json_format

    def initialize(project_dir = Dir.pwd, config = {})
      @project_dir = sanitize_project_dir(project_dir)
      @config = config
      @level = determine_log_level
      @json_format = config[:json] || false
      @max_size = config[:max_size_mb] ? config[:max_size_mb] * 1024 * 1024 : DEFAULT_MAX_SIZE
      @max_files = config[:max_backups] || DEFAULT_MAX_FILES
      @instrument_internal = config.key?(:instrument) ? config[:instrument] : (ENV["AIDP_LOG_INSTRUMENT"] == "1")

      ensure_log_directory
      setup_logger
    end

    # Log info level message
    def info(component, message, **metadata)
      log(:info, component, message, **metadata)
    end

    # Log error level message
    def error(component, message, **metadata)
      log(:error, component, message, **metadata)
    end

    # Log warn level message
    def warn(component, message, **metadata)
      log(:warn, component, message, **metadata)
    end

    # Log debug level message
    def debug(component, message, **metadata)
      log(:debug, component, message, **metadata)
    end

    # Log at specified level
    def log(level, component, message, **metadata)
      return unless should_log?(level)

      # Redact sensitive data
      safe_message = redact(message)
      safe_metadata = redact_hash(metadata)

      write_entry(level, component, safe_message, safe_metadata)
    end

    # Close all loggers
    def close
      @logger&.close
    end

    private

    def determine_log_level
      # Priority: explicit env override > DEBUG flags > config > default
      level_str = if ENV["AIDP_LOG_LEVEL"]
        ENV["AIDP_LOG_LEVEL"]
      elsif debug_env_enabled?
        "debug"
      elsif @config[:level]
        @config[:level]
      else
        "info"
      end
      level_sym = level_str.to_s.to_sym
      LEVELS.key?(level_sym) ? level_sym : :info
    end

    def debug_env_enabled?
      raw = ENV["AIDP_DEBUG"] || ENV["DEBUG"]
      return false if raw.nil?

      normalized = raw.to_s.strip.downcase
      return true if %w[true on yes debug].include?(normalized)

      /\A\d+\z/.match?(normalized) ? normalized.to_i.positive? : false
    end

    def should_log?(level)
      LEVELS[level] >= LEVELS[@level]
    end

    def ensure_log_directory
      log_dir = File.join(@project_dir, LOG_DIR)
      return if Dir.exist?(log_dir)
      begin
        FileUtils.mkdir_p(log_dir)
      rescue SystemCallError => e
        Kernel.warn "[AIDP Logger] Cannot create log directory #{log_dir}: #{e.class}: #{e.message}. Falling back to STDERR logging."
        # We intentionally do not re-raise; file logger setup will attempt and then fall back itself.
      end
    end

    def setup_logger
      info_path = determine_log_file_path
      @logger = create_logger(info_path)
      # Emit instrumentation after logger is available (avoid recursive Aidp.log_* calls during bootstrap)
      return unless @instrument_internal
      if defined?(@root_fallback) && @root_fallback
        debug("logger", "root_fallback_applied", effective_dir: @root_fallback)
      end
      debug("logger", "logger_initialized", path: info_path, project_dir: @project_dir)
    end

    def create_logger(path)
      # Ensure parent directory exists before creating logger
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

      # Create logger with custom SafeLogDevice that suppresses closed stream errors
      logdev = SafeLogDevice.new(path, shift_age: @max_files, shift_size: @max_size)
      logger = ::Logger.new(logdev)
      logger.level = ::Logger::DEBUG # Control at write level instead
      logger.formatter = proc { |severity, datetime, progname, msg| "#{msg}\n" }
      logger
    rescue => e
      # Fall back to STDERR if file logging fails
      Kernel.warn "[AIDP Logger] Failed to create log file at #{path}: #{e.message}. Falling back to STDERR."
      logdev = SafeLogDevice.new($stderr)
      logger = ::Logger.new(logdev)
      logger.level = ::Logger::DEBUG
      logger.formatter = proc { |severity, datetime, progname, msg| "#{msg}\n" }
      logger
    end

    def write_entry(level, component, message, metadata)
      entry = format_entry(level, component, message, metadata)
      @logger.send(logger_method(level), entry)
    end

    def logger_method(level)
      case level
      when :debug then :debug
      when :info then :info
      when :warn then :warn
      when :error then :error
      else :info
      end
    end

    def format_entry(level, component, message, metadata)
      if @json_format
        format_json(level, component, message, metadata)
      else
        format_text(level, component, message, metadata)
      end
    end

    def format_text(level, component, message, metadata)
      timestamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
      level_str = level.to_s.upcase
      parts = ["#{timestamp} #{level_str} #{component} #{message}"]

      unless metadata.empty?
        metadata_str = metadata.map { |k, v| "#{k}=#{redact(v.to_s)}" }.join(" ")
        parts << "(#{metadata_str})"
      end

      parts.join(" ")
    end

    def format_json(level, component, message, metadata)
      entry = {
        ts: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
        level: level.to_s,
        component: component,
        msg: message
      }.merge(metadata)

      JSON.generate(entry)
    end

    def determine_log_file_path
      custom = (ENV["AIDP_LOG_FILE"] || @config[:file]).to_s.strip
      relative_path = custom.empty? ? INFO_LOG : custom

      if Pathname.new(relative_path).absolute?
        relative_path
      else
        File.join(@project_dir, relative_path)
      end
    end

    # Redaction patterns for common secrets
    REDACTION_PATTERNS = [
      # API keys and tokens (with capture groups)
      [/\b(api[_-]?key|token|secret|password|passwd|pwd)[=:]\s*['"]?([^\s'")]+)['"]?/i, '\1=<REDACTED>'],
      # Bearer tokens
      [/Bearer\s+[A-Za-z0-9\-._~+\/]+=*/, "<REDACTED>"],
      # GitHub tokens
      [/\bgh[ps]_[A-Za-z0-9_]{36,}/, "<REDACTED>"],
      # AWS keys
      [/\bAKIA[0-9A-Z]{16}/, "<REDACTED>"],
      # Generic secrets in key=value format
      [/\b(secret|credentials?|auth)[=:]\s*['"]?([^\s'")]{8,})['"]?/i, '\1=<REDACTED>']
    ].freeze

    def redact(text)
      return text unless text.is_a?(String)

      redacted = text.dup
      REDACTION_PATTERNS.each do |pattern, replacement|
        redacted.gsub!(pattern, replacement)
      end
      redacted
    end

    def redact_hash(hash)
      hash.transform_values { |v| v.is_a?(String) ? redact(v) : v }
    end

    # Guard against accidentally passing stream sentinel strings or invalid characters
    # that would create odd top-level directories like "<STDERR>".
    def sanitize_project_dir(dir)
      return Dir.pwd if dir.nil?
      raw_input = dir.to_s
      raw_invalid = raw_input.empty? || raw_input.match?(/[<>|]/) || raw_input.match?(/[\x00-\x1F]/)
      if raw_invalid
        Kernel.warn "[AIDP Logger] Invalid project_dir '#{raw_input}' - falling back to #{Dir.pwd}"
        if Dir.pwd == File::SEPARATOR
          fallback = begin
            home = Dir.home
            (home && !home.empty?) ? home : Dir.tmpdir
          rescue
            Dir.tmpdir
          end
          @root_fallback = fallback
          Kernel.warn "[AIDP Logger] Root directory detected - using #{fallback} for logging instead of '#{Dir.pwd}'"
          return fallback
        end
        return Dir.pwd
      end
      if raw_input == File::SEPARATOR
        fallback = begin
          home = Dir.home
          (home && !home.empty?) ? home : Dir.tmpdir
        rescue
          Dir.tmpdir
        end
        @root_fallback = fallback
        Kernel.warn "[AIDP Logger] Root directory detected - using #{fallback} for logging instead of '#{raw_input}'"
        return fallback
      end
      raw_input
    end
  end

  # Module-level logger accessor
  class << self
    # Set up global logger instance
    def setup_logger(project_dir = Dir.pwd, config = {})
      @logger = Logger.new(project_dir, config)
    end

    # Get current logger instance (creates default if not set up)
    def logger
      @logger ||= Logger.new
    end

    # Convenience logging methods
    def log_info(component, message, **metadata)
      logger.info(component, message, **metadata)
    end

    def log_error(component, message, **metadata)
      logger.error(component, message, **metadata)
    end

    def log_warn(component, message, **metadata)
      logger.warn(component, message, **metadata)
    end

    def log_debug(component, message, **metadata)
      logger.debug(component, message, **metadata)
    end
  end
end
