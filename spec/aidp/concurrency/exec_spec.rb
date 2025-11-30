# frozen_string_literal: true

RSpec.describe Aidp::Concurrency::Exec do
  # Reset pool cache before each test to ensure clean state
  before(:each) do
    described_class.instance_variable_set(:@pools, nil)
    described_class.instance_variable_set(:@default_pool, nil)
  end

  after(:each) do
    # Clean up pools after each test
    described_class.shutdown_all(timeout: 1)
  end

  describe ".pool" do
    it "creates a new fixed thread pool" do
      pool = described_class.pool(name: :test_pool, size: 4)
      expect(pool).to be_a(Concurrent::FixedThreadPool)
      expect(pool.max_length).to eq(4)
    end

    it "returns the same pool for the same name" do
      pool1 = described_class.pool(name: :test_pool, size: 4)
      pool2 = described_class.pool(name: :test_pool, size: 8)

      expect(pool1).to be(pool2) # Same object
      expect(pool1.max_length).to eq(4) # Original size preserved
    end

    it "creates different pools for different names" do
      pool1 = described_class.pool(name: :pool1, size: 4)
      pool2 = described_class.pool(name: :pool2, size: 8)

      expect(pool1).not_to be(pool2)
      expect(pool1.max_length).to eq(4)
      expect(pool2.max_length).to eq(8)
    end

    it "creates a cached thread pool when type is :cached" do
      pool = described_class.pool(name: :cached_pool, type: :cached)
      expect(pool).to be_a(Concurrent::CachedThreadPool)
    end

    it "uses default sizes for known pool names" do
      io_pool = described_class.pool(name: :io_pool)
      expect(io_pool.max_length).to eq(20)

      cpu_pool = described_class.pool(name: :cpu_pool)
      expect(cpu_pool.max_length).to eq(Concurrent.processor_count)

      bg_pool = described_class.pool(name: :background)
      expect(bg_pool.max_length).to eq(5)
    end

    it "raises on unknown pool type" do
      expect {
        described_class.pool(name: :bad_pool, type: :unknown)
      }.to raise_error(ArgumentError, /Unknown pool type/)
    end
  end

  describe ".future" do
    it "executes block asynchronously" do
      future = described_class.future { 1 + 1 }
      expect(future).to be_a(Concurrent::Promises::Future)
      expect(future.value!).to eq(2)
    end

    it "uses custom executor if provided" do
      custom_pool = described_class.pool(name: :custom, size: 2)
      future = described_class.future(executor: custom_pool) { Thread.current.name }

      result = future.value!
      expect(result).to be_a(String)
    end

    it "requires a block" do
      expect {
        described_class.future
      }.to raise_error(ArgumentError, /Block required/)
    end

    it "can handle exceptions" do
      future = described_class.future { raise "boom" }
      expect { future.value! }.to raise_error(StandardError, /boom/)
    end
  end

  describe ".zip" do
    it "waits for all futures to complete" do
      f1 = described_class.future {
        sleep 0.1
        "a"
      }
      f2 = described_class.future {
        sleep 0.1
        "b"
      }
      f3 = described_class.future {
        sleep 0.1
        "c"
      }

      result = described_class.zip(f1, f2, f3).value!
      expect(result).to eq(["a", "b", "c"])
    end

    it "returns empty array for no futures" do
      result = described_class.zip.value!
      expect(result).to eq([])
    end
  end

  describe ".default_pool" do
    it "returns a thread pool" do
      pool = described_class.default_pool
      expect(pool).to be_a(Concurrent::ThreadPoolExecutor)
    end

    it "returns the same pool on repeated calls" do
      pool1 = described_class.default_pool
      pool2 = described_class.default_pool
      expect(pool1).to be(pool2)
    end
  end

  describe ".shutdown_pool" do
    it "shuts down a specific pool" do
      pool = described_class.pool(name: :shutdown_test, size: 2)
      result = described_class.shutdown_pool(:shutdown_test, timeout: 1)

      expect(result).to be true
      expect(pool.shutdown?).to be true
    end

    it "returns true for non-existent pool" do
      result = described_class.shutdown_pool(:nonexistent, timeout: 1)
      expect(result).to be true
    end
  end

  describe ".shutdown_all" do
    it "shuts down all pools" do
      pool1 = described_class.pool(name: :pool1, size: 2)
      pool2 = described_class.pool(name: :pool2, size: 2)

      results = described_class.shutdown_all(timeout: 1)

      expect(results[:pool1]).to be true
      expect(results[:pool2]).to be true
      expect(pool1.shutdown?).to be true
      expect(pool2.shutdown?).to be true
    end

    it "shuts down default pool" do
      default_pool = described_class.default_pool

      described_class.shutdown_all(timeout: 1)

      expect(default_pool.shutdown?).to be true
    end
  end

  describe ".stats" do
    it "returns stats for all pools" do
      described_class.pool(name: :stats_test, size: 4)

      stats = described_class.stats

      expect(stats[:stats_test]).to be_a(Hash)
      expect(stats[:stats_test][:pool_size]).to eq(4)
      expect(stats[:stats_test]).to have_key(:queue_length)
      expect(stats[:stats_test]).to have_key(:active_threads)
      expect(stats[:stats_test]).to have_key(:completed_tasks)
    end

    it "includes default pool stats if it exists" do
      described_class.default_pool # Create default pool

      stats = described_class.stats

      expect(stats[:default]).to be_a(Hash)
      expect(stats[:default]).to have_key(:pool_size)
    end
  end

  describe "concurrent execution" do
    it "actually runs tasks in parallel" do
      start_time = Time.now
      counter = Concurrent::AtomicFixnum.new(0)

      futures = 3.times.map do
        described_class.future do
          sleep 0.2
          counter.increment
        end
      end

      described_class.zip(*futures).value!
      elapsed = Time.now - start_time

      expect(counter.value).to eq(3)
      # Should complete near the single-task duration, not the full sum if sequential
      expect(elapsed).to be < 0.45
    end
  end
end
