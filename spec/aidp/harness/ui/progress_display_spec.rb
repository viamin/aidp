# frozen_string_literal: true

require "spec_helper"
require "stringio"
require_relative "../../../support/test_prompt"
require_relative "../../../../lib/aidp/harness/ui/progress_display"

RSpec.describe Aidp::Harness::UI::ProgressDisplay do
  let(:output) { StringIO.new }
  let(:test_prompt) { TestPrompt.new }
  let(:progress_display) { described_class.new(output: output, prompt: test_prompt) }
  let(:sample_progress_data) { build_sample_progress_data }

  def message_texts
    test_prompt.messages.map { |m| m[:message] }
  end

  describe "#display_progress" do
    context "when displaying standard progress" do
      it "shows progress bar with percentage" do
        progress_display.display_progress(sample_progress_data, :standard)
        expect(message_texts.join(" ")).to match(/50%/)
      end

      it "includes step information when available" do
        progress_with_steps = sample_progress_data.merge(
          current_step: 2,
          total_steps: 5
        )

        progress_display.display_progress(progress_with_steps, :standard)
        expect(message_texts.join(" ")).to match(/Step: 2\/5/)
      end

      it "handles missing total_steps gracefully" do
        progress_with_only_current = sample_progress_data.merge(
          current_step: 3,
          total_steps: nil
        )

        progress_display.display_progress(progress_with_only_current, :standard)
        expect(message_texts.join(" ")).to match(/Step: 3/)
      end

      it "includes task ID when provided" do
        progress_with_id = sample_progress_data.merge(id: "task-123")

        progress_display.display_progress(progress_with_id, :standard)
        expect(message_texts.join(" ")).to match(/\[task-123\]/)
      end

      it "handles missing progress value" do
        progress_without_value = sample_progress_data.dup
        progress_without_value.delete(:progress)

        progress_display.display_progress(progress_without_value, :standard)
        expect(message_texts.join(" ")).to match(/0%/)
      end

      it "handles missing message" do
        progress_without_message = sample_progress_data.dup
        progress_without_message.delete(:message)

        progress_display.display_progress(progress_without_message, :standard)
        expect(message_texts.join(" ")).to match(/Processing\.\.\./)
      end
    end

    context "when displaying detailed progress" do
      it "shows comprehensive progress information" do
        progress_display.display_progress(sample_progress_data, :detailed)
        expect(message_texts.join(" ")).to match(/Progress:/)
      end

      it "includes timestamp information" do
        progress_display.display_progress(sample_progress_data, :detailed)
        expect(message_texts.join(" ")).to match(/Started:/)
      end

      it "handles missing timestamp" do
        progress_without_timestamp = sample_progress_data.dup
        progress_without_timestamp.delete(:started_at)

        progress_display.display_progress(progress_without_timestamp, :detailed)
        expect(message_texts.join(" ")).to match(/Started: N\/A/)
      end

      it "includes ETA information" do
        progress_with_eta = sample_progress_data.merge(eta: "5 minutes")

        progress_display.display_progress(progress_with_eta, :detailed)
        expect(message_texts.join(" ")).to match(/ETA: 5 minutes/)
      end

      it "handles missing ETA" do
        progress_without_eta = sample_progress_data.dup
        progress_without_eta.delete(:eta)

        progress_display.display_progress(progress_without_eta, :detailed)
        expect(message_texts.join(" ")).to match(/ETA: N\/A/)
      end
    end

    context "when displaying minimal progress" do
      it "shows only essential information" do
        progress_display.display_progress(sample_progress_data, :minimal)
        expect(message_texts.join(" ")).to match(/50%/)
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

      it "raises DisplayError wrapping ArgumentError for non-hash data" do
        expect {
          progress_display.display_progress("not a hash", :standard)
        }.to raise_error(Aidp::Harness::UI::ProgressDisplay::DisplayError, /Progress data must be a hash/)
      end

      it "raises InvalidProgressError for non-numeric progress" do
        invalid_data = sample_progress_data.merge(progress: "fifty")

        expect {
          progress_display.display_progress(invalid_data, :standard)
        }.to raise_error(Aidp::Harness::UI::ProgressDisplay::InvalidProgressError, /Progress must be a number/)
      end

      it "raises InvalidProgressError for invalid display type" do
        expect {
          progress_display.display_progress(sample_progress_data, :invalid_type)
        }.to raise_error(Aidp::Harness::UI::ProgressDisplay::InvalidProgressError, /Invalid display type/)
      end

      it "wraps unexpected errors in DisplayError" do
        allow(progress_display).to receive(:display_standard_progress).and_raise(StandardError.new("Unexpected"))

        expect {
          progress_display.display_progress(sample_progress_data, :standard)
        }.to raise_error(Aidp::Harness::UI::ProgressDisplay::DisplayError, /Failed to display progress/)
      end
    end
  end

  describe "spinner management" do
    it "starts and stops spinner" do
      spinner = double("TTY::Spinner")
      expect(spinner).to receive(:start)
      expect(spinner).to receive(:stop)
      allow(TTY::Spinner).to receive(:new).and_return(spinner)
      progress_display.start_spinner("Loading...")
      progress_display.stop_spinner
    end

    it "handles missing spinner class gracefully" do
      display_without_spinner = described_class.new(output: output, prompt: test_prompt, spinner: nil)
      expect { display_without_spinner.start_spinner("Loading...") }.not_to raise_error
    end
  end

  describe "#start_auto_refresh" do
    after { progress_display.stop_auto_refresh if progress_display.auto_refresh_enabled? }

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

  describe "#show_progress" do
    it "displays progress bar and executes block" do
      mock_bar = double("TTY::ProgressBar")
      allow(TTY::ProgressBar).to receive(:new).and_return(mock_bar)
      expect(mock_bar).to receive(:tick).exactly(3).times

      progress_display.show_progress(3) do |bar|
        expect(bar).to eq(mock_bar)
      end
    end

    it "raises DisplayError wrapping InvalidProgressError for non-positive steps" do
      expect {
        progress_display.show_progress(0) {}
      }.to raise_error(Aidp::Harness::UI::ProgressDisplay::DisplayError, /Total steps must be positive/)
    end

    it "wraps errors in DisplayError" do
      allow(TTY::ProgressBar).to receive(:new).and_raise(StandardError.new("Bar error"))

      expect {
        progress_display.show_progress(5) {}
      }.to raise_error(Aidp::Harness::UI::ProgressDisplay::DisplayError, /Failed to display progress/)
    end
  end

  describe "#update_progress" do
    it "ticks the progress bar" do
      bar = double("ProgressBar")
      expect(bar).to receive(:tick)
      expect(bar).to receive(:update_title).with("Step completed")

      progress_display.update_progress(bar, "Step completed")
    end

    it "raises DisplayError wrapping InvalidProgressError for nil bar" do
      expect {
        progress_display.update_progress(nil)
      }.to raise_error(Aidp::Harness::UI::ProgressDisplay::DisplayError, /Progress bar cannot be nil/)
    end

    it "wraps update errors in DisplayError" do
      bar = double("ProgressBar")
      allow(bar).to receive(:tick).and_raise(StandardError.new("Tick error"))

      expect {
        progress_display.update_progress(bar)
      }.to raise_error(Aidp::Harness::UI::ProgressDisplay::DisplayError, /Failed to update progress/)
    end
  end

  describe "#show_step_progress" do
    it "displays step progress with substeps" do
      allow(TTY::ProgressBar).to receive(:progress).and_yield(double("bar", update_title: nil, tick: nil))

      expect {
        progress_display.show_step_progress("Test Step", 3) { |bar, index| }
      }.not_to raise_error
    end

    it "raises DisplayError wrapping InvalidProgressError for empty step name" do
      expect {
        progress_display.show_step_progress("", 3) {}
      }.to raise_error(Aidp::Harness::UI::ProgressDisplay::DisplayError, /Step name cannot be empty/)
    end

    it "raises DisplayError wrapping InvalidProgressError for non-positive substeps" do
      expect {
        progress_display.show_step_progress("Test", 0) {}
      }.to raise_error(Aidp::Harness::UI::ProgressDisplay::DisplayError, /Total substeps must be positive/)
    end

    it "wraps errors in DisplayError" do
      allow(TTY::ProgressBar).to receive(:progress).and_raise(StandardError.new("Progress error"))

      expect {
        progress_display.show_step_progress("Test", 3) {}
      }.to raise_error(Aidp::Harness::UI::ProgressDisplay::DisplayError, /Failed to display step progress/)
    end
  end

  describe "#show_indeterminate_progress" do
    it "displays indeterminate progress with message" do
      allow(TTY::ProgressBar).to receive(:progress).and_yield(double("bar", update_title: nil))

      expect {
        progress_display.show_indeterminate_progress("Loading...") { |bar| }
      }.not_to raise_error
    end

    it "raises DisplayError wrapping InvalidProgressError for empty message" do
      expect {
        progress_display.show_indeterminate_progress("") {}
      }.to raise_error(Aidp::Harness::UI::ProgressDisplay::DisplayError, /Message cannot be empty/)
    end

    it "wraps errors in DisplayError" do
      allow(TTY::ProgressBar).to receive(:progress).and_raise(StandardError.new("Progress error"))

      expect {
        progress_display.show_indeterminate_progress("Loading...") {}
      }.to raise_error(Aidp::Harness::UI::ProgressDisplay::DisplayError, /Failed to display indeterminate progress/)
    end
  end

  describe "#display_progress" do
    context "when displaying multiple progress items" do
      it "shows all progress items" do
        multiple_data = [
          sample_progress_data.merge(id: "task_1", progress: 25),
          sample_progress_data.merge(id: "task_2", progress: 75)
        ]

        progress_display.display_multiple_progress(multiple_data, :standard)
        expect(message_texts.join(" ")).to match(/task_1/)
        expect(message_texts.join(" ")).to match(/task_2/)
      end
    end

    context "when no progress data is provided" do
      it "handles empty array gracefully" do
        expect { progress_display.display_multiple_progress([], :standard) }
          .not_to raise_error
      end

      it "displays muted message for empty array" do
        progress_display.display_multiple_progress([], :standard)
        expect(message_texts.join(" ")).to match(/No progress items/)
      end
    end

    context "when invalid input is provided" do
      it "raises ArgumentError for non-array input" do
        expect {
          progress_display.display_multiple_progress("not an array", :standard)
        }.to raise_error(ArgumentError, "Progress items must be an array")
      end
    end
  end

  describe "#get_display_history" do
    context "when progress has been displayed" do
      before do
        allow(TTY::Prompt).to receive(:new).and_return(double(ask: "response"))
        progress_display.display_progress(sample_progress_data, :standard)
      end

      after do
        # Clean up the global TTY::Prompt stub
        RSpec::Mocks.space.proxy_for(TTY::Prompt).reset
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

      after do
        # Clean up the global TTY::Prompt stub
        RSpec::Mocks.space.proxy_for(TTY::Prompt).reset
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
