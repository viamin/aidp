# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

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
