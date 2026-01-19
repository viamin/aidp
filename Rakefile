# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "timeout"

# Shared constants
COVERAGE_DIR = File.expand_path("coverage", __dir__)

RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = "--format failures"
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

# Coverage tasks
#
# Coverage is enforced using SimpleCov's minimum_coverage feature (see .simplecov)
# - Minimum thresholds: 84% line coverage, 80% branch coverage
# - coverage:run: Runs tests with coverage enabled (excludes system tests to match CI)
# - coverage:summary: Generates summary.json and coverage badge SVG
# - prep/pc tasks: Automatically run coverage:run before commits
#
# Local Workflow:
# 1. Make changes and add tests
# 2. Run 'rake prep' or 'rake pc' before committing
# 3. SimpleCov will fail the test suite if coverage drops below 84%
# 4. Add more tests if coverage is below the minimum threshold
namespace :coverage do
  desc "Run RSpec with coverage (COVERAGE=1)"
  # Optional args:
  #   timeout_seconds: override the default timeout (120s)
  task :run, [:timeout_seconds] do |_t, args|
    ENV["COVERAGE"] = "1"
    timeout_seconds = (args[:timeout_seconds] || ENV["COVERAGE_TIMEOUT"] || 120).to_i
    timeout_seconds = 120 if timeout_seconds <= 0

    begin
      Timeout.timeout(timeout_seconds) do
        # Allow rerun in the same Rake session if needed
        Rake::Task["spec"].reenable
        Rake::Task["spec"].invoke
      end
    rescue Timeout::Error
      warn "coverage:run timed out after #{timeout_seconds} seconds"
      raise
    end

    puts "\nCoverage report: #{File.join(COVERAGE_DIR, "index.html")}" if File.exist?(File.join(COVERAGE_DIR,
      "index.html"))
  end

  desc "Clean coverage artifacts"
  task :clean do
    if Dir.exist?(COVERAGE_DIR)
      rm_r COVERAGE_DIR
      puts "Removed #{COVERAGE_DIR}"
    else
      puts "No coverage directory to remove"
    end
  end

  desc "Clean then run coverage"
  task all: %i[clean run]

  desc "Write coverage summary.json & badge.svg (requires prior coverage:run)"
  task :summary do
    require "json"
    resultset = File.join(COVERAGE_DIR, ".resultset.json")
    unless File.exist?(resultset)
      puts "No coverage data found. Run 'rake coverage:run' first."
      next
    end
    data = JSON.parse(File.read(resultset))
    coverage_hash = data["RSpec"]["coverage"] if data["RSpec"]
    unless coverage_hash
      puts "Unexpected resultset structure, cannot find rspec.coverage"
      next
    end
    covered = 0
    total = 0
    coverage_hash.each_value do |file_cov|
      lines = file_cov["lines"]
      lines.each do |val|
        next if val.nil?

        total += 1
        covered += 1 if val > 0
      end
    end
    pct = total.positive? ? (covered.to_f / total * 100.0) : 0.0
    summary_file = File.join(COVERAGE_DIR, "summary.json")
    File.write(summary_file, JSON.pretty_generate({timestamp: Time.now.utc.iso8601, line_coverage: pct.round(2)}))
    # Badge
    color = case pct
    when 90..100 then "#4c1"
    when 80...90 then "#97CA00"
    when 70...80 then "#dfb317"
    when 60...70 then "#fe7d37"
    else "#e05d44"
    end
    badge = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" width="150" height="20" role="img" aria-label="coverage: #{pct.round(2)}%">
        <linearGradient id="s" x2="0" y2="100%"><stop offset="0" stop-color="#bbb" stop-opacity=".1"/><stop offset="1" stop-opacity=".1"/></linearGradient>
        <rect rx="3" width="150" height="20" fill="#555"/>
        <rect rx="3" x="70" width="80" height="20" fill="#{color}"/>
        <path fill="#{color}" d="M70 0h4v20h-4z"/>
        <rect rx="3" width="150" height="20" fill="url(#s)"/>
        <g fill="#fff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="11">
          <text x="35" y="14">coverage</text>
          <text x="110" y="14">#{format("%.2f", pct)}%</text>
        </g>
      </svg>
    SVG
    # Write standard coverage/badge.svg (existing) and duplicate to badges/coverage.svg for README stability
    File.write(File.join(COVERAGE_DIR, "badge.svg"), badge)
    badges_dir = File.join("badges")
    FileUtils.mkdir_p(badges_dir)
    File.write(File.join(badges_dir, "coverage.svg"), badge)
    puts "Coverage: #{pct.round(2)}% (summary.json, coverage/badge.svg & badges/coverage.svg written)"
  end

  desc "Ratchet minimum coverage (writes coverage/ratchet.json if higher)"
  task :ratchet do
    require "json"
    resultset = File.join(COVERAGE_DIR, ".resultset.json")
    unless File.exist?(resultset)
      puts "No coverage data found. Run 'rake coverage:run' first."
      next
    end
    data = JSON.parse(File.read(resultset))
    coverage_hash = data["RSpec"]["coverage"] if data["RSpec"]
    unless coverage_hash
      puts "Unexpected resultset structure, cannot find rspec.coverage"
      next
    end
    covered = 0
    total = 0
    coverage_hash.each_value do |file_cov|
      lines = file_cov["lines"]
      lines.each do |val|
        next if val.nil?

        total += 1
        covered += 1 if val > 0
      end
    end
    current = (total.positive? ? (covered.to_f / total * 100.0) : 0.0).round(2)
    ratchet_file = File.join(COVERAGE_DIR, "ratchet.json")
    previous = if File.exist?(ratchet_file)
      begin
        JSON.parse(File.read(ratchet_file))["line_coverage"]
      rescue
        nil
      end
    end
    if previous && current <= previous
      puts "Coverage #{current}% not higher than previous #{previous}% (no change)"
      next
    end
    File.write(ratchet_file, JSON.pretty_generate({line_coverage: current, updated_at: Time.now.utc.iso8601}))
    puts "Ratchet updated to #{current}%"
  end
end

# Markdown lint tasks
namespace :markdownlint do
  desc "Run markdownlint with auto-fix (disables MD013 line length)"
  task :fix do
    sh "markdownlint . --fix"
  end
end

# Short pre-commit preparation task: runs formatters + coverage
desc "Run standard:fix, markdownlint:fix, and coverage:run (pre-commit helper)"
task prep: ["standard:fix", "markdownlint:fix", "coverage:run"]

desc "Alias for prep"
task pc: :prep
