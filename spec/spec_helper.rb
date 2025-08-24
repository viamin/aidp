# frozen_string_literal: true

require "bundler/setup"
require "rspec"
require "timeout"

ENV["RACK_ENV"] = "test"

# Workaround for Ruby 3.4.2 compatibility with RSpec 3.12.x
module RSpec
  module Core
    Time = ::Time unless defined?(Time)
  end
end

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

  # Add timeout to prevent hanging tests
  config.around(:each) do |example|
    Timeout.timeout(10) do
      example.run
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

  config.before(:each) do
    DatabaseHelper.clear_que_tables
  end

  config.around(:each) do |example|
    # Ensure each test starts with a clean connection
    Aidp::DatabaseConnection.disconnect
    example.run
    Aidp::DatabaseConnection.disconnect
  end
end
