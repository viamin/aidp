# frozen_string_literal: true

require "spec_helper"
require "stringio"
require_relative "../../../../lib/aidp/harness/ui/progress_display"

RSpec.describe Aidp::Harness::UI::ProgressDisplay do
  let(:output) { StringIO.new }
  let(:progress_display) { described_class.new(output: output) }
  let(:sample_progress_data) { build_sample_progress_data }

  describe "#display_progress" do
    context "when displaying standard progress" do
      it "shows progress bar with percentage" do
        progress_display.display_progress(sample_progress_data, :standard)
        expect(output.string).to match(/50%/)
      end

      it "includes step information when available" do
        progress_with_steps = sample_progress_data.merge(
          current_step: 2,
          total_steps: 5
        )

        progress_display.display_progress(progress_with_steps, :standard)
        expect(output.string).to match(/Step: 2\/5/)
      end
    end

    context "when displaying detailed progress" do
      it "shows comprehensive progress information" do
        progress_display.display_progress(sample_progress_data, :detailed)
        expect(output.string).to match(/Progress:/)
      end

      it "includes timestamp information" do
        progress_display.display_progress(sample_progress_data, :detailed)
        expect(output.string).to match(/Started:/)
      end
    end

    context "when displaying minimal progress" do
      it "shows only essential information" do
        progress_display.display_progress(sample_progress_data, :minimal)
        expect(output.string).to match(/50%/)
      end
    end

    context "when progress data is invalid" do
      it "raises InvalidProgressError for negative progress" do
        invalid_data = sample_progress_data.merge(progress: -10)

        expect {
          progress_display.display_progress(invalid_data, :standard)
        }.to raise_error(Aidp::Harness::UI::ProgressDisplay::InvalidProgressError)
      end

      it "raises InvalidProgressError for progress over 100%" do
        invalid_data = sample_progress_data.merge(progress: 150)

        expect {
          progress_display.display_progress(invalid_data, :standard)
        }.to raise_error(Aidp::Harness::UI::ProgressDisplay::InvalidProgressError)
      end
    end
  end

  describe "#start_auto_refresh" do
    context "when auto refresh is started" do
      it "enables auto refresh mode" do
        progress_display.start_auto_refresh(1.0)

        expect(progress_display.auto_refresh_enabled?).to be true
      end

      it "sets the refresh interval" do
        progress_display.start_auto_refresh(2.0)

        expect(progress_display.refresh_interval).to eq(2.0)
      end
    end

    context "when auto refresh is already running" do
      before { progress_display.start_auto_refresh(1.0) }

      it "does not start a second refresh thread" do
        expect { progress_display.start_auto_refresh(1.0) }
          .not_to raise_error
      end
    end
  end

  describe "#stop_auto_refresh" do
    context "when auto refresh is running" do
      before { progress_display.start_auto_refresh(1.0) }

      it "disables auto refresh mode" do
        progress_display.stop_auto_refresh

        expect(progress_display.auto_refresh_enabled?).to be false
      end
    end

    context "when auto refresh is not running" do
      it "does not raise an error" do
        expect { progress_display.stop_auto_refresh }
          .not_to raise_error
      end
    end
  end

  describe "#display_multiple_progress" do
    context "when displaying multiple progress items" do
      it "shows all progress items" do
        multiple_data = [
          sample_progress_data.merge(id: "task_1", progress: 25),
          sample_progress_data.merge(id: "task_2", progress: 75)
        ]

        progress_display.display_multiple_progress(multiple_data, :standard)
        expect(output.string).to match(/task_1/)
        expect(output.string).to match(/task_2/)
      end
    end

    context "when no progress data is provided" do
      it "handles empty array gracefully" do
        expect { progress_display.display_multiple_progress([], :standard) }
          .not_to raise_error
      end
    end
  end

  describe "#get_display_history" do
    context "when progress has been displayed" do
      before do
        allow(TTY::Prompt).to receive(:new).and_return(double(ask: "response"))
        progress_display.display_progress(sample_progress_data, :standard)
      end

      it "returns display history" do
        history = progress_display.get_display_history

        expect(history).to be_an(Array)
        expect(history.first).to include(:timestamp, :progress_data, :display_type)
      end
    end

    context "when no progress has been displayed" do
      it "returns empty history" do
        history = progress_display.get_display_history

        expect(history).to be_empty
      end
    end
  end

  describe "#clear_display_history" do
    context "when history exists" do
      before do
        allow(TTY::Prompt).to receive(:new).and_return(double(ask: "response"))
        progress_display.display_progress(sample_progress_data, :standard)
      end

      it "clears the display history" do
        progress_display.clear_display_history

        expect(progress_display.get_display_history).to be_empty
      end
    end
  end

  private

  def build_sample_progress_data
    {
      id: "test_task",
      progress: 50,
      current_step: 1,
      total_steps: 2,
      created_at: Time.now,
      last_updated: Time.now,
      estimated_completion: Time.now + 300
    }
  end
end