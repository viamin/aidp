# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/checkpoint_display"

RSpec.describe Aidp::Execute::CheckpointDisplay do
  let(:display) { described_class.new }

  describe "#display_inline_progress" do
    it "shows formatted status line" do
      metrics = {lines_of_code: 100, test_coverage: 75.2, code_quality: 61.3, prd_task_progress: 40.7}
      expect { display.display_inline_progress(5, metrics) }.not_to raise_error
    end
  end

  describe "#format_percentage_with_color" do
    it "returns colored string" do
      val = display.send(:format_percentage_with_color, 82.6)
      expect(val).to be_a(String)
    end
  end

  describe "#display_checkpoint" do
    it "shows checkpoint with details" do
      data = {
        iteration: 3,
        metrics: {lines_of_code: 101, test_coverage: 55.2, code_quality: 70.1, prd_task_progress: 10.0, file_count: 12},
        status: :healthy,
        trends: {test_coverage: {direction: :up, change: 5, change_percent: 9.2}}
      }
      expect { display.display_checkpoint(data, show_details: true) }.not_to raise_error
    end
  end

  describe "#display_progress_summary" do
    it "shows summary with trends and quality score" do
      summary = {
        current: {step_name: "stepA", iteration: 7, status: :healthy, metrics: {lines_of_code: 150, test_coverage: 60.0, code_quality: 65.0, prd_task_progress: 30.0, file_count: 20}},
        trends: {code_quality: {direction: :down, change: -2, change_percent: -3.1}},
        quality_score: 72.4
      }
      expect { display.display_progress_summary(summary) }.not_to raise_error
    end
  end

  describe "#display_checkpoint_history" do
    it "prints history table" do
      history = [
        {iteration: 1, timestamp: Time.now.iso8601, metrics: {lines_of_code: 90, test_coverage: 50, code_quality: 60, prd_task_progress: 5}, status: :healthy},
        {iteration: 2, timestamp: Time.now.iso8601, metrics: {lines_of_code: 95, test_coverage: 52, code_quality: 61, prd_task_progress: 8}, status: :warning}
      ]
      expect { display.display_checkpoint_history(history, limit: 2) }.not_to raise_error
    end
  end
end
