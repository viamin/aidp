# frozen_string_literal: true

require 'bundler/setup'
require 'aidp'
require 'tempfile'
require 'fileutils'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Clean up temporary files after tests
  config.after(:each) do
    FileUtils.rm_rf(Dir.glob('/tmp/aidp_test_*'))
  end
end
