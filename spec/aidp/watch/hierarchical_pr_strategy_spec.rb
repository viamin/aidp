# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::HierarchicalPrStrategy do
  let(:repository_client) { instance_double("Aidp::Watch::RepositoryClient") }
  let(:state_store) { instance_double("Aidp::Watch::StateStore") }

  subject(:strategy) do
    described_class.new(
      repository_client: repository_client,
      state_store: state_store
    )
  end

  describe "#parent_issue?" do
    context "when issue has sub-issues" do
      before do
        allow(state_store).to receive(:sub_issues).with(42).and_return([43, 44])
      end

      it "returns true" do
        expect(strategy.parent_issue?(42)).to be true
      end
    end

    context "when issue has no sub-issues" do
      before do
        allow(state_store).to receive(:sub_issues).with(42).and_return([])
      end

      it "returns false" do
        expect(strategy.parent_issue?(42)).to be false
      end
    end
  end

  describe "#sub_issue?" do
    context "when issue has a parent" do
      before do
        allow(state_store).to receive(:parent_issue).with(43).and_return(42)
      end

      it "returns true" do
        expect(strategy.sub_issue?(43)).to be true
      end
    end

    context "when issue has no parent" do
      before do
        allow(state_store).to receive(:parent_issue).with(42).and_return(nil)
      end

      it "returns false" do
        expect(strategy.sub_issue?(42)).to be false
      end
    end
  end

  describe "#branch_name_for" do
    let(:issue) { {number: 42, title: "Add new feature"} }

    context "for a parent issue" do
      before do
        allow(state_store).to receive(:sub_issues).with(42).and_return([43])
        allow(state_store).to receive(:parent_issue).with(42).and_return(nil)
      end

      it "generates parent branch name" do
        expect(strategy.branch_name_for(issue)).to eq("aidp/parent-42-add-new-feature")
      end
    end

    context "for a sub-issue" do
      let(:issue) { {number: 43, title: "Sub task"} }

      before do
        allow(state_store).to receive(:sub_issues).with(43).and_return([])
        allow(state_store).to receive(:parent_issue).with(43).and_return(42)
      end

      it "generates sub-issue branch name" do
        expect(strategy.branch_name_for(issue)).to eq("aidp/sub-42-43-sub-task")
      end
    end

    context "for a regular issue" do
      before do
        allow(state_store).to receive(:sub_issues).with(42).and_return([])
        allow(state_store).to receive(:parent_issue).with(42).and_return(nil)
      end

      it "generates regular branch name" do
        expect(strategy.branch_name_for(issue)).to eq("aidp/issue-42-add-new-feature")
      end
    end
  end

  describe "#pr_options_for_issue" do
    let(:issue) { {number: 42, title: "Feature"} }
    let(:default_base) { "main" }

    context "for a parent issue" do
      before do
        allow(state_store).to receive(:sub_issues).with(42).and_return([43])
        allow(state_store).to receive(:parent_issue).with(42).and_return(nil)
        allow(state_store).to receive(:workstream_for_issue).and_return(nil)
      end

      it "returns draft PR targeting main" do
        options = strategy.pr_options_for_issue(issue, default_base_branch: default_base)
        expect(options[:base_branch]).to eq("main")
        expect(options[:draft]).to be true
        expect(options[:labels]).to include("aidp-parent-pr")
      end
    end

    context "for a sub-issue with existing parent branch" do
      let(:issue) { {number: 43, title: "Sub task"} }

      before do
        allow(state_store).to receive(:sub_issues).with(43).and_return([])
        allow(state_store).to receive(:parent_issue).with(43).and_return(42)
        allow(state_store).to receive(:workstream_for_issue).with(42).and_return({branch: "aidp/parent-42-feature"})
      end

      it "returns PR targeting parent branch" do
        options = strategy.pr_options_for_issue(issue, default_base_branch: default_base)
        expect(options[:base_branch]).to eq("aidp/parent-42-feature")
        expect(options[:draft]).to be false
        expect(options[:labels]).to include("aidp-sub-pr")
      end
    end

    context "for a regular issue" do
      before do
        allow(state_store).to receive(:sub_issues).with(42).and_return([])
        allow(state_store).to receive(:parent_issue).with(42).and_return(nil)
      end

      it "returns default options" do
        options = strategy.pr_options_for_issue(issue, default_base_branch: default_base)
        expect(options[:base_branch]).to eq("main")
        expect(options[:draft]).to be true
        expect(options[:labels]).to be_empty
      end
    end
  end

  describe "#pr_description_for" do
    let(:issue) { {number: 42, title: "Feature", url: "https://github.com/test/repo/issues/42"} }
    let(:plan_summary) { "Implement the feature" }

    context "for a parent issue" do
      before do
        allow(state_store).to receive(:sub_issues).with(42).and_return([43, 44])
        allow(state_store).to receive(:parent_issue).with(42).and_return(nil)
        allow(state_store).to receive(:workstream_for_issue).and_return(nil)
      end

      it "includes parent PR context" do
        description = strategy.pr_description_for(issue, plan_summary: plan_summary)
        expect(description).to include("Implements #42")
        expect(description).to include("Sub-Issues")
        expect(description).to include("requires human review")
      end
    end

    context "for a sub-issue" do
      let(:issue) { {number: 43, title: "Sub task"} }

      before do
        allow(state_store).to receive(:sub_issues).with(43).and_return([])
        allow(state_store).to receive(:parent_issue).with(43).and_return(42)
        allow(state_store).to receive(:workstream_for_issue).with(42).and_return({pr_url: "https://github.com/test/repo/pull/100"})
      end

      it "includes sub-issue context" do
        description = strategy.pr_description_for(issue, plan_summary: plan_summary)
        expect(description).to include("Fixes #43")
        expect(description).to include("Parent Issue")
        expect(description).to include("auto-merged")
      end
    end
  end
end
