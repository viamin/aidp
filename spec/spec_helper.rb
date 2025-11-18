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
    # Monkey-patch TTY::Prompt to use TestPrompt in test environment
    # This ensures all components use our quiet prompt without needing explicit injection
    TTY::Prompt.class_eval do
      alias_method :original_say, :say

      def say(message, **options)
        return if TestPrompt::SUPPRESS_PATTERNS.any? { |pattern| message.to_s.match?(pattern) }
        original_say(message, **options)
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
    if defined?(Aidp) && Aidp.instance_variable_get(:@logger)
      begin
        Aidp.instance_variable_get(:@logger)&.close
      rescue IOError
        # Ignore closed stream errors during cleanup
      end
      Aidp.instance_variable_set(:@logger, nil)
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
