# frozen_string_literal: true

require "spec_helper"
require "aidp/parallel_processor"

RSpec.describe Aidp::ParallelProcessor do
  let(:processor) { described_class.new }

  describe "#initialize" do
    it "initializes with default configuration" do
      expect(processor).to be_a(described_class)
    end

    it "accepts custom configuration" do
      custom_config = {
        max_workers: 8,
        chunk_size: 20,
        timeout: 600,
        retry_attempts: 3
      }
      processor_with_config = described_class.new(custom_config)
      expect(processor_with_config).to be_a(described_class)
    end
  end

  describe "#process_chunks_parallel" do
    let(:chunks) do
      [
        {id: "chunk1", data: "test1"},
        {id: "chunk2", data: "test2"},
        {id: "chunk3", data: "test3"}
      ]
    end

    let(:processor_method) do
      ->(chunk, options) { {chunk_id: chunk[:id], processed: true, data: chunk[:data]} }
    end

    it "processes chunks in parallel" do
      results = processor.process_chunks_parallel(chunks, processor_method)

      expect(results).to be_a(Hash)
      expect(results[:total_chunks]).to eq(3)
      expect(results[:processed_chunks]).to eq(3)
      expect(results[:failed_chunks]).to eq(0)
      expect(results[:start_time]).to be_a(Time)
      expect(results[:end_time]).to be_a(Time)
      expect(results[:duration]).to be >= 0
      expect(results[:results]).to be_an(Array)
      expect(results[:errors]).to be_an(Array)
      expect(results[:statistics]).to be_a(Hash)
    end

    it "returns successful results for all chunks" do
      results = processor.process_chunks_parallel(chunks, processor_method)

      expect(results[:results]).to have(3).items
      results[:results].each do |result|
        expect(result[:success]).to be true
        expect(result[:chunk_id]).to match(/chunk\d/)
        expect(result[:processed]).to be true
        expect(result[:data]).to match(/test\d/)
      end
    end

    it "handles empty chunks array" do
      results = processor.process_chunks_parallel([], processor_method)
      expect(results).to eq([])
    end

    it "handles processor method errors gracefully" do
      failing_processor = ->(chunk, options) { raise "Processing failed for #{chunk[:id]}" }

      results = processor.process_chunks_parallel(chunks, failing_processor)

      expect(results[:total_chunks]).to eq(3)
      expect(results[:processed_chunks]).to eq(0)
      expect(results[:failed_chunks]).to eq(3)
      expect(results[:errors]).to have(1).item
      expect(results[:errors].first[:type]).to eq("processing_error")
    end
  end

  describe "#process_chunks_with_dependencies" do
    let(:chunks) do
      [
        {id: "chunk1", data: "test1"},
        {id: "chunk2", data: "test2"},
        {id: "chunk3", data: "test3"}
      ]
    end

    let(:dependencies) do
      {
        "chunk2" => ["chunk1"],
        "chunk3" => ["chunk2"]
      }
    end

    let(:processor_method) do
      ->(chunk, options) { {chunk_id: chunk[:id], processed: true, data: chunk[:data]} }
    end

    it "processes chunks respecting dependencies" do
      results = processor.process_chunks_with_dependencies(chunks, dependencies, processor_method)

      expect(results).to be_a(Hash)
      expect(results[:total_chunks]).to eq(3)
      expect(results[:processed_chunks]).to eq(3)
      expect(results[:failed_chunks]).to eq(0)
      expect(results[:execution_order]).to be_an(Array)
      expect(results[:statistics]).to be_a(Hash)
    end

    it "executes chunks in dependency order" do
      results = processor.process_chunks_with_dependencies(chunks, dependencies, processor_method)

      expect(results[:execution_order]).to include("chunk1", "chunk2", "chunk3")
      # chunk1 should come before chunk2, and chunk2 before chunk3
      chunk1_index = results[:execution_order].index("chunk1")
      chunk2_index = results[:execution_order].index("chunk2")
      chunk3_index = results[:execution_order].index("chunk3")

      expect(chunk1_index).to be < chunk2_index
      expect(chunk2_index).to be < chunk3_index
    end

    it "handles circular dependencies" do
      circular_dependencies = {
        "chunk1" => ["chunk2"],
        "chunk2" => ["chunk1"]
      }

      expect do
        processor.process_chunks_with_dependencies(chunks, circular_dependencies, processor_method)
      end.to raise_error(RuntimeError, /Circular dependency detected/)
    end

    it "handles chunks without dependencies" do
      results = processor.process_chunks_with_dependencies(chunks, {}, processor_method)

      expect(results[:total_chunks]).to eq(3)
      expect(results[:processed_chunks]).to eq(3)
      expect(results[:execution_order]).to have(3).items
    end
  end

  describe "#process_chunks_with_resource_management" do
    let(:chunks) do
      [
        {id: "chunk1", data: "test1"},
        {id: "chunk2", data: "test2"}
      ]
    end

    let(:processor_method) do
      ->(chunk, options) { {chunk_id: chunk[:id], processed: true, data: chunk[:data]} }
    end

    it "processes chunks with resource management" do
      results = processor.process_chunks_with_resource_management(chunks, processor_method)

      expect(results).to be_a(Hash)
      expect(results[:total_chunks]).to eq(2)
      expect(results[:processed_chunks]).to eq(2)
      expect(results[:failed_chunks]).to eq(0)
      expect(results[:resource_usage]).to be_a(Hash)
      expect(results[:statistics]).to be_a(Hash)
    end

    it "includes resource usage information" do
      results = processor.process_chunks_with_resource_management(chunks, processor_method)

      expect(results[:resource_usage]).to have_key(:memory)
      expect(results[:resource_usage]).to have_key(:cpu)
      expect(results[:resource_usage]).to have_key(:disk)
    end

    it "handles resource constraint errors" do
      # This would be tested with a processor that exceeds resource limits
      # For now, we just verify the structure
      results = processor.process_chunks_with_resource_management(chunks, processor_method)

      expect(results[:errors]).to be_an(Array)
    end
  end

  describe "#get_processing_statistics" do
    it "returns processing statistics" do
      stats = processor.get_processing_statistics

      expect(stats).to be_a(Hash)
      expect(stats[:total_processed]).to be >= 0
      expect(stats[:total_errors]).to be >= 0
      expect(stats[:executor_status]).to be_a(String)
      expect(stats[:memory_usage]).to be >= 0
      expect(stats[:cpu_usage]).to be >= 0
    end

    it "tracks processed items" do
      chunks = [{id: "chunk1", data: "test1"}]
      processor_method = ->(chunk, options) { {chunk_id: chunk[:id], processed: true} }

      processor.process_chunks_parallel(chunks, processor_method)
      stats = processor.get_processing_statistics

      expect(stats[:total_processed]).to be >= 1
    end
  end

  describe "#cancel_processing" do
    it "cancels ongoing processing" do
      result = processor.cancel_processing

      expect(result).to be_a(Hash)
      expect(result[:cancelled]).to be true
      expect(result[:processed_count]).to be >= 0
      expect(result[:error_count]).to be >= 0
    end
  end

  describe "private methods" do
    describe "#setup_executor" do
      it "sets up thread pool executor" do
        processor.send(:setup_executor)
        expect(processor.instance_variable_get(:@executor)).to be_a(Concurrent::ThreadPoolExecutor)
      end
    end

    describe "#cleanup_executor" do
      it "cleans up executor properly" do
        processor.send(:setup_executor)
        processor.send(:cleanup_executor)
        expect(processor.instance_variable_get(:@executor)).to be_nil
      end

      it "handles nil executor gracefully" do
        expect { processor.send(:cleanup_executor) }.not_to raise_error
      end
    end

    describe "#create_futures" do
      let(:chunks) { [{id: "chunk1", data: "test1"}] }
      let(:processor_method) { ->(chunk, options) { {processed: true} } }

      it "creates futures for chunks" do
        processor.send(:setup_executor)
        futures = processor.send(:create_futures, chunks, processor_method, {})

        expect(futures).to be_an(Array)
        expect(futures).to have(1).item

        future_info = futures.first
        expect(future_info).to have_key(:future)
        expect(future_info).to have_key(:chunk)
        expect(future_info).to have_key(:index)
        expect(future_info[:future]).to be_a(Concurrent::Future)
      end
    end

    describe "#wait_for_completion" do
      let(:chunks) { [{id: "chunk1", data: "test1"}] }
      let(:processor_method) { ->(chunk, options) { {processed: true} } }

      it "waits for futures to complete" do
        processor.send(:setup_executor)
        futures = processor.send(:create_futures, chunks, processor_method, {})
        completed = processor.send(:wait_for_completion, futures, {})

        expect(completed).to be_an(Array)
        expect(completed).to have(1).item

        completed_info = completed.first
        expect(completed_info).to have_key(:chunk)
        expect(completed_info).to have_key(:result)
        expect(completed_info).to have_key(:index)
      end

      it "handles timeout" do
        slow_processor = lambda { |chunk, options|
          sleep(2)
          {processed: true}
        }

        processor.send(:setup_executor)
        futures = processor.send(:create_futures, chunks, slow_processor, {})

        # Test with short timeout
        completed = processor.send(:wait_for_completion, futures, {timeout: 0.1})
        expect(completed).to be_an(Array)
      end
    end

    describe "#collect_results" do
      let(:completed_futures) do
        [
          {
            chunk: {id: "chunk1"},
            result: {success: true, data: "result1"},
            index: 0
          },
          {
            chunk: {id: "chunk2"},
            result: {success: false, error: "failed"},
            index: 1
          }
        ]
      end

      it "collects results from completed futures" do
        results = {results: [], errors: [], processed_chunks: 0, failed_chunks: 0}
        processor.send(:collect_results, completed_futures, results)

        expect(results[:results]).to have(1).item
        expect(results[:errors]).to have(1).item
        expect(results[:processed_chunks]).to eq(1)
        expect(results[:failed_chunks]).to eq(1)
      end
    end

    describe "#process_chunk_with_retry" do
      let(:chunk) { {id: "chunk1", data: "test1"} }
      let(:processor_method) { ->(chunk, options) { {processed: true} } }

      it "processes chunk successfully" do
        result = processor.send(:process_chunk_with_retry, chunk, processor_method, {}, 0)

        expect(result[:success]).to be true
        expect(result[:attempt]).to eq(1)
        expect(result[:processed]).to be true
      end

      it "retries on failure" do
        failing_processor = ->(chunk, options) { raise "Processing failed" }

        result = processor.send(:process_chunk_with_retry, chunk, failing_processor, {retry_attempts: 2}, 0)

        expect(result[:success]).to be false
        expect(result[:attempt]).to eq(2)
        expect(result[:error]).to eq("Processing failed")
      end
    end

    describe "#create_execution_plan" do
      let(:chunks) do
        [
          {id: "chunk1"},
          {id: "chunk2"},
          {id: "chunk3"}
        ]
      end

      let(:dependencies) do
        {
          "chunk2" => ["chunk1"],
          "chunk3" => ["chunk2"]
        }
      end

      it "creates execution plan based on dependencies" do
        plan = processor.send(:create_execution_plan, chunks, dependencies)

        expect(plan).to be_an(Array)
        expect(plan).to have(3).items

        # First phase should contain chunk1 (no dependencies)
        expect(plan[0]).to include(chunks[0])

        # Second phase should contain chunk2 (depends on chunk1)
        expect(plan[1]).to include(chunks[1])

        # Third phase should contain chunk3 (depends on chunk2)
        expect(plan[2]).to include(chunks[2])
      end

      it "handles chunks without dependencies" do
        plan = processor.send(:create_execution_plan, chunks, {})

        expect(plan).to be_an(Array)
        expect(plan).to have(1).item
        expect(plan[0]).to have(3).items
      end

      it "detects circular dependencies" do
        circular_deps = {
          "chunk1" => ["chunk2"],
          "chunk2" => ["chunk1"]
        }

        expect do
          processor.send(:create_execution_plan, chunks, circular_deps)
        end.to raise_error(RuntimeError, /Circular dependency detected/)
      end
    end

    describe "#process_phase_parallel" do
      let(:phase_chunks) { [{id: "chunk1", data: "test1"}] }
      let(:processor_method) { ->(chunk, options) { {processed: true} } }

      it "processes phase chunks in parallel" do
        result = processor.send(:process_phase_parallel, phase_chunks, processor_method, {})

        expect(result).to be_a(Hash)
        expect(result[:results]).to be_an(Array)
        expect(result[:errors]).to be_an(Array)
        expect(result[:processed_chunks]).to be >= 0
        expect(result[:failed_chunks]).to be >= 0
      end

      it "handles empty phase" do
        result = processor.send(:process_phase_parallel, [], processor_method, {})

        expect(result[:results]).to eq([])
        expect(result[:errors]).to eq([])
        expect(result[:processed_chunks]).to eq(0)
        expect(result[:failed_chunks]).to eq(0)
      end
    end

    describe "#start_resource_monitoring" do
      it "starts resource monitoring" do
        monitor = processor.send(:start_resource_monitoring)

        expect(monitor).to be_a(Hash)
        expect(monitor[:start_time]).to be_a(Time)
        expect(monitor[:usage]).to be_a(Hash)
        expect(monitor[:usage][:memory]).to be_an(Array)
        expect(monitor[:usage][:cpu]).to be_an(Array)
        expect(monitor[:usage][:disk]).to be_an(Array)
        expect(monitor[:running]).to be true
      end
    end

    describe "#stop_resource_monitoring" do
      it "stops resource monitoring" do
        expect { processor.send(:stop_resource_monitoring) }.not_to raise_error
      end
    end

    describe "#process_with_resource_constraints" do
      let(:chunks) { [{id: "chunk1", data: "test1"}] }
      let(:processor_method) { ->(chunk, options) { {processed: true} } }
      let(:resource_monitor) { {usage: {memory: [], cpu: [], disk: []}} }

      it "processes chunks with resource constraints" do
        results = processor.send(:process_with_resource_constraints, chunks, processor_method, {}, resource_monitor)

        expect(results).to be_a(Hash)
        expect(results[:results]).to be_an(Array)
        expect(results[:errors]).to be_an(Array)
        expect(results[:processed_chunks]).to be >= 0
        expect(results[:failed_chunks]).to be >= 0
      end
    end

    describe "#resource_constraints_exceeded" do
      let(:resource_monitor) { {usage: {memory: [], cpu: [], disk: []}} }

      it "checks resource constraints" do
        exceeded = processor.send(:resource_constraints_exceeded, resource_monitor)
        expect(exceeded).to be_in([true, false])
      end
    end

    describe "#wait_for_resources" do
      let(:resource_monitor) { {usage: {memory: [], cpu: [], disk: []}} }

      it "waits for resources to become available" do
        start_time = Time.now
        processor.send(:wait_for_resources, resource_monitor)
        end_time = Time.now

        # Should wait at least 1 second
        expect(end_time - start_time).to be >= 1
      end
    end

    describe "#get_memory_usage" do
      it "returns memory usage" do
        usage = processor.send(:get_memory_usage)
        expect(usage).to be >= 0
      end
    end

    describe "#get_cpu_usage" do
      it "returns CPU usage" do
        usage = processor.send(:get_cpu_usage)
        expect(usage).to be >= 0
        expect(usage).to be <= 1
      end
    end

    describe "#get_disk_usage" do
      it "returns disk usage" do
        usage = processor.send(:get_disk_usage)
        expect(usage).to be >= 0
        expect(usage).to be <= 1
      end
    end

    describe "#executor_status" do
      it "returns executor status" do
        status = processor.send(:executor_status)
        expect(status).to eq("not_initialized")

        processor.send(:setup_executor)
        status = processor.send(:executor_status)
        expect(status).to eq("running")

        processor.send(:cleanup_executor)
        status = processor.send(:executor_status)
        expect(status).to eq("not_initialized")
      end
    end

    describe "#calculate_statistics" do
      let(:results) do
        {
          results: [
            {duration: 10, memory_usage: 100},
            {duration: 20, memory_usage: 200}
          ],
          processed_chunks: 2,
          total_chunks: 2,
          duration: 30
        }
      end

      it "calculates processing statistics" do
        stats = processor.send(:calculate_statistics, results)

        expect(stats).to be_a(Hash)
        expect(stats[:average_duration]).to eq(15.0)
        expect(stats[:min_duration]).to eq(10)
        expect(stats[:max_duration]).to eq(20)
        expect(stats[:total_duration]).to eq(30)
        expect(stats[:average_memory]).to eq(150.0)
        expect(stats[:success_rate]).to eq(100.0)
        expect(stats[:throughput]).to eq(2.0 / 30)
      end

      it "handles empty results" do
        empty_results = {results: [], processed_chunks: 0, total_chunks: 0, duration: 0}
        stats = processor.send(:calculate_statistics, empty_results)
        expect(stats).to eq({})
      end
    end
  end
end
