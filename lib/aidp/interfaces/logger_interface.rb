# frozen_string_literal: true

module Aidp
  module Interfaces
    # LoggerInterface defines the contract for logging implementations.
    # This interface allows for dependency injection of different logging
    # backends, facilitating extraction of provider code into standalone gems.
    #
    # All logging methods follow a consistent signature:
    #   log_<level>(component, message, **metadata)
    #
    # Where:
    #   - component: String identifying the subsystem (e.g., "anthropic_provider")
    #   - message: String describing the event (e.g., "rate_limit_detected")
    #   - metadata: Optional keyword arguments for structured logging context
    #
    # @example Implementing the interface
    #   class MyLogger
    #     include Aidp::Interfaces::LoggerInterface
    #
    #     def log_debug(component, message, **metadata)
    #       puts "[DEBUG] #{component}: #{message} #{metadata}"
    #     end
    #
    #     def log_info(component, message, **metadata)
    #       puts "[INFO] #{component}: #{message} #{metadata}"
    #     end
    #
    #     def log_warn(component, message, **metadata)
    #       puts "[WARN] #{component}: #{message} #{metadata}"
    #     end
    #
    #     def log_error(component, message, **metadata)
    #       puts "[ERROR] #{component}: #{message} #{metadata}"
    #     end
    #   end
    #
    # @example Using an injected logger
    #   class Provider
    #     def initialize(logger: Aidp::Interfaces::NullLogger.new)
    #       @logger = logger
    #     end
    #
    #     def perform_action
    #       @logger.log_debug("provider", "action_started", action: "perform")
    #     end
    #   end
    #
    module LoggerInterface
      # Log a debug-level message.
      # Use for detailed diagnostic information useful during development.
      #
      # @param component [String] the subsystem or module name
      # @param message [String] the log message
      # @param metadata [Hash] optional structured key-value pairs
      # @return [void]
      def log_debug(component, message, **metadata)
        raise NotImplementedError, "#{self.class} must implement #log_debug"
      end

      # Log an info-level message.
      # Use for general operational events that don't indicate problems.
      #
      # @param component [String] the subsystem or module name
      # @param message [String] the log message
      # @param metadata [Hash] optional structured key-value pairs
      # @return [void]
      def log_info(component, message, **metadata)
        raise NotImplementedError, "#{self.class} must implement #log_info"
      end

      # Log a warning-level message.
      # Use for potentially problematic situations that don't prevent operation.
      #
      # @param component [String] the subsystem or module name
      # @param message [String] the log message
      # @param metadata [Hash] optional structured key-value pairs
      # @return [void]
      def log_warn(component, message, **metadata)
        raise NotImplementedError, "#{self.class} must implement #log_warn"
      end

      # Log an error-level message.
      # Use for error events that might still allow operation to continue.
      #
      # @param component [String] the subsystem or module name
      # @param message [String] the log message
      # @param metadata [Hash] optional structured key-value pairs
      # @return [void]
      def log_error(component, message, **metadata)
        raise NotImplementedError, "#{self.class} must implement #log_error"
      end
    end

    # NullLogger implements LoggerInterface as a no-op.
    # Useful as a default when no logging is required.
    #
    # @example Using as a default
    #   def initialize(logger: NullLogger.new)
    #     @logger = logger
    #   end
    #
    class NullLogger
      include LoggerInterface

      def log_debug(component, message, **metadata)
        # no-op
      end

      def log_info(component, message, **metadata)
        # no-op
      end

      def log_warn(component, message, **metadata)
        # no-op
      end

      def log_error(component, message, **metadata)
        # no-op
      end
    end

    # AidpLoggerAdapter wraps Aidp's module-level logging methods.
    # This adapter bridges the LoggerInterface to AIDP's existing logging system.
    #
    # @example Creating an adapter
    #   logger = AidpLoggerAdapter.new
    #   provider = SomeProvider.new(logger: logger)
    #
    class AidpLoggerAdapter
      include LoggerInterface

      def log_debug(component, message, **metadata)
        Aidp.log_debug(component, message, **metadata)
      end

      def log_info(component, message, **metadata)
        Aidp.log_info(component, message, **metadata)
      end

      def log_warn(component, message, **metadata)
        Aidp.log_warn(component, message, **metadata)
      end

      def log_error(component, message, **metadata)
        Aidp.log_error(component, message, **metadata)
      end
    end
  end
end
