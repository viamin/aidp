# frozen_string_literal: true

require "shellwords"

module Aidp
  # Parses and validates a configured command string for shell-free execution.
  #
  # Commands configured in aidp.yml are library-provided configuration, not
  # trusted shell source. They must never reach a shell: +argv_for+ splits a
  # command line with shell-style quoting rules, and +syntax_error+ rejects
  # shell-only syntax so a misconfigured command fails loudly instead of
  # silently running only part of the command line.
  module ShellFreeCommand
    # Token shape that only makes sense to a shell: operators (&&, ||, |, ;,
    # &) and redirections (>, >>, <, 2>&1) all start with a metacharacter,
    # optionally prefixed by a file-descriptor digit.
    SHELL_METACHARACTER_PATTERN = /\A\d*[<>&|;]/

    # Ruby passes a single-string command through sh -c whenever it contains
    # one of these characters, so a one-token argv that holds any of them
    # would reintroduce shell interpretation.
    SINGLE_TOKEN_SHELL_PATTERN = /[*?\[\]{}()<>|;&$\\"'`\r\n~#=]/

    # Leading `NAME=value` tokens are shell environment assignments; without a
    # shell they would be treated as the program name.
    ENV_ASSIGNMENT_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*=/

    module_function

    # Split a configured command into argv without invoking a shell.
    #
    # @param command [String] the raw command line
    # @return [Array<String>] program and arguments
    # @raise [ArgumentError] for unbalanced quotes or NUL bytes
    def argv_for(command)
      Shellwords.shellsplit(command.to_s)
    end

    # Return an error message when argv contains shell-only syntax that direct
    # argv execution cannot honor, or nil when it is runnable.
    #
    # @param argv [Array<String>] the tokenized command
    # @return [String, nil]
    def syntax_error(argv)
      return "blank command" if argv.empty?
      return "shell operators are not supported; split into separate commands" if argv.any? { |token| token.match?(SHELL_METACHARACTER_PATTERN) }
      return "environment variable assignments are not supported; prefix the command with env (e.g. env VAR=value command)" if ENV_ASSIGNMENT_PATTERN.match?(argv.first)
      return "shell metacharacters in a single-token command are not supported; split into program and arguments" if argv.length == 1 && argv.first.match?(SINGLE_TOKEN_SHELL_PATTERN)

      nil
    end
  end
end
