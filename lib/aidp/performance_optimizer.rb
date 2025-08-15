# frozen_string_literal: true

require 'concurrent'
require 'digest'
require 'json'

module Aidp
  # Performance optimization system for large codebases
  class PerformanceOptimizer
    attr_reader :cache, :memory_manager, :parallel_executor, :config

    def initialize(project_dir, config = {})
      @project_dir = project_dir
      @config = DEFAULT_CONFIG.merge(config)
      @cache = setup_cache
      @memory_manager = MemoryManager.new(@config[:memory])
      @parallel_executor = setup_parallel_executor
      @performance_metrics = {}
    end

    # Optimize analysis performance for large codebases
    def optimize_analysis(analysis_type, data, options = {})
      start_time = Time.current

      # Check cache first
      cache_key = generate_cache_key(analysis_type, data)
      cached_result = @cache.get(cache_key)

      if cached_result && !options[:force_refresh]
        log_performance_metric(analysis_type, 'cache_hit', Time.current - start_time)
        return cached_result
      end

      # Apply optimization strategies
      optimized_data = apply_optimization_strategies(analysis_type, data, options)

      # Execute analysis with optimizations
      result = execute_optimized_analysis(analysis_type, optimized_data, options)

      # Cache result
      @cache.set(cache_key, result, @config[:cache_ttl])

      # Record performance metrics
      duration = Time.current - start_time
      log_performance_metric(analysis_type, 'analysis', duration)

      result
    end

    # Optimize file processing for large repositories
    def optimize_file_processing(files, processor, options = {})
      return process_files_sequentially(files, processor) if files.length < @config[:parallel_threshold]

      # Determine optimal chunk size
      chunk_size = calculate_optimal_chunk_size(files.length)

      # Split files into chunks
      chunks = files.each_slice(chunk_size).to_a

      # Process chunks in parallel
      results = process_chunks_parallel(chunks, processor, options)

      # Merge results
      merge_parallel_results(results)
    end

    # Optimize database operations
    def optimize_database_operations(operations, options = {})
      return execute_operations_sequentially(operations) if operations.length < @config[:batch_threshold]

      # Group operations by type
      grouped_operations = group_operations_by_type(operations)

      # Execute in batches
      results = execute_batched_operations(grouped_operations, options)

      # Merge results
      merge_database_results(results)
    end

    # Optimize memory usage
    def optimize_memory_usage(operation, options = {})
      @memory_manager.process_large_dataset(operation, options)
    end

    # Get performance statistics
    def get_performance_statistics
      {
        cache_stats: @cache.statistics,
        memory_stats: @memory_manager.get_memory_statistics,
        parallel_stats: @parallel_executor.statistics,
        analysis_metrics: @performance_metrics,
        recommendations: generate_performance_recommendations
      }
    end

    # Clear cache and reset metrics
    def clear_cache
      @cache.clear
      @performance_metrics.clear
    end

    private

    DEFAULT_CONFIG = {
      cache_ttl: 3600, # 1 hour
      parallel_threshold: 50,
      batch_threshold: 100,
      memory: {
        max_memory: 1024 * 1024 * 1024, # 1GB
        chunk_size: 1000,
        gc_threshold: 0.8
      },
      parallel: {
        max_workers: Concurrent.processor_count,
        timeout: 300,
        retry_attempts: 2
      }
    }.freeze

    def setup_cache
      CacheManager.new(
        max_size: @config[:cache_size] || 1000,
        ttl: @config[:cache_ttl]
      )
    end

    def setup_parallel_executor
      ParallelExecutor.new(
        max_workers: @config[:parallel][:max_workers],
        timeout: @config[:parallel][:timeout]
      )
    end

    def generate_cache_key(analysis_type, data)
      content = "#{analysis_type}:#{data.hash}:#{File.mtime(@project_dir).to_i}"
      Digest::MD5.hexdigest(content)
    end

    def apply_optimization_strategies(analysis_type, data, options)
      case analysis_type
      when 'repository_analysis'
        optimize_repository_analysis(data, options)
      when 'architecture_analysis'
        optimize_architecture_analysis(data, options)
      when 'static_analysis'
        optimize_static_analysis(data, options)
      else
        data
      end
    end

    def optimize_repository_analysis(data, options)
      # Optimize Git log processing
      if data[:git_log] && data[:git_log].length > @config[:parallel_threshold]
        data[:git_log] = chunk_git_log(data[:git_log])
      end

      # Optimize file analysis
      if data[:files] && data[:files].length > @config[:parallel_threshold]
        data[:files] = chunk_files_for_analysis(data[:files])
      end

      data
    end

    def optimize_architecture_analysis(data, options)
      # Optimize dependency analysis
      if data[:dependencies] && data[:dependencies].length > @config[:parallel_threshold]
        data[:dependencies] = chunk_dependencies(data[:dependencies])
      end

      # Optimize pattern detection
      if data[:patterns] && data[:patterns].length > @config[:parallel_threshold]
        data[:patterns] = chunk_patterns(data[:patterns])
      end

      data
    end

    def optimize_static_analysis(data, options)
      # Optimize tool execution
      data[:tools] = group_tools_for_parallel_execution(data[:tools]) if data[:tools] && data[:tools].length > 1

      # Optimize file processing
      if data[:files] && data[:files].length > @config[:parallel_threshold]
        data[:files] = chunk_files_for_static_analysis(data[:files])
      end

      data
    end

    def execute_optimized_analysis(analysis_type, data, options)
      case analysis_type
      when 'repository_analysis'
        execute_repository_analysis_optimized(data, options)
      when 'architecture_analysis'
        execute_architecture_analysis_optimized(data, options)
      when 'static_analysis'
        execute_static_analysis_optimized(data, options)
      else
        execute_generic_analysis(data, options)
      end
    end

    def execute_repository_analysis_optimized(data, options)
      results = []

      # Process Git log chunks in parallel
      if data[:git_log_chunks]
        git_results = @parallel_executor.execute(
          data[:git_log_chunks],
          method(:process_git_log_chunk)
        )
        results.concat(git_results)
      end

      # Process file chunks in parallel
      if data[:file_chunks]
        file_results = @parallel_executor.execute(
          data[:file_chunks],
          method(:process_file_chunk)
        )
        results.concat(file_results)
      end

      # Merge results
      merge_repository_analysis_results(results)
    end

    def execute_architecture_analysis_optimized(data, options)
      results = []

      # Process dependency chunks in parallel
      if data[:dependency_chunks]
        dep_results = @parallel_executor.execute(
          data[:dependency_chunks],
          method(:process_dependency_chunk)
        )
        results.concat(dep_results)
      end

      # Process pattern chunks in parallel
      if data[:pattern_chunks]
        pattern_results = @parallel_executor.execute(
          data[:pattern_chunks],
          method(:process_pattern_chunk)
        )
        results.concat(pattern_results)
      end

      # Merge results
      merge_architecture_analysis_results(results)
    end

    def execute_static_analysis_optimized(data, options)
      results = []

      # Execute tools in parallel
      if data[:tool_groups]
        tool_results = @parallel_executor.execute(
          data[:tool_groups],
          method(:execute_tool_group)
        )
        results.concat(tool_results)
      end

      # Process file chunks in parallel
      if data[:file_chunks]
        file_results = @parallel_executor.execute(
          data[:file_chunks],
          method(:process_static_analysis_chunk)
        )
        results.concat(file_results)
      end

      # Merge results
      merge_static_analysis_results(results)
    end

    def execute_generic_analysis(data, options)
      # Generic optimization for unknown analysis types
      if data.length > @config[:parallel_threshold]
        chunks = data.each_slice(@config[:parallel_threshold]).to_a
        results = @parallel_executor.execute(chunks, method(:process_generic_chunk))
        merge_generic_results(results)
      else
        process_generic_data(data)
      end
    end

    def process_files_sequentially(files, processor)
      files.map { |file| processor.call(file) }
    end

    def calculate_optimal_chunk_size(total_files)
      workers = @config[:parallel][:max_workers]
      optimal_size = (total_files.to_f / workers).ceil
      [optimal_size, @config[:memory][:chunk_size]].min
    end

    def process_chunks_parallel(chunks, processor, options)
      @parallel_executor.execute(chunks) do |chunk|
        chunk.map { |item| processor.call(item) }
      end
    end

    def merge_parallel_results(results)
      results.flatten.compact
    end

    def execute_operations_sequentially(operations)
      operations.map { |op| execute_database_operation(op) }
    end

    def group_operations_by_type(operations)
      operations.group_by { |op| op[:type] }
    end

    def execute_batched_operations(grouped_operations, options)
      results = {}

      grouped_operations.each do |type, ops|
        batches = ops.each_slice(@config[:batch_threshold]).to_a
        batch_results = @parallel_executor.execute(batches) do |batch|
          execute_batch_operation(type, batch)
        end
        results[type] = batch_results.flatten
      end

      results
    end

    def merge_database_results(results)
      results.values.flatten
    end

    def chunk_git_log(git_log)
      chunk_size = calculate_optimal_chunk_size(git_log.length)
      git_log.each_slice(chunk_size).to_a
    end

    def chunk_files_for_analysis(files)
      chunk_size = calculate_optimal_chunk_size(files.length)
      files.each_slice(chunk_size).to_a
    end

    def chunk_dependencies(dependencies)
      chunk_size = calculate_optimal_chunk_size(dependencies.length)
      dependencies.each_slice(chunk_size).to_a
    end

    def chunk_patterns(patterns)
      chunk_size = calculate_optimal_chunk_size(patterns.length)
      patterns.each_slice(chunk_size).to_a
    end

    def group_tools_for_parallel_execution(tools)
      # Group tools that can run in parallel
      groups = []
      current_group = []

      tools.each do |tool|
        if can_run_in_parallel?(current_group, tool)
          current_group << tool
        else
          groups << current_group unless current_group.empty?
          current_group = [tool]
        end
      end

      groups << current_group unless current_group.empty?
      groups
    end

    def chunk_files_for_static_analysis(files)
      chunk_size = calculate_optimal_chunk_size(files.length)
      files.each_slice(chunk_size).to_a
    end

    def can_run_in_parallel?(current_group, tool)
      # Check if tool can run in parallel with current group
      # This is a simplified check - in practice, you'd check for resource conflicts
      current_group.length < @config[:parallel][:max_workers]
    end

    # Processing methods for parallel execution
    def process_git_log_chunk(chunk)
      # Process a chunk of Git log entries
      chunk.map do |entry|
        {
          commit: entry[:hash],
          author: entry[:author],
          date: entry[:date],
          files: entry[:files]
        }
      end
    end

    def process_file_chunk(chunk)
      # Process a chunk of files
      chunk.map do |file|
        {
          path: file[:path],
          size: File.size(file[:path]),
          modified: File.mtime(file[:path])
        }
      end
    end

    def process_dependency_chunk(chunk)
      # Process a chunk of dependencies
      chunk.map do |dep|
        {
          source: dep[:source],
          target: dep[:target],
          type: dep[:type]
        }
      end
    end

    def process_pattern_chunk(chunk)
      # Process a chunk of patterns
      chunk.map do |pattern|
        {
          name: pattern[:name],
          files: pattern[:files],
          confidence: pattern[:confidence]
        }
      end
    end

    def execute_tool_group(tool_group)
      # Execute a group of tools
      tool_group.map do |tool|
        {
          tool: tool[:name],
          result: execute_single_tool(tool)
        }
      end
    end

    def process_static_analysis_chunk(chunk)
      # Process a chunk for static analysis
      chunk.map do |file|
        {
          file: file[:path],
          analysis: analyze_single_file(file)
        }
      end
    end

    def process_generic_chunk(chunk)
      # Process a generic chunk
      chunk.map { |item| process_generic_item(item) }
    end

    # Result merging methods
    def merge_repository_analysis_results(results)
      {
        commits: results.flat_map { |r| r[:commits] || [] },
        files: results.flat_map { |r| r[:files] || [] },
        statistics: aggregate_statistics(results.map { |r| r[:statistics] })
      }
    end

    def merge_architecture_analysis_results(results)
      {
        dependencies: results.flat_map { |r| r[:dependencies] || [] },
        patterns: results.flat_map { |r| r[:patterns] || [] },
        components: results.flat_map { |r| r[:components] || [] }
      }
    end

    def merge_static_analysis_results(results)
      {
        tool_results: results.flat_map { |r| r[:tool_results] || [] },
        file_analysis: results.flat_map { |r| r[:file_analysis] || [] },
        issues: results.flat_map { |r| r[:issues] || [] }
      }
    end

    def merge_generic_results(results)
      results.flatten.compact
    end

    # Database operation methods
    def execute_database_operation(operation)
      case operation[:type]
      when 'select'
        execute_select_operation(operation)
      when 'insert'
        execute_insert_operation(operation)
      when 'update'
        execute_update_operation(operation)
      when 'delete'
        execute_delete_operation(operation)
      else
        raise ArgumentError, "Unknown operation type: #{operation[:type]}"
      end
    end

    def execute_batch_operation(type, batch)
      batch.map { |op| execute_database_operation(op) }
    end

    def execute_select_operation(operation)
      # Execute SELECT operation
      { type: 'select', result: 'mock_result' }
    end

    def execute_insert_operation(operation)
      # Execute INSERT operation
      { type: 'insert', result: 'mock_result' }
    end

    def execute_update_operation(operation)
      # Execute UPDATE operation
      { type: 'update', result: 'mock_result' }
    end

    def execute_delete_operation(operation)
      # Execute DELETE operation
      { type: 'delete', result: 'mock_result' }
    end

    # Utility methods
    def execute_single_tool(tool)
      # Execute a single static analysis tool
      { tool: tool[:name], status: 'completed', issues: [] }
    end

    def analyze_single_file(file)
      # Analyze a single file
      { file: file[:path], complexity: 5, issues: [] }
    end

    def process_generic_item(item)
      # Process a generic item
      { processed: true, data: item }
    end

    def aggregate_statistics(statistics_list)
      # Aggregate statistics from multiple results
      {
        total_files: statistics_list.sum { |s| s[:total_files] || 0 },
        total_commits: statistics_list.sum { |s| s[:total_commits] || 0 },
        total_lines: statistics_list.sum { |s| s[:total_lines] || 0 }
      }
    end

    def log_performance_metric(analysis_type, metric, duration)
      @performance_metrics[analysis_type] ||= {}
      @performance_metrics[analysis_type][metric] = duration
    end

    def generate_performance_recommendations
      recommendations = []

      # Analyze cache performance
      cache_stats = @cache.statistics
      recommendations << 'Consider increasing cache size or TTL for better performance' if cache_stats[:hit_rate] < 0.5

      # Analyze memory usage
      memory_stats = @memory_manager.get_memory_statistics
      if memory_stats[:usage_percentage] > 80
        recommendations << 'Consider reducing chunk size or implementing streaming for large datasets'
      end

      # Analyze parallel performance
      parallel_stats = @parallel_executor.statistics
      if parallel_stats[:utilization] < 0.7
        recommendations << 'Consider adjusting parallel worker count for better resource utilization'
      end

      recommendations
    end
  end

  # Cache manager for performance optimization
  class CacheManager
    attr_reader :statistics

    def initialize(max_size: 1000, ttl: 3600)
      @max_size = max_size
      @ttl = ttl
      @cache = {}
      @statistics = { hits: 0, misses: 0, sets: 0 }
    end

    def get(key)
      entry = @cache[key]
      return nil unless entry && !expired?(entry)

      @statistics[:hits] += 1
      entry[:value]
    end

    def set(key, value, ttl = nil)
      cleanup_if_needed

      @cache[key] = {
        value: value,
        timestamp: Time.current,
        ttl: ttl || @ttl
      }

      @statistics[:sets] += 1
    end

    def clear
      @cache.clear
      @statistics = { hits: 0, misses: 0, sets: 0 }
    end

    def statistics
      total_requests = @statistics[:hits] + @statistics[:misses]
      hit_rate = total_requests > 0 ? @statistics[:hits].to_f / total_requests : 0

      {
        size: @cache.size,
        max_size: @max_size,
        hit_rate: hit_rate,
        hits: @statistics[:hits],
        misses: @statistics[:misses],
        sets: @statistics[:sets]
      }
    end

    private

    def expired?(entry)
      Time.current - entry[:timestamp] > entry[:ttl]
    end

    def cleanup_if_needed
      return unless @cache.size >= @max_size

      # Remove expired entries first
      @cache.delete_if { |_, entry| expired?(entry) }

      # If still over limit, remove oldest entries
      return unless @cache.size >= @max_size

      sorted_entries = @cache.sort_by { |_, entry| entry[:timestamp] }
      entries_to_remove = @cache.size - @max_size + 1
      entries_to_remove.times { |i| @cache.delete(sorted_entries[i][0]) }
    end
  end

  # Parallel executor for performance optimization
  class ParallelExecutor
    attr_reader :statistics

    def initialize(max_workers: Concurrent.processor_count, timeout: 300)
      @max_workers = max_workers
      @timeout = timeout
      @statistics = { executions: 0, total_time: 0, errors: 0 }
    end

    def execute(items, processor = nil)
      start_time = Time.current
      @statistics[:executions] += 1

      processor = method(processor) if processor.is_a?(Symbol) || processor.is_a?(String)

      futures = items.map do |item|
        Concurrent::Future.execute do
          processor ? processor.call(item) : item
        rescue StandardError => e
          @statistics[:errors] += 1
          { error: e.message, item: item }
        end
      end

      results = futures.map do |future|
        future.value(@timeout)
      end

      @statistics[:total_time] += Time.current - start_time
      results
    end

    def statistics
      avg_time = @statistics[:executions] > 0 ? @statistics[:total_time] / @statistics[:executions] : 0
      utilization = @statistics[:executions] > 0 ? @statistics[:total_time] / (@statistics[:executions] * @timeout) : 0

      {
        max_workers: @max_workers,
        executions: @statistics[:executions],
        total_time: @statistics[:total_time],
        average_time: avg_time,
        errors: @statistics[:errors],
        utilization: utilization
      }
    end
  end
end
