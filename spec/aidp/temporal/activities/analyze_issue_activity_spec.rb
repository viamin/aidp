# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Activities::AnalyzeIssueActivity do
  let(:activity) { described_class.new }
  let(:project_dir) { Dir.mktmpdir }
  let(:mock_context) { instance_double("Temporalio::Activity::Context", info: mock_info) }
  let(:mock_info) { double("ActivityInfo", task_token: "test_token_123") }

  before do
    allow(Temporalio::Activity).to receive(:context).and_return(mock_context)
    allow(Temporalio::Activity).to receive(:heartbeat)
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#execute" do
    let(:base_input) do
      {project_dir: project_dir, issue_number: 123}
    end

    context "with invalid issue number" do
      it "returns error for non-numeric issue number" do
        result = activity.execute(base_input.merge(issue_number: "abc"))
        expect(result[:success]).to be false
        expect(result[:error]).to include("Invalid issue number")
      end

      it "returns error for issue number with special chars" do
        result = activity.execute(base_input.merge(issue_number: "123; rm -rf"))
        expect(result[:success]).to be false
      end
    end

    context "when fetch fails" do
      before do
        allow(activity).to receive(:fetch_issue).and_return(nil)
      end

      it "returns error result" do
        result = activity.execute(base_input)
        expect(result[:success]).to be false
        expect(result[:error]).to include("Failed to fetch issue")
      end
    end

    context "when fetch succeeds" do
      let(:issue_data) do
        {number: 123, title: "Test Issue", body: "Description", labels: [], comments: []}
      end

      before do
        allow(activity).to receive(:fetch_issue).and_return(issue_data)
      end

      it "returns success result" do
        result = activity.execute(base_input)
        expect(result[:success]).to be true
        expect(result[:issue_number]).to eq(123)
      end
    end
  end

  describe "#identify_affected_areas (private)" do
    it "identifies tests area" do
      issue_data = {title: "Add tests for feature", body: ""}
      result = activity.send(:identify_affected_areas, project_dir, issue_data)
      expect(result).to include("tests")
    end

    it "identifies documentation area" do
      issue_data = {title: "Update README", body: ""}
      result = activity.send(:identify_affected_areas, project_dir, issue_data)
      expect(result).to include("documentation")
    end

    it "identifies api area" do
      issue_data = {title: "", body: "Add new API endpoint"}
      result = activity.send(:identify_affected_areas, project_dir, issue_data)
      expect(result).to include("api")
    end

    it "identifies ui area" do
      issue_data = {title: "Fix UI display issue", body: ""}
      result = activity.send(:identify_affected_areas, project_dir, issue_data)
      expect(result).to include("ui")
    end

    it "identifies database area" do
      issue_data = {title: "", body: "Add database migration"}
      result = activity.send(:identify_affected_areas, project_dir, issue_data)
      expect(result).to include("database")
    end

    it "identifies configuration area" do
      issue_data = {title: "Update config settings", body: ""}
      result = activity.send(:identify_affected_areas, project_dir, issue_data)
      expect(result).to include("configuration")
    end

    it "returns empty for unrelated content" do
      issue_data = {title: "Fix bug", body: "Simple fix"}
      result = activity.send(:identify_affected_areas, project_dir, issue_data)
      expect(result).to eq([])
    end
  end

  describe "#extract_acceptance_criteria (private)" do
    it "extracts criteria from acceptance criteria section" do
      issue_data = {body: "## Acceptance Criteria\n- First criterion\n- Second criterion"}
      result = activity.send(:extract_acceptance_criteria, issue_data)
      expect(result).to include("First criterion")
    end

    it "returns empty when no acceptance criteria section" do
      issue_data = {body: "Just a description"}
      result = activity.send(:extract_acceptance_criteria, issue_data)
      expect(result).to eq([])
    end

    it "handles nil body" do
      issue_data = {body: nil}
      result = activity.send(:extract_acceptance_criteria, issue_data)
      expect(result).to eq([])
    end
  end

  describe "#extract_requirements (private)" do
    it "extracts requirements from body" do
      issue_data = {body: "- Requirement one here\n- Requirement two here", comments: []}
      result = activity.send(:extract_requirements, issue_data)
      expect(result.length).to be >= 1
    end

    it "extracts from comments" do
      issue_data = {body: "", comments: ["- Comment requirement here"]}
      result = activity.send(:extract_requirements, issue_data)
      expect(result.length).to be >= 1
    end

    it "handles nil body and comments" do
      issue_data = {body: nil, comments: nil}
      result = activity.send(:extract_requirements, issue_data)
      expect(result).to eq([])
    end
  end

  describe "#fetch_with_url (private)" do
    it "returns nil for invalid URL format" do
      result = activity.send(:fetch_with_url, "not-a-url")
      expect(result).to be_nil
    end

    it "returns nil for non-github URL" do
      result = activity.send(:fetch_with_url, "https://gitlab.com/owner/repo/issues/1")
      expect(result).to be_nil
    end
  end
end
