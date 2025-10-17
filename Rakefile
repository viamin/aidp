# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

# Shared constants
COVERAGE_DIR = File.expand_path("coverage", __dir__)

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

# Coverage tasks
#
# Coverage Ratchet System:
# The coverage ratchet prevents test coverage from decreasing over time.
# - coverage_baseline.json: Committed to git, tracks minimum allowed coverage
# - coverage:run: Runs tests with coverage enabled
# - coverage:check: Verifies coverage hasn't decreased (fails CI if it has)
# - coverage:update_baseline: Updates baseline when coverage improves
# - prep/pc tasks: Automatically run coverage:check before commits
#
# Automatic Updates:
# - When PRs are merged to main and coverage improves, CI automatically:
#   1. Updates coverage_baseline.json
#   2. Commits the change back to main
#   3. Uses [skip ci] to avoid triggering another build
#
# Local Workflow:
# 1. Make changes and add tests
# 2. Run 'rake prep' or 'rake pc' before committing
# 3. If coverage improved and you want to update baseline locally:
#    - Run 'rake coverage:update_baseline' and commit the file
#    - Or just merge to main and let CI update it automatically
# 4. If coverage decreased, add more tests or fix the issue
# 5. CI will fail if coverage decreases on any branch
namespace :coverage do
  desc "Run RSpec with coverage (COVERAGE=1)"
  task :run do
    sh({"COVERAGE" => "1"}, "bundle exec rspec")
    puts "\nCoverage report: #{File.join(COVERAGE_DIR, "index.html")}" if File.exist?(File.join(COVERAGE_DIR, "index.html"))
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
  task all: [:clean, :run]

  desc "Write coverage summary.json & badge.svg (requires prior coverage:run)"
  task :summary do
    require "json"
    resultset = File.join(COVERAGE_DIR, ".resultset.json")
    unless File.exist?(resultset)
      puts "No coverage data found. Run 'rake coverage:run' first."
      next
    end
    data = JSON.parse(File.read(resultset))
    coverage_hash = data["rspec"]["coverage"] if data["rspec"]
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
          <text x="110" y="14">#{sprintf("%.2f", pct)}%</text>
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
    coverage_hash = data["rspec"]["coverage"] if data["rspec"]
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

  desc "Check coverage against ratchet baseline (fails if coverage decreased)"
  task :check do
    require "json"

    # Check for coverage data
    resultset = File.join(COVERAGE_DIR, ".resultset.json")
    unless File.exist?(resultset)
      puts "❌ No coverage data found. Run 'rake coverage:run' first."
      exit 1
    end

    # Calculate current coverage
    data = JSON.parse(File.read(resultset))
    coverage_hash = data["rspec"]["coverage"] if data["rspec"]
    unless coverage_hash
      puts "❌ Unexpected resultset structure, cannot find rspec.coverage"
      exit 1
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

    # Check against baseline
    baseline_file = "coverage_baseline.json"
    unless File.exist?(baseline_file)
      puts "⚠️  No coverage baseline found at #{baseline_file}"
      puts "   Creating initial baseline at #{current}%"
      File.write(baseline_file, JSON.pretty_generate({
        line_coverage: current,
        created_at: Time.now.utc.iso8601,
        note: "Coverage ratchet baseline - do not decrease this value"
      }))
      puts "✅ Baseline created. Commit this file to git."
      next
    end

    baseline_data = JSON.parse(File.read(baseline_file))
    baseline = baseline_data["line_coverage"]

    puts "\n📊 Coverage Ratchet Check"
    puts "=" * 60
    puts "Current coverage:  #{current}%"
    puts "Baseline coverage: #{baseline}%"
    puts "Difference:        #{(current - baseline).round(2)}%"
    puts "=" * 60

    if current < baseline
      puts "\n❌ COVERAGE DECREASED!"
      puts "   Coverage dropped from #{baseline}% to #{current}%"
      puts "   This is not allowed by the coverage ratchet."
      puts "\n   To fix:"
      puts "   1. Add tests to restore coverage to at least #{baseline}%"
      puts "   2. Or if intentional, update baseline: rake coverage:update_baseline"
      exit 1
    elsif current > baseline
      puts "\n✅ Coverage improved! #{current}% > #{baseline}%"
      puts "   Consider updating the baseline: rake coverage:update_baseline"
    else
      puts "\n✅ Coverage maintained at #{current}%"
    end
  end

  desc "Update coverage baseline to current level"
  task :update_baseline do
    require "json"

    resultset = File.join(COVERAGE_DIR, ".resultset.json")
    unless File.exist?(resultset)
      puts "❌ No coverage data found. Run 'rake coverage:run' first."
      exit 1
    end

    data = JSON.parse(File.read(resultset))
    coverage_hash = data["rspec"]["coverage"] if data["rspec"]
    unless coverage_hash
      puts "❌ Unexpected resultset structure"
      exit 1
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

    baseline_file = "coverage_baseline.json"
    previous = if File.exist?(baseline_file)
      begin
        JSON.parse(File.read(baseline_file))["line_coverage"]
      rescue
        nil
      end
    end

    File.write(baseline_file, JSON.pretty_generate({
      line_coverage: current,
      updated_at: Time.now.utc.iso8601,
      note: "Coverage ratchet baseline - do not decrease this value"
    }))

    if previous && current > previous
      puts "✅ Baseline updated from #{previous}% to #{current}%"
    elsif previous && current == previous
      puts "✅ Baseline unchanged at #{current}%"
    else
      puts "✅ Baseline set to #{current}%"
    end
    puts "   File: #{baseline_file}"
    puts "   Make sure to commit this file!"
  end

  desc "Update baseline if coverage improved (safe for automation)"
  task :update_baseline_if_improved do
    require "json"

    resultset = File.join(COVERAGE_DIR, ".resultset.json")
    unless File.exist?(resultset)
      puts "No coverage data found. Skipping baseline update."
      next
    end

    data = JSON.parse(File.read(resultset))
    coverage_hash = data["rspec"]["coverage"] if data["rspec"]
    unless coverage_hash
      puts "Unexpected resultset structure. Skipping baseline update."
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

    baseline_file = "coverage_baseline.json"
    previous = if File.exist?(baseline_file)
      begin
        JSON.parse(File.read(baseline_file))["line_coverage"]
      rescue
        nil
      end
    end

    # Only update if improved
    if previous.nil? || current > previous
      File.write(baseline_file, JSON.pretty_generate({
        line_coverage: current,
        updated_at: Time.now.utc.iso8601,
        note: "Coverage ratchet baseline - do not decrease this value"
      }))

      if previous
        puts "✅ Coverage improved! Baseline updated from #{previous}% to #{current}%"
      else
        puts "✅ Initial baseline set to #{current}%"
      end
      puts "   Don't forget to commit #{baseline_file}"
    else
      puts "Coverage unchanged at #{current}%, baseline not updated"
    end
  end
end

# Markdown lint tasks
namespace :markdownlint do
  desc "Run markdownlint with auto-fix (disables MD013 line length)"
  task :fix do
    sh "markdownlint . --fix"
  end
end

# Short pre-commit preparation task: runs formatters + coverage + ratchet check + smart baseline update
desc "Run standard:fix, markdownlint:fix, coverage:run, coverage:check, and auto-update baseline if improved (pre-commit helper)"
task prep: ["standard:fix", "markdownlint:fix", "coverage:run", "coverage:check", "coverage:update_baseline_if_improved"]

desc "Alias for prep"
task pc: :prep
