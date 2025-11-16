#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to audit mock usage in AIDP test suite
# Per LLM_STYLE_GUIDE.md: "Mock ONLY external boundaries (network, filesystem, user input, APIs)"

require "json"
require "pathname"

# External dependencies that are ALLOWED to be mocked
ALLOWED_MOCKS = [
  # Network/HTTP
  "Net::HTTP", "HTTP", "Faraday", "RestClient", "HTTParty",
  # User input/TTY
  "TTY::Prompt", "TTY::Spinner", "TTY::ProgressBar", "TTY::Table", "TTY::Reader",
  # Filesystem operations (when testing file handling)
  "File", "Dir", "FileUtils", "Pathname",
  # External commands/processes
  "Open3", "Kernel.system", "Kernel.`",
  # Time/Date (external system dependency)
  "Time", "Date", "DateTime",
  # Environment
  "ENV",
  # Logger (external I/O)
  "Logger",
  # Test utilities
  "TestPrompt", # Our own test double for TTY::Prompt
  # Git (external command)
  "Git", "Rugged",
  # Database
  "ActiveRecord", "Sequel",
  # External AI providers (these are the boundaries we're wrapping)
  "Anthropic::Client", "OpenAI::Client", "Gemini::Client"
].freeze

class MockAuditor
  def initialize
    @violations = []
    @compliant = []
    @needs_review = []
  end

  def audit_file(file_path)
    content = File.read(file_path, encoding: "UTF-8")
    lines = content.split("\n")

    violations_in_file = []

    lines.each_with_index do |line, index|
      line_num = index + 1

      # Skip comments
      next if line.strip.start_with?("#")

      # Check for various mocking patterns
      if line =~ /allow\((.*?)\)\.to receive/
        target = $1.strip
        violations_in_file << check_mock_target(target, line_num, line, "allow().to receive")
      end

      if line =~ /allow_any_instance_of\((.*?)\)/
        target = $1.strip
        violations_in_file << check_mock_target(target, line_num, line, "allow_any_instance_of")
      end

      if line =~ /expect\((.*?)\)\.to receive/
        target = $1.strip
        violations_in_file << check_mock_target(target, line_num, line, "expect().to receive")
      end

      if line =~ /expect_any_instance_of\((.*?)\)/
        target = $1.strip
        violations_in_file << check_mock_target(target, line_num, line, "expect_any_instance_of")
      end

      if line =~ /instance_double\(['"](.*?)['"]/
        klass = $1.strip
        violations_in_file << check_mock_target(klass, line_num, line, "instance_double")
      end

      if line =~ /class_double\(['"](.*?)['"]/
        klass = $1.strip
        violations_in_file << check_mock_target(klass, line_num, line, "class_double")
      end

      if line =~ /double\(['"](.*?)['"]/
        name = $1.strip
        # Doubles with generic names are OK (they're test-only objects)
        # But doubles named after internal classes are violations
        if name =~ /^[A-Z]/ && name.include?("::")
          violations_in_file << check_mock_target(name, line_num, line, "double")
        end
      end

      # Check for stubbing instance variables (code smell)
      if /instance_variable_set|instance_variable_get/.match?(line)
        violations_in_file << {
          type: "violation",
          reason: "Direct instance variable manipulation (code smell)",
          line_num: line_num,
          line: line.strip,
          pattern: "instance_variable manipulation"
        }
      end
    end

    violations_in_file.compact!

    {
      file: file_path,
      violations: violations_in_file
    }
  end

  def check_mock_target(target, line_num, line, pattern)
    # Clean up target
    target = target.gsub(/^described_class/, "DESCRIBED_CLASS")
    target = target.gsub(/^subject/, "SUBJECT")

    # Check if it's an internal AIDP class/module
    if target.start_with?("Aidp::")
      # This is definitely internal code - violation!
      return {
        type: "violation",
        reason: "Mocking internal AIDP class: #{target}",
        line_num: line_num,
        line: line.strip,
        pattern: pattern,
        target: target
      }
    end

    # Check if it's the class under test (described_class)
    if target == "DESCRIBED_CLASS"
      # Mocking the class under test is usually wrong
      return {
        type: "violation",
        reason: "Mocking the class under test (described_class)",
        line_num: line_num,
        line: line.strip,
        pattern: pattern,
        target: "described_class"
      }
    end

    # Check if it's subject
    if target == "SUBJECT"
      # Mocking subject (the instance under test) is definitely wrong
      return {
        type: "violation",
        reason: "Mocking the instance under test (subject)",
        line_num: line_num,
        line: line.strip,
        pattern: pattern,
        target: "subject"
      }
    end

    # Check if it's a local variable (these might be doubles, which could be OK)
    if /^[a-z_]/.match?(target)
      # Could be a method call or local variable - needs context
      # If it's a simple variable name, it's likely a double which is OK
      return nil if target =~ /^[a-z_]+$/ && !target.include?(".")

      # If it's calling methods on something, might need review
      return {
        type: "needs_review",
        reason: "Mocking method call or complex expression: #{target}",
        line_num: line_num,
        line: line.strip,
        pattern: pattern,
        target: target
      }
    end

    # Check against allowed mocks
    ALLOWED_MOCKS.each do |allowed|
      if target.start_with?(allowed) || target == allowed
        return nil # This is allowed
      end
    end

    # Check for Ruby standard library (generally OK to mock)
    if /^(String|Array|Hash|Integer|Float|Symbol|Regexp|Range|Struct|OpenStruct|Set|Matrix|Vector)($|::)/.match?(target)
      return nil # Ruby stdlib is OK
    end

    # Unknown class - might be internal
    if /^[A-Z]/.match?(target)
      return {
        type: "needs_review",
        reason: "Mocking unknown class (might be internal): #{target}",
        line_num: line_num,
        line: line.strip,
        pattern: pattern,
        target: target
      }
    end

    nil
  end

  def run_audit
    spec_files = Dir.glob("spec/**/*_spec.rb").sort

    results = {
      total_files: spec_files.size,
      files_with_violations: 0,
      files_clean: 0,
      files_need_review: 0,
      violations_by_file: []
    }

    spec_files.each do |file|
      file_result = audit_file(file)

      if file_result[:violations].any?
        violations_count = file_result[:violations].count { |v| v[:type] == "violation" }
        review_count = file_result[:violations].count { |v| v[:type] == "needs_review" }

        if violations_count > 0
          results[:files_with_violations] += 1
        elsif review_count > 0
          results[:files_need_review] += 1
        end

        results[:violations_by_file] << file_result
      else
        results[:files_clean] += 1
      end
    end

    results
  end

  def generate_report(results)
    puts "=" * 80
    puts "AIDP Mock Usage Audit Report"
    puts "=" * 80
    puts
    puts "Summary:"
    puts "  Total spec files: #{results[:total_files]}"
    puts "  Files with violations: #{results[:files_with_violations]}"
    puts "  Files needing review: #{results[:files_need_review]}"
    puts "  Clean files: #{results[:files_clean]}"
    puts

    total_violations = 0
    total_reviews = 0

    results[:violations_by_file].each do |file_result|
      violations = file_result[:violations].select { |v| v[:type] == "violation" }
      reviews = file_result[:violations].select { |v| v[:type] == "needs_review" }

      next if violations.empty? && reviews.empty?

      total_violations += violations.size
      total_reviews += reviews.size

      puts "-" * 80
      puts "File: #{file_result[:file]}"
      puts "-" * 80

      if violations.any?
        puts "\n  VIOLATIONS (#{violations.size}):"
        violations.each do |v|
          puts "    Line #{v[:line_num]}: #{v[:reason]}"
          puts "      Pattern: #{v[:pattern]}"
          puts "      Code: #{v[:line]}"
          puts
        end
      end

      if reviews.any?
        puts "\n  NEEDS REVIEW (#{reviews.size}):"
        reviews.each do |v|
          puts "    Line #{v[:line_num]}: #{v[:reason]}"
          puts "      Pattern: #{v[:pattern]}"
          puts "      Code: #{v[:line]}"
          puts
        end
      end
    end

    puts "=" * 80
    puts "Total violations: #{total_violations}"
    puts "Total needing review: #{total_reviews}"
    puts "=" * 80
  end
end

if __FILE__ == $0
  auditor = MockAuditor.new
  results = auditor.run_audit
  auditor.generate_report(results)

  # Also save JSON report
  File.write("mock_audit_report.json", JSON.pretty_generate(results))
  puts "\nDetailed JSON report saved to: mock_audit_report.json"
end
