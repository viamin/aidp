# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"

module Aidp
  class CodeMaatIntegration
    def initialize(project_dir = Dir.pwd)
      @project_dir = project_dir
      @docker_image = "philipssoftware/code-maat:latest"
    end

    # Check if Docker is available and Code Maat image is accessible
    def check_prerequisites
      {
        docker_available: docker_available?,
        code_maat_image_available: code_maat_image_available?,
        git_repository: git_repository?,
        git_log_available: git_log_available?
      }
    end

    # Generate Git log for Code Maat analysis
    def generate_git_log(output_file = nil)
      output_file ||= File.join(@project_dir, "git.log")

      raise "Not a Git repository. Code Maat requires a Git repository for analysis." unless git_repository?

      cmd = [
        "git", "log",
        '--pretty=format:"%h|%an|%ad|%aE|%s"',
        "--date=short",
        "--numstat"
      ]

      stdout, stderr, status = Open3.capture3(*cmd, chdir: @project_dir)

      raise "Failed to generate Git log: #{stderr}" unless status.success?

      File.write(output_file, stdout)
      output_file
    end

    # Run Code Maat analysis for code churn
    def analyze_churn(git_log_file = nil)
      git_log_file ||= File.join(@project_dir, "git.log")
      output_file = File.join(@project_dir, "churn.csv")

      run_code_maat("churn", git_log_file, output_file)
      parse_churn_results(output_file)
    end

    # Run Code Maat analysis for coupling
    def analyze_coupling(git_log_file = nil)
      git_log_file ||= File.join(@project_dir, "git.log")
      output_file = File.join(@project_dir, "coupling.csv")

      run_code_maat("coupling", git_log_file, output_file)
      parse_coupling_results(output_file)
    end

    # Run Code Maat analysis for authorship
    def analyze_authorship(git_log_file = nil)
      git_log_file ||= File.join(@project_dir, "git.log")
      output_file = File.join(@project_dir, "authorship.csv")

      run_code_maat("authorship", git_log_file, output_file)
      parse_authorship_results(output_file)
    end

    # Run Code Maat analysis for summary
    def analyze_summary(git_log_file = nil)
      git_log_file ||= File.join(@project_dir, "git.log")
      output_file = File.join(@project_dir, "summary.csv")

      run_code_maat("summary", git_log_file, output_file)
      parse_summary_results(output_file)
    end

    # Run comprehensive Code Maat analysis
    def run_comprehensive_analysis
      # Generate Git log if not exists
      git_log_file = File.join(@project_dir, "git.log")
      generate_git_log(git_log_file) unless File.exist?(git_log_file)

      # Check if repository is large and needs chunking
      if large_repository?(git_log_file)
        run_chunked_analysis(git_log_file)
      else
        run_full_analysis(git_log_file)
      end
    end

    # Run analysis on large repositories using chunking
    def run_chunked_analysis(git_log_file)
      puts "Large repository detected. Running chunked analysis..."

      # Split analysis into chunks
      chunks = create_analysis_chunks(git_log_file)

      results = {
        churn: {files: [], total_files: 0, total_changes: 0},
        coupling: {couplings: [], total_couplings: 0, average_coupling: 0},
        authorship: {files: [], total_files: 0, files_with_multiple_authors: 0, files_with_single_author: 0},
        summary: {summary: {}}
      }

      chunks.each_with_index do |chunk, index|
        puts "Processing chunk #{index + 1}/#{chunks.length}..."

        chunk_results = analyze_chunk(chunk)

        # Merge results
        merge_analysis_results(results, chunk_results)
      end

      # Generate consolidated report
      generate_consolidated_report(results)

      results
    end

    # Run full analysis on smaller repositories
    def run_full_analysis(git_log_file)
      # Run all analyses
      results = {
        churn: analyze_churn(git_log_file),
        coupling: analyze_coupling(git_log_file),
        authorship: analyze_authorship(git_log_file),
        summary: analyze_summary(git_log_file)
      }

      # Generate consolidated report
      generate_consolidated_report(results)

      results
    end

    # Get high-churn files for prioritization
    def get_high_churn_files(threshold = 10)
      churn_data = analyze_churn
      churn_data[:files].select { |file| file[:changes] > threshold }
        .sort_by { |file| -file[:changes] }
    end

    # Get tightly coupled files
    def get_tightly_coupled_files(threshold = 5)
      coupling_data = analyze_coupling
      coupling_data[:couplings].select { |coupling| coupling[:shared_changes] > threshold }
        .sort_by { |coupling| -coupling[:shared_changes] }
    end

    # Get knowledge silos (files with single author)
    def get_knowledge_silos
      authorship_data = analyze_authorship
      authorship_data[:files].select { |file| file[:authors].length == 1 }
        .sort_by { |file| -file[:changes] }
    end

    private

    def run_code_maat(analysis_type, input_file, output_file)
      # Ensure input file exists
      raise "Input file not found: #{input_file}" unless File.exist?(input_file)

      # For now, use a mock implementation for testing
      # TODO: Implement proper Docker-based Code Maat execution
      mock_code_maat_analysis(analysis_type, input_file, output_file)
    end

    def mock_code_maat_analysis(analysis_type, input_file, output_file)
      # Parse the Git log to generate mock analysis data
      git_log_content = File.read(input_file)

      case analysis_type
      when "churn"
        generate_mock_churn_data(git_log_content, output_file)
      when "coupling"
        generate_mock_coupling_data(git_log_content, output_file)
      when "authorship"
        generate_mock_authorship_data(git_log_content, output_file)
      when "summary"
        generate_mock_summary_data(git_log_content, output_file)
      else
        raise "Unknown analysis type: #{analysis_type}"
      end

      output_file
    end

    def generate_mock_churn_data(git_log_content, output_file)
      # Extract file names from Git log and generate mock churn data
      files = extract_files_from_git_log(git_log_content)

      csv_content = "entity,n-revs,n-lines-added,n-lines-deleted\n"
      files.each_with_index do |file, index|
        changes = rand(1..20)
        additions = rand(0..changes * 10)
        deletions = rand(0..changes * 5)
        csv_content += "#{file},#{changes},#{additions},#{deletions}\n"
      end

      File.write(output_file, csv_content)
    end

    def generate_mock_coupling_data(git_log_content, output_file)
      # Generate mock coupling data between files
      files = extract_files_from_git_log(git_log_content)

      csv_content = "entity,coupled,degree,average-revs\n"
      files.each_slice(2) do |file1, file2|
        next unless file2

        shared_changes = rand(1..10)
        rand(0.1..1.0).round(2)
        avg_revs = rand(1..5)
        csv_content += "#{file1},#{file2},#{shared_changes},#{avg_revs}\n"
      end

      File.write(output_file, csv_content)
    end

    def generate_mock_authorship_data(git_log_content, output_file)
      # Generate mock authorship data
      files = extract_files_from_git_log(git_log_content)
      authors = %w[Alice Bob Charlie Diana Eve]

      csv_content = "entity,n-authors,revs\n"
      files.each do |file|
        author_count = rand(1..3)
        file_authors = authors.sample(author_count)
        revs = rand(1..15)
        csv_content += "#{file},\"#{file_authors.join(";")}\",#{revs}\n"
      end

      File.write(output_file, csv_content)
    end

    def generate_mock_summary_data(git_log_content, output_file)
      # Generate mock summary data
      summary_content = <<~SUMMARY
        Number of commits: 42
        Number of entities: 15
        Number of authors: 5
        First commit: 2023-01-01
        Last commit: 2024-01-01
        Total lines added: 1250
        Total lines deleted: 450
      SUMMARY

      File.write(output_file, summary_content)
    end

    def extract_files_from_git_log(git_log_content)
      # Extract file names from Git log content
      files = []
      git_log_content.lines.each do |line|
        # Look for lines that contain file paths (not commit info)
        next unless line.match?(/\d+\s+\d+\s+[^\s]+$/)

        parts = line.strip.split(/\s+/)
        files << parts[2] if parts.length >= 3 && parts[2] != "-"
      end

      # Return unique files, limited to a reasonable number
      files.uniq.first(20)
    end

    # Check if repository is large enough to require chunking
    def large_repository?(git_log_file)
      return false unless File.exist?(git_log_file)

      file_size = File.size(git_log_file)
      line_count = File.readlines(git_log_file).count

      # Consider large if file is > 10MB or has > 10,000 lines
      file_size > 10 * 1024 * 1024 || line_count > 10_000
    end

    # Create analysis chunks for large repositories
    def create_analysis_chunks(git_log_file)
      content = File.read(git_log_file)
      lines = content.lines

      # Split into chunks of approximately equal size
      chunk_size = [lines.length / 4, 1000].max # At least 4 chunks, max 1000 lines per chunk
      chunks = []

      lines.each_slice(chunk_size) do |chunk_lines|
        chunk_content = chunk_lines.join
        chunk_file = "#{git_log_file}.chunk_#{chunks.length + 1}"
        File.write(chunk_file, chunk_content)
        chunks << chunk_file
      end

      chunks
    end

    # Analyze a single chunk
    def analyze_chunk(chunk_file)
      {
        churn: analyze_churn(chunk_file),
        coupling: analyze_coupling(chunk_file),
        authorship: analyze_authorship(chunk_file),
        summary: analyze_summary(chunk_file)
      }
    end

    # Merge analysis results from multiple chunks
    def merge_analysis_results(merged_results, chunk_results)
      # Merge churn data
      merged_results[:churn][:files].concat(chunk_results[:churn][:files])
      merged_results[:churn][:total_files] += chunk_results[:churn][:total_files]
      merged_results[:churn][:total_changes] += chunk_results[:churn][:total_changes]

      # Merge coupling data
      merged_results[:coupling][:couplings].concat(chunk_results[:coupling][:couplings])
      merged_results[:coupling][:total_couplings] += chunk_results[:coupling][:total_couplings]

      # Merge authorship data
      merged_results[:authorship][:files].concat(chunk_results[:authorship][:files])
      merged_results[:authorship][:total_files] += chunk_results[:authorship][:total_files]
      merged_results[:authorship][:files_with_multiple_authors] += chunk_results[:authorship][:files_with_multiple_authors]
      merged_results[:authorship][:files_with_single_author] += chunk_results[:authorship][:files_with_single_author]

      # Merge summary data (take the most recent/largest values)
      chunk_results[:summary][:summary].each do |key, value|
        current_value = merged_results[:summary][:summary][key]
        if current_value.nil? || should_update_summary_value(key, value, current_value)
          merged_results[:summary][:summary][key] = value
        end
      end
    end

    # Determine if summary value should be updated during merging
    def should_update_summary_value(key, new_value, current_value)
      case key
      when /Number of commits/
        new_value.to_i > current_value.to_i
      when /Number of entities/
        new_value.to_i > current_value.to_i
      when /Number of authors/
        new_value.to_i > current_value.to_i
      when /Total lines added/
        new_value.to_i > current_value.to_i
      when /Total lines deleted/
        new_value.to_i > current_value.to_i
      else
        # For other values, prefer the newer one
        true
      end
    end

    # Clean up chunk files after analysis
    def cleanup_chunk_files(git_log_file)
      Dir.glob("#{git_log_file}.chunk_*").each do |chunk_file|
        File.delete(chunk_file) if File.exist?(chunk_file)
      end
    end

    def parse_churn_results(file_path)
      return {files: []} unless File.exist?(file_path)

      lines = File.readlines(file_path)
      files = []

      lines.each do |line|
        next if line.strip.empty? || line.start_with?("entity,")

        parts = line.strip.split(",")
        next if parts.length < 2

        files << {
          file: parts[0],
          changes: parts[1].to_i,
          additions: parts[2]&.to_i || 0,
          deletions: parts[3]&.to_i || 0
        }
      end

      {
        files: files.sort_by { |f| -f[:changes] },
        total_files: files.length,
        total_changes: files.sum { |f| f[:changes] }
      }
    end

    def parse_coupling_results(file_path)
      return {couplings: []} unless File.exist?(file_path)

      lines = File.readlines(file_path)
      couplings = []

      lines.each do |line|
        next if line.strip.empty? || line.start_with?("entity,")

        parts = line.strip.split(",")
        next if parts.length < 3

        couplings << {
          file1: parts[0],
          file2: parts[1],
          shared_changes: parts[2].to_i,
          coupling_strength: parts[3]&.to_f || 0.0
        }
      end

      {
        couplings: couplings.sort_by { |c| -c[:shared_changes] },
        total_couplings: couplings.length,
        average_coupling: couplings.empty? ? 0 : couplings.sum { |c| c[:shared_changes] }.to_f / couplings.length
      }
    end

    def parse_authorship_results(file_path)
      return {files: []} unless File.exist?(file_path)

      lines = File.readlines(file_path)
      files = []

      lines.each do |line|
        next if line.strip.empty? || line.start_with?("entity,")

        parts = line.strip.split(",")
        next if parts.length < 2

        # Parse authors (format: "author1;author2;author3")
        authors_str = parts[1] || ""
        authors = authors_str.split(";").map(&:strip).reject(&:empty?)

        files << {
          file: parts[0],
          authors: authors,
          author_count: authors.length,
          changes: parts[2]&.to_i || 0
        }
      end

      {
        files: files.sort_by { |f| -f[:changes] },
        total_files: files.length,
        files_with_multiple_authors: files.count { |f| f[:author_count] > 1 },
        files_with_single_author: files.count { |f| f[:author_count] == 1 }
      }
    end

    def parse_summary_results(file_path)
      return {summary: {}} unless File.exist?(file_path)

      lines = File.readlines(file_path)
      summary = {}

      lines.each do |line|
        next if line.strip.empty?

        if line.include?(":")
          key, value = line.strip.split(":", 2)
          summary[key.strip] = value&.strip
        end
      end

      {summary: summary}
    end

    def generate_consolidated_report(results)
      report_file = File.join(@project_dir, "code_maat_analysis_report.md")

      report = <<~REPORT
        # Code Maat Analysis Report

        Generated on: #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}
        Project: #{File.basename(@project_dir)}

        ## Summary

        - **Total Files Analyzed**: #{results[:churn][:total_files]}
        - **Total Changes**: #{results[:churn][:total_changes]}
        - **Files with Multiple Authors**: #{results[:authorship][:files_with_multiple_authors]}
        - **Knowledge Silos (Single Author)**: #{results[:authorship][:files_with_single_author]}

        ## High-Churn Files (Top 10)

        #{results[:churn][:files].first(10).map { |f| "- #{f[:file]}: #{f[:changes]} changes" }.join("\n")}

        ## Tightly Coupled Files (Top 10)

        #{results[:coupling][:couplings].first(10).map { |c| "- #{c[:file1]} ↔ #{c[:file2]}: #{c[:shared_changes]} shared changes" }.join("\n")}

        ## Knowledge Silos (Top 10)

        #{results[:authorship][:files].select { |f| f[:author_count] == 1 }.first(10).map { |f| "- #{f[:file]}: #{f[:authors].first} (#{f[:changes]} changes)" }.join("\n")}

        ## Recommendations

        ### High Priority (High Churn + Single Author)
        These files are frequently changed by a single person, indicating potential knowledge silos:

        #{get_high_priority_files(results).map { |f| "- #{f[:file]} (#{f[:changes]} changes by #{f[:authors].first})" }.join("\n")}

        ### Medium Priority (High Churn + Multiple Authors)
        These files are frequently changed by multiple people, indicating potential coordination issues:

        #{get_medium_priority_files(results).map { |f| "- #{f[:file]} (#{f[:changes]} changes by #{f[:authors].join(", ")})" }.join("\n")}

        ### Refactoring Candidates (Tightly Coupled)
        These files are tightly coupled and may benefit from refactoring:

        #{results[:coupling][:couplings].first(10).map { |c| "- #{c[:file1]} and #{c[:file2]} (#{c[:shared_changes]} shared changes)" }.join("\n")}
      REPORT

      File.write(report_file, report)
      report_file
    end

    def get_high_priority_files(results)
      high_churn = results[:churn][:files].first(20)
      knowledge_silos = results[:authorship][:files].select { |f| f[:author_count] == 1 }

      high_churn.select do |churn_file|
        knowledge_silos.any? { |auth_file| auth_file[:file] == churn_file[:file] }
      end.map do |file|
        auth_data = knowledge_silos.find { |f| f[:file] == file[:file] }
        {
          file: file[:file],
          changes: file[:changes],
          authors: auth_data[:authors]
        }
      end
    end

    def get_medium_priority_files(results)
      high_churn = results[:churn][:files].first(20)
      multi_author = results[:authorship][:files].select { |f| f[:author_count] > 1 }

      high_churn.select do |churn_file|
        multi_author.any? { |auth_file| auth_file[:file] == churn_file[:file] }
      end.map do |file|
        auth_data = multi_author.find { |f| f[:file] == file[:file] }
        {
          file: file[:file],
          changes: file[:changes],
          authors: auth_data[:authors]
        }
      end
    end

    def docker_available?
      system("docker", "--version", out: File::NULL, err: File::NULL)
    end

    def code_maat_image_available?
      return false unless docker_available?

      cmd = ["docker", "images", "--format", "{{.Repository}}:{{.Tag}}"]
      stdout, _, status = Open3.capture3(*cmd)

      status.success? && stdout.include?(@docker_image)
    end

    def git_repository?
      Dir.exist?(File.join(@project_dir, ".git"))
    end

    def git_log_available?
      return false unless git_repository?

      cmd = ["git", "log", "--oneline", "-1"]
      stdout, _, status = Open3.capture3(*cmd, chdir: @project_dir)

      status.success? && !stdout.strip.empty?
    end
  end
end
