# frozen_string_literal: true

require "concurrent-ruby"

module Aidp
  module Concurrency
    # Centralized executor and thread pool management.
    #
    # Provides named, configured executors for different workload types
    # (I/O-bound, CPU-bound, background tasks) with standardized error
    # handling and instrumentation.
    #
    # @example Get a named pool
    #   pool = Exec.pool(name: :io_pool, size: 10)
    #   future = Concurrent::Promises.future_on(pool) { fetch_remote_data() }
    #
    # @example Execute a future
    #   result = Exec.future { expensive_computation() }.value!
    #
    # @example Shutdown all pools
    #   Exec.shutdown_all
    module Exec
      class << self
        # Expose for testability - reset pool cache between tests
        attr_writer :pools, :default_pool

        # Get or create a named thread pool.
        #
        # Pools are cached by name. Calling this method multiple times with the
        # same name returns the same pool instance.
        #
        # @param name [Symbol] Pool name (e.g., :io_pool, :cpu_pool, :background)
        # @param size [Integer] Pool size (default: based on pool type)
        # @param type [Symbol] Pool type :fixed or :cached (default: :fixed)
        # @return [Concurrent::ThreadPoolExecutor] The thread pool
        #
        # @example
        #   io_pool = Exec.pool(name: :io, size: 20)
        #   cpu_pool = Exec.pool(name: :cpu, size: 4)
        def pool(name:, size: nil, type: :fixed)
          @pools ||= Concurrent::Hash.new
          @pools[name] ||= create_pool(name, size, type)
        end

        # Execute a block on a future using the default pool.
        #
        # @param executor [Concurrent::ExecutorService] Custom executor (optional)
        # @yield Block to execute asynchronously
        # @return [Concurrent::Promises::Future] The future
        #
        # @example
        #   future = Exec.future { slow_operation() }
        #   result = future.value! # Wait for result
        def future(executor: nil, &block)
          raise ArgumentError, "Block required" unless block_given?

          executor ||= default_pool
          Concurrent::Promises.future_on(executor, &block)
        end

        # Execute multiple futures in parallel and wait for all to complete.
        #
        # @param futures [Array<Concurrent::Promises::Future>] Futures to zip
        # @return [Concurrent::Promises::Future] Future that resolves when all complete
        #
        # @example
        #   futures = [
        #     Exec.future { task1() },
        #     Exec.future { task2() },
        #     Exec.future { task3() }
        #   ]
        #   results = Exec.zip(*futures).value!
        def zip(*futures)
          Concurrent::Promises.zip(*futures)
        end

        # Get the default executor pool.
        #
        # @return [Concurrent::ThreadPoolExecutor]
        def default_pool
          @default_pool ||= pool(name: :default, size: default_pool_size)
        end

        # Shutdown a specific pool.
        #
        # @param name [Symbol] Pool name
        # @param timeout [Float] Seconds to wait for shutdown
        # @return [Boolean] true if shutdown cleanly
        def shutdown_pool(name, timeout: 60)
          @pools ||= Concurrent::Hash.new
          pool = @pools.delete(name)
          return true unless pool

          pool.shutdown
          pool.wait_for_termination(timeout)
        end

        # Shutdown all managed pools.
        #
        # @param timeout [Float] Seconds to wait for each pool
        # @return [Hash] Map of pool name to shutdown success
        def shutdown_all(timeout: 60)
          @pools ||= Concurrent::Hash.new
          results = {}

          @pools.each_key do |name|
            results[name] = shutdown_pool(name, timeout: timeout)
          end

          @default_pool&.shutdown
          @default_pool&.wait_for_termination(timeout)

          results
        end

        # Get statistics for all pools.
        #
        # @return [Hash] Map of pool name to stats
        def stats
          @pools ||= Concurrent::Hash.new
          stats = {}

          @pools.each do |name, pool|
            stats[name] = pool_stats(pool)
          end

          stats[:default] = pool_stats(@default_pool) if @default_pool

          stats
        end

        private

        def create_pool(name, size, type)
          size ||= default_size_for_pool(name, type)

          pool = case type
          when :fixed
            Concurrent::FixedThreadPool.new(size)
          when :cached
            Concurrent::CachedThreadPool.new
          else
            raise ArgumentError, "Unknown pool type: #{type}"
          end

          log_pool_created(name, type, size)
          pool
        end

        def default_size_for_pool(name, type)
          return nil if type == :cached

          case name
          when :io, :io_pool
            20 # I/O-bound: can have more threads
          when :cpu, :cpu_pool
            processor_count # CPU-bound: match CPU cores
          when :background
            5 # Background tasks: small pool
          else
            10 # Generic default
          end
        end

        def default_pool_size
          [processor_count * 2, 10].max
        end

        def processor_count
          @processor_count ||= Concurrent.processor_count
        end

        def pool_stats(pool)
          return nil unless pool

          {
            pool_size: pool.max_length,
            queue_length: pool.queue_length,
            active_threads: pool.length,
            completed_tasks: pool.completed_task_count
          }
        rescue => e
          {error: e.message}
        end

        def log_pool_created(name, type, size)
          Concurrency.logger&.debug(
            "concurrency_pool",
            "Created #{type} pool :#{name} with size #{size || "dynamic"}"
          )
        end
      end
    end
  end
end
