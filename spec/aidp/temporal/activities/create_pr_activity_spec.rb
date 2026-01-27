# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Activities::CreatePrActivity do
  let(:activity) { described_class.new }

  describe "#execute" do
    let(:input) do
      {
        project_dir: "/tmp/project",
        issue_number: 123,
        implementation: {summary: "done"},
        iterations: 2
      }
    end

    before do
      allow(activity).to receive(:with_activity_context).and_yield
      allow(activity).to receive(:log_activity)
      allow(activity).to receive(:heartbeat)
    end

    it "rejects non-numeric issue number" do
      result = activity.execute(input.merge(issue_number: "abc"))

      expect(result[:success]).to be false
      expect(result[:error]).to include("Invalid issue number")
    end

    it "returns error when no changes exist" do
      allow(activity).to receive(:has_uncommitted_changes?).and_return(false)
      allow(activity).to receive(:has_unpushed_commits?).and_return(false)

      result = activity.execute(input)

      expect(result[:success]).to be false
      expect(result[:error]).to include("No changes to create PR")
    end

    it "creates PR when changes exist" do
      allow(activity).to receive(:has_uncommitted_changes?).and_return(true)
      allow(activity).to receive(:has_unpushed_commits?).and_return(false)
      allow(activity).to receive(:ensure_branch).and_return("aidp/issue-123")
      allow(activity).to receive(:commit_changes)
      allow(activity).to receive(:push_branch)
      allow(activity).to receive(:create_pull_request).and_return(
        {success: true, pr_url: "https://github.com/org/repo/pull/1", pr_number: 1}
      )

      result = activity.execute(input)

      expect(result[:success]).to be true
      expect(result[:pr_number]).to eq(1)
      expect(activity).to have_received(:commit_changes)
      expect(activity).to have_received(:push_branch)
    end

    it "returns error when PR creation fails" do
      allow(activity).to receive(:has_uncommitted_changes?).and_return(true)
      allow(activity).to receive(:has_unpushed_commits?).and_return(false)
      allow(activity).to receive(:ensure_branch).and_return("aidp/issue-123")
      allow(activity).to receive(:commit_changes)
      allow(activity).to receive(:push_branch)
      allow(activity).to receive(:create_pull_request).and_return(
        {success: false, error: "gh failed"}
      )

      result = activity.execute(input)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("gh failed")
    end
  end

  describe "#ensure_branch" do
    let(:status_ok) { instance_double(Process::Status, success?: true) }
    let(:status_fail) { instance_double(Process::Status, success?: false) }

    it "returns branch when already on branch" do
      allow(Open3).to receive(:capture3)
        .with("git", "branch", "--show-current", chdir: "/test")
        .and_return(["aidp/issue-123\n", "", status_ok])

      result = activity.send(:ensure_branch, "/test", 123)

      expect(result).to eq("aidp/issue-123")
    end

    it "checks out existing branch when not current" do
      allow(Open3).to receive(:capture3).and_return(
        ["main\n", "", status_ok],
        ["", "", status_ok],
        ["", "", status_ok]
      )

      result = activity.send(:ensure_branch, "/test", 456)

      expect(result).to eq("aidp/issue-456")
    end

    it "creates branch when missing" do
      allow(Open3).to receive(:capture3).and_return(
        ["main\n", "", status_ok],
        ["", "", status_fail],
        ["", "", status_ok]
      )

      result = activity.send(:ensure_branch, "/test", 789)

      expect(result).to eq("aidp/issue-789")
    end
  end

  describe "#create_pull_request" do
    it "returns success with PR details" do
      status_ok = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3).and_return(
        ["https://github.com/org/repo/pull/12\n", "", status_ok]
      )

      result = activity.send(
        :create_pull_request,
        project_dir: "/tmp/project",
        branch_name: "aidp/issue-12",
        issue_number: 12,
        implementation: {},
        iterations: 2
      )

      expect(result[:success]).to be true
      expect(result[:pr_number]).to eq(12)
    end

    it "returns error when gh fails" do
      status_fail = instance_double(Process::Status, success?: false)
      allow(Open3).to receive(:capture3).and_return(
        ["", "error", status_fail]
      )

      result = activity.send(
        :create_pull_request,
        project_dir: "/tmp/project",
        branch_name: "aidp/issue-12",
        issue_number: 12,
        implementation: {},
        iterations: 2
      )

      expect(result[:success]).to be false
      expect(result[:error]).to eq("error")
    end
  end

  describe "#build_commit_message" do
    it "builds message with issue number and iterations" do
      result = activity.send(:build_commit_message, 123, 5)

      expect(result).to include("issue #123")
      expect(result).to include("Iterations: 5")
      expect(result).to include("Closes #123")
    end

    it "handles non-integer iterations" do
      result = activity.send(:build_commit_message, 456, "10")

      expect(result).to include("Iterations: 10")
    end
  end

  describe "#build_pr_body" do
    it "builds PR body with issue number" do
      result = activity.send(:build_pr_body, 789, {}, 3)

      expect(result).to include("#789")
      expect(result).to include("3 iterations")
      expect(result).to include("Closes #789")
    end

    it "includes testing checklist" do
      result = activity.send(:build_pr_body, 100, {}, 1)

      expect(result).to include("All tests pass")
      expect(result).to include("Lint checks pass")
    end
  end

  describe "#has_uncommitted_changes?" do
    it "returns true when status output is not empty" do
      allow(Open3).to receive(:capture3)
        .with("git", "status", "--porcelain", chdir: "/test")
        .and_return(["M file.rb\n", "", double(success?: true)])

      result = activity.send(:has_uncommitted_changes?, "/test")

      expect(result).to be true
    end

    it "returns false when status output is empty" do
      allow(Open3).to receive(:capture3)
        .with("git", "status", "--porcelain", chdir: "/test")
        .and_return(["", "", double(success?: true)])

      result = activity.send(:has_uncommitted_changes?, "/test")

      expect(result).to be false
    end

    it "returns false when git command fails" do
      allow(Open3).to receive(:capture3)
        .with("git", "status", "--porcelain", chdir: "/test")
        .and_return(["", "", double(success?: false)])

      result = activity.send(:has_uncommitted_changes?, "/test")

      expect(result).to be false
    end
  end

  describe "#has_unpushed_commits?" do
    it "returns true when count is greater than 0" do
      allow(Open3).to receive(:capture3)
        .with("git", "rev-list", "--count", "@{upstream}..HEAD", chdir: "/test")
        .and_return(["3\n", "", double(success?: true)])

      result = activity.send(:has_unpushed_commits?, "/test")

      expect(result).to be true
    end

    it "returns false when count is 0" do
      allow(Open3).to receive(:capture3)
        .with("git", "rev-list", "--count", "@{upstream}..HEAD", chdir: "/test")
        .and_return(["0\n", "", double(success?: true)])

      result = activity.send(:has_unpushed_commits?, "/test")

      expect(result).to be false
    end

    it "returns false when command raises error" do
      allow(Open3).to receive(:capture3)
        .with("git", "rev-list", "--count", "@{upstream}..HEAD", chdir: "/test")
        .and_raise(StandardError.new("No upstream"))

      result = activity.send(:has_unpushed_commits?, "/test")

      expect(result).to be false
    end
  end
end
