# frozen_string_literal: true

require "spec_helper"
require "aidp/code_maat_integration"

RSpec.describe Aidp::CodeMaatIntegration do
  let(:project_dir) { Dir.mktmpdir("aidp_test") }
  let(:integration) { described_class.new(project_dir) }

  before do
    # Create a mock Git repository structure
    File.write(File.join(project_dir, "test1.rb"), 'puts "test1"')
    File.write(File.join(project_dir, "test2.rb"), 'puts "test2"')
    FileUtils.mkdir_p(File.join(project_dir, "lib"))
    File.write(File.join(project_dir, "lib", "helper.rb"), "module Helper; end")
  end

  after do
    FileUtils.remove_entry(project_dir)
  end

  describe "#initialize" do
    it "initializes with project directory" do
      expect(integration).to be_a(described_class)
      expect(integration.instance_variable_get(:@project_dir)).to eq(project_dir)
    end

    it "sets up Docker configuration" do
      expect(integration.instance_variable_get(:@docker_image)).to eq("adamtornhill/code-maat")
      expect(integration.instance_variable_get(:@docker_tag)).to eq("latest")
    end
  end

  describe "#run_code_maat" do
    it "returns mock analysis results" do
      result = integration.run_code_maat("churn", "git_log.txt")

      expect(result).to be_a(Hash)
      expect(result[:analysis_type]).to eq("churn")
      expect(result[:input_file]).to eq("git_log.txt")
      expect(result[:status]).to eq("completed")
      expect(result[:data]).to be_an(Array)
      expect(result[:statistics]).to be_a(Hash)
    end

    it "handles different analysis types" do
      %w[churn coupling authors summary].each do |analysis_type|
        result = integration.run_code_maat(analysis_type, "git_log.txt")

        expect(result[:analysis_type]).to eq(analysis_type)
        expect(result[:status]).to eq("completed")
        expect(result[:data]).to be_an(Array)
      end
    end

    it "includes mock data for churn analysis" do
      result = integration.run_code_maat("churn", "git_log.txt")

      expect(result[:data]).not_to be_empty
      result[:data].each do |entry|
        expect(entry).to have_key(:entity)
        expect(entry).to have_key(:nrev)
        expect(entry).to have_key(:nloc)
        expect(entry).to have_key(:churn)
      end
    end

    it "includes mock data for coupling analysis" do
      result = integration.run_code_maat("coupling", "git_log.txt")

      expect(result[:data]).not_to be_empty
      result[:data].each do |entry|
        expect(entry).to have_key(:entity)
        expect(entry).to have_key(:coupled)
        expect(entry).to have_key(:degree)
        expect(entry).to have_key(:average_revs)
      end
    end

    it "includes mock data for authors analysis" do
      result = integration.run_code_maat("authors", "git_log.txt")

      expect(result[:data]).not_to be_empty
      result[:data].each do |entry|
        expect(entry).to have_key(:entity)
        expect(entry).to have_key(:nrev)
        expect(entry).to have_key(:author)
        expect(entry).to have_key(:ownership)
      end
    end

    it "includes mock data for summary analysis" do
      result = integration.run_code_maat("summary", "git_log.txt")

      expect(result[:data]).not_to be_empty
      result[:data].each do |entry|
        expect(entry).to have_key(:entity)
        expect(entry).to have_key(:nrev)
        expect(entry).to have_key(:nloc)
        expect(entry).to have_key(:avg)
      end
    end
  end

  describe "#generate_git_log" do
    it "generates mock Git log data" do
      result = integration.generate_git_log

      expect(result).to be_a(Hash)
      expect(result[:status]).to eq("completed")
      expect(result[:output_file]).to be_a(String)
      expect(result[:commit_count]).to be >= 0
      expect(result[:time_range]).to be_a(Hash)
    end

    it "includes time range information" do
      result = integration.generate_git_log

      expect(result[:time_range]).to have_key(:start_date)
      expect(result[:time_range]).to have_key(:end_date)
      expect(result[:time_range]).to have_key(:duration_days)
    end
  end

  describe "#run_churn_analysis" do
    it "runs churn analysis with Git log" do
      result = integration.run_churn_analysis("git_log.txt")

      expect(result).to be_a(Hash)
      expect(result[:analysis_type]).to eq("churn")
      expect(result[:status]).to eq("completed")
      expect(result[:data]).to be_an(Array)
    end

    it "includes churn statistics" do
      result = integration.run_churn_analysis("git_log.txt")

      expect(result[:statistics]).to have_key(:total_files)
      expect(result[:statistics]).to have_key(:total_commits)
      expect(result[:statistics]).to have_key(:total_lines)
      expect(result[:statistics]).to have_key(:average_churn)
    end
  end

  describe "#run_coupling_analysis" do
    it "runs coupling analysis with Git log" do
      result = integration.run_coupling_analysis("git_log.txt")

      expect(result).to be_a(Hash)
      expect(result[:analysis_type]).to eq("coupling")
      expect(result[:status]).to eq("completed")
      expect(result[:data]).to be_an(Array)
    end

    it "includes coupling statistics" do
      result = integration.run_coupling_analysis("git_log.txt")

      expect(result[:statistics]).to have_key(:total_files)
      expect(result[:statistics]).to have_key(:coupled_files)
      expect(result[:statistics]).to have_key(:average_coupling)
      expect(result[:statistics]).to have_key(:max_coupling)
    end
  end

  describe "#run_authors_analysis" do
    it "runs authors analysis with Git log" do
      result = integration.run_authors_analysis("git_log.txt")

      expect(result).to be_a(Hash)
      expect(result[:analysis_type]).to eq("authors")
      expect(result[:status]).to eq("completed")
      expect(result[:data]).to be_an(Array)
    end

    it "includes authors statistics" do
      result = integration.run_authors_analysis("git_log.txt")

      expect(result[:statistics]).to have_key(:total_files)
      expect(result[:statistics]).to have_key(:total_authors)
      expect(result[:statistics]).to have_key(:average_ownership)
      expect(result[:statistics]).to have_key(:ownership_distribution)
    end
  end

  describe "#run_summary_analysis" do
    it "runs summary analysis with Git log" do
      result = integration.run_summary_analysis("git_log.txt")

      expect(result).to be_a(Hash)
      expect(result[:analysis_type]).to eq("summary")
      expect(result[:status]).to eq("completed")
      expect(result[:data]).to be_an(Array)
    end

    it "includes summary statistics" do
      result = integration.run_summary_analysis("git_log.txt")

      expect(result[:statistics]).to have_key(:total_files)
      expect(result[:statistics]).to have_key(:total_commits)
      expect(result[:statistics]).to have_key(:total_lines)
      expect(result[:statistics]).to have_key(:average_commits_per_file)
    end
  end

  describe "#chunk_large_repository" do
    it "chunks large repository for analysis" do
      result = integration.chunk_large_repository("time_based", "git_log.txt")

      expect(result).to be_a(Hash)
      expect(result[:strategy]).to eq("time_based")
      expect(result[:total_chunks]).to be >= 0
      expect(result[:chunks]).to be_an(Array)
      expect(result[:config]).to be_a(Hash)
    end

    it "includes chunk information" do
      result = integration.chunk_large_repository("time_based", "git_log.txt")

      if result[:chunks].any?
        chunk = result[:chunks].first
        expect(chunk).to have_key(:id)
        expect(chunk).to have_key(:strategy)
        expect(chunk).to have_key(:time_range)
        expect(chunk).to have_key(:commits)
        expect(chunk).to have_key(:files)
      end
    end

    it "handles different chunking strategies" do
      %w[time_based commit_count size_based feature_based].each do |strategy|
        result = integration.chunk_large_repository(strategy, "git_log.txt")

        expect(result[:strategy]).to eq(strategy)
        expect(result[:chunks]).to be_an(Array)
      end
    end
  end

  describe "#analyze_chunk" do
    let(:chunk) do
      {
        id: "chunk1",
        strategy: "time_based",
        time_range: {start: "2023-01-01", end: "2023-01-31"},
        commits: %w[commit1 commit2],
        files: ["file1.rb", "file2.rb"]
      }
    end

    it "analyzes a single chunk" do
      result = integration.analyze_chunk(chunk, "churn")

      expect(result).to be_a(Hash)
      expect(result[:chunk_id]).to eq("chunk1")
      expect(result[:analysis_type]).to eq("churn")
      expect(result[:status]).to eq("completed")
      expect(result[:data]).to be_an(Array)
    end

    it "includes chunk-specific data" do
      result = integration.analyze_chunk(chunk, "churn")

      expect(result[:chunk_info]).to eq(chunk)
      expect(result[:statistics]).to be_a(Hash)
      expect(result[:start_time]).to be_a(Time)
      expect(result[:end_time]).to be_a(Time)
      expect(result[:duration]).to be >= 0
    end
  end

  describe "#merge_chunk_analyses" do
    let(:chunk_results) do
      [
        {
          chunk_id: "chunk1",
          analysis_type: "churn",
          status: "completed",
          data: [{entity: "file1.rb", nrev: 5, nloc: 100, churn: 20}],
          statistics: {total_files: 1, total_commits: 5}
        },
        {
          chunk_id: "chunk2",
          analysis_type: "churn",
          status: "completed",
          data: [{entity: "file2.rb", nrev: 3, nloc: 50, churn: 15}],
          statistics: {total_files: 1, total_commits: 3}
        }
      ]
    end

    it "merges chunk analysis results" do
      merged = integration.merge_chunk_analyses(chunk_results, "churn")

      expect(merged).to be_a(Hash)
      expect(merged[:analysis_type]).to eq("churn")
      expect(merged[:total_chunks]).to eq(2)
      expect(merged[:successful_chunks]).to eq(2)
      expect(merged[:failed_chunks]).to eq(0)
      expect(merged[:merged_data]).to be_an(Array)
      expect(merged[:merged_statistics]).to be_a(Hash)
    end

    it "combines data from all chunks" do
      merged = integration.merge_chunk_analyses(chunk_results, "churn")

      expect(merged[:merged_data]).to have(2).items
      entities = merged[:merged_data].map { |entry| entry[:entity] }
      expect(entities).to include("file1.rb", "file2.rb")
    end

    it "aggregates statistics" do
      merged = integration.merge_chunk_analyses(chunk_results, "churn")

      expect(merged[:merged_statistics][:total_files]).to eq(2)
      expect(merged[:merged_statistics][:total_commits]).to eq(8)
    end
  end

  describe "#get_analysis_statistics" do
    let(:analysis_results) do
      [
        {
          analysis_type: "churn",
          status: "completed",
          data: [{entity: "file1.rb", nrev: 5, nloc: 100, churn: 20}],
          statistics: {total_files: 1, total_commits: 5}
        },
        {
          analysis_type: "coupling",
          status: "completed",
          data: [{entity: "file1.rb", coupled: "file2.rb", degree: 3}],
          statistics: {total_files: 1, coupled_files: 1}
        }
      ]
    end

    it "generates overall analysis statistics" do
      stats = integration.get_analysis_statistics(analysis_results)

      expect(stats).to be_a(Hash)
      expect(stats[:total_analyses]).to eq(2)
      expect(stats[:successful_analyses]).to eq(2)
      expect(stats[:failed_analyses]).to eq(0)
      expect(stats[:analysis_types]).to be_an(Array)
      expect(stats[:total_duration]).to be >= 0
    end

    it "includes analysis type breakdown" do
      stats = integration.get_analysis_statistics(analysis_results)

      expect(stats[:analysis_types]).to include("churn", "coupling")
      expect(stats[:type_breakdown]).to be_a(Hash)
      expect(stats[:type_breakdown]["churn"]).to eq(1)
      expect(stats[:type_breakdown]["coupling"]).to eq(1)
    end
  end

  describe "private methods" do
    describe "#check_docker_availability" do
      it "checks if Docker is available" do
        available = integration.send(:check_docker_availability)
        expect(available).to be_in([true, false])
      end
    end

    describe "#build_docker_command" do
      it "builds Docker command for analysis" do
        command = integration.send(:build_docker_command, "churn", "git_log.txt")

        expect(command).to be_a(String)
        expect(command).to include("docker")
        expect(command).to include("run")
        expect(command).to include("adamtornhill/code-maat")
        expect(command).to include("churn")
        expect(command).to include("git_log.txt")
      end
    end

    describe "#parse_code_maat_output" do
      let(:mock_output) do
        "entity,nrev,nloc,churn\nfile1.rb,5,100,20\nfile2.rb,3,50,15"
      end

      it "parses Code Maat CSV output" do
        parsed = integration.send(:parse_code_maat_output, mock_output, "churn")

        expect(parsed).to be_an(Array)
        expect(parsed).to have(2).items

        first_entry = parsed.first
        expect(first_entry).to have_key(:entity)
        expect(first_entry).to have_key(:nrev)
        expect(first_entry).to have_key(:nloc)
        expect(first_entry).to have_key(:churn)
      end
    end

    describe "#calculate_analysis_statistics" do
      let(:mock_data) do
        [
          {entity: "file1.rb", nrev: 5, nloc: 100, churn: 20},
          {entity: "file2.rb", nrev: 3, nloc: 50, churn: 15}
        ]
      end

      it "calculates statistics for churn analysis" do
        stats = integration.send(:calculate_analysis_statistics, mock_data, "churn")

        expect(stats).to be_a(Hash)
        expect(stats[:total_files]).to eq(2)
        expect(stats[:total_commits]).to eq(8)
        expect(stats[:total_lines]).to eq(150)
        expect(stats[:average_churn]).to eq(17.5)
      end
    end
  end
end
