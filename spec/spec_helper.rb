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
