# frozen_string_literal: true

require "json"
require "yaml"

module Aidp
  module Analyze
    class RepositoryChunker
      # Chunking strategies
      CHUNKING_STRATEGIES = %w[time_based commit_count size_based feature_based].freeze

      # Default chunking configuration
      DEFAULT_CHUNK_CONFIG = {
        "time_based" => {
          "chunk_size" => "30d", # 30 days
          "overlap" => "7d" # 7 days overlap
        },
        "commit_count" => {
          "chunk_size" => 1000, # 1000 commits per chunk
          "overlap" => 100 # 100 commits overlap
        },
        "size_based" => {
          "chunk_size" => "100MB", # 100MB per chunk
          "overlap" => "10MB" # 10MB overlap
        },
        "feature_based" => {
          "max_files_per_chunk" => 500,
          "max_commits_per_chunk" => 500
        }
      }.freeze

      def initialize(project_dir = Dir.pwd, config = {})
        @project_dir = project_dir
        @config = config
        @chunk_config = load_chunk_config
      end

      # Chunk repository for analysis
      def chunk_repository(strategy = "time_based", options = {})
        strategy_config = @chunk_config[strategy] || DEFAULT_CHUNK_CONFIG[strategy]

        case strategy
        when "time_based"
          chunk_by_time(strategy_config, options)
        when "commit_count"
          chunk_by_commit_count(strategy_config, options)
        when "size_based"
          chunk_by_size(strategy_config, options)
        when "feature_based"
          chunk_by_features(strategy_config, options)
        else
          raise "Unknown chunking strategy: #{strategy}"
        end
      end

      # Chunk by time periods
      def chunk_by_time(config, options = {})
        chunk_size = parse_time_duration(config["chunk_size"])
        overlap = parse_time_duration(config["overlap"])

        # Get repository time range
        time_range = get_repository_time_range
        return [] if time_range.empty?

        chunks = []
        current_start = time_range[:start]

        while current_start < time_range[:end]
          current_end = [current_start + chunk_size, time_range[:end]].min

          chunk = {
            id: generate_chunk_id("time", current_start),
            strategy: "time_based",
            start_time: current_start,
            end_time: current_end,
            duration: current_end - current_start,
            commits: get_commits_in_time_range(current_start, current_end),
            files: get_files_in_time_range(current_start, current_end),
            overlap: overlap
          }

          chunks << chunk
          current_start = current_end - overlap
        end

        {
          strategy: "time_based",
          total_chunks: chunks.length,
          chunks: chunks,
          time_range: time_range,
          config: config
        }
      end

      # Chunk by commit count
      def chunk_by_commit_count(config, options = {})
        chunk_size = config["chunk_size"] || 1000
        overlap = config["overlap"] || 100

        # Get all commits
        all_commits = get_all_commits
        return [] if all_commits.empty?

        chunks = []
        total_commits = all_commits.length

        (0...total_commits).step(chunk_size - overlap) do |start_index|
          end_index = [start_index + chunk_size, total_commits].min

          chunk_commits = all_commits[start_index...end_index]

          chunk = {
            id: generate_chunk_id("commit", start_index),
            strategy: "commit_count",
            start_index: start_index,
            end_index: end_index,
            commit_count: chunk_commits.length,
            commits: chunk_commits,
            files: get_files_for_commits(chunk_commits),
            overlap: overlap
          }

          chunks << chunk
        end

        {
          strategy: "commit_count",
          total_chunks: chunks.length,
          chunks: chunks,
          total_commits: total_commits,
          config: config
        }
      end

      # Chunk by repository size
      def chunk_by_size(config, options = {})
        chunk_size = parse_size(config["chunk_size"])
        parse_size(config["overlap"])

        # Get repository structure
        repo_structure = analyze_repository_structure
        return [] if repo_structure.empty?

        chunks = []
        current_chunk = {
          id: generate_chunk_id("size", chunks.length),
          strategy: "size_based",
          files: [],
          size: 0,
          directories: []
        }

        repo_structure.each do |item|
          if current_chunk[:size] + item[:size] > chunk_size
            # Current chunk is full, save it and start new one
            chunks << current_chunk
            current_chunk = {
              id: generate_chunk_id("size", chunks.length),
              strategy: "size_based",
              files: [],
              size: 0,
              directories: []
            }
          end

          current_chunk[:files] << item[:path]
          current_chunk[:size] += item[:size]
          current_chunk[:directories] << File.dirname(item[:path])
        end

        # Add the last chunk if it has content
        chunks << current_chunk if current_chunk[:files].any?

        {
          strategy: "size_based",
          total_chunks: chunks.length,
          chunks: chunks,
          total_size: repo_structure.sum { |item| item[:size] },
          config: config
        }
      end

      # Chunk by features/components
      def chunk_by_features(config, options = {})
        max_files = config["max_files_per_chunk"] || 500
        max_commits = config["max_commits_per_chunk"] || 500

        # Identify features/components
        features = identify_features
        return [] if features.empty?

        chunks = []

        features.each do |feature|
          feature_files = get_feature_files(feature)
          feature_commits = get_feature_commits(feature)

          # Split large features into chunks
          if feature_files.length > max_files || feature_commits.length > max_commits
            feature_chunks = split_large_feature(feature, feature_files, feature_commits, max_files, max_commits)
            chunks.concat(feature_chunks)
          else
            chunk = {
              id: generate_chunk_id("feature", feature[:name]),
              strategy: "feature_based",
              feature: feature,
              files: feature_files,
              commits: feature_commits,
              file_count: feature_files.length,
              commit_count: feature_commits.length
            }
            chunks << chunk
          end
        end

        {
          strategy: "feature_based",
          total_chunks: chunks.length,
          chunks: chunks,
          features: features,
          config: config
        }
      end

      # Get chunk analysis plan
      def get_chunk_analysis_plan(chunks, analysis_type, options = {})
        plan = {
          analysis_type: analysis_type,
          total_chunks: chunks.length,
          chunks: [],
          estimated_duration: 0,
          dependencies: []
        }

        chunks.each_with_index do |chunk, index|
          chunk_plan = {
            chunk_id: chunk[:id],
            chunk_index: index,
            strategy: chunk[:strategy],
            estimated_duration: estimate_chunk_analysis_duration(chunk, analysis_type),
            dependencies: get_chunk_dependencies(chunk, chunks),
            priority: calculate_chunk_priority(chunk, analysis_type),
            resources: estimate_chunk_resources(chunk, analysis_type)
          }

          plan[:chunks] << chunk_plan
          plan[:estimated_duration] += chunk_plan[:estimated_duration]
        end

        # Sort chunks by priority
        plan[:chunks].sort_by! { |chunk| -chunk[:priority] }

        plan
      end

      # Execute chunk analysis
      def execute_chunk_analysis(chunk, analysis_type, options = {})
        start_time = Time.now

        results = {
          chunk_id: chunk[:id],
          analysis_type: analysis_type,
          start_time: start_time,
          status: "running"
        }

        # Perform analysis based on chunk type
        case chunk[:strategy]
        when "time_based"
          results[:data] = analyze_time_chunk(chunk, analysis_type, options)
        when "commit_count"
          results[:data] = analyze_commit_chunk(chunk, analysis_type, options)
        when "size_based"
          results[:data] = analyze_size_chunk(chunk, analysis_type, options)
        when "feature_based"
          results[:data] = analyze_feature_chunk(chunk, analysis_type, options)
        end

        results[:status] = "completed"
        results[:end_time] = Time.now
        results[:duration] = results[:end_time] - results[:start_time]

        results
      end

      # Merge chunk analysis results
      def merge_chunk_results(chunk_results, options = {})
        merged = {
          total_chunks: chunk_results.length,
          successful_chunks: chunk_results.count { |r| r[:status] == "completed" },
          failed_chunks: chunk_results.count { |r| r[:status] == "failed" },
          total_duration: chunk_results.sum { |r| r[:duration] || 0 },
          merged_data: {},
          errors: []
        }

        # Collect errors
        chunk_results.each do |result|
          next unless result[:status] == "failed"

          merged[:errors] << {
            chunk_id: result[:chunk_id],
            error: result[:error]
          }
        end

        # Merge successful results
        successful_results = chunk_results.select { |r| r[:status] == "completed" }

        successful_results.each do |result|
          merge_chunk_data(merged[:merged_data], result[:data])
        end

        merged
      end

      # Get chunk statistics
      def get_chunk_statistics(chunks)
        return {} if chunks.empty?

        stats = {
          total_chunks: chunks.length,
          strategies: chunks.map { |c| c[:strategy] }.tally,
          total_files: chunks.sum { |c| c[:files]&.length || 0 },
          total_commits: chunks.sum { |c| c[:commits]&.length || 0 },
          average_chunk_size: calculate_average_chunk_size(chunks),
          chunk_distribution: analyze_chunk_distribution(chunks)
        }

        # Strategy-specific statistics
        strategies = chunks.map { |c| c[:strategy] }.uniq
        strategies.each do |strategy|
          strategy_chunks = chunks.select { |c| c[:strategy] == strategy }
          stats["#{strategy}_stats"] = get_strategy_statistics(strategy_chunks, strategy)
        end

        stats
      end

      private

      def load_chunk_config
        config_file = File.join(@project_dir, ".aidp-chunk-config.yml")

        if File.exist?(config_file)
          YAML.load_file(config_file) || DEFAULT_CHUNK_CONFIG
        else
          DEFAULT_CHUNK_CONFIG
        end
      end

      def parse_time_duration(duration_str)
        # Parse duration strings like "30d", "7d", "1w", etc.
        # Use anchored patterns with limited digit repetition to prevent ReDoS
        case duration_str.to_s.strip
        when /\A(\d{1,6})d\z/
          ::Regexp.last_match(1).to_i * 24 * 60 * 60
        when /\A(\d{1,6})w\z/
          ::Regexp.last_match(1).to_i * 7 * 24 * 60 * 60
        when /\A(\d{1,6})m\z/
          ::Regexp.last_match(1).to_i * 30 * 24 * 60 * 60
        when /\A(\d{1,6})y\z/
          ::Regexp.last_match(1).to_i * 365 * 24 * 60 * 60
        else
          30 * 24 * 60 * 60 # Default to 30 days
        end
      end

      def parse_size(size_str)
        # Parse size strings like "100MB", "1GB", etc.
        # Use anchored patterns with limited digit repetition to prevent ReDoS
        case size_str.to_s.strip
        when /\A(\d{1,10})KB\z/i
          ::Regexp.last_match(1).to_i * 1024
        when /\A(\d{1,10})MB\z/i
          ::Regexp.last_match(1).to_i * 1024 * 1024
        when /\A(\d{1,10})GB\z/i
          ::Regexp.last_match(1).to_i * 1024 * 1024 * 1024
        else
          100 * 1024 * 1024 # Default to 100MB
        end
      end

      def get_repository_time_range
        # Get the time range of the repository
        # This would use git commands to get the first and last commit dates
        {
          start: Time.now - (365 * 24 * 60 * 60), # 1 year ago
          end: Time.now
        }
      end

      def get_commits_in_time_range(start_time, end_time)
        # Get commits within the specified time range
        # This would use git log with date filtering
        []
      end

      def get_files_in_time_range(start_time, end_time)
        # Get files modified within the specified time range
        # This would use git log --name-only with date filtering
        []
      end

      def get_all_commits
        # Get all commits in the repository
        # This would use git log
        []
      end

      def get_files_for_commits(commits)
        # Get files modified in the specified commits
        # This would use git show --name-only
        []
      end

      def analyze_repository_structure
        # Analyze the repository structure to get file sizes and organization
        structure = []

        Dir.glob(File.join(@project_dir, "**", "*")).each do |path|
          next unless File.file?(path)

          relative_path = path.sub(@project_dir + "/", "")
          structure << {
            path: relative_path,
            size: File.size(path),
            type: File.extname(path)
          }
        end

        structure
      end

      def identify_features
        # Identify features/components in the repository
        features = []

        # Look for common feature patterns
        feature_patterns = [
          "app/features/**/*",
          "features/**/*",
          "src/features/**/*",
          "lib/features/**/*"
        ]

        feature_patterns.each do |pattern|
          Dir.glob(File.join(@project_dir, pattern)).each do |path|
            next unless Dir.exist?(path)

            feature_name = File.basename(path)
            features << {
              name: feature_name,
              path: path.sub(@project_dir + "/", ""),
              type: "directory"
            }
          end
        end

        features
      end

      def get_feature_files(feature)
        # Get files associated with a feature
        feature_path = File.join(@project_dir, feature[:path])
        return [] unless Dir.exist?(feature_path)

        files = []
        Dir.glob(File.join(feature_path, "**", "*")).each do |path|
          next unless File.file?(path)

          files << path.sub(@project_dir + "/", "")
        end

        files
      end

      def get_feature_commits(feature)
        # Get commits related to a feature
        # This would use git log with path filtering
        []
      end

      def split_large_feature(feature, files, commits, max_files, max_commits)
        # Split a large feature into smaller chunks
        chunks = []

        # Split by files
        files.each_slice(max_files) do |file_chunk|
          chunks << {
            id: generate_chunk_id("feature", "#{feature[:name]}_files_#{chunks.length}"),
            strategy: "feature_based",
            feature: feature,
            files: file_chunk,
            commits: commits,
            file_count: file_chunk.length,
            commit_count: commits.length
          }
        end

        chunks
      end

      def generate_chunk_id(prefix, identifier)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        "#{prefix}_#{identifier}_#{timestamp}"
      end

      def estimate_chunk_analysis_duration(chunk, analysis_type)
        # Estimate analysis duration based on chunk size and analysis type
        base_duration = case analysis_type
        when "static_analysis"
          30 # seconds per file
        when "security_analysis"
          60 # seconds per file
        when "performance_analysis"
          45 # seconds per file
        else
          30 # seconds per file
        end

        file_count = chunk[:files]&.length || 0
        commit_count = chunk[:commits]&.length || 0

        (file_count + commit_count) * base_duration
      end

      def get_chunk_dependencies(chunk, all_chunks)
        # Get dependencies between chunks
        []

        # This would analyze relationships between chunks
        # For now, return empty array
      end

      def calculate_chunk_priority(chunk, analysis_type)
        # Calculate priority for chunk analysis
        priority = 0

        # Higher priority for larger chunks
        priority += chunk[:files]&.length || 0
        priority += chunk[:commits]&.length || 0

        # Higher priority for certain analysis types
        case analysis_type
        when "security_analysis"
          priority *= 2
        when "performance_analysis"
          priority *= 1.5
        end

        priority
      end

      def estimate_chunk_resources(chunk, analysis_type)
        # Estimate resource requirements for chunk analysis
        {
          memory: estimate_memory_usage(chunk),
          cpu: estimate_cpu_usage(chunk, analysis_type),
          disk: estimate_disk_usage(chunk)
        }
      end

      def estimate_memory_usage(chunk)
        # Estimate memory usage based on chunk size
        file_count = chunk[:files]&.length || 0
        commit_count = chunk[:commits]&.length || 0

        (file_count + commit_count) * 1024 * 1024 # 1MB per item
      end

      def estimate_cpu_usage(chunk, analysis_type)
        # Estimate CPU usage based on analysis type
        case analysis_type
        when "static_analysis"
          "medium"
        when "security_analysis"
          "high"
        when "performance_analysis"
          "high"
        else
          "low"
        end
      end

      def estimate_disk_usage(chunk)
        # Estimate disk usage for temporary files
        file_count = chunk[:files]&.length || 0
        file_count * 1024 * 1024 # 1MB per file for temporary storage
      end

      def analyze_time_chunk(chunk, analysis_type, options)
        # Analyze a time-based chunk
        {
          time_range: {
            start: chunk[:start_time],
            end: chunk[:end_time]
          },
          commits: chunk[:commits],
          files: chunk[:files],
          analysis_results: {}
        }
      end

      def analyze_commit_chunk(chunk, analysis_type, options)
        # Analyze a commit-based chunk
        {
          commit_range: {
            start: chunk[:start_index],
            end: chunk[:end_index]
          },
          commits: chunk[:commits],
          files: chunk[:files],
          analysis_results: {}
        }
      end

      def analyze_size_chunk(chunk, analysis_type, options)
        # Analyze a size-based chunk
        {
          size: chunk[:size],
          files: chunk[:files],
          directories: chunk[:directories],
          analysis_results: {}
        }
      end

      def analyze_feature_chunk(chunk, analysis_type, options)
        # Analyze a feature-based chunk
        {
          feature: chunk[:feature],
          files: chunk[:files],
          commits: chunk[:commits],
          analysis_results: {}
        }
      end

      def merge_chunk_data(merged_data, chunk_data)
        # Merge data from a chunk into the merged results
        chunk_data.each do |key, value|
          if merged_data[key].is_a?(Array) && value.is_a?(Array)
            merged_data[key].concat(value)
          elsif merged_data[key].is_a?(Hash) && value.is_a?(Hash)
            merged_data[key].merge!(value)
          else
            merged_data[key] = value
          end
        end
      end

      def calculate_average_chunk_size(chunks)
        return 0 if chunks.empty?

        total_size = chunks.sum do |chunk|
          (chunk[:files]&.length || 0) + (chunk[:commits]&.length || 0)
        end

        total_size.to_f / chunks.length
      end

      def analyze_chunk_distribution(chunks)
        # Analyze the distribution of chunk sizes
        sizes = chunks.map do |chunk|
          (chunk[:files]&.length || 0) + (chunk[:commits]&.length || 0)
        end

        {
          min: sizes.min,
          max: sizes.max,
          average: sizes.sum.to_f / sizes.length,
          median: calculate_median(sizes)
        }
      end

      def calculate_median(values)
        sorted = values.sort
        length = sorted.length

        if length.odd?
          sorted[length / 2]
        else
          (sorted[length / 2 - 1] + sorted[length / 2]) / 2.0
        end
      end

      def get_strategy_statistics(chunks, strategy)
        # Get statistics for a specific chunking strategy
        {
          chunk_count: chunks.length,
          total_files: chunks.sum { |c| c[:files]&.length || 0 },
          total_commits: chunks.sum { |c| c[:commits]&.length || 0 },
          average_size: calculate_average_chunk_size(chunks)
        }
      end
    end
  end
end
