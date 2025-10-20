# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/instruction_queue"

RSpec.describe Aidp::Execute::InstructionQueue do
  let(:queue) { described_class.new }

  describe "#enqueue" do
    it "adds instruction to queue" do
      expect { queue.enqueue("test instruction") }.to change(queue, :count).from(0).to(1)
    end

    it "accepts different instruction types" do
      instruction = queue.enqueue("test", type: :plan_update)
      expect(instruction.type).to eq(:plan_update)
    end

    it "accepts different priorities" do
      instruction = queue.enqueue("test", priority: :high)
      expect(instruction.priority).to eq(2) # HIGH = 2
    end

    it "defaults to user_input type" do
      instruction = queue.enqueue("test")
      expect(instruction.type).to eq(:user_input)
    end

    it "defaults to normal priority" do
      instruction = queue.enqueue("test")
      expect(instruction.priority).to eq(3) # NORMAL = 3
    end

    it "raises error for invalid type" do
      expect {
        queue.enqueue("test", type: :invalid)
      }.to raise_error(ArgumentError, /Invalid instruction type/)
    end

    it "raises error for invalid priority" do
      expect {
        queue.enqueue("test", priority: :invalid)
      }.to raise_error(ArgumentError, /Invalid priority/)
    end

    it "stores timestamp" do
      instruction = queue.enqueue("test")
      expect(instruction.timestamp).to be_a(Time)
    end
  end

  describe "#dequeue_all" do
    it "returns all instructions sorted by priority" do
      queue.enqueue("low priority", priority: :low)
      queue.enqueue("critical priority", priority: :critical)
      queue.enqueue("normal priority", priority: :normal)

      instructions = queue.dequeue_all
      expect(instructions.map(&:content)).to eq([
        "critical priority",
        "normal priority",
        "low priority"
      ])
    end

    it "sorts by timestamp within same priority" do
      queue.enqueue("first", priority: :normal)
      queue.enqueue("second", priority: :normal)

      instructions = queue.dequeue_all
      expect(instructions.first.content).to eq("first")
      expect(instructions.last.content).to eq("second")
    end

    it "clears queue after dequeuing" do
      queue.enqueue("test")
      queue.dequeue_all
      expect(queue).to be_empty
    end

    it "returns empty array when queue is empty" do
      expect(queue.dequeue_all).to eq([])
    end
  end

  describe "#peek_all" do
    it "returns instructions without removing them" do
      queue.enqueue("test")
      expect(queue.peek_all.size).to eq(1)
      expect(queue.count).to eq(1)
    end

    it "returns sorted instructions" do
      queue.enqueue("low", priority: :low)
      queue.enqueue("high", priority: :high)

      instructions = queue.peek_all
      expect(instructions.first.content).to eq("high")
    end
  end

  describe "#empty?" do
    it "returns true when empty" do
      expect(queue).to be_empty
    end

    it "returns false when not empty" do
      queue.enqueue("test")
      expect(queue).not_to be_empty
    end
  end

  describe "#clear" do
    it "removes all instructions" do
      queue.enqueue("first")
      queue.enqueue("second")
      queue.clear
      expect(queue).to be_empty
    end
  end

  describe "#format_for_prompt" do
    it "formats instructions for PROMPT.md" do
      queue.enqueue("Add error handling", type: :user_input)
      queue.enqueue("Update plan", type: :plan_update, priority: :high)

      formatted = queue.format_for_prompt
      expect(formatted).to include("🔄 Queued Instructions from REPL")
      expect(formatted).to include("USER_INPUT")
      expect(formatted).to include("PLAN_UPDATE")
      expect(formatted).to include("Add error handling")
      expect(formatted).to include("Update plan")
    end

    it "returns empty string when queue is empty" do
      expect(queue.format_for_prompt).to eq("")
    end

    it "marks critical priority instructions" do
      queue.enqueue("Critical task", priority: :critical)
      formatted = queue.format_for_prompt
      expect(formatted).to include("🔴 CRITICAL")
    end

    it "groups instructions by type" do
      queue.enqueue("User input 1", type: :user_input)
      queue.enqueue("User input 2", type: :user_input)
      queue.enqueue("Plan update", type: :plan_update)

      formatted = queue.format_for_prompt
      user_input_section = formatted.split("### USER_INPUT").last.split("### PLAN_UPDATE").first
      expect(user_input_section).to include("User input 1")
      expect(user_input_section).to include("User input 2")
    end
  end

  describe "#summary" do
    context "when empty" do
      it "returns no queued instructions message" do
        expect(queue.summary).to eq("No queued instructions")
      end
    end

    context "when has instructions" do
      before do
        queue.enqueue("test1", type: :user_input, priority: :high)
        queue.enqueue("test2", type: :plan_update, priority: :normal)
        queue.enqueue("test3", type: :user_input, priority: :high)
      end

      it "returns summary hash" do
        summary = queue.summary
        expect(summary).to be_a(Hash)
        expect(summary[:total]).to eq(3)
      end

      it "groups by type" do
        summary = queue.summary
        expect(summary[:by_type][:user_input]).to eq(2)
        expect(summary[:by_type][:plan_update]).to eq(1)
      end

      it "groups by priority" do
        summary = queue.summary
        expect(summary[:by_priority][:high]).to eq(2)
        expect(summary[:by_priority][:normal]).to eq(1)
      end
    end
  end

  describe "instruction types" do
    it "supports all defined types" do
      types = [:user_input, :plan_update, :constraint, :clarification, :acceptance]
      types.each do |type|
        expect { queue.enqueue("test", type: type) }.not_to raise_error
      end
    end
  end

  describe "priority levels" do
    it "supports all defined priorities" do
      priorities = [:critical, :high, :normal, :low]
      priorities.each do |priority|
        expect { queue.enqueue("test", priority: priority) }.not_to raise_error
      end
    end

    it "orders critical > high > normal > low" do
      queue.enqueue("low", priority: :low)
      queue.enqueue("normal", priority: :normal)
      queue.enqueue("high", priority: :high)
      queue.enqueue("critical", priority: :critical)

      instructions = queue.dequeue_all
      expect(instructions.map(&:content)).to eq(["critical", "high", "normal", "low"])
    end
  end
end
