# frozen_string_literal: true

require "spec_helper"
require "aidp/repository_chunker"

RSpec.describe Aidp::RepositoryChunker do
  let(:project_dir) { Dir.mktmpdir("aidp_test") }
  let(:chunker) { described_class.new(project_dir) }

  before do
    # Create some test files
    File.write(File.join(project_dir, "test1.rb"), 'puts "test1"')
    File.write(File.join(project_dir, "test2.rb"), 'puts "test2"')
    FileUtils.mkdir_p(File.join(project_dir, "lib"))
    File.write(File.join(project_dir, "lib", "helper.rb"), "module Helper; end")
  end

  after do
    FileUtils.remove_entry(project_dir)
  end

  describe "#initialize" do
    it "initializes with default configuration" do
      expect(chunker).to be_a(described_class)
    end

    it "loads custom configuration from file" do
      config_file = File.join(project_dir, ".aidp-chunk-config.yml")
      custom_config = {
        "time_based" => {"chunk_size" => "60d", "overlap" => "14d"},
        "commit_count" => {"chunk_size" => 500, "overlap" => 50}
      }
      File.write(config_file, custom_config.to_yaml)

      chunker_with_config = described_class.new(project_dir)
      expect(chunker_with_config).to be_a(described_class)
    end
  end

  describe "#chunk_repository" do
    context "with invalid strategy" do
      it "raises an error for unknown strategy" do
        expect do
          chunker.chunk_repository("invalid_strategy")
        end.to raise_error(RuntimeError, /Unknown chunking strategy/)
      end
    end
  end

  describe "#get_chunk_analysis_plan" do
    let(:chunks) do
      [
        {id: "chunk1", strategy: "time_based", files: ["file1.rb"], commits: []},
        {id: "chunk2", strategy: "time_based", files: ["file2.rb"], commits: []}
      ]
    end

    it "creates analysis plan for chunks" do
      plan = chunker.get_chunk_analysis_plan(chunks, "static_analysis")

      expect(plan).to be_a(Hash)
      expect(plan[:analysis_type]).to eq("static_analysis")
      expect(plan[:total_chunks]).to eq(2)
      expect(plan[:chunks]).to be_an(Array)
      expect(plan[:estimated_duration]).to be >= 0
      expect(plan[:dependencies]).to be_an(Array)
    end

    it "includes chunk-specific information in plan" do
      plan = chunker.get_chunk_analysis_plan(chunks, "static_analysis")

      plan[:chunks].each do |chunk_plan|
        expect(chunk_plan).to have_key(:chunk_id)
        expect(chunk_plan).to have_key(:chunk_index)
        expect(chunk_plan).to have_key(:strategy)
        expect(chunk_plan).to have_key(:estimated_duration)
        expect(chunk_plan).to have_key(:dependencies)
        expect(chunk_plan).to have_key(:priority)
        expect(chunk_plan).to have_key(:resources)
      end
    end
  end

  describe "#execute_chunk_analysis" do
    let(:chunk) do
      {id: "test_chunk", strategy: "time_based", files: ["test.rb"], commits: []}
    end

    it "executes analysis for a chunk" do
      result = chunker.execute_chunk_analysis(chunk, "static_analysis")

      expect(result).to be_a(Hash)
      expect(result[:chunk_id]).to eq("test_chunk")
      expect(result[:analysis_type]).to eq("static_analysis")
      expect(result[:start_time]).to be_a(Time)
      expect(result[:status]).to be_in(%w[completed failed])
    end
  end

  describe "#merge_chunk_results" do
    let(:chunk_results) do
      [
        {
          chunk_id: "chunk1",
          status: "completed",
          duration: 10,
          data: {files: ["file1.rb"]}
        },
        {
          chunk_id: "chunk2",
          status: "failed",
          duration: 5,
          error: "Analysis failed"
        }
      ]
    end

    it "merges chunk analysis results" do
      merged = chunker.merge_chunk_results(chunk_results)

      expect(merged).to be_a(Hash)
      expect(merged[:total_chunks]).to eq(2)
      expect(merged[:successful_chunks]).to eq(1)
      expect(merged[:failed_chunks]).to eq(1)
      expect(merged[:total_duration]).to eq(15)
      expect(merged[:merged_data]).to be_a(Hash)
      expect(merged[:errors]).to be_an(Array)
    end

    it "collects errors from failed chunks" do
      merged = chunker.merge_chunk_results(chunk_results)

      expect(merged[:errors].length).to eq(1)
      error = merged[:errors].first
      expect(error[:chunk_id]).to eq("chunk2")
      expect(error[:error]).to eq("Analysis failed")
    end

    it "merges data from successful chunks" do
      merged = chunker.merge_chunk_results(chunk_results)

      expect(merged[:merged_data]).to have_key(:files)
      expect(merged[:merged_data][:files]).to include("file1.rb")
    end
  end

  describe "#get_chunk_statistics" do
    let(:chunks) do
      [
        {id: "chunk1", strategy: "time_based", files: ["file1.rb"], commits: []},
        {id: "chunk2", strategy: "size_based", files: ["file2.rb", "file3.rb"], commits: []}
      ]
    end

    it "returns statistics for chunks" do
      stats = chunker.get_chunk_statistics(chunks)

      expect(stats).to be_a(Hash)
      expect(stats[:total_chunks]).to eq(2)
      expect(stats[:strategies]).to be_a(Hash)
      expect(stats[:total_files]).to eq(3)
      expect(stats[:total_commits]).to eq(0)
      expect(stats[:average_chunk_size]).to be >= 0
      expect(stats[:chunk_distribution]).to be_a(Hash)
    end

    it "handles empty chunks array" do
      stats = chunker.get_chunk_statistics([])
      expect(stats).to eq({})
    end
  end

  describe "private methods" do
    describe "#parse_time_duration" do
      it "parses day durations" do
        expect(chunker.send(:parse_time_duration, "30d")).to eq(30 * 24 * 60 * 60)
        expect(chunker.send(:parse_time_duration, "7d")).to eq(7 * 24 * 60 * 60)
      end

      it "parses week durations" do
        expect(chunker.send(:parse_time_duration, "2w")).to eq(2 * 7 * 24 * 60 * 60)
      end

      it "parses month durations" do
        expect(chunker.send(:parse_time_duration, "1m")).to eq(30 * 24 * 60 * 60)
      end

      it "parses year durations" do
        expect(chunker.send(:parse_time_duration, "1y")).to eq(365 * 24 * 60 * 60)
      end

      it "returns default for invalid format" do
        expect(chunker.send(:parse_time_duration, "invalid")).to eq(30 * 24 * 60 * 60)
      end
    end

    describe "#parse_size" do
      it "parses KB sizes" do
        expect(chunker.send(:parse_size, "100KB")).to eq(100 * 1024)
        expect(chunker.send(:parse_size, "100kb")).to eq(100 * 1024)
      end

      it "parses MB sizes" do
        expect(chunker.send(:parse_size, "100MB")).to eq(100 * 1024 * 1024)
        expect(chunker.send(:parse_size, "100mb")).to eq(100 * 1024 * 1024)
      end

      it "parses GB sizes" do
        expect(chunker.send(:parse_size, "1GB")).to eq(1024 * 1024 * 1024)
        expect(chunker.send(:parse_size, "1gb")).to eq(1024 * 1024 * 1024)
      end

      it "returns default for invalid format" do
        expect(chunker.send(:parse_size, "invalid")).to eq(100 * 1024 * 1024)
      end
    end

    describe "#analyze_repository_structure" do
      it "analyzes repository structure" do
        structure = chunker.send(:analyze_repository_structure)

        expect(structure).to be_an(Array)
        structure.each do |item|
          expect(item).to have_key(:path)
          expect(item).to have_key(:size)
          expect(item).to have_key(:type)
        end
      end

      it "includes test files in structure" do
        structure = chunker.send(:analyze_repository_structure)
        paths = structure.map { |item| item[:path] }

        expect(paths).to include("test1.rb")
        expect(paths).to include("test2.rb")
        expect(paths).to include("lib/helper.rb")
      end
    end

    describe "#identify_features" do
      it "identifies features in repository" do
        features = chunker.send(:identify_features)

        expect(features).to be_an(Array)
        features.each do |feature|
          expect(feature).to have_key(:name)
          expect(feature).to have_key(:path)
          expect(feature).to have_key(:type)
        end
      end
    end

    describe "#generate_chunk_id" do
      it "generates unique chunk IDs" do
        id1 = chunker.send(:generate_chunk_id, "time", "start")
        id2 = chunker.send(:generate_chunk_id, "time", "start")

        expect(id1).to be_a(String)
        expect(id2).to be_a(String)
        expect(id1).to include("time_start")
        expect(id2).to include("time_start")
      end
    end

    describe "#estimate_chunk_analysis_duration" do
      let(:chunk) { {files: ["file1.rb", "file2.rb"], commits: %w[commit1 commit2]} }

      it "estimates duration for different analysis types" do
        %w[static_analysis security_analysis performance_analysis].each do |analysis_type|
          duration = chunker.send(:estimate_chunk_analysis_duration, chunk, analysis_type)
          expect(duration).to be >= 0
        end
      end
    end

    describe "#calculate_chunk_priority" do
      let(:chunk) { {files: ["file1.rb"], commits: ["commit1"]} }

      it "calculates priority for different analysis types" do
        static_priority = chunker.send(:calculate_chunk_priority, chunk, "static_analysis")
        security_priority = chunker.send(:calculate_chunk_priority, chunk, "security_analysis")
        performance_priority = chunker.send(:calculate_chunk_priority, chunk, "performance_analysis")

        expect(static_priority).to be >= 0
        expect(security_priority).to be >= static_priority
        expect(performance_priority).to be >= static_priority
      end
    end
  end
end
