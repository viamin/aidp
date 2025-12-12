# frozen_string_literal: true

require "spec_helper"
require "aidp/evaluations/evaluation_record"

RSpec.describe Aidp::Evaluations::EvaluationRecord do
  describe "#initialize" do
    it "creates a record with valid rating" do
      record = described_class.new(rating: "good")

      expect(record.rating).to eq("good")
      expect(record.id).to start_with("eval_")
      expect(record.created_at).to be_a(String)
    end

    it "accepts all valid ratings" do
      %w[good neutral bad].each do |rating|
        record = described_class.new(rating: rating)
        expect(record.rating).to eq(rating)
      end
    end

    it "normalizes rating to lowercase" do
      record = described_class.new(rating: "GOOD")
      expect(record.rating).to eq("good")
    end

    it "raises error for invalid rating" do
      expect { described_class.new(rating: "excellent") }
        .to raise_error(ArgumentError, /Invalid rating/)
    end

    it "accepts optional comment" do
      record = described_class.new(rating: "good", comment: "Great work!")
      expect(record.comment).to eq("Great work!")
    end

    it "accepts target_type" do
      record = described_class.new(rating: "good", target_type: "work_unit")
      expect(record.target_type).to eq("work_unit")
    end

    it "raises error for invalid target_type" do
      expect { described_class.new(rating: "good", target_type: "invalid") }
        .to raise_error(ArgumentError, /Invalid target_type/)
    end

    it "accepts target_id" do
      record = described_class.new(rating: "good", target_id: "01_INIT")
      expect(record.target_id).to eq("01_INIT")
    end

    it "accepts context hash" do
      context = {step: "test", iteration: 1}
      record = described_class.new(rating: "good", context: context)
      expect(record.context).to eq(context)
    end

    it "allows custom id" do
      record = described_class.new(rating: "good", id: "custom_id")
      expect(record.id).to eq("custom_id")
    end

    it "allows custom created_at" do
      timestamp = "2024-01-01T00:00:00Z"
      record = described_class.new(rating: "good", created_at: timestamp)
      expect(record.created_at).to eq(timestamp)
    end
  end

  describe "#to_h" do
    it "converts record to hash" do
      record = described_class.new(
        rating: "good",
        comment: "Test",
        target_type: "prompt",
        target_id: "123"
      )

      hash = record.to_h

      expect(hash[:id]).to eq(record.id)
      expect(hash[:rating]).to eq("good")
      expect(hash[:comment]).to eq("Test")
      expect(hash[:target_type]).to eq("prompt")
      expect(hash[:target_id]).to eq("123")
      expect(hash[:created_at]).to be_a(String)
      expect(hash[:context]).to be_a(Hash)
    end
  end

  describe ".from_h" do
    it "creates record from hash" do
      hash = {
        id: "eval_test",
        rating: "neutral",
        comment: "Okay",
        target_type: "step",
        target_id: "02_TEST",
        context: {foo: "bar"},
        created_at: "2024-01-01T00:00:00Z"
      }

      record = described_class.from_h(hash)

      expect(record.id).to eq("eval_test")
      expect(record.rating).to eq("neutral")
      expect(record.comment).to eq("Okay")
      expect(record.target_type).to eq("step")
      expect(record.target_id).to eq("02_TEST")
      expect(record.context).to eq({foo: "bar"})
      expect(record.created_at).to eq("2024-01-01T00:00:00Z")
    end

    it "handles string keys" do
      hash = {
        "id" => "eval_test",
        "rating" => "good",
        "comment" => nil
      }

      record = described_class.from_h(hash)
      expect(record.id).to eq("eval_test")
      expect(record.rating).to eq("good")
    end
  end

  describe "predicate methods" do
    it "#good? returns true for good rating" do
      record = described_class.new(rating: "good")
      expect(record.good?).to be true
      expect(record.bad?).to be false
      expect(record.neutral?).to be false
    end

    it "#bad? returns true for bad rating" do
      record = described_class.new(rating: "bad")
      expect(record.good?).to be false
      expect(record.bad?).to be true
      expect(record.neutral?).to be false
    end

    it "#neutral? returns true for neutral rating" do
      record = described_class.new(rating: "neutral")
      expect(record.good?).to be false
      expect(record.bad?).to be false
      expect(record.neutral?).to be true
    end
  end
end
