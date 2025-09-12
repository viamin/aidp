# frozen_string_literal: true

require "bundler/setup"
require "rspec"
require "timeout"

ENV["RACK_ENV"] = "test"
ENV["RSPEC_RUNNING"] = "true"  # Signal that we're running tests

require "aidp"
require "tempfile"
require "fileutils"
require "que"
require "logger"
require_relative "support/database_helper"
require_relative "support/job_helper"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Add timeout to prevent hanging tests and configure output logger
  config.around(:each) do |example|
    Timeout.timeout(10) do
      # Ensure each test starts with a clean connection
      Aidp::DatabaseConnection.disconnect

      # Configure output logger for tests (only for non-logger and non-output tests)
      unless example.full_description.include?('OutputLogger') ||
             example.full_description.include?('OutputHelper') ||
             example.full_description.include?('control interface') ||
             example.full_description.include?('displays') ||
             example.full_description.include?('output') ||
             example.full_description.include?('CLI') ||
             example.full_description.include?('cli')
        Aidp::OutputLogger.test_mode!
      end

      example.run

      # Reset output logger after test
      Aidp::OutputLogger.normal_mode!
      Aidp::DatabaseConnection.disconnect
    end
  rescue Timeout::Error
    raise "Test timed out after 10 seconds"
  end

  # Configure Que for testing
  config.before(:suite) do
    DatabaseHelper.setup_test_db
    Que.logger = Logger.new(nil)
    ENV["QUE_QUEUE"] = "test_queue"
  end

  config.after(:suite) do
    DatabaseHelper.drop_test_db
  end

  # Only clear database tables for tests that actually need it
  # This reduces database connection overhead
  config.before(:each, :database) do
    DatabaseHelper.clear_que_tables
  end

end
