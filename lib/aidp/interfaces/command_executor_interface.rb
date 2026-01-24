# frozen_string_literal: true

module Aidp
  module Interfaces
    # CommandExecutorInterface defines the contract for executing shell commands.
    # This interface allows for dependency injection of different command execution
    # backends, facilitating extraction of provider code into standalone gems.
    #
    # @example Implementing the interface
    #   class MyExecutor
    #     include Aidp::Interfaces::CommandExecutorInterface
    #
    #     def execute(command, args: [], input: nil, timeout: nil, **options)
    #       # Implementation here
    #       CommandResult.new(stdout: "output", stderr: "", exit_status: 0)
    #     end
    #   end
    #
    # @example Using an injected executor
    #   class Provider
    #     def initialize(executor: Aidp::Interfaces::TtyCommandExecutor.new)
    #       @executor = executor
    #     end
    #
    #     def run_cli(command, args)
    #       @executor.execute(command, args: args, timeout: 30)
    #     end
    #   end
    #
    module CommandExecutorInterface
      # Execute a shell command.
      #
      # @param command [String] the command to execute (e.g., "claude", "cursor-agent")
      # @param args [Array<String>] command-line arguments
      # @param input [String, nil] input to pass to stdin (or file path to read from)
      # @param timeout [Integer, nil] timeout in seconds
      # @param options [Hash] additional options (env vars, working directory, etc.)
      # @return [CommandResult] the result of the command execution
      # @raise [CommandTimeoutError] if the command times out
      # @raise [CommandExecutionError] if the command fails to execute
      def execute(command, args: [], input: nil, timeout: nil, **options)
        raise NotImplementedError, "#{self.class} must implement #execute"
      end
    end

    # Result object returned by command execution.
    # Immutable value object containing stdout, stderr, and exit status.
    #
    # @example Creating a result
    #   result = CommandResult.new(stdout: "Hello", stderr: "", exit_status: 0)
    #   result.success? # => true
    #   result.out      # => "Hello"
    #
    class CommandResult
      attr_reader :stdout, :stderr, :exit_status

      # @param stdout [String] standard output from the command
      # @param stderr [String] standard error from the command
      # @param exit_status [Integer] exit status code
      def initialize(stdout:, stderr:, exit_status:)
        @stdout = stdout.to_s.freeze
        @stderr = stderr.to_s.freeze
        @exit_status = exit_status.to_i
        freeze
      end

      # @return [Boolean] true if exit_status is 0
      def success?
        @exit_status.zero?
      end

      # Alias for stdout for compatibility with TTY::Command::Result
      # @return [String]
      def out
        @stdout
      end

      # Alias for stderr for compatibility with TTY::Command::Result
      # @return [String]
      def err
        @stderr
      end
    end

    # Error raised when a command times out.
    class CommandTimeoutError < StandardError
      attr_reader :command, :timeout

      def initialize(command:, timeout:)
        @command = command
        @timeout = timeout
        super("Command '#{command}' timed out after #{timeout} seconds")
      end
    end

    # Error raised when command execution fails.
    class CommandExecutionError < StandardError
      attr_reader :command, :original_error

      def initialize(command:, original_error:)
        @command = command
        @original_error = original_error
        super("Command '#{command}' failed: #{original_error.message}")
      end
    end

    # NullExecutor implements CommandExecutorInterface as a no-op.
    # Returns successful empty results. Useful for testing.
    #
    # @example Using as a test double
    #   provider = Provider.new(executor: NullExecutor.new)
    #
    class NullExecutor
      include CommandExecutorInterface

      def execute(command, args: [], input: nil, timeout: nil, **options)
        CommandResult.new(stdout: "", stderr: "", exit_status: 0)
      end
    end

    # TtyCommandExecutor wraps TTY::Command for command execution.
    # This adapter provides the standard implementation used by AIDP.
    #
    # @example Creating an executor with a logger
    #   logger = AidpLoggerAdapter.new
    #   executor = TtyCommandExecutor.new(logger: logger)
    #
    class TtyCommandExecutor
      include CommandExecutorInterface

      # @param logger [LoggerInterface] optional logger for debug output
      # @param component_name [String] component name for logging
      def initialize(logger: nil, component_name: "command_executor")
        @logger = logger
        @component_name = component_name
      end

      # Execute a shell command using TTY::Command.
      #
      # @param command [String] the command to execute
      # @param args [Array<String>] command-line arguments
      # @param input [String, nil] input to pass to stdin (or file path to read from)
      # @param timeout [Integer, nil] timeout in seconds
      # @param options [Hash] additional options passed to TTY::Command#run
      # @return [CommandResult] the result of the command execution
      def execute(command, args: [], input: nil, timeout: nil, **options)
        require "tty-command"

        log_debug("executing_command", command: command, args: args, timeout: timeout)

        start_time = Time.now

        begin
          cmd_obj = TTY::Command.new(printer: :null)

          # Prepare input data
          input_data = resolve_input(input)

          # Execute command - use run! to get result even on non-zero exit
          result = cmd_obj.run!(command, *args, input: input_data, timeout: timeout, **options)

          duration = Time.now - start_time
          log_debug("command_completed",
            command: command,
            exit_status: result.exit_status,
            duration: duration.round(2))

          CommandResult.new(
            stdout: result.out,
            stderr: result.err,
            exit_status: result.exit_status
          )
        rescue TTY::Command::TimeoutExceeded
          duration = Time.now - start_time
          log_debug("command_timeout",
            command: command,
            timeout: timeout,
            duration: duration.round(2))
          raise CommandTimeoutError.new(command: command, timeout: timeout)
        rescue Errno::ENOENT, Errno::EACCES => e
          # Command not found or not executable
          duration = Time.now - start_time
          log_debug("command_not_found",
            command: command,
            error: e.message,
            duration: duration.round(2))
          raise CommandExecutionError.new(command: command, original_error: e)
        rescue => e
          duration = Time.now - start_time
          log_debug("command_failed",
            command: command,
            error: e.message,
            duration: duration.round(2))
          raise CommandExecutionError.new(command: command, original_error: e)
        end
      end

      private

      def resolve_input(input)
        return nil unless input

        if input.is_a?(String) && File.exist?(input)
          log_debug("reading_input_file", path: input)
          File.read(input)
        else
          input
        end
      end

      def log_debug(message, **metadata)
        @logger&.log_debug(@component_name, message, **metadata)
      end
    end
  end
end
