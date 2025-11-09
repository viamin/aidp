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
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.order = :random

  # Show the 10 slowest examples at the end of the test run
  config.profile_examples = 5
end
