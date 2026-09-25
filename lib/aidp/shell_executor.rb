# frozen_string_literal: true

require "open3"

module Aidp
  # Shell command executor wrapper for testability
  #
  # Provides two modes of execution:
  # 1. `run(*command)` - Captures combined output via Open3 without a shell
  # 2. `system(*args)` - Wraps Kernel.system() with optional output suppression
  #
  # Both modes execute commands directly (no shell), so arguments are never
  # subject to shell interpretation or injection.
  #
  # In tests, set `ShellExecutor.suppress_output = true` to suppress all
  # system() output without changing any production code behavior.
  #
  # @example Production usage
  #   executor = Aidp::ShellExecutor.new
  #   executor.run("git", "diff", "--staged", "--name-only")  # => String
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

    # Run a command and capture its combined stdout/stderr output
    #
    # The command runs without a shell, so each argument is passed to the
    # program verbatim and cannot introduce shell metacharacters.
    #
    # @param command [Array<String>] The program and its arguments
    # @return [String] The command's combined output
    def run(*command)
      output, status = Open3.capture2e(*command)
      @last_status = status
      output
    end

    # Check if the last command succeeded
    #
    # @return [Boolean] true if last command exited with status 0
    def success?
      status = @last_status || $?
      !status.nil? && status.success?
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
      @last_status = nil
      if self.class.suppress_output && !opts.key?(:out) && !opts.key?(:err)
        opts = opts.merge(out: File::NULL, err: File::NULL)
      end
      Kernel.system(*args, **opts)
    end
  end
end
