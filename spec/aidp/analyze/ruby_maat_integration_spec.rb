# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/test_prompt"

RSpec.describe Aidp::Analyze::RubyMaatIntegration do
  let(:test_prompt) { TestPrompt.new }
  let(:project_dir) { Dir.mktmpdir }
  let(:integration) { described_class.new(project_dir, prompt: test_prompt) }

  after { FileUtils.rm_rf(project_dir) }

  describe "initialization" do
    it "accepts a prompt parameter for dependency injection" do
      expect(integration.instance_variable_get(:@prompt)).to eq(test_prompt)
    end
  end

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
  end
end
