# frozen_string_literal: true

module Aidp
  # Shell command executor wrapper for testability
  #
  # Commands are always executed in argument form so shell
  # metacharacters in any value are treated as literal data:
  # 1. `run_argv(*command)` - Captures output without shell interpretation
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

    # Run a command without shell interpretation and capture its output
    #
    # The command and its arguments are passed directly to the operating
    # system, so shell metacharacters in any argument are treated as
    # literal data. Prefer this over #run whenever an argument may contain
    # externally supplied values.
    #
    # @param command [Array<String>] the command and its arguments
    # @return [Result] captured stdout/stderr with the exit status
    def run_argv(*command, **opts)
      require "open3"
      program, *args = command.map(&:to_s)
      raise ArgumentError, "command must not be blank" if program.nil? || program.empty?

      # The [program, argv0] form forces direct execution even when a command
      # has no arguments. Passing one string to Open3 can otherwise invoke a
      # shell when that string contains shell metacharacters.
      stdout, stderr, status = Open3.capture3([program, program], *args, **opts)
      Result.new(stdout: stdout, stderr: stderr, exit_status: status.exitstatus)
    end

    # Run a command line without shell interpretation and capture its output
    #
    # The line is tokenized with Shellwords, so quoting in the command
    # string is honored as argument boundaries, but the resulting argv is
    # passed directly to the operating system. Shell metacharacters
    # (operators, redirections, substitutions) are never interpreted,
    # which makes this safe for command lines built from untrusted input.
    #
    # @param command [String] the command line to run
    # @param opts [Hash] options forwarded to Open3.capture3 (e.g. chdir:)
    # @return [Result] captured stdout/stderr with the exit status
    # @raise [ArgumentError] when the command line is blank, has
    #   unbalanced quotes, or uses shell operators/redirections
    def run_line(command, **opts)
      require "shellwords"
      argv = Shellwords.split(command.to_s)
      raise ArgumentError, "command must not be blank" if argv.empty?

      # A leading NAME=value token is a shell environment assignment; without
      # a shell it would be treated as the program name and fail to run.
      if argv.first.match?(/\A[A-Za-z_][A-Za-z0-9_]*=/)
        raise ArgumentError,
          "environment variable assignments are not supported; " \
          "prefix the command with env (e.g. env VAR=value command)"
      end

      # Operator and redirection tokens signal an intent to use shell
      # features, which are intentionally unsupported here; reject them
      # loudly rather than running them as literal arguments. A leading file
      # descriptor digit (e.g. `2>`) still introduces a shell redirect.
      if argv.any? { |token| %w[&& || ; |].include?(token) || token.match?(/\A\d*[<>&]/) }
        raise ArgumentError,
          "shell operators are not supported in configured commands; " \
          "split into separate commands instead: #{command.inspect}"
      end

      # A single token that still contains shell metacharacters would be
      # handed to Process.spawn as a lone string, which Ruby routes through
      # sh -c; reject it rather than let the shell interpret it.
      if argv.length == 1 && argv.first.match?(/[*?\[\]{}()<>|;&$\\"'`\r\n~#=]/)
        raise ArgumentError,
          "shell metacharacters in a single-token command are not supported; " \
          "split into program and arguments"
      end

      run_argv(*argv, **opts)
    end

    # Run a command via system(), optionally suppressing output
    #
    # When suppress_output is true, output is redirected to /dev/null
    # unless explicit out:/err: options are provided.
    #
    # Commands are always executed in argument form so a shell never
    # interprets any value. A leading environment hash is forwarded
    # unchanged; otherwise the [program, argv0] form forces direct
    # execution even when a single command string is supplied.
    #
    # @param args [Array] Arguments passed to Kernel.system
    # @param opts [Hash] Options passed to Kernel.system
    # @return [Boolean, nil] Same as Kernel.system
    def system(*args, **opts)
      if self.class.suppress_output && !opts.key?(:out) && !opts.key?(:err)
        opts = opts.merge(out: File::NULL, err: File::NULL)
      end

      if args.first.is_a?(Hash)
        environment, *command = args
        program, *rest = command.map(&:to_s)
        raise ArgumentError, "command must not be blank" if program.nil? || program.empty?

        Kernel.system(environment, [program, program], *rest, **opts)
      else
        program, *rest = args.map(&:to_s)
        raise ArgumentError, "command must not be blank" if program.nil? || program.empty?

        Kernel.system([program, program], *rest, **opts)
      end
    end
  end
end
