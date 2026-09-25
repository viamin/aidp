# frozen_string_literal: true

module Aidp
  # Shell command executor wrapper for testability
  #
  # Provides two modes of execution:
  # 1. `run(command)` - Captures output silently via backticks
  # 2. `system(*args)` - Wraps Kernel.system() with optional output suppression
  #
  # In tests, set `ShellExecutor.suppress_output = true` to suppress all
  # system() output without changing any production code behavior.
  #
  # @example Production usage
  #   executor = Aidp::ShellExecutor.new
  #   executor.system("git", "fetch", "origin")  # Output shown normally
  #
  # @example Test setup (in spec_helper.rb)
  #   Aidp::ShellExecutor.suppress_output = true
  #
  class ShellExecutor
    class << self
      # When true, system() calls will have output redirected to /dev/null
      # Default: false (output shown normally)
      attr_accessor :suppress_output
    end
    self.suppress_output = false

    # Immutable result of a shell-free command execution
    class Result
      attr_reader :stdout, :stderr, :exit_status

      # @param stdout [String] standard output from the command
      # @param stderr [String] standard error from the command
      # @param exit_status [Integer] exit status code
      def initialize(stdout:, stderr:, exit_status:)
        @stdout = stdout.to_s.freeze
        @stderr = stderr.to_s.freeze
        @exit_status = exit_status || 1
        freeze
      end

      # @return [Boolean] true if exit_status is 0
      def success?
        @exit_status.zero?
      end

      # Combined output, equivalent to shell `2>&1` redirection
      # @return [String]
      def output
        [@stdout, @stderr].reject(&:empty?).join("\n")
      end
    end

    # Run a command and capture its output
    #
    # @param command [String] The shell command to run
    # @return [String] The command's stdout output
    def run(command)
      `#{command}`
    end

    # Run a command without shell interpretation and capture its output
    #
    # The command and its arguments are passed directly to the operating
    # system, so shell metacharacters in any argument are treated as
    # literal data. Prefer this over #run whenever an argument may contain
    # externally supplied values.
    #
    # @param command [Array<String>] the command and its arguments
    # @return [Result] captured stdout/stderr with the exit status
    def run_argv(*command)
      require "open3"
      stdout, stderr, status = Open3.capture3(*command.map(&:to_s))
      Result.new(stdout: stdout, stderr: stderr, exit_status: status.exitstatus)
    end

    # Run a command via system(), optionally suppressing output
    #
    # When suppress_output is true, output is redirected to /dev/null
    # unless explicit out:/err: options are provided.
    #
    # @param args [Array] Arguments passed to Kernel.system
    # @param opts [Hash] Options passed to Kernel.system
    # @return [Boolean, nil] Same as Kernel.system
    def system(*args, **opts)
      if self.class.suppress_output && !opts.key?(:out) && !opts.key?(:err)
        opts = opts.merge(out: File::NULL, err: File::NULL)
      end
      Kernel.system(*args, **opts)
    end
  end
end
