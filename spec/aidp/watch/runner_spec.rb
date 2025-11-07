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
  let(:safety_checker) { instance_double(Aidp::Watch::RepositorySafetyChecker) }

  before do
    allow(Aidp::Watch::RepositoryClient).to receive(:parse_issues_url).and_return(["owner", "repo"])
    allow(Aidp::Watch::RepositoryClient).to receive(:new).and_return(repository_client)
    allow(Aidp::Watch::RepositorySafetyChecker).to receive(:new).and_return(safety_checker)
    allow(Aidp::Watch::StateStore).to receive(:new).and_return(state_store)
    allow(Aidp::Watch::PlanProcessor).to receive(:new).and_return(plan_processor)
    allow(Aidp::Watch::BuildProcessor).to receive(:new).and_return(build_processor)

    # By default, allow safety checks to pass
    allow(safety_checker).to receive(:validate_watch_mode_safety!)
    allow(safety_checker).to receive(:should_process_issue?).and_return(true)
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
  end

  describe "#process_cycle" do
    it "processes plan and build triggers" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      allow(runner).to receive(:process_plan_triggers)
      allow(runner).to receive(:process_build_triggers)

      runner.send(:process_cycle)

      expect(runner).to have_received(:process_plan_triggers)
      expect(runner).to have_received(:process_build_triggers)
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
  end

  describe "#process_build_triggers" do
    it "fetches and processes build issues" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {number: 2, labels: [{"name" => "aidp-build"}]}
      detailed_issue = {number: 2, body: "build details", author: "alice"}

      allow(repository_client).to receive(:list_issues).and_return([issue])
      allow(state_store).to receive(:build_status).with(2).and_return({"status" => "pending"})
      allow(repository_client).to receive(:fetch_issue).with(2).and_return(detailed_issue)
      allow(build_processor).to receive(:process)

      runner.send(:process_build_triggers)

      expect(build_processor).to have_received(:process).with(detailed_issue)
    end

    it "skips completed build issues" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {number: 2, labels: [{"name" => "aidp-build"}]}

      allow(repository_client).to receive(:list_issues).and_return([issue])
      allow(state_store).to receive(:build_status).with(2).and_return({"status" => "completed"})
      allow(build_processor).to receive(:process)

      runner.send(:process_build_triggers)

      expect(build_processor).not_to have_received(:process)
    end

    it "skips issues with unauthorized authors" do
      runner = described_class.new(issues_url: issues_url, once: true, prompt: prompt)
      issue = {number: 2, labels: [{"name" => "aidp-build"}]}
      detailed_issue = {number: 2, body: "build details", author: "untrusted"}

      allow(repository_client).to receive(:list_issues).and_return([issue])
      allow(state_store).to receive(:build_status).with(2).and_return({"status" => "pending"})
      allow(repository_client).to receive(:fetch_issue).with(2).and_return(detailed_issue)
      allow(safety_checker).to receive(:should_process_issue?).with(detailed_issue, enforce: false).and_return(false)
      allow(build_processor).to receive(:process)

      runner.send(:process_build_triggers)

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
end
