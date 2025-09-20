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

# Global TTY::Prompt mocks for testing
RSpec.configure do |config|
  config.before(:each) do
    allow_any_instance_of(TTY::Prompt).to receive(:keypress).and_return("")
  end

  config.after(:each) do
    # Clean up any TTY::Prompt class-level stubs to prevent order-dependent failures
    RSpec::Mocks.space.proxy_for(TTY::Prompt)&.reset
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
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.order = :random
end
