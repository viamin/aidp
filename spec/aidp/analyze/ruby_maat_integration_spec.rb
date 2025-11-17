# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/test_prompt"

RSpec.describe Aidp::Analyze::RubyMaatIntegration do
  let(:test_prompt) { TestPrompt.new }
  let(:project_dir) { Dir.mktmpdir }
  let(:integration) { described_class.new(project_dir, prompt: test_prompt) }

  after { FileUtils.rm_rf(project_dir) }

  describe "#generate_git_log" do
    it "raises when not a git repository" do
      expect { integration.generate_git_log }.to raise_error(/Not a Git repository/)
    end
  end

  describe "#large_repository?" do
    it "returns false for missing file" do
      path = File.join(project_dir, "git.log")
      expect(integration.send(:large_repository?, path)).to be(false)
    end
  end

  describe "#parse_churn_results" do
    it "returns empty structure when file missing" do
      result = integration.send(:parse_churn_results, File.join(project_dir, "missing.csv"))
      expect(result[:files]).to eq([])
    end
  end

  describe "#should_update_summary_value" do
    it "compares numeric summary keys" do
      expect(integration.send(:should_update_summary_value, "Number of commits", "10", "2")).to be(true)
    end
  end

  describe "chunk creation" do
    it "creates chunk files" do
      log_path = File.join(project_dir, "git.log")
      File.write(log_path, (1..120).map { |i| "line #{i}" }.join("\n"))
      chunks = integration.send(:create_analysis_chunks, log_path)
      expect(chunks).not_to be_empty
    end
  end

  describe "parsers" do
    it "parses coupling results" do
      path = File.join(project_dir, "coupling.csv")
      File.write(path, "file1.rb,file2.rb,5,0.7\n")
      result = integration.send(:parse_coupling_results, path)
      expect(result[:couplings].first[:shared_changes]).to eq(5)
    end

    it "parses authorship results" do
      path = File.join(project_dir, "authorship.csv")
      File.write(path, "file1.rb,alice;bob,10\n")
      result = integration.send(:parse_authorship_results, path)
      expect(result[:files].first[:author_count]).to eq(2)
    end

    it "parses summary results" do
      path = File.join(project_dir, "summary.csv")
      File.write(path, "Number of commits: 42\n")
      result = integration.send(:parse_summary_results, path)
      expect(result[:summary]["Number of commits"]).to eq("42")
    end

    it "parses empty authorship file" do
      path = File.join(project_dir, "authorship_empty.csv")
      File.write(path, "")
      result = integration.send(:parse_authorship_results, path)
      expect(result[:files]).to eq([])
    end

    it "parses summary with multiple lines" do
      path = File.join(project_dir, "multi_summary.csv")
      File.write(path, "Number of commits: 100\nTotal lines added: 5000\n")
      result = integration.send(:parse_summary_results, path)
      expect(result[:summary]["Number of commits"]).to eq("100")
      expect(result[:summary]["Total lines added"]).to eq("5000")
    end
  end

  describe "#git_repository?" do
    it "returns false when no .git directory" do
      expect(integration.send(:git_repository?)).to be(false)
    end

    it "returns true when .git directory exists" do
      FileUtils.mkdir_p(File.join(project_dir, ".git"))
      expect(integration.send(:git_repository?)).to be(true)
    end
  end

  describe "#get_high_priority_files" do
    it "returns files with high churn and single author" do
      results = {
        churn: {files: [{file: "a.rb", changes: 50}, {file: "b.rb", changes: 30}], total_files: 2, total_changes: 80},
        authorship: {files: [{file: "a.rb", authors: ["alice"], author_count: 1, changes: 50}], total_files: 1, files_with_single_author: 1, files_with_multiple_authors: 0}
      }
      high_pri = integration.send(:get_high_priority_files, results)
      expect(high_pri.first[:file]).to eq("a.rb")
      expect(high_pri.first[:authors]).to eq(["alice"])
    end
  end

  describe "#get_medium_priority_files" do
    it "returns files with high churn and multiple authors" do
      results = {
        churn: {files: [{file: "x.rb", changes: 60}, {file: "y.rb", changes: 20}], total_files: 2, total_changes: 80},
        authorship: {files: [{file: "x.rb", authors: ["alice", "bob"], author_count: 2, changes: 60}], total_files: 1, files_with_single_author: 0, files_with_multiple_authors: 1}
      }
      med_pri = integration.send(:get_medium_priority_files, results)
      expect(med_pri.first[:file]).to eq("x.rb")
      expect(med_pri.first[:authors]).to eq(["alice", "bob"])
    end
  end

  describe "#generate_consolidated_report" do
    it "generates markdown report file" do
      results = {
        churn: {files: [{file: "file.rb", changes: 10}], total_files: 1, total_changes: 10},
        coupling: {couplings: [{file1: "a.rb", file2: "b.rb", shared_changes: 3}], total_couplings: 1, average_coupling: 3},
        authorship: {files: [{file: "file.rb", authors: ["alice"], author_count: 1, changes: 10}], total_files: 1, files_with_single_author: 1, files_with_multiple_authors: 0},
        summary: {summary: {}}
      }
      report_path = integration.send(:generate_consolidated_report, results)
      expect(File.exist?(report_path)).to be(true)
      content = File.read(report_path)
      expect(content).to include("Ruby-maat Analysis Report")
      expect(content).to include("Total Files Analyzed")
    end
  end

  describe "#merge_analysis_results" do
    it "merges churn data from chunks" do
      merged = {
        churn: {files: [{file: "a.rb", changes: 5}], total_files: 1, total_changes: 5},
        coupling: {couplings: [], total_couplings: 0},
        authorship: {files: [], total_files: 0, files_with_single_author: 0, files_with_multiple_authors: 0},
        summary: {summary: {}}
      }
      chunk = {
        churn: {files: [{file: "b.rb", changes: 3}], total_files: 1, total_changes: 3},
        coupling: {couplings: [], total_couplings: 0},
        authorship: {files: [], total_files: 0, files_with_single_author: 0, files_with_multiple_authors: 0},
        summary: {summary: {"Number of commits" => "10"}}
      }
      integration.send(:merge_analysis_results, merged, chunk)
      expect(merged[:churn][:total_files]).to eq(2)
      expect(merged[:churn][:total_changes]).to eq(8)
      expect(merged[:summary][:summary]["Number of commits"]).to eq("10")
    end
  end

  describe "#get_high_churn_files" do
    it "filters files above threshold" do
      allow(integration).to receive(:analyze_churn).and_return(
        {files: [{file: "high.rb", changes: 20}, {file: "low.rb", changes: 5}], total_files: 2, total_changes: 25}
      )
      high = integration.get_high_churn_files(10)
      expect(high.length).to eq(1)
      expect(high.first[:file]).to eq("high.rb")
    end
  end

  describe "#get_tightly_coupled_files" do
    it "filters couplings above threshold" do
      allow(integration).to receive(:analyze_coupling).and_return(
        {couplings: [{file1: "a.rb", file2: "b.rb", shared_changes: 10}, {file1: "c.rb", file2: "d.rb", shared_changes: 2}], total_couplings: 2, average_coupling: 6}
      )
      tight = integration.get_tightly_coupled_files(5)
      expect(tight.length).to eq(1)
      expect(tight.first[:shared_changes]).to eq(10)
    end
  end

  describe "#get_knowledge_silos" do
    it "returns files with single author" do
      allow(integration).to receive(:analyze_authorship).and_return(
        {files: [{file: "solo.rb", authors: ["alice"], author_count: 1, changes: 30}, {file: "team.rb", authors: ["alice", "bob"], author_count: 2, changes: 20}], total_files: 2, files_with_single_author: 1, files_with_multiple_authors: 1}
      )
      silos = integration.get_knowledge_silos
      expect(silos.length).to eq(1)
      expect(silos.first[:file]).to eq("solo.rb")
    end
  end
end
