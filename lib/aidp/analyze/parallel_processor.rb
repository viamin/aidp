# frozen_string_literal: true

require "concurrent"
require "json"

module Aidp
  module Analyze
    class ParallelProcessor
      # Default configuration
      DEFAULT_CONFIG = {
        max_workers: 4,
        chunk_size: 10,
        timeout: 300, # 5 minutes
        retry_attempts: 2,
        memory_limit: 1024 * 1024 * 1024, # 1GB
        cpu_limit: 0.8 # 80% CPU usage
      }.freeze

      def initialize(config = {})
        @config = DEFAULT_CONFIG.merge(config)
        @executor = nil
        @results = Concurrent::Array.new
        @errors = Concurrent::Array.new
        @progress = Concurrent::AtomicFixnum.new(0)
      end

      # Process chunks in parallel
      def process_chunks_parallel(chunks, processor_method, options = {})
        return [] if chunks.empty?

        setup_executor
        start_time = Time.now

        results = {
          total_chunks: chunks.length,
          processed_chunks: 0,
          failed_chunks: 0,
          start_time: start_time,
          end_time: nil,
          duration: nil,
          results: [],
          errors: [],
          statistics: {}
        }

        begin
          # Create futures for each chunk
          futures = create_futures(chunks, processor_method, options)

          # Wait for all futures to complete
          completed_futures = wait_for_completion(futures, options)

          # Collect results
          collect_results(completed_futures, results)
        rescue => e
          results[:errors] << {
            type: "processing_error",
            message: e.message,
            backtrace: e.backtrace
          }
        ensure
          cleanup_executor
          results[:end_time] = Time.now
          results[:duration] = results[:end_time] - results[:start_time]
          results[:statistics] = calculate_statistics(results)
        end

        results
      end

      # Process chunks with dependency management
      def process_chunks_with_dependencies(chunks, dependencies, processor_method, options = {})
        return [] if chunks.empty?

        setup_executor
        start_time = Time.now

        results = {
          total_chunks: chunks.length,
          processed_chunks: 0,
          failed_chunks: 0,
          start_time: start_time,
          end_time: nil,
          duration: nil,
          results: [],
          errors: [],
          execution_order: [],
          statistics: {}
        }

        begin
          # Create execution plan based on dependencies
          execution_plan = create_execution_plan(chunks, dependencies)

          # Execute chunks in dependency order
          execution_plan.each do |phase|
            phase_results = process_phase_parallel(phase, processor_method, options)
            results[:results].concat(phase_results[:results])
            results[:errors].concat(phase_results[:errors])
            results[:processed_chunks] += phase_results[:processed_chunks]
            results[:failed_chunks] += phase_results[:failed_chunks]
            results[:execution_order].concat(phase.map { |chunk| chunk[:id] })
          end
        rescue => e
          results[:errors] << {
            type: "dependency_error",
            message: e.message,
            backtrace: e.backtrace
          }
        ensure
          cleanup_executor
          results[:end_time] = Time.now
          results[:duration] = results[:end_time] - results[:start_time]
          results[:statistics] = calculate_statistics(results)
        end

        results
      end

      # Process chunks with resource management
      def process_chunks_with_resource_management(chunks, processor_method, options = {})
        return [] if chunks.empty?

        setup_executor
        start_time = Time.now

        results = {
          total_chunks: chunks.length,
          processed_chunks: 0,
          failed_chunks: 0,
          start_time: start_time,
          end_time: nil,
          duration: nil,
          results: [],
          errors: [],
          resource_usage: {},
          statistics: {}
        }

        begin
          # Monitor system resources
          resource_monitor = start_resource_monitoring

          # Process chunks with resource constraints
          chunk_results = process_with_resource_constraints(chunks, processor_method, options, resource_monitor)

          results[:results] = chunk_results[:results]
          results[:errors] = chunk_results[:errors]
          results[:processed_chunks] = chunk_results[:processed_chunks]
          results[:failed_chunks] = chunk_results[:failed_chunks]
          results[:resource_usage] = resource_monitor[:usage]
        rescue => e
          results[:errors] << {
            type: "resource_error",
            message: e.message,
            backtrace: e.backtrace
          }
        ensure
          stop_resource_monitoring
          cleanup_executor
          results[:end_time] = Time.now
          results[:duration] = results[:end_time] - results[:start_time]
          results[:statistics] = calculate_statistics(results)
        end

        results
      end

      # Get processing statistics
      def get_processing_statistics
        {
          total_processed: @progress.value,
          total_errors: @errors.length,
          executor_status: executor_status,
          memory_usage: get_memory_usage,
          cpu_usage: get_cpu_usage
        }
      end

      # Cancel ongoing processing
      def cancel_processing
        cleanup_executor
        {
          cancelled: true,
          processed_count: @progress.value,
          error_count: @errors.length
        }
      end

      private

      def setup_executor
        @executor = Concurrent::ThreadPoolExecutor.new(
          min_threads: 1,
          max_threads: @config[:max_workers],
          max_queue: @config[:max_workers] * 2,
          fallback_policy: :caller_runs
        )
      end

      def cleanup_executor
        return unless @executor

        @executor.shutdown
        @executor.wait_for_termination(@config[:timeout])
        @executor = nil
      end

      def create_futures(chunks, processor_method, options)
        futures = []

        chunks.each_with_index do |chunk, index|
          future = @executor.post do
            process_chunk_with_retry(chunk, processor_method, options, index)
          end

          futures << {
            future: future,
            chunk: chunk,
            index: index
          }
        end

        futures
      end

      def wait_for_completion(futures, options)
        timeout = options[:timeout] || @config[:timeout]
        completed_futures = []

        futures.each do |future_info|
          result = future_info[:future].value(timeout)
          completed_futures << {
            chunk: future_info[:chunk],
            result: result,
            index: future_info[:index]
          }
          @progress.increment
        end

        completed_futures
      end

      def collect_results(completed_futures, results)
        completed_futures.each do |future_result|
          if future_result[:result][:success]
            results[:results] << future_result[:result]
            results[:processed_chunks] += 1
          else
            results[:errors] << {
              chunk_id: future_result[:chunk][:id],
              error: future_result[:result][:error],
              index: future_result[:index]
            }
            results[:failed_chunks] += 1
          end
        end
      end

      def process_chunk_with_retry(chunk, processor_method, options, index)
        retry_attempts = options[:retry_attempts] || @config[:retry_attempts]
        attempt = 0

        begin
          attempt += 1
          result = processor_method.call(chunk, options)
          result[:success] = true
          result[:attempt] = attempt
          result
        rescue => e
          if attempt < retry_attempts
            Async::Task.current.sleep(2**attempt) # Exponential backoff
            retry
          else
            {
              success: false,
              error: e.message,
              attempt: attempt,
              chunk_id: chunk[:id]
            }
          end
        end
      end

      def create_execution_plan(chunks, dependencies)
        # Create a topological sort of chunks based on dependencies
        execution_plan = []
        remaining_chunks = chunks.dup
        completed_chunks = Set.new

        until remaining_chunks.empty?
          phase = []

          remaining_chunks.each do |chunk|
            chunk_deps = dependencies[chunk[:id]] || []
            phase << chunk if chunk_deps.all? { |dep| completed_chunks.include?(dep) }
          end

          if phase.empty?
            # Circular dependency detected
            raise "Circular dependency detected in chunks"
          end

          execution_plan << phase
          phase.each { |chunk| completed_chunks.add(chunk[:id]) }
          remaining_chunks.reject! { |chunk| phase.include?(chunk) }
        end

        execution_plan
      end

      def process_phase_parallel(phase_chunks, processor_method, options)
        return {results: [], errors: [], processed_chunks: 0, failed_chunks: 0} if phase_chunks.empty?

        phase_results = process_chunks_parallel(phase_chunks, processor_method, options)

        {
          results: phase_results[:results],
          errors: phase_results[:errors],
          processed_chunks: phase_results[:processed_chunks],
          failed_chunks: phase_results[:failed_chunks]
        }
      end

      def start_resource_monitoring
        monitor = {
          start_time: Time.now,
          usage: {
            memory: [],
            cpu: [],
            disk: []
          },
          running: true
        }

        # Start monitoring task using Async
        require "async"
        Async do |task|
          task.async do
            while monitor[:running]
              monitor[:usage][:memory] << get_memory_usage
              monitor[:usage][:cpu] << get_cpu_usage
              monitor[:usage][:disk] << get_disk_usage
              Async::Task.current.sleep(1) # Non-blocking sleep
            end
          end
        end

        monitor
      end

      def stop_resource_monitoring
        # This would be called to stop the monitoring thread
        # For now, just return
      end

      def process_with_resource_constraints(chunks, processor_method, options, resource_monitor)
        results = {
          results: [],
          errors: [],
          processed_chunks: 0,
          failed_chunks: 0
        }

        chunks.each do |chunk|
          # Check resource constraints
          if resource_constraints_exceeded(resource_monitor)
            # Wait for resources to become available
            wait_for_resources(resource_monitor)
          end

          # Process chunk
          begin
            result = processor_method.call(chunk, options)
            if result[:success]
              results[:results] << result
              results[:processed_chunks] += 1
            else
              results[:errors] << {
                chunk_id: chunk[:id],
                error: result[:error]
              }
              results[:failed_chunks] += 1
            end
          rescue => e
            results[:errors] << {
              chunk_id: chunk[:id],
              error: e.message
            }
            results[:failed_chunks] += 1
          end
        end

        results
      end

      def resource_constraints_exceeded(resource_monitor)
        memory_usage = get_memory_usage
        cpu_usage = get_cpu_usage

        memory_usage > @config[:memory_limit] || cpu_usage > @config[:cpu_limit]
      end

      def wait_for_resources(resource_monitor)
        # Wait until resources are available
        Async::Task.current.sleep(1)
      end

      def get_memory_usage
        # Get current memory usage
        # This is a simplified implementation
        Process.getrusage(:SELF).maxrss * 1024 # Convert to bytes
      end

      def get_cpu_usage
        # Get current CPU usage
        # This is a simplified implementation
        0.5 # Return 50% as default
      end

      def get_disk_usage
        # Get current disk usage
        # This is a simplified implementation
        0.3 # Return 30% as default
      end

      def executor_status
        return "not_initialized" unless @executor

        if @executor.shutdown?
          "shutdown"
        elsif @executor.shuttingdown?
          "shutting_down"
        else
          "running"
        end
      end

      def calculate_statistics(results)
        return {} if results[:results].empty?

        durations = results[:results].map { |r| r[:duration] || 0 }
        memory_usage = results[:results].map { |r| r[:memory_usage] || 0 }

        {
          average_duration: durations.sum.to_f / durations.length,
          min_duration: durations.min,
          max_duration: durations.max,
          total_duration: durations.sum,
          average_memory: memory_usage.sum.to_f / memory_usage.length,
          success_rate: results[:processed_chunks].to_f / results[:total_chunks] * 100,
          throughput: results[:processed_chunks].to_f / results[:duration]
        }
      end
    end
  end
end
