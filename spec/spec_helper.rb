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

  # Add timeout to prevent hanging tests and configure output logger
  config.around(:each) do |example|
    # Configure output logger for tests (only for non-logger and non-output tests)
    unless example.full_description.include?('OutputLogger') ||
           example.full_description.include?('OutputHelper') ||
           example.full_description.include?('control interface') ||
           example.full_description.include?('displays') ||
           example.full_description.include?('output') ||
           example.full_description.include?('CLI') ||
           example.full_description.include?('cli') ||
           example.full_description.include?('KBInspector')
      Aidp::OutputLogger.test_mode!
    end

    example.run

    # Reset output logger after test
    Aidp::OutputLogger.normal_mode!
  end


end
