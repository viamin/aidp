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
    allow(Aidp::AutoUpdate).to receive(:coordinator).and_return(auto_update)
    allow_any_instance_of(described_class).to receive(:display_message)
    allow(Aidp).to receive(:log_info)
    allow(Aidp).to receive(:log_debug)
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
end
