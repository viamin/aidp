# frozen_string_literal: true

require "bundler/setup"
require "rspec"
require "timeout"

ENV["RACK_ENV"] = "test"
ENV["RSPEC_RUNNING"] = "true"  # Signal that we're running tests

require "aidp"
require "tempfile"
require "fileutils"
require "logger"

# Aruba configuration for system tests
if ENV["ARUBA_RUNNING"]
  require "aruba/cucumber"

  Aruba.configure do |config|
    config.command_launcher = :in_process
    config.main_class = Aidp::CLINew
    config.working_directory = "tmp/aruba"
    config.exit_timeout = 30
    config.io_wait_timeout = 1
  end
end

# Load test support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Add timeout to prevent hanging tests
  config.around(:each) do |example|
    example.run
  end
end
