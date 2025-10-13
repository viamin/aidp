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
      JSON.parse(File.read(ratchet_file))["line_coverage"] rescue nil
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

  desc "Normalize fenced code blocks: add language to unlabeled openings and remove language from closing fences"
  task :normalize_fences do
    files = Dir.glob("{docs,tasks,templates}/**/*.md")
    files.reject! { |f| File.basename(f) == "CHANGELOG.md" }
    normalized = []
    files.each do |file|
      lines = File.read(file).lines
      in_code = false
      changed = false
      lines.map!.with_index do |line, _i|
        if line.start_with?("```")
          # Match a pure fence line optionally with a language token (alphanum, +, -)
          if (m = line.strip.match(/^```([A-Za-z0-9_+-]*)?$/))
            lang = m[1]
            if in_code
              # This should be a closing fence. Always normalize to bare ```
              in_code = false
              if lang && !lang.empty?
                changed = true
                "```\n"
              else
                line
              end
            else
              # Opening fence
              in_code = true
              if lang.nil? || lang.empty?
                changed = true
                "```text\n" # default language for previously unlabeled fences
              else
                line
              end
            end
          else
            line
          end
        else
          line
        end
      end
      if changed
        File.write(file, lines.join)
        normalized << file
      end
    end
    if normalized.empty?
      puts "No fence normalization needed"
    else
      puts "Normalized fences in #{normalized.size} files"
      normalized.each { |f| puts "  - #{f}" }
    end
  end

  # Backwards-compatible task name kept for existing workflow references
  desc "(Deprecated) Use markdownlint:normalize_fences instead"
  task auto_label_fences: :normalize_fences
end

# Short pre-commit preparation task: runs formatters + coverage
desc "Run standard:fix, markdownlint:fix, then coverage:run (pre-commit helper)"
task prep: ["standard:fix", "markdownlint:fix", "coverage:run"]

desc "Alias for prep"
task pc: :prep
