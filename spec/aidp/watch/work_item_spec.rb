# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::WorkItem do
  let(:issue_data) { {title: "Test Issue", body: "Issue body"} }
  let(:pr_data) { {title: "Test PR", body: "PR body"} }

  describe "#initialize" do
    it "creates a valid issue work item" do
      item = described_class.new(
        number: 123,
        item_type: :issue,
        processor_type: :plan,
        label: "aidp-plan",
        data: issue_data
      )

      expect(item.number).to eq(123)
      expect(item.item_type).to eq(:issue)
      expect(item.processor_type).to eq(:plan)
      expect(item.label).to eq("aidp-plan")
      expect(item.data).to eq(issue_data)
    end

    it "creates a valid PR work item" do
      item = described_class.new(
        number: 456,
        item_type: :pr,
        processor_type: :review,
        label: "aidp-review",
        data: pr_data
      )

      expect(item.number).to eq(456)
      expect(item.item_type).to eq(:pr)
      expect(item.processor_type).to eq(:review)
    end

    it "raises error for invalid item_type" do
      expect {
        described_class.new(
          number: 123,
          item_type: :invalid,
          processor_type: :plan,
          label: "test",
          data: {}
        )
      }.to raise_error(ArgumentError, /Invalid item_type/)
    end

    it "raises error for invalid processor_type" do
      expect {
        described_class.new(
          number: 123,
          item_type: :issue,
          processor_type: :invalid,
          label: "test",
          data: {}
        )
      }.to raise_error(ArgumentError, /Invalid processor_type/)
    end
  end

  describe "#key" do
    it "generates unique key for issue" do
      item = described_class.new(
        number: 123,
        item_type: :issue,
        processor_type: :plan,
        label: "aidp-plan",
        data: {}
      )

      expect(item.key).to eq("issue_123_plan")
    end

    it "generates unique key for PR" do
      item = described_class.new(
        number: 456,
        item_type: :pr,
        processor_type: :review,
        label: "aidp-review",
        data: {}
      )

      expect(item.key).to eq("pr_456_review")
    end
  end

  describe "#priority" do
    it "assigns high priority (1) to plan items" do
      item = described_class.new(
        number: 123,
        item_type: :issue,
        processor_type: :plan,
        label: "aidp-plan",
        data: {}
      )

      expect(item.priority).to eq(described_class::PRIORITY_PLAN)
      expect(item.priority).to eq(1)
    end

    it "assigns normal priority (2) to non-plan items" do
      item = described_class.new(
        number: 123,
        item_type: :issue,
        processor_type: :build,
        label: "aidp-build",
        data: {}
      )

      expect(item.priority).to eq(described_class::PRIORITY_NORMAL)
      expect(item.priority).to eq(2)
    end

    it "allows custom priority override" do
      item = described_class.new(
        number: 123,
        item_type: :issue,
        processor_type: :build,
        label: "aidp-build",
        data: {},
        priority: 0
      )

      expect(item.priority).to eq(0)
    end
  end

  describe "#issue? and #pr?" do
    it "identifies issues correctly" do
      item = described_class.new(
        number: 123,
        item_type: :issue,
        processor_type: :plan,
        label: "aidp-plan",
        data: {}
      )

      expect(item.issue?).to be true
      expect(item.pr?).to be false
    end

    it "identifies PRs correctly" do
      item = described_class.new(
        number: 456,
        item_type: :pr,
        processor_type: :review,
        label: "aidp-review",
        data: {}
      )

      expect(item.issue?).to be false
      expect(item.pr?).to be true
    end
  end

  describe "#plan?" do
    it "identifies plan items" do
      plan_item = described_class.new(
        number: 123,
        item_type: :issue,
        processor_type: :plan,
        label: "aidp-plan",
        data: {}
      )

      build_item = described_class.new(
        number: 123,
        item_type: :issue,
        processor_type: :build,
        label: "aidp-build",
        data: {}
      )

      expect(plan_item.plan?).to be true
      expect(build_item.plan?).to be false
    end
  end

  describe "#same_entity?" do
    it "returns true for same issue number and type" do
      item1 = described_class.new(
        number: 123,
        item_type: :issue,
        processor_type: :plan,
        label: "aidp-plan",
        data: {}
      )

      item2 = described_class.new(
        number: 123,
        item_type: :issue,
        processor_type: :build,
        label: "aidp-build",
        data: {}
      )

      expect(item1.same_entity?(item2)).to be true
    end

    it "returns false for different numbers" do
      item1 = described_class.new(
        number: 123,
        item_type: :issue,
        processor_type: :plan,
        label: "aidp-plan",
        data: {}
      )

      item2 = described_class.new(
        number: 456,
        item_type: :issue,
        processor_type: :plan,
        label: "aidp-plan",
        data: {}
      )

      expect(item1.same_entity?(item2)).to be false
    end

    it "returns false for different item types" do
      item1 = described_class.new(
        number: 123,
        item_type: :issue,
        processor_type: :plan,
        label: "aidp-plan",
        data: {}
      )

      item2 = described_class.new(
        number: 123,
        item_type: :pr,
        processor_type: :review,
        label: "aidp-review",
        data: {}
      )

      expect(item1.same_entity?(item2)).to be false
    end
  end

  describe "#<=>" do
    it "sorts by priority (lower = higher priority)" do
      plan_item = described_class.new(
        number: 1,
        item_type: :issue,
        processor_type: :plan,
        label: "aidp-plan",
        data: {}
      )

      build_item = described_class.new(
        number: 2,
        item_type: :issue,
        processor_type: :build,
        label: "aidp-build",
        data: {}
      )

      items = [build_item, plan_item]
      sorted = items.sort

      expect(sorted.first).to eq(plan_item)
      expect(sorted.last).to eq(build_item)
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      item = described_class.new(
        number: 123,
        item_type: :issue,
        processor_type: :plan,
        label: "aidp-plan",
        data: {}
      )

      hash = item.to_h

      expect(hash[:number]).to eq(123)
      expect(hash[:item_type]).to eq(:issue)
      expect(hash[:processor_type]).to eq(:plan)
      expect(hash[:label]).to eq("aidp-plan")
      expect(hash[:priority]).to eq(1)
    end
  end
end
