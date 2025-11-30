# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::Runner do
  let(:repo_client) { instance_double("RepositoryClient", full_repo: "o/r") }
  let(:safety_checker) { instance_double("RepositorySafetyChecker", validate_watch_mode_safety!: true) }
  let(:state_store) { instance_double("StateStore", state: {}) }
  let(:state_extractor) { instance_double("GitHubStateExtractor") }
  let(:plan_processor) { instance_double("PlanProcessor", plan_label: "plan", process: nil) }
  let(:build_processor) { instance_double("BuildProcessor", build_label: "build", process: nil) }
  let(:auto_processor) { instance_double("AutoProcessor", process: nil) }
  let(:review_processor) { instance_double("ReviewProcessor", process: nil) }
  let(:ci_fix_processor) { instance_double("CiFixProcessor", process: nil) }
  let(:auto_pr_processor) { instance_double("AutoPrProcessor", process: nil) }
  let(:change_request_processor) { instance_double("ChangeRequestProcessor", process: nil) }
  let(:auto_update_policy) { instance_double("AutoUpdatePolicy", enabled: true, check_interval_seconds: 1) }
  let(:auto_update_check) { instance_double("UpdateCheck", should_update?: true, current_version: "1", available_version: "2") }
  let(:auto_update) { instance_double("AutoUpdateCoordinator", check_for_updates: nil, check_for_update: auto_update_check, policy: auto_update_policy, restore_from_checkpoint: nil, hot_reload_available?: false, initiate_update: nil) }
  let(:issue_detail) { {number: 1, labels: ["plan"], comments: [], author: "alice"} }

  before do
    extractor_class = Class.new
    extractor_class.const_set(:IN_PROGRESS_LABEL, "aidp-in-progress")
    stub_const("Aidp::Watch::GitHubStateExtractor", extractor_class)
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
    allow(Aidp::AutoUpdate).to receive(:coordinator).and_return(auto_update)
    allow_any_instance_of(described_class).to receive(:display_message)
    allow(Aidp).to receive(:log_info)
    allow(Aidp).to receive(:log_debug)
    allow(Aidp).to receive(:log_error)
    allow(Aidp).to receive(:log_warn)

    allow(state_extractor).to receive_messages(
      in_progress?: false,
      detection_comment_posted?: false,
      build_completed?: false
    )
    allow(safety_checker).to receive(:should_process_issue?).and_return(true)
  end

  describe "#start" do
    it "runs a single cycle when once is true" do
      runner = described_class.new(issues_url: "o/r", once: true, interval: 0.01)
      expect(safety_checker).to receive(:validate_watch_mode_safety!)
      expect(runner).to receive(:process_cycle).and_return(nil)

      runner.start
    end
  end

  describe "#process_cycle" do
    it "calls each processor in order" do
      runner = described_class.new(issues_url: "o/r", once: true)
      %i[
        process_plan_triggers
        process_build_triggers
        process_auto_issue_triggers
        check_for_updates_if_due
        process_review_triggers
        process_ci_fix_triggers
        process_auto_pr_triggers
        process_change_request_triggers
      ].each do |method|
        allow(runner).to receive(method).and_return(nil)
        expect(runner).to receive(method).once
      end

      runner.send(:process_cycle)
    end
  end

  describe "#check_for_updates_if_due" do
    it "invokes coordinator when interval has passed" do
      runner = described_class.new(issues_url: "o/r", once: true, interval: 0.01)
      runner.instance_variable_set(:@last_update_check, Time.now - 100)
      expect(auto_update).to receive(:check_for_update).and_return(auto_update_check)
      expect(auto_update).to receive(:initiate_update)

      runner.send(:check_for_updates_if_due)
    end
  end

  describe "post detection comments" do
    it "enables post_detection_comments by default" do
      runner = described_class.new(issues_url: "o/r", once: true)
      expect(runner.instance_variable_get(:@post_detection_comments)).to be true
    end
  end

  describe "trigger processing" do
    let(:runner) { described_class.new(issues_url: "o/r", once: true) }

    before do
      allow(runner).to receive(:post_detection_comment)
    end

    it "processes plan triggers and posts detection comment" do
      allow(repo_client).to receive(:list_issues).and_return([{number: 1, labels: ["plan"]}])
      allow(repo_client).to receive(:fetch_issue).and_return(issue_detail)

      runner.send(:process_plan_triggers)

      expect(plan_processor).to have_received(:process).with(issue_detail)
      expect(runner).to have_received(:post_detection_comment)
    end

    it "skips when plan poll fails" do
      allow(repo_client).to receive(:list_issues).and_raise(StandardError.new("boom"))

      expect { runner.send(:process_plan_triggers) }.not_to raise_error
    end

    it "processes build triggers with in-progress label handling" do
      allow(repo_client).to receive(:list_issues).and_return([{number: 2, labels: ["build"]}])
      allow(repo_client).to receive(:fetch_issue).and_return(issue_detail.merge(number: 2, labels: ["build"]))
      allow(repo_client).to receive(:add_labels)
      allow(repo_client).to receive(:remove_labels)

      runner.send(:process_build_triggers)

      expect(build_processor).to have_received(:process)
      expect(repo_client).to have_received(:add_labels)
      expect(repo_client).to have_received(:remove_labels)
    end

    it "processes auto issue triggers" do
      allow(auto_processor).to receive(:auto_label).and_return("auto")
      allow(repo_client).to receive(:list_issues).and_return([{number: 3, labels: ["auto"]}])
      allow(repo_client).to receive(:fetch_issue).and_return(issue_detail.merge(number: 3, labels: ["auto"]))

      runner.send(:process_auto_issue_triggers)

      expect(auto_processor).to have_received(:process)
    end

    it "processes review triggers" do
      allow(review_processor).to receive(:review_label).and_return("review")
      allow(repo_client).to receive(:list_pull_requests).and_return([{number: 4, labels: ["review"]}])
      allow(repo_client).to receive(:fetch_pull_request).and_return({number: 4, labels: ["review"]})

      runner.send(:process_review_triggers)

      expect(review_processor).to have_received(:process)
    end

    it "processes auto PR triggers" do
      allow(auto_pr_processor).to receive(:auto_label).and_return("auto-pr")
      allow(repo_client).to receive(:list_pull_requests).and_return([{number: 5, labels: ["auto-pr"]}])
      allow(repo_client).to receive(:fetch_pull_request).and_return({number: 5, labels: ["auto-pr"]})

      runner.send(:process_auto_pr_triggers)

      expect(auto_pr_processor).to have_received(:process)
    end

    it "processes ci fix triggers" do
      allow(ci_fix_processor).to receive(:ci_fix_label).and_return("ci-fix")
      allow(repo_client).to receive(:list_pull_requests).and_return([{number: 6, labels: ["ci-fix"]}])
      allow(repo_client).to receive(:fetch_pull_request).and_return({number: 6, labels: ["ci-fix"]})

      runner.send(:process_ci_fix_triggers)

      expect(ci_fix_processor).to have_received(:process)
    end

    it "processes change request triggers" do
      allow(change_request_processor).to receive(:change_request_label).and_return("cr")
      allow(repo_client).to receive(:list_pull_requests).and_return([{number: 7, labels: ["cr"]}])
      allow(repo_client).to receive(:fetch_pull_request).and_return({number: 7, labels: ["cr"]})

      runner.send(:process_change_request_triggers)

      expect(change_request_processor).to have_received(:process)
    end
  end
end
