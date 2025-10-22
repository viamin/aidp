# frozen_string_literal: true

# Central SimpleCov configuration.
# Run with: COVERAGE=1 bundle exec rspec
# Incrementally raise thresholds as test suite improves (see issue #127).

require "simplecov"

SimpleCov.start do
  enable_coverage :branch

  track_files "lib/**/*.rb"

  add_filter "lib/aidp/version.rb"
  add_filter "/spec/"
  add_filter "/pkg/"
  add_filter "/tmp/"

  add_group "CLI", "lib/aidp/cli"
  add_group "Providers", "lib/aidp/providers"
  add_group "Daemon", "lib/aidp/daemon"
  add_group "Setup", "lib/aidp/setup"
  add_group "Analysis", "lib/aidp/analyze"

  # Initial baseline; raise gradually.
  minimum_coverage 70
  minimum_coverage_by_file 30
  refuse_coverage_drop
end
