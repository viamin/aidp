# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/watch/runner"

RSpec.describe Aidp::Watch::Runner do
  let(:issues_url) { "https://github.com/owner/repo/issues" }
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:repository_client) do
    instance_double(Aidp::Watch::RepositoryClient,
      full_repo: "owner/repo",
      gh_available?: true)
  end
  let(:state_store) { instance_double(Aidp::Watch::StateStore) }
  let(:plan_processor) { instance_double(Aidp::Watch::PlanProcessor, plan_label: "aidp-plan") }
  let(:build_processor) { instance_double(Aidp::Watch::BuildProcessor, build_label: "aidp-build") }
  let(:auto_processor) { instance_double(Aidp::Watch::AutoProcessor, auto_label: "aidp-auto") }
  let(:auto_pr_processor) { instance_double(Aidp::Watch::AutoPrProcessor, auto_label: "aidp-auto") }
  let(:review_processor) { instance_double(Aidp::Watch::ReviewProcessor, review_label: "aidp-review") }
  let(:ci_fix_processor) { instance_double(Aidp::Watch::CiFixProcessor, ci_fix_label: "aidp-fix-ci") }
  let(:change_request_processor) { instance_double(Aidp::Watch::ChangeRequestProcessor, change_request_label: "aidp-request-changes") }
  let(:state_extractor) { instance_double(Aidp::Watch::GitHubStateExtractor) }
  let(:safety_checker) { instance_double(Aidp::Watch::RepositorySafetyChecker) }

  before do
    allow(Aidp).to receive(:log_info)
    allow(Aidp).to receive(:log_debug)
    allow(Aidp).to receive(:log_warn)
    allow(Aidp).to receive(:log_error)
    allow(Aidp::Watch::RepositoryClient).to receive(:parse_issues_url).and_return(["owner", "repo"])
    # FIXME: Internal class mocking violations - see docs/TESTING_MOCK_VIOLATIONS_REMEDIATION.md "Hard Violations"
    # Watch::Runner#initialize creates dependencies internally without DI support
    # Needs: repository_client, safety_checker, state_store, plan_processor, build_processor as optional params
    # Risk: Medium - Watch mode is complex, needs careful testing
    # Estimated effort: 3-4 hours
    # Additional violations at line: 302
    allow(Aidp::Watch::RepositoryClient).to receive(:new).and_return(repository_client)
    allow(Aidp::Watch::RepositorySafetyChecker).to receive(:new).and_return(safety_checker)
    allow(Aidp::Watch::StateStore).to receive(:new).and_return(state_store)
    allow(Aidp::Watch::PlanProcessor).to receive(:new).and_return(plan_processor)
    allow(Aidp::Watch::BuildProcessor).to receive(:new).and_return(build_processor)
    allow(Aidp::Watch::AutoProcessor).to receive(:new).and_return(auto_processor)
    allow(Aidp::Watch::AutoPrProcessor).to receive(:new).and_return(auto_pr_processor)
    allow(Aidp::Watch::ReviewProcessor).to receive(:new).and_return(review_processor)
    allow(Aidp::Watch::CiFixProcessor).to receive(:new).and_return(ci_fix_processor)
    allow(Aidp::Watch::ChangeRequestProcessor).to receive(:new).and_return(change_request_processor)
    allow(Aidp::Watch::GitHubStateExtractor).to receive(:new).and_return(state_extractor)

    # By default, allow safety checks to pass
    allow(safety_checker).to receive(:validate_watch_mode_safety!)
    allow(safety_checker).to receive(:should_process_issue?).and_return(true)

    # Stub detection comment tracking methods (issue #280)
    allow(state_store).to receive(:detection_comment_posted?).and_return(false)
    allow(state_store).to receive(:record_detection_comment)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:add_labels)
    allow(repository_client).to receive(:remove_labels)
    allow(state_extractor).to receive(:detection_comment_posted?).and_return(true)
    allow(state_extractor).to receive(:in_progress?).and_return(false)
    allow(state_extractor).to receive(:build_completed?).and_return(false)
  end

  describe "#initialize" do
    it "initializes with default interval" do
      runner = described_class.new(issues_url: issues_url, prompt: prompt)
      expect(runner.instance_variable_get(:@interval)).to eq(30)
    end

    it "initializes with custom interval" do
      runner = described_class.new(issues_url: issues_url, interval: 60, prompt: prompt)
      expect(runner.instance_variable_get(:@interval)).to eq(60)
    end

    it "initializes with once mode" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      expect(runner.instance_variable_get(:@once)).to be true
    end

    it "parses issues URL" do
      expect(Aidp::Watch::RepositoryClient).to receive(:parse_issues_url).with(issues_url)
      described_class.new(issues_url: issues_url, prompt: prompt)
    end

    it "creates repository client" do
      expect(Aidp::Watch::RepositoryClient).to receive(:new).with(
        owner: "owner",
        repo: "repo",
        gh_available: nil
      )
      described_class.new(issues_url: issues_url, prompt: prompt)
    end
  end

  describe "#start" do
    it "displays welcome message" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      allow(runner).to receive(:display_message)
      allow(runner).to receive(:process_cycle)

      runner.start

      expect(runner).to have_received(:display_message).with(/Watch mode enabled/, type: :highlight)
    end

    it "runs one cycle in once mode" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      allow(runner).to receive(:display_message)
      allow(runner).to receive(:process_cycle)

      runner.start

      expect(runner).to have_received(:process_cycle).once
    end

    it "handles interrupt signal" do
      runner = described_class.new(issues_url: issues_url, prompt: prompt)
      allow(runner).to receive(:display_message)
      allow(runner).to receive(:process_cycle).and_raise(Interrupt)

      runner.start

      expect(runner).to have_received(:display_message).with(/interrupted/, type: :warning)
    end

    it "logs cycle activity" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      allow(runner).to receive(:display_message)
      allow(runner).to receive(:process_cycle)

      runner.start

      expect(Aidp).to have_received(:log_info).with(
        "watch_runner",
        "watch_mode_started",
        hash_including(repo: "owner/repo", interval: 30, once: true)
      )
      expect(Aidp).to have_received(:log_debug).with(
        "watch_runner",
        "poll_cycle.begin",
        hash_including(repo: "owner/repo", interval: 30)
      )
      expect(Aidp).to have_received(:log_debug).with(
        "watch_runner",
        "poll_cycle.complete",
        hash_including(once: true, next_poll_in: nil)
      )
    end
  end

  describe "#process_cycle" do
    it "processes plan and build triggers" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      allow(runner).to receive(:process_auto_issue_triggers)
      allow(runner).to receive(:process_plan_triggers)
      allow(runner).to receive(:process_auto_pr_triggers)
      allow(runner).to receive(:process_build_triggers)
      allow(runner).to receive(:process_review_triggers)
      allow(runner).to receive(:process_ci_fix_triggers)
      allow(runner).to receive(:process_change_request_triggers)

      runner.send(:process_cycle)

      expect(runner).to have_received(:process_auto_issue_triggers)
      expect(runner).to have_received(:process_plan_triggers)
      expect(runner).to have_received(:process_auto_pr_triggers)
      expect(runner).to have_received(:process_build_triggers)
      expect(runner).to have_received(:process_review_triggers)
      expect(runner).to have_received(:process_ci_fix_triggers)
      expect(runner).to have_received(:process_change_request_triggers)
    end
  end

  describe "#process_auto_issue_triggers" do
    let(:runner) { described_class.new(issues_url: issues_url, once: true, prompt: prompt) }
    let(:issue) { {number: 1, labels: [{"name" => "aidp-auto"}]} }
    let(:detailed_issue) { issue.merge(author: "alice") }

    before do
      allow(repository_client).to receive(:list_issues).and_return([issue])
      allow(repository_client).to receive(:fetch_issue).with(1).and_return(detailed_issue)
      allow(auto_processor).to receive(:process)
    end

    it "processes auto issues when authorized and not in progress" do
      runner.send(:process_auto_issue_triggers)

      expect(auto_processor).to have_received(:process).with(detailed_issue)
    end

    it "skips unauthorized authors" do
      allow(safety_checker).to receive(:should_process_issue?).and_return(false)

      runner.send(:process_auto_issue_triggers)

      expect(auto_processor).not_to have_received(:process)
    end
  end

  describe "#process_auto_pr_triggers" do
    let(:runner) { described_class.new(issues_url: issues_url, once: true, prompt: prompt) }
    let(:pr) { {number: 2, labels: [{"name" => "aidp-auto"}]} }
    let(:detailed_pr) { pr.merge(author: "bob") }

    before do
      allow(repository_client).to receive(:list_pull_requests).and_return([pr])
      allow(repository_client).to receive(:fetch_pull_request).with(2).and_return(detailed_pr)
      allow(auto_pr_processor).to receive(:process)
    end

    it "processes auto PRs when authorized and not in progress" do
      runner.send(:process_auto_pr_triggers)

      expect(auto_pr_processor).to have_received(:process).with(detailed_pr)
    end

    it "skips unauthorized authors" do
      allow(safety_checker).to receive(:should_process_issue?).and_return(false)

      runner.send(:process_auto_pr_triggers)

      expect(auto_pr_processor).not_to have_received(:process)
    end
  end

  describe "#process_plan_triggers" do
    it "fetches and processes plan issues" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {number: 1, labels: [{"name" => "aidp-plan"}]}
      detailed_issue = {number: 1, body: "details", author: "alice"}

      allow(repository_client).to receive(:list_issues).and_return([issue])
      allow(repository_client).to receive(:fetch_issue).with(1).and_return(detailed_issue)
      allow(plan_processor).to receive(:process)

      runner.send(:process_plan_triggers)

      expect(plan_processor).to have_received(:process).with(detailed_issue)
    end

    it "skips issues without plan label" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {number: 1, labels: [{"name" => "bug"}]}

      allow(repository_client).to receive(:list_issues).and_return([issue])
      allow(plan_processor).to receive(:process)

      runner.send(:process_plan_triggers)

      expect(plan_processor).not_to have_received(:process)
    end

    it "skips issues with unauthorized authors" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {number: 1, labels: [{"name" => "aidp-plan"}]}
      detailed_issue = {number: 1, body: "details", author: "untrusted"}

      allow(repository_client).to receive(:list_issues).and_return([issue])
      allow(repository_client).to receive(:fetch_issue).with(1).and_return(detailed_issue)
      allow(safety_checker).to receive(:should_process_issue?).with(detailed_issue, enforce: false).and_return(false)
      allow(plan_processor).to receive(:process)

      runner.send(:process_plan_triggers)

      expect(plan_processor).not_to have_received(:process)
    end

    it "logs plan polling and processing" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {number: 1, labels: [{"name" => "aidp-plan"}]}
      detailed_issue = {number: 1, body: "details", author: "alice"}

      allow(repository_client).to receive(:list_issues).and_return([issue])
      allow(repository_client).to receive(:fetch_issue).with(1).and_return(detailed_issue)
      allow(plan_processor).to receive(:process)

      runner.send(:process_plan_triggers)

      expect(Aidp).to have_received(:log_debug).with("watch_runner", "plan_poll", hash_including(total: 1))
      expect(Aidp).to have_received(:log_debug).with("watch_runner", "plan_process", hash_including(issue: 1))
    end
  end

  describe "#process_build_triggers" do
    it "fetches and processes build issues" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {number: 2, labels: [{"name" => "aidp-build"}]}
      detailed_issue = {number: 2, body: "build details", author: "alice", comments: []}

      allow(repository_client).to receive(:list_issues).and_return([issue])
      allow(repository_client).to receive(:fetch_issue).with(2).and_return(detailed_issue)
      allow(repository_client).to receive(:add_labels).with(2, "aidp-in-progress")
      allow(repository_client).to receive(:remove_labels).with(2, "aidp-in-progress")
      allow(build_processor).to receive(:process)

      runner.send(:process_build_triggers)

      expect(build_processor).to have_received(:process).with(detailed_issue)
    end

    it "skips completed build issues" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {number: 2, labels: [{"name" => "aidp-build"}]}
      # Add completion comment to indicate it's already done
      detailed_issue = {
        number: 2,
        body: "build details",
        author: "alice",
        comments: [
          {"body" => "✅ Implementation complete for #2", "author" => "aidp-bot", "createdAt" => Time.now.utc.iso8601}
        ]
      }

      allow(repository_client).to receive(:list_issues).and_return([issue])
      allow(repository_client).to receive(:fetch_issue).with(2).and_return(detailed_issue)
      allow(build_processor).to receive(:process)
      allow(state_extractor).to receive(:build_completed?).with(detailed_issue).and_return(true)

      runner.send(:process_build_triggers)

      expect(build_processor).not_to have_received(:process)
    end

    it "skips issues with unauthorized authors" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {number: 2, labels: [{"name" => "aidp-build"}]}
      detailed_issue = {number: 2, body: "build details", author: "untrusted", comments: []}

      allow(repository_client).to receive(:list_issues).and_return([issue])
      allow(repository_client).to receive(:fetch_issue).with(2).and_return(detailed_issue)
      allow(repository_client).to receive(:add_labels).with(2, "aidp-in-progress")
      allow(repository_client).to receive(:remove_labels).with(2, "aidp-in-progress")
      allow(safety_checker).to receive(:should_process_issue?).with(detailed_issue, enforce: false).and_return(false)
      allow(build_processor).to receive(:process)

      runner.send(:process_build_triggers)

      expect(build_processor).not_to have_received(:process)
    end

    it "logs build polling and processing" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {number: 2, labels: [{"name" => "aidp-build"}]}
      detailed_issue = {number: 2, body: "build details", author: "alice", comments: []}

      allow(repository_client).to receive(:list_issues).and_return([issue])
      allow(repository_client).to receive(:fetch_issue).with(2).and_return(detailed_issue)
      allow(repository_client).to receive(:add_labels).with(2, "aidp-in-progress")
      allow(repository_client).to receive(:remove_labels).with(2, "aidp-in-progress")
      allow(build_processor).to receive(:process)

      runner.send(:process_build_triggers)

      expect(Aidp).to have_received(:log_debug).with("watch_runner", "build_poll", hash_including(total: 1))
      expect(Aidp).to have_received(:log_debug).with("watch_runner", "build_process", hash_including(issue: 2))
    end

    it "handles list_issues API failures gracefully" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)

      allow(repository_client).to receive(:list_issues).and_raise(RuntimeError.new("GitHub API error"))
      allow(build_processor).to receive(:process)

      # Should not raise, just log error and return
      expect { runner.send(:process_build_triggers) }.not_to raise_error

      expect(Aidp).to have_received(:log_error).with("watch_runner", "build_poll_failed", hash_including(error: "GitHub API error"))
      expect(build_processor).not_to have_received(:process)
    end

    it "handles fetch_issue API failures gracefully" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {number: 2, labels: [{"name" => "aidp-build"}]}

      allow(repository_client).to receive(:list_issues).and_return([issue])
      allow(repository_client).to receive(:fetch_issue).with(2).and_raise(RuntimeError.new("Network timeout"))
      allow(build_processor).to receive(:process)

      # Should not raise, just log error and skip issue
      expect { runner.send(:process_build_triggers) }.not_to raise_error

      expect(Aidp).to have_received(:log_error).with("watch_runner", "fetch_issue_failed", hash_including(issue: 2, error: "Network timeout"))
      expect(build_processor).not_to have_received(:process)
    end
  end

  describe "#issue_has_label?" do
    it "finds label in hash format" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {labels: [{"name" => "aidp-plan"}]}

      result = runner.send(:issue_has_label?, issue, "aidp-plan")

      expect(result).to be true
    end

    it "finds label case-insensitively" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {labels: [{"name" => "AIDP-PLAN"}]}

      result = runner.send(:issue_has_label?, issue, "aidp-plan")

      expect(result).to be true
    end

    it "returns false when label not found" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {labels: [{"name" => "bug"}]}

      result = runner.send(:issue_has_label?, issue, "aidp-plan")

      expect(result).to be false
    end

    it "handles string labels" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {labels: ["aidp-plan"]}

      result = runner.send(:issue_has_label?, issue, "aidp-plan")

      expect(result).to be true
    end
  end

  describe "#process_change_request_triggers" do
    let(:change_request_processor) { instance_double(Aidp::Watch::ChangeRequestProcessor) }

    before do
      allow(Aidp::Watch::ChangeRequestProcessor).to receive(:new).and_return(change_request_processor)
      allow(change_request_processor).to receive(:change_request_label).and_return("aidp-request-changes")
    end

    it "fetches and processes PRs with change request label" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      pr = {number: 123, labels: [{"name" => "aidp-request-changes"}], title: "Fix bug"}
      detailed_pr = {number: 123, title: "Fix bug", author: "alice"}

      allow(repository_client).to receive(:list_pull_requests).and_return([pr])
      allow(repository_client).to receive(:fetch_pull_request).with(123).and_return(detailed_pr)
      allow(change_request_processor).to receive(:process)

      runner.send(:process_change_request_triggers)

      expect(change_request_processor).to have_received(:process).with(detailed_pr)
    end

    it "skips PRs without the label" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      pr = {number: 123, labels: [{"name" => "other-label"}]}

      allow(repository_client).to receive(:list_pull_requests).and_return([pr])
      allow(change_request_processor).to receive(:process)

      runner.send(:process_change_request_triggers)

      expect(change_request_processor).not_to have_received(:process)
    end

    it "skips PRs with unauthorized authors" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      pr = {number: 123, labels: [{"name" => "aidp-request-changes"}]}
      detailed_pr = {number: 123, title: "Fix bug", author: "untrusted"}

      allow(repository_client).to receive(:list_pull_requests).and_return([pr])
      allow(repository_client).to receive(:fetch_pull_request).with(123).and_return(detailed_pr)
      allow(safety_checker).to receive(:should_process_issue?).with(detailed_pr, enforce: false).and_return(false)
      allow(change_request_processor).to receive(:process)

      runner.send(:process_change_request_triggers)

      expect(change_request_processor).not_to have_received(:process)
    end

    it "logs change request polling and processing" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      pr = {number: 123, labels: [{"name" => "aidp-request-changes"}]}
      detailed_pr = {number: 123, title: "Fix bug", author: "alice"}

      allow(repository_client).to receive(:list_pull_requests).and_return([pr])
      allow(repository_client).to receive(:fetch_pull_request).with(123).and_return(detailed_pr)
      allow(change_request_processor).to receive(:process)

      runner.send(:process_change_request_triggers)

      expect(Aidp).to have_received(:log_debug).with("watch_runner", "change_request_poll", hash_including(total: 1))
      expect(Aidp).to have_received(:log_debug).with("watch_runner", "change_request_process", hash_including(pr: 123))
    end

    it "handles UnauthorizedAuthorError gracefully" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      pr = {number: 123, labels: [{"name" => "aidp-request-changes"}]}
      detailed_pr = {number: 123, title: "Fix bug", author: "untrusted"}

      allow(repository_client).to receive(:list_pull_requests).and_return([pr])
      allow(repository_client).to receive(:fetch_pull_request).with(123).and_return(detailed_pr)
      allow(safety_checker).to receive(:should_process_issue?).and_raise(Aidp::Watch::RepositorySafetyChecker::UnauthorizedAuthorError.new("Unauthorized"))
      allow(Aidp).to receive(:log_warn)

      expect {
        runner.send(:process_change_request_triggers)
      }.not_to raise_error

      expect(Aidp).to have_received(:log_warn).with("watch_runner", "unauthorized PR author", hash_including(pr: 123))
    end

    it "processes multiple PRs" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      pr1 = {number: 123, labels: [{"name" => "aidp-request-changes"}]}
      pr2 = {number: 456, labels: [{"name" => "aidp-request-changes"}]}
      detailed_pr1 = {number: 123, title: "Fix bug", author: "alice"}
      detailed_pr2 = {number: 456, title: "Add feature", author: "bob"}

      allow(repository_client).to receive(:list_pull_requests).and_return([pr1, pr2])
      allow(repository_client).to receive(:fetch_pull_request).with(123).and_return(detailed_pr1)
      allow(repository_client).to receive(:fetch_pull_request).with(456).and_return(detailed_pr2)
      allow(change_request_processor).to receive(:process)

      runner.send(:process_change_request_triggers)

      expect(change_request_processor).to have_received(:process).with(detailed_pr1)
      expect(change_request_processor).to have_received(:process).with(detailed_pr2)
    end
  end

  describe "#pr_has_label?" do
    it "finds label in hash format" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      pr = {labels: [{"name" => "aidp-request-changes"}]}

      result = runner.send(:pr_has_label?, pr, "aidp-request-changes")

      expect(result).to be true
    end

    it "finds label case-insensitively" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      pr = {labels: [{"name" => "AIDP-REQUEST-CHANGES"}]}

      result = runner.send(:pr_has_label?, pr, "aidp-request-changes")

      expect(result).to be true
    end

    it "returns false when label not found" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      pr = {labels: [{"name" => "bug"}]}

      result = runner.send(:pr_has_label?, pr, "aidp-request-changes")

      expect(result).to be false
    end

    it "handles string labels" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      pr = {labels: ["aidp-request-changes"]}

      result = runner.send(:pr_has_label?, pr, "aidp-request-changes")

      expect(result).to be true
    end
  end
end
