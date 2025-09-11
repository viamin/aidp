# frozen_string_literal: true

module Aidp
  # Helper module to provide easy access to output logging throughout the codebase
  module OutputHelper
    # Delegate all output methods to the OutputLogger
    def puts(*args)
      Aidp::OutputLogger.puts(*args)
    end

    def print(*args)
      Aidp::OutputLogger.print(*args)
    end

    def flush
      Aidp::OutputLogger.flush
    end

    # Convenience methods for different output types
    def error_puts(*args)
      Aidp::OutputLogger.error_puts(*args)
    end

    def warning_puts(*args)
      Aidp::OutputLogger.warning_puts(*args)
    end

    def success_puts(*args)
      Aidp::OutputLogger.success_puts(*args)
    end

    def info_puts(*args)
      Aidp::OutputLogger.info_puts(*args)
    end

    def debug_puts(*args)
      Aidp::OutputLogger.debug_puts(*args)
    end

    def verbose_puts(*args)
      Aidp::OutputLogger.verbose_puts(*args)
    end
  end
end
