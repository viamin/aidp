# frozen_string_literal: true

require "bundler/setup"
require "rspec"
require "timeout"

# Coverage must start before any application files are loaded.
if ENV["COVERAGE"] == "1" || ENV["SIMPLECOV"] == "1"

  require "simplecov"
  SimpleCov.command_name "RSpec"
  puts "[SimpleCov] Coverage enabled" if ENV["DEBUG"]

end

ENV["RACK_ENV"] = "test"
ENV["RSPEC_RUNNING"] = "true" # Signal that we're running tests
# Always capture test output in dedicated log, regardless of outer env.
ENV["AIDP_LOG_FILE"] = ".aidp/logs/aidp.test.log"
ENV["AIDP_DISABLE_BOOTSTRAP"] ||= "1" # Default off in tests; enable explicitly in bootstrap specs

require "aidp"
require "tempfile"
require "fileutils"
require "logger"
require "tty-prompt"
require "tty-spinner"

# Monkey-patch Logger::LogDevice to suppress closed stream warnings during tests
# This prevents "log shifting failed. closed stream" messages during test cleanup
class Logger::LogDevice
  alias_method :original_handle_write_errors, :handle_write_errors

  def handle_write_errors(mesg)
    yield
  rescue *@reraise_write_errors
    raise
  rescue IOError => e
    # Silently ignore closed stream errors during tests
    return if e.message.include?("closed stream")
    warn("log #{mesg} failed. #{e}")
  rescue => e
    warn("log #{mesg} failed. #{e}")
  end
end

# Aruba configuration for system tests
require "aruba/rspec"

Aruba.configure do |config|
  config.command_launcher = :spawn
  config.working_directory = "tmp/aruba"
  config.exit_timeout = 30
  config.io_wait_timeout = 1
end

# Load test support files
Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

# When collecting coverage, load all library files so SimpleCov includes every line
if ENV["COVERAGE"] == "1" || ENV["SIMPLECOV"] == "1" || ENV["CI"]
  Dir[File.expand_path("../lib/**/*.rb", __dir__)].sort.each { |file| require file }
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  # Disable in CI to avoid permission issues with read-only file systems
  unless ENV["CI"]
    config.example_status_persistence_file_path = ".rspec_status"
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
    # Suppress false positive warnings about raise_error
    c.on_potential_false_positives = :nothing
  end

  config.order = :random

  # Show the 10 slowest examples at the end of the test run
  config.profile_examples = 5

  # Set up global test prompt to suppress verbose output
  config.before(:suite) do
    # Note: We don't enable quiet mode globally here because unit tests need to
    # verify that output is generated correctly. The --quiet flag is for production
    # use or system tests that invoke the actual CLI.
    # Instead, we use TestPrompt::SUPPRESS_PATTERNS to filter known noisy messages
    # while still allowing tests to verify critical output.

    # Suppress system() command output in tests
    # This redirects stdout/stderr to /dev/null for all ShellExecutor.system() calls
    Aidp::ShellExecutor.suppress_output = true

    # Monkey-patch TTY::Prompt to suppress output matching SUPPRESS_PATTERNS
    # This ensures all components use quiet output without needing explicit injection
    TTY::Prompt.class_eval do
      alias_method :original_say, :say
      alias_method :original_warn, :warn
      alias_method :original_error, :error
      alias_method :original_ok, :ok

      def say(message, **options)
        return if TestPrompt::SUPPRESS_PATTERNS.any? { |pattern| message.to_s.match?(pattern) }
        original_say(message, **options)
      end

      def warn(message, **options)
        return if TestPrompt::SUPPRESS_PATTERNS.any? { |pattern| message.to_s.match?(pattern) }
        original_warn(message, **options)
      end

      def error(message, **options)
        return if TestPrompt::SUPPRESS_PATTERNS.any? { |pattern| message.to_s.match?(pattern) }
        original_error(message, **options)
      end

      def ok(message, **options)
        return if TestPrompt::SUPPRESS_PATTERNS.any? { |pattern| message.to_s.match?(pattern) }
        original_ok(message, **options)
      end
    end

    # Monkey-patch TTY::Spinner to suppress all spinner output in tests
    # Spinners produce animated output that clutters test output
    TTY::Spinner.class_eval do
      alias_method :original_auto_spin, :auto_spin
      alias_method :original_spin, :spin
      alias_method :original_success, :success
      alias_method :original_error, :error
      alias_method :original_stop, :stop
      alias_method :original_update, :update

      def auto_spin
      end

      def spin
      end

      def success(message = nil)
      end

      def error(message = nil)
      end

      def stop(message = nil)
      end

      def update(options = {})
      end
    end

    # Monkey-patch Kernel#puts to filter output using SUPPRESS_PATTERNS
    # This catches direct puts calls that bypass TTY::Prompt
    Kernel.module_eval do
      alias_method :original_puts, :puts

      define_method(:puts) do |*args|
        args.each do |arg|
          message = arg.to_s
          next if TestPrompt::SUPPRESS_PATTERNS.any? { |pattern| message.match?(pattern) }
          original_puts(arg)
        end
        nil
      end
    end

    # Mock Pastel to avoid TTY stream access issues in CI
    # Pastel.new tries to detect color support which accesses TTY streams
    # In CI these streams may be closed, causing IOError
    require "pastel"
    original_pastel_new = Pastel.method(:new)
    Pastel.define_singleton_method(:new) do |*args, **kwargs|
      pastel = original_pastel_new.call(*args, **kwargs)
      # Override the methods to be safe in test environments
      pastel.define_singleton_method(:enabled?) { false } if pastel.respond_to?(:enabled?)
      pastel
    rescue IOError
      # If we get IOError from stream access, return a simple pass-through Pastel
      Class.new do
        def green(text) = text.to_s
        def red(text) = text.to_s
        def yellow(text) = text.to_s
        def blue(text) = text.to_s
        def magenta(text) = text.to_s
        def cyan(text) = text.to_s
        def white(text) = text.to_s
        def black(text) = text.to_s
        def bold(text) = text.to_s
        def dim(text) = text.to_s
        def italic(text) = text.to_s
        def underline(text) = text.to_s
        def inverse(text) = text.to_s
        def on(color) = self
        def method_missing(method, *args) = args.first.to_s
        def respond_to_missing?(*) = true
      end.new
    end
  end

  # Clean up loggers after each test to prevent closed stream warnings
  config.after(:each) do
    # Close the Aidp logger if it exists
    # Use instance_variable_get to check without side effects (logger getter may create new logger)
    if defined?(Aidp)
      logger_instance = Aidp.instance_variable_get(:@logger)
      if logger_instance
        begin
          logger_instance.close
        rescue IOError
          # Ignore closed stream errors during cleanup
        end
        Aidp.logger = nil
      end
    end

    # Kill any leftover threads to prevent test suite hangs
    # Keep only the main thread and RSpec's internal threads
    Thread.list.each do |thread|
      next if thread == Thread.main
      next if thread == Thread.current
      # Don't kill SimpleCov's result thread
      next if thread.backtrace&.any? { |line| line.include?("simplecov") }

      # Kill and join with timeout to prevent hanging
      thread.kill
      begin
        thread.join(0.1)
      rescue
        nil
      end
    end
  end
end
