# frozen_string_literal: true

require "json"
require "yaml"
require "digest"

module Aidp
  class MemoryManager
    # Memory management strategies
    MEMORY_STRATEGIES = %w[streaming chunking caching garbage_collection].freeze

    # Default configuration
    DEFAULT_CONFIG = {
      max_memory_usage: 1024 * 1024 * 1024, # 1GB
      chunk_size: 1000,
      cache_size: 100,
      gc_threshold: 0.8, # 80% memory usage triggers GC
      streaming_enabled: true,
      compression_enabled: false
    }.freeze

    def initialize(config = {})
      @config = DEFAULT_CONFIG.merge(config)
      @cache = {}
      @memory_usage = 0
      @peak_memory_usage = 0
      @gc_count = 0
      @streaming_data = []
    end

    # Process large dataset with memory management
    def process_large_dataset(dataset, processor_method, options = {})
      strategy = options[:strategy] || "streaming"

      case strategy
      when "streaming"
        process_with_streaming(dataset, processor_method, options)
      when "chunking"
        process_with_chunking(dataset, processor_method, options)
      when "caching"
        process_with_caching(dataset, processor_method, options)
      else
        raise "Unknown memory management strategy: #{strategy}"
      end
    end

    # Process data with streaming approach
    def process_with_streaming(dataset, processor_method, options = {})
      results = {
        processed_items: 0,
        memory_usage: [],
        gc_count: 0,
        results: [],
        errors: []
      }

      dataset.each_with_index do |item, index|
        # Check memory usage
        current_memory = get_memory_usage
        results[:memory_usage] << current_memory

        # Trigger garbage collection if needed
        if should_trigger_gc?(current_memory)
          trigger_garbage_collection
          results[:gc_count] += 1
        end

        # Process item
        result = processor_method.call(item, options)
        results[:results] << result
        results[:processed_items] += 1

        # Update memory tracking
        update_memory_tracking(current_memory)
      end

      results
    end

    # Process data with chunking approach
    def process_with_chunking(dataset, processor_method, options = {})
      chunk_size = options[:chunk_size] || @config[:chunk_size]
      results = {
        processed_chunks: 0,
        processed_items: 0,
        memory_usage: [],
        gc_count: 0,
        results: [],
        errors: []
      }

      dataset.each_slice(chunk_size) do |chunk|
        # Check memory before processing chunk
        pre_chunk_memory = get_memory_usage
        results[:memory_usage] << pre_chunk_memory

        # Process chunk
        chunk_results = process_chunk(chunk, processor_method, options)
        results[:results].concat(chunk_results[:results])
        results[:errors].concat(chunk_results[:errors])
        results[:processed_items] += chunk_results[:processed_items]

        # Trigger garbage collection after chunk
        if should_trigger_gc?(pre_chunk_memory)
          trigger_garbage_collection
          results[:gc_count] += 1
        end

        results[:processed_chunks] += 1
        update_memory_tracking(pre_chunk_memory)
      end

      results
    end

    # Process data with caching approach
    def process_with_caching(dataset, processor_method, options = {})
      cache_size = options[:cache_size] || @config[:cache_size]
      results = {
        processed_items: 0,
        cache_hits: 0,
        cache_misses: 0,
        memory_usage: [],
        gc_count: 0,
        results: [],
        errors: []
      }

      begin
        dataset.each_with_index do |item, index|
          # Check memory usage
          current_memory = get_memory_usage
          results[:memory_usage] << current_memory

          # Check cache
          cache_key = generate_cache_key(item)
          if @cache.key?(cache_key)
            results[:cache_hits] += 1
            result = @cache[cache_key]
          else
            results[:cache_misses] += 1
            begin
              result = processor_method.call(item, options)
              cache_result(cache_key, result, cache_size)
            rescue => e
              results[:errors] << {
                item_index: index,
                error: e.message
              }
              next
            end
          end

          results[:results] << result
          results[:processed_items] += 1

          # Trigger garbage collection if needed
          if should_trigger_gc?(current_memory)
            trigger_garbage_collection
            results[:gc_count] += 1
          end

          update_memory_tracking(current_memory)
        end
      rescue => e
        results[:errors] << {
          type: "caching_error",
          message: e.message
        }
      end

      results
    end

    # Optimize memory usage
    def optimize_memory_usage(options = {})
      optimizations = {
        memory_before: get_memory_usage,
        optimizations_applied: [],
        memory_after: 0,
        memory_saved: 0
      }

      # Clear cache if memory usage is high
      if get_memory_usage > @config[:max_memory_usage] * 0.8
        clear_cache
        optimizations[:optimizations_applied] << "cache_cleared"
      end

      # Trigger garbage collection
      trigger_garbage_collection
      optimizations[:optimizations_applied] << "garbage_collection"

      # Compress data if enabled
      if @config[:compression_enabled]
        compress_data
        optimizations[:optimizations_applied] << "data_compression"
      end

      optimizations[:memory_after] = get_memory_usage
      optimizations[:memory_saved] = optimizations[:memory_before] - optimizations[:memory_after]

      optimizations
    end

    # Get memory statistics
    def get_memory_statistics
      {
        current_memory: get_memory_usage,
        peak_memory: @peak_memory_usage,
        cache_size: @cache.length,
        gc_count: @gc_count,
        streaming_data_size: @streaming_data.length,
        memory_limit: @config[:max_memory_usage],
        memory_usage_percentage: (get_memory_usage.to_f / @config[:max_memory_usage] * 100).round(2)
      }
    end

    # Clear memory
    def clear_memory
      clear_cache
      @streaming_data.clear
      trigger_garbage_collection

      {
        memory_cleared: true,
        memory_after_clear: get_memory_usage
      }
    end

    # Monitor memory usage
    def monitor_memory_usage(duration = 60, interval = 1)
      monitoring_data = {
        start_time: Time.now,
        duration: duration,
        interval: interval,
        measurements: [],
        alerts: []
      }

      start_time = Time.now
      end_time = start_time + duration

      while Time.now < end_time
        current_memory = get_memory_usage
        current_time = Time.now

        measurement = {
          timestamp: current_time,
          memory_usage: current_memory,
          memory_percentage: (current_memory.to_f / @config[:max_memory_usage] * 100).round(2)
        }

        monitoring_data[:measurements] << measurement

        # Check for memory alerts
        if current_memory > @config[:max_memory_usage] * 0.9
          monitoring_data[:alerts] << {
            timestamp: current_time,
            type: "high_memory_usage",
            message: "Memory usage is at #{measurement[:memory_percentage]}%"
          }
        end

        Async::Task.current.sleep(interval)
      end

      monitoring_data[:end_time] = Time.now
      monitoring_data
    end

    private

    def process_chunk(chunk, processor_method, options)
      results = {
        processed_items: 0,
        results: [],
        errors: []
      }

      chunk.each_with_index do |item, index|
        result = processor_method.call(item, options)
        results[:results] << result
        results[:processed_items] += 1
      end

      results
    end

    def should_trigger_gc?(current_memory)
      current_memory > @config[:max_memory_usage] * @config[:gc_threshold]
    end

    def trigger_garbage_collection
      GC.start
      @gc_count += 1
    end

    def get_memory_usage
      # Get current memory usage in bytes
      Process.getrusage(:SELF).maxrss * 1024
    end

    def update_memory_tracking(current_memory)
      @memory_usage = current_memory
      @peak_memory_usage = [@peak_memory_usage, current_memory].max
    end

    def generate_cache_key(item)
      # Generate a cache key for the item
      Digest::MD5.hexdigest(item.to_json)
    rescue JSON::GeneratorError
      # Fallback to object_id if JSON serialization fails
      "item_#{item.object_id}"
    end

    def cache_result(key, result, max_cache_size)
      # Add result to cache
      @cache[key] = result

      # Remove oldest entries if cache is full
      return unless @cache.length > max_cache_size

      oldest_key = @cache.keys.first
      @cache.delete(oldest_key)
    end

    def clear_cache
      @cache.clear
    end

    def compress_data
      # Compress streaming data if it's large
      return unless @streaming_data.length > 1000

      @streaming_data = @streaming_data.last(500) # Keep only recent data
    end
  end
end
