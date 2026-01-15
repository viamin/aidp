# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::Runner do
  let(:repo_client) { instance_double("RepositoryClient", full_repo: "o/r") }
  let(:safety_checker) { instance_double("RepositorySafetyChecker", validate_watch_mode_safety!: true) }
  let(:state_store) { instance_double("StateStore", state: {}, round_robin_last_key: nil, record_round_robin_position: nil) }
  let(:state_extractor) { instance_double("GitHubStateExtractor") }
  let(:plan_processor) { instance_double("PlanProcessor", plan_label: "plan", process: nil) }
  let(:build_processor) { instance_double("BuildProcessor", build_label: "build", process: nil) }
  let(:auto_processor) { instance_double("AutoProcessor", process: nil) }
  let(:review_processor) { instance_double("ReviewProcessor", process: nil) }
  let(:ci_fix_processor) { instance_double("CiFixProcessor", process: nil) }
  let(:auto_pr_processor) { instance_double("AutoPrProcessor", process: nil) }
  let(:change_request_processor) { instance_double("ChangeRequestProcessor", process: nil) }
  let(:feedback_collector) { instance_double("FeedbackCollector", collect_feedback: []) }
  let(:auto_update_policy) { instance_double("AutoUpdatePolicy", enabled: true, check_interval_seconds: 1) }
  let(:auto_update_check) { instance_double("UpdateCheck", should_update?: true, current_version: "1", available_version: "2") }
  let(:auto_update) { instance_double("AutoUpdateCoordinator", check_for_updates: nil, check_for_update: auto_update_check, policy: auto_update_policy, restore_from_checkpoint: nil, hot_reload_available?: false, initiate_update: nil) }
  let(:worktree_cleanup_job) { instance_double("WorktreeCleanupJob", enabled?: true, cleanup_due?: false, cleanup_interval_seconds: 604_800, execute: {cleaned: 0, skipped: 0, errors: []}) }
  let(:issue_detail) { {number: 1, labels: ["plan"], comments: [], author: "alice"} }

  # Silent test prompt that doesn't output
  let(:test_prompt) { instance_double(TTY::Prompt, say: nil) }

  before do
    stub_const("Aidp::Watch::GitHubStateExtractor", Class.new)
    allow(Aidp::Watch::RepositoryClient).to receive(:parse_issues_url).and_return(["o", "r"])
    allow(Aidp::Watch::RepositoryClient).to receive(:new).and_return(repo_client)
    allow(Aidp::Watch::RepositorySafetyChecker).to receive(:new).and_return(safety_checker)
    allow(Aidp::Watch::StateStore).to receive(:new).and_return(state_store)
    allow(Aidp::Watch::GitHubStateExtractor).to receive(:new).and_return(state_extractor)
    allow(Aidp::Watch::PlanProcessor).to receive(:new).and_return(plan_processor)
    allow(Aidp::Watch::BuildProcessor).to receive(:new).and_return(build_processor)
    allow(Aidp::Watch::AutoProcessor).to receive(:new).and_return(auto_processor)
    allow(Aidp::Watch::ReviewProcessor).to receive(:new).and_return(review_processor)
    allow(Aidp::Watch::CiFixProcessor).to receive(:new).and_return(ci_fix_processor)
    allow(Aidp::Watch::AutoPrProcessor).to receive(:new).and_return(auto_pr_processor)
    allow(Aidp::Watch::ChangeRequestProcessor).to receive(:new).and_return(change_request_processor)
    allow(Aidp::Watch::FeedbackCollector).to receive(:new).and_return(feedback_collector)
    allow(Aidp::Watch::WorktreeCleanupJob).to receive(:new).and_return(worktree_cleanup_job)
    allow(Aidp::Config).to receive(:worktree_cleanup_config).and_return({enabled: true, frequency: "weekly"})
    allow(Aidp::AutoUpdate).to receive(:coordinator).and_return(auto_update)
    allow(Aidp).to receive(:log_info)
    allow(Aidp).to receive(:log_debug)
    allow(Aidp).to receive(:log_error)
    allow(Aidp).to receive(:log_warn)

    allow(state_extractor).to receive_messages(
      detection_comment_posted?: false,
      build_completed?: false
    )
    allow(safety_checker).to receive(:should_process_issue?).and_return(true)
  end

  describe "#start" do
    it "runs a single cycle when once is true" do
      runner = described_class.new(issues_url: "o/r", once: true, interval: 0.01, prompt: test_prompt)
      allow(runner).to receive(:display_message)
      expect(safety_checker).to receive(:validate_watch_mode_safety!)
      expect(runner).to receive(:process_cycle).and_return(nil)

      runner.start
    end
  end

  describe "#process_cycle" do
    it "collects work items and processes via round-robin" do
      runner = described_class.new(issues_url: "o/r", once: true, prompt: test_prompt)
      allow(runner).to receive(:display_message)

      # Allow round-robin scheduler methods
      allow(runner).to receive(:collect_all_work_items).and_return([])
      allow(runner).to receive(:fetch_paused_item_numbers).and_return([])

      # Maintenance tasks should still be called
      %i[
        check_for_updates_if_due
        collect_feedback
        process_worktree_cleanup
        process_worktree_reconciliation
      ].each do |method|
        allow(runner).to receive(method).and_return(nil)
        expect(runner).to receive(method).once
      end

      runner.send(:process_cycle)
    end
  end

  describe "#check_for_updates_if_due" do
    it "invokes coordinator when interval has passed" do
      runner = described_class.new(issues_url: "o/r", once: true, interval: 0.01, prompt: test_prompt)
      allow(runner).to receive(:display_message)
      runner.last_update_check = Time.now - 100
      expect(auto_update).to receive(:check_for_update).and_return(auto_update_check)
      expect(auto_update).to receive(:initiate_update)

      runner.send(:check_for_updates_if_due)
    end
  end

  describe "post detection comments" do
    it "enables post_detection_comments by default" do
      runner = described_class.new(issues_url: "o/r", once: true, prompt: test_prompt)
      allow(runner).to receive(:display_message)
      expect(runner.post_detection_comments).to be true
    end
  end

  describe "work item collection (round-robin)" do
    let(:runner) do
      r = described_class.new(issues_url: "o/r", once: true, prompt: test_prompt)
      allow(r).to receive(:display_message)
      r
    end

    before do
      allow(runner).to receive(:post_detection_comment)
    end

    it "collects plan work items" do
      allow(repo_client).to receive(:list_issues).and_return([{number: 1, labels: ["plan"]}])

      items = runner.send(:collect_plan_work_items)

      expect(items.size).to eq(1)
      expect(items.first.processor_type).to eq(:plan)
      expect(items.first.number).to eq(1)
    end

    it "returns empty array when plan poll fails" do
      allow(repo_client).to receive(:list_issues).and_raise(StandardError.new("boom"))

      items = runner.send(:collect_plan_work_items)

      expect(items).to eq([])
    end

    it "collects build work items" do
      allow(repo_client).to receive(:list_issues).and_return([{number: 2, labels: ["build"]}])
      allow(repo_client).to receive(:fetch_issue).and_return(issue_detail.merge(number: 2, labels: ["build"]))

      items = runner.send(:collect_build_work_items)

      expect(items.size).to eq(1)
      expect(items.first.processor_type).to eq(:build)
    end

    it "collects auto issue work items" do
      allow(auto_processor).to receive(:auto_label).and_return("auto")
      allow(repo_client).to receive(:list_issues).and_return([{number: 3, labels: ["auto"]}])

      items = runner.send(:collect_auto_issue_work_items)

      expect(items.size).to eq(1)
      expect(items.first.processor_type).to eq(:auto_issue)
    end

    it "collects review work items" do
      allow(review_processor).to receive(:review_label).and_return("review")
      allow(repo_client).to receive(:list_pull_requests).and_return([{number: 4, labels: ["review"]}])

      items = runner.send(:collect_review_work_items)

      expect(items.size).to eq(1)
      expect(items.first.processor_type).to eq(:review)
    end

    it "collects auto PR work items" do
      allow(auto_pr_processor).to receive(:auto_label).and_return("auto-pr")
      allow(repo_client).to receive(:list_pull_requests).and_return([{number: 5, labels: ["auto-pr"]}])

      items = runner.send(:collect_auto_pr_work_items)

      expect(items.size).to eq(1)
      expect(items.first.processor_type).to eq(:auto_pr)
    end

    it "collects ci fix work items" do
      allow(ci_fix_processor).to receive(:ci_fix_label).and_return("ci-fix")
      allow(repo_client).to receive(:list_pull_requests).and_return([{number: 6, labels: ["ci-fix"]}])

      items = runner.send(:collect_ci_fix_work_items)

      expect(items.size).to eq(1)
      expect(items.first.processor_type).to eq(:ci_fix)
    end

    it "collects change request work items" do
      allow(change_request_processor).to receive(:change_request_label).and_return("cr")
      allow(repo_client).to receive(:list_pull_requests).and_return([{number: 7, labels: ["cr"]}])

      items = runner.send(:collect_change_request_work_items)

      expect(items.size).to eq(1)
      expect(items.first.processor_type).to eq(:change_request)
    end
  end

  describe "#dispatch_work_item" do
    let(:runner) do
      r = described_class.new(issues_url: "o/r", once: true, prompt: test_prompt)
      allow(r).to receive(:display_message)
      r
    end

    before do
      allow(runner).to receive(:post_detection_comment_for_item)
    end

    it "dispatches plan work item to plan processor" do
      allow(repo_client).to receive(:fetch_issue).and_return(issue_detail)
      work_item = Aidp::Watch::WorkItem.new(
        number: 1,
        item_type: :issue,
        processor_type: :plan,
        label: "aidp-plan",
        data: {}
      )

      runner.send(:dispatch_work_item, work_item)

      expect(plan_processor).to have_received(:process).with(issue_detail)
    end

    it "dispatches build work item to build processor" do
      allow(repo_client).to receive(:fetch_issue).and_return(issue_detail.merge(labels: ["build"]))
      work_item = Aidp::Watch::WorkItem.new(
        number: 1,
        item_type: :issue,
        processor_type: :build,
        label: "aidp-build",
        data: {}
      )

      runner.send(:dispatch_work_item, work_item)

      expect(build_processor).to have_received(:process)
    end

    it "dispatches review work item to review processor" do
      allow(repo_client).to receive(:fetch_pull_request).and_return({number: 1, labels: ["review"]})
      work_item = Aidp::Watch::WorkItem.new(
        number: 1,
        item_type: :pr,
        processor_type: :review,
        label: "aidp-review",
        data: {}
      )

      runner.send(:dispatch_work_item, work_item)

      expect(review_processor).to have_received(:process)
    end
  end

  describe "#process_worktree_cleanup" do
    let(:runner) do
      r = described_class.new(issues_url: "o/r", once: true, prompt: test_prompt)
      allow(r).to receive(:display_message)
      r
    end

    it "skips cleanup when job is disabled" do
      allow(worktree_cleanup_job).to receive(:enabled?).and_return(false)
      expect(worktree_cleanup_job).not_to receive(:execute)

      runner.send(:process_worktree_cleanup)
    end

    it "skips cleanup when not due" do
      allow(worktree_cleanup_job).to receive(:enabled?).and_return(true)
      allow(worktree_cleanup_job).to receive(:cleanup_due?).and_return(false)
      allow(state_store).to receive(:last_worktree_cleanup).and_return(Time.now)
      expect(worktree_cleanup_job).not_to receive(:execute)

      runner.send(:process_worktree_cleanup)
    end

    it "executes cleanup when due" do
      allow(worktree_cleanup_job).to receive(:enabled?).and_return(true)
      allow(worktree_cleanup_job).to receive(:cleanup_due?).and_return(true)
      allow(state_store).to receive(:last_worktree_cleanup).and_return(nil)
      allow(worktree_cleanup_job).to receive(:execute).and_return({cleaned: 2, skipped: 1, errors: []})
      expect(state_store).to receive(:record_worktree_cleanup).with(
        cleaned: 2,
        skipped: 1,
        errors: []
      )

      runner.send(:process_worktree_cleanup)
    end

    it "displays message when worktrees are cleaned" do
      allow(worktree_cleanup_job).to receive(:enabled?).and_return(true)
      allow(worktree_cleanup_job).to receive(:cleanup_due?).and_return(true)
      allow(state_store).to receive(:last_worktree_cleanup).and_return(nil)
      allow(worktree_cleanup_job).to receive(:execute).and_return({cleaned: 3, skipped: 0, errors: []})
      allow(state_store).to receive(:record_worktree_cleanup)

      expect(runner).to receive(:display_message).with(/3 cleaned/, type: :info)

      runner.send(:process_worktree_cleanup)
    end

    it "handles errors gracefully" do
      allow(worktree_cleanup_job).to receive(:enabled?).and_return(true)
      allow(worktree_cleanup_job).to receive(:cleanup_due?).and_return(true)
      allow(state_store).to receive(:last_worktree_cleanup).and_return(nil)
      allow(worktree_cleanup_job).to receive(:execute).and_raise(StandardError.new("cleanup failed"))

      expect { runner.send(:process_worktree_cleanup) }.not_to raise_error
    end
  end
end
