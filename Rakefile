# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

# Unit tests (excludes system tests)
RSpec::Core::RakeTask.new(:spec_unit) do |t|
  t.pattern = "spec/**/*_spec.rb"
  t.exclude_pattern = "spec/system/**/*_spec.rb"
end

# System tests (only system tests with Aruba)
RSpec::Core::RakeTask.new(:spec_system) do |t|
  t.pattern = "spec/system/**/*_spec.rb"
  t.rspec_opts = "--tag type:aruba"
end

# Test namespace for better organization
namespace :test do
  desc "Run unit tests (excludes system tests)"
  task unit: :spec_unit

  desc "Run system tests (Aruba integration tests)"
  task system: :spec_system

  desc "Run all tests (unit + system)"
  task all: [:unit, :system]
end

# Spec namespace (alternative naming)
namespace :spec do
  desc "Run unit specs (excludes system tests)"
  task unit: :spec_unit

  desc "Run system specs (Aruba integration tests)"
  task system: :spec_system

  desc "Run all specs (unit + system)"
  task all: [:unit, :system]
end

# StandardRB tasks
namespace :standard do
  desc "Run StandardRB linter"
  task :check do
    sh "bundle exec standardrb"
  end

  desc "Run StandardRB linter and auto-fix"
  task :fix do
    sh "bundle exec standardrb --fix"
  end
end

task default: :spec
