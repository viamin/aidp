# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/harness/usage_period"

RSpec.describe Aidp::Harness::UsagePeriod do
  describe ".current" do
    it "creates a period for the current time" do
      period = described_class.current(period_type: "monthly")
      expect(period.period_type).to eq("monthly")
      expect(period.start_time).to be_a(Time)
      expect(period.end_time).to be_a(Time)
    end

    it "accepts custom reference time" do
      reference = Time.new(2024, 6, 15, 12, 0, 0)
      period = described_class.current(period_type: "monthly", reference_time: reference)

      expect(period.start_time.month).to eq(6)
    end
  end

  describe "daily period" do
    let(:reference) { Time.new(2024, 6, 15, 14, 30, 0) }
    let(:period) { described_class.current(period_type: "daily", reference_time: reference) }

    it "starts at midnight of the current day" do
      expect(period.start_time).to eq(Time.new(2024, 6, 15, 0, 0, 0))
    end

    it "ends at midnight of the next day" do
      expect(period.end_time).to eq(Time.new(2024, 6, 16, 0, 0, 0))
    end

    it "generates correct period key" do
      expect(period.period_key).to eq("2024-06-15")
    end

    it "generates correct description" do
      expect(period.description).to eq("June 15, 2024")
    end
  end

  describe "weekly period" do
    let(:reference) { Time.new(2024, 6, 13, 14, 30, 0) } # Thursday
    let(:period) { described_class.current(period_type: "weekly", reference_time: reference) }

    it "starts on Monday" do
      expect(period.start_time.wday).to eq(1) # Monday
      expect(period.start_time.day).to eq(10) # Monday of that week
    end

    it "ends on next Monday" do
      expect(period.end_time.wday).to eq(1) # Monday
    end

    it "generates correct period key" do
      expect(period.period_key).to match(/2024-W\d{2}/)
    end
  end

  describe "monthly period with reset_day" do
    context "when reference is after reset_day" do
      let(:reference) { Time.new(2024, 6, 20, 14, 30, 0) }
      let(:period) { described_class.current(period_type: "monthly", reset_day: 15, reference_time: reference) }

      it "starts on reset_day of current month" do
        expect(period.start_time).to eq(Time.new(2024, 6, 15, 0, 0, 0))
      end

      it "ends on reset_day of next month" do
        expect(period.end_time).to eq(Time.new(2024, 7, 15, 0, 0, 0))
      end
    end

    context "when reference is before reset_day" do
      let(:reference) { Time.new(2024, 6, 10, 14, 30, 0) }
      let(:period) { described_class.current(period_type: "monthly", reset_day: 15, reference_time: reference) }

      it "starts on reset_day of previous month" do
        expect(period.start_time).to eq(Time.new(2024, 5, 15, 0, 0, 0))
      end

      it "ends on reset_day of current month" do
        expect(period.end_time).to eq(Time.new(2024, 6, 15, 0, 0, 0))
      end
    end
  end

  describe "#contains?" do
    let(:reference) { Time.new(2024, 6, 15, 12, 0, 0) }
    let(:period) { described_class.current(period_type: "daily", reference_time: reference) }

    it "returns true for time within period" do
      within_time = Time.new(2024, 6, 15, 18, 0, 0)
      expect(period.contains?(within_time)).to be true
    end

    it "returns false for time before period" do
      before_time = Time.new(2024, 6, 14, 23, 59, 59)
      expect(period.contains?(before_time)).to be false
    end

    it "returns false for time after period" do
      after_time = Time.new(2024, 6, 16, 0, 0, 1)
      expect(period.contains?(after_time)).to be false
    end
  end

  describe "#ended?" do
    let(:reference) { Time.new(2024, 6, 15, 12, 0, 0) }
    let(:period) { described_class.current(period_type: "daily", reference_time: reference) }

    it "returns false when period is active" do
      current = Time.new(2024, 6, 15, 23, 59, 59)
      expect(period.ended?(current)).to be false
    end

    it "returns true when period has ended" do
      current = Time.new(2024, 6, 16, 0, 0, 1)
      expect(period.ended?(current)).to be true
    end
  end

  describe "#next_period" do
    let(:reference) { Time.new(2024, 6, 15, 12, 0, 0) }
    let(:period) { described_class.current(period_type: "daily", reference_time: reference) }

    it "returns the next period" do
      next_period = period.next_period
      expect(next_period.start_time).to eq(period.end_time)
    end
  end

  describe "#previous_period" do
    let(:reference) { Time.new(2024, 6, 15, 12, 0, 0) }
    let(:period) { described_class.current(period_type: "daily", reference_time: reference) }

    it "returns the previous period" do
      previous = period.previous_period
      expect(previous.end_time.day).to eq(period.start_time.day)
    end
  end

  describe "#remaining_seconds" do
    let(:period) { described_class.current(period_type: "daily", reference_time: Time.new(2024, 6, 15, 12, 0, 0)) }

    it "returns positive seconds when period is active" do
      current = Time.new(2024, 6, 15, 18, 0, 0)
      remaining = period.remaining_seconds(current)
      expect(remaining).to eq(6 * 60 * 60) # 6 hours
    end

    it "returns 0 when period has ended" do
      current = Time.new(2024, 6, 16, 12, 0, 0)
      expect(period.remaining_seconds(current)).to eq(0)
    end
  end

  describe "immutability" do
    it "is frozen after initialization" do
      period = described_class.current(period_type: "monthly")
      expect(period).to be_frozen
    end
  end

  describe "value equality" do
    it "considers two periods with same values as equal" do
      reference = Time.new(2024, 6, 15, 12, 0, 0)
      period1 = described_class.current(period_type: "monthly", reference_time: reference)
      period2 = described_class.current(period_type: "monthly", reference_time: reference)

      expect(period1).to eq(period2)
    end
  end
end
