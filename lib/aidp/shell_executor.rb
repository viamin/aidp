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
    def run_argv(*command)
      require "open3"
      stdout, stderr, status = Open3.capture3(*command.map(&:to_s))
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
      require "open3"
      require "shellwords"
      argv = Shellwords.split(command.to_s)
      raise ArgumentError, "command must not be blank" if argv.empty?

      # Operator tokens signal an intent to use shell features, which are
      # intentionally unsupported here; reject them loudly rather than
      # running them as literal arguments.
      if argv.any? { |token| %w[&& || ; |].include?(token) || token.match?(/^[<>&]/) }
        raise ArgumentError,
          "shell operators are not supported in configured commands; " \
          "split into separate commands instead: #{command.inspect}"
      end

      stdout, stderr, status = Open3.capture3(*argv, **opts)
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
