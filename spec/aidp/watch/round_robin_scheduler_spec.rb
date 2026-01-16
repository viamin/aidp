# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::RoundRobinScheduler do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:state_store) { Aidp::Watch::StateStore.new(project_dir: tmp_dir, repository: "owner/repo") }
  let(:scheduler) { described_class.new(state_store: state_store) }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  def create_work_item(number:, item_type:, processor_type:, label: "test-label")
    Aidp::Watch::WorkItem.new(
      number: number,
      item_type: item_type,
      processor_type: processor_type,
      label: label,
      data: {}
    )
  end

  describe "#initialize" do
    it "creates scheduler with empty queue" do
      expect(scheduler.queue).to be_empty
      expect(scheduler.last_processed_key).to be_nil
    end

    it "restores last processed key from state store" do
      state_store.record_round_robin_position(last_key: "issue_123_plan", processed_at: Time.now.utc.iso8601)

      new_scheduler = described_class.new(state_store: state_store)

      expect(new_scheduler.last_processed_key).to eq("issue_123_plan")
    end
  end

  describe "#refresh_queue" do
    it "populates queue with work items" do
      items = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 2, item_type: :issue, processor_type: :plan),
        create_work_item(number: 3, item_type: :pr, processor_type: :review)
      ]

      scheduler.refresh_queue(items)

      expect(scheduler.queue.size).to eq(3)
    end

    it "sorts items by priority (plan items first)" do
      items = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 2, item_type: :issue, processor_type: :plan),
        create_work_item(number: 3, item_type: :pr, processor_type: :review)
      ]

      scheduler.refresh_queue(items)

      # Plan items (priority 1) should come before build/review (priority 2)
      expect(scheduler.queue.first.processor_type).to eq(:plan)
    end

    it "replaces existing queue on refresh" do
      items1 = [create_work_item(number: 1, item_type: :issue, processor_type: :build)]
      items2 = [
        create_work_item(number: 2, item_type: :issue, processor_type: :build),
        create_work_item(number: 3, item_type: :issue, processor_type: :build)
      ]

      scheduler.refresh_queue(items1)
      expect(scheduler.queue.size).to eq(1)

      scheduler.refresh_queue(items2)
      expect(scheduler.queue.size).to eq(2)
      expect(scheduler.queue.map(&:number)).to eq([2, 3])
    end
  end

  describe "#next_item" do
    it "returns nil for empty queue" do
      expect(scheduler.next_item).to be_nil
    end

    it "returns first item when no prior processing" do
      items = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 2, item_type: :issue, processor_type: :build)
      ]
      scheduler.refresh_queue(items)

      item = scheduler.next_item

      expect(item.number).to eq(1)
    end

    it "rotates to next item after processing" do
      items = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 2, item_type: :issue, processor_type: :build),
        create_work_item(number: 3, item_type: :issue, processor_type: :build)
      ]
      scheduler.refresh_queue(items)

      # Process first item
      first = scheduler.next_item
      scheduler.mark_processed(first)

      # Next should be second item
      second = scheduler.next_item
      expect(second.number).to eq(2)
    end

    it "wraps around to beginning after last item" do
      items = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 2, item_type: :issue, processor_type: :build)
      ]
      scheduler.refresh_queue(items)

      # Process both items
      scheduler.mark_processed(scheduler.next_item)
      scheduler.mark_processed(scheduler.next_item)

      # Next should wrap to first
      next_item = scheduler.next_item
      expect(next_item.number).to eq(1)
    end

    it "skips paused items" do
      items = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 2, item_type: :issue, processor_type: :build),
        create_work_item(number: 3, item_type: :issue, processor_type: :build)
      ]
      scheduler.refresh_queue(items)

      # Item 1 is paused
      item = scheduler.next_item(paused_numbers: [1])

      expect(item.number).to eq(2)
    end

    it "returns nil when all items are paused" do
      items = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 2, item_type: :issue, processor_type: :build)
      ]
      scheduler.refresh_queue(items)

      item = scheduler.next_item(paused_numbers: [1, 2])

      expect(item).to be_nil
    end

    it "maintains rotation position across paused items" do
      items = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 2, item_type: :issue, processor_type: :build),
        create_work_item(number: 3, item_type: :issue, processor_type: :build)
      ]
      scheduler.refresh_queue(items)

      # Process item 1
      first = scheduler.next_item
      scheduler.mark_processed(first)

      # Now item 2 is paused, should get item 3
      next_item = scheduler.next_item(paused_numbers: [2])
      expect(next_item.number).to eq(3)
    end
  end

  describe "#mark_processed" do
    it "updates last processed key" do
      items = [create_work_item(number: 1, item_type: :issue, processor_type: :build)]
      scheduler.refresh_queue(items)

      item = scheduler.next_item
      scheduler.mark_processed(item)

      expect(scheduler.last_processed_key).to eq("issue_1_build")
    end

    it "persists position to state store" do
      items = [create_work_item(number: 1, item_type: :issue, processor_type: :build)]
      scheduler.refresh_queue(items)

      item = scheduler.next_item
      scheduler.mark_processed(item)

      # Verify persistence
      expect(state_store.round_robin_last_key).to eq("issue_1_build")
      expect(state_store.round_robin_last_processed_at).to be_a(Time)
    end
  end

  describe "#work?" do
    it "returns false for empty queue" do
      expect(scheduler.work?).to be false
    end

    it "returns true when queue has non-paused items" do
      items = [create_work_item(number: 1, item_type: :issue, processor_type: :build)]
      scheduler.refresh_queue(items)

      expect(scheduler.work?).to be true
    end

    it "returns false when all items are paused" do
      items = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 2, item_type: :issue, processor_type: :build)
      ]
      scheduler.refresh_queue(items)

      expect(scheduler.work?(paused_numbers: [1, 2])).to be false
    end

    it "returns true when some items are not paused" do
      items = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 2, item_type: :issue, processor_type: :build)
      ]
      scheduler.refresh_queue(items)

      expect(scheduler.work?(paused_numbers: [1])).to be true
    end
  end

  describe "#stats" do
    it "returns queue statistics" do
      items = [
        create_work_item(number: 1, item_type: :issue, processor_type: :plan),
        create_work_item(number: 2, item_type: :issue, processor_type: :build),
        create_work_item(number: 3, item_type: :pr, processor_type: :review),
        create_work_item(number: 4, item_type: :pr, processor_type: :review)
      ]
      scheduler.refresh_queue(items)

      stats = scheduler.stats

      expect(stats[:total]).to eq(4)
      expect(stats[:by_processor]).to eq({plan: 1, build: 1, review: 2})
      expect(stats[:by_priority]).to eq({1 => 1, 2 => 3})
      expect(stats[:last_processed_key]).to be_nil
    end

    it "includes last processed key after processing" do
      items = [create_work_item(number: 1, item_type: :issue, processor_type: :build)]
      scheduler.refresh_queue(items)

      item = scheduler.next_item
      scheduler.mark_processed(item)

      stats = scheduler.stats

      expect(stats[:last_processed_key]).to eq("issue_1_build")
    end
  end

  describe "priority-based scheduling" do
    it "processes plan items before other items" do
      items = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 2, item_type: :issue, processor_type: :plan),
        create_work_item(number: 3, item_type: :pr, processor_type: :review)
      ]
      scheduler.refresh_queue(items)

      # First item should be the plan (highest priority)
      first = scheduler.next_item
      expect(first.processor_type).to eq(:plan)
      expect(first.number).to eq(2)
    end

    it "maintains priority order across refresh" do
      items1 = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 2, item_type: :issue, processor_type: :plan)
      ]
      scheduler.refresh_queue(items1)

      # Process plan item
      first = scheduler.next_item
      scheduler.mark_processed(first)

      # Add more items
      items2 = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 3, item_type: :issue, processor_type: :plan)
      ]
      scheduler.refresh_queue(items2)

      # New plan item should be next
      next_item = scheduler.next_item
      expect(next_item.processor_type).to eq(:plan)
    end
  end

  describe "round-robin rotation persistence" do
    it "continues from last position after scheduler recreation" do
      items = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 2, item_type: :issue, processor_type: :build),
        create_work_item(number: 3, item_type: :issue, processor_type: :build)
      ]
      scheduler.refresh_queue(items)

      # Process first two items
      scheduler.mark_processed(scheduler.next_item)
      scheduler.mark_processed(scheduler.next_item)

      # Create new scheduler (simulates restart)
      new_scheduler = described_class.new(state_store: state_store)
      new_scheduler.refresh_queue(items)

      # Should continue from item 3
      next_item = new_scheduler.next_item
      expect(next_item.number).to eq(3)
    end

    it "handles removed items gracefully" do
      items1 = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 2, item_type: :issue, processor_type: :build)
      ]
      scheduler.refresh_queue(items1)

      # Process item 2
      scheduler.mark_processed(scheduler.next_item)
      scheduler.mark_processed(scheduler.next_item)

      # Create new scheduler with different items (item 2 removed)
      items2 = [
        create_work_item(number: 1, item_type: :issue, processor_type: :build),
        create_work_item(number: 3, item_type: :issue, processor_type: :build)
      ]

      new_scheduler = described_class.new(state_store: state_store)
      new_scheduler.refresh_queue(items2)

      # Should start from beginning since last processed item is gone
      next_item = new_scheduler.next_item
      expect(next_item.number).to eq(1)
    end
  end
end
