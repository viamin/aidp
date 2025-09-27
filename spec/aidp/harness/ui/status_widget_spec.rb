# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/harness/ui/status_widget"
require_relative "../../../support/test_prompt"

RSpec.describe Aidp::Harness::UI::StatusWidget do
  let(:test_prompt) { TestPrompt.new }
  let(:status_widget) { described_class.new({output: test_prompt}) }
  let(:sample_status_data) { build_sample_status_data }

  describe "#display_status" do
    context "when displaying loading status" do
      it "shows loading spinner with message" do
        status_widget.display_status(:loading, "Processing...")
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Processing/) }).to be true
      end

      it "includes loading indicator" do
        status_widget.display_status(:loading, "Loading data")
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/⏳/) }).to be true
      end
    end

    context "when displaying success status" do
      it "shows success message with checkmark" do
        status_widget.display_status(:success, "Completed successfully")
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/✅/) }).to be true
      end

      it "includes success message" do
        status_widget.display_status(:success, "Task completed")
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Task completed/) }).to be true
      end
    end

    context "when displaying error status" do
      it "shows error message with X mark" do
        status_widget.display_status(:error, "Something went wrong")
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/❌/) }).to be true
      end

      it "includes error details when provided" do
        error_data = {message: "Connection failed", code: 500}
        status_widget.display_status(:error, "Error occurred", error_data)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/Connection failed/) }).to be true
      end
    end

    context "when displaying warning status" do
      it "shows warning message with warning icon" do
        status_widget.display_status(:warning, "Please check configuration")
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/⚠️/) }).to be true
      end
    end

    context "when invalid status type is provided" do
      it "raises InvalidStatusError" do
        expect {
          status_widget.display_status(:invalid_status, "Test message")
        }.to raise_error(Aidp::Harness::UI::StatusWidget::InvalidStatusError)
      end
    end
  end

  describe "#start_spinner" do
    context "when starting a new spinner" do
      it "creates spinner with correct message" do
        status_widget.start_spinner("Loading...")

        expect(status_widget.spinner_active?).to be true
      end

      it "sets spinner message" do
        status_widget.start_spinner("Processing data")

        expect(status_widget.current_spinner_message).to eq("Processing data")
      end
    end

    context "when spinner is already active" do
      before { status_widget.start_spinner("Initial message") }

      it "updates the existing spinner message" do
        status_widget.start_spinner("Updated message")

        expect(status_widget.current_spinner_message).to eq("Updated message")
      end
    end
  end

  describe "#stop_spinner" do
    context "when spinner is active" do
      before { status_widget.start_spinner("Loading...") }

      it "stops the spinner" do
        status_widget.stop_spinner

        expect(status_widget.spinner_active?).to be false
      end

      it "clears spinner message" do
        status_widget.stop_spinner

        expect(status_widget.current_spinner_message).to be_nil
      end
    end

    context "when spinner is not active" do
      it "does not raise an error" do
        expect { status_widget.stop_spinner }
          .not_to raise_error
      end
    end
  end

  describe "#update_spinner_message" do
    context "when spinner is active" do
      before { status_widget.start_spinner("Initial message") }

      it "updates spinner message" do
        status_widget.update_spinner_message("Updated message")

        expect(status_widget.current_spinner_message).to eq("Updated message")
      end
    end

    context "when spinner is not active" do
      it "raises DisplayError" do
        expect {
          status_widget.update_spinner_message("New message")
        }.to raise_error(Aidp::Harness::UI::StatusWidget::DisplayError)
      end
    end
  end

  describe "#display_status_with_duration" do
    context "when displaying status with duration" do
      it "shows status with time information" do
        status_widget.display_status_with_duration(:success, "Completed", 5.5)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/5\.5s/) }).to be true
      end

      it "formats duration correctly" do
        status_widget.display_status_with_duration(:success, "Done", 125.7)
        expect(test_prompt.messages.any? { |msg| msg[:message].match(/2m 5s/) }).to be true
      end
    end
  end

  describe "#display_multiple_status" do
    context "when displaying multiple status items" do
      it "shows all status items" do
        status_items = [
          {type: :success, message: "Task 1 completed"},
          {type: :loading, message: "Task 2 in progress"},
          {type: :error, message: "Task 3 failed"}
        ]

        status_widget.display_multiple_status(status_items)
        message_texts = test_prompt.messages.map { |m| m[:message] }
        expect(message_texts.join(" ")).to match(/Task 1 completed.*Task 2 in progress.*Task 3 failed/m)
      end
    end

    context "when no status items are provided" do
      it "handles empty array gracefully" do
        expect { status_widget.display_multiple_status([]) }
          .not_to raise_error
      end
    end
  end

  describe "#get_status_history" do
    context "when status has been displayed" do
      before do
        status_widget.display_status(:success, "Test message")
      end

      it "returns status history" do
        history = status_widget.get_status_history

        expect(history).to be_an(Array)
        expect(history.first).to include(:timestamp, :type, :message)
      end
    end

    context "when no status has been displayed" do
      it "returns empty history" do
        history = status_widget.get_status_history

        expect(history).to be_empty
      end
    end
  end

  describe "#clear_status_history" do
    context "when history exists" do
      before do
        status_widget.display_status(:success, "Test message")
      end

      it "clears the status history" do
        status_widget.clear_status_history

        expect(status_widget.get_status_history).to be_empty
      end
    end
  end

  describe "#format_duration" do
    context "when formatting short durations" do
      it "formats seconds correctly" do
        result = status_widget.format_duration(5.5)

        expect(result).to eq("5.5s")
      end
    end

    context "when formatting longer durations" do
      it "formats minutes and seconds" do
        result = status_widget.format_duration(125.7)

        expect(result).to eq("2m 5s")
      end

      it "formats hours, minutes, and seconds" do
        result = status_widget.format_duration(3665.2)

        expect(result).to eq("1h 1m 5s")
      end
    end

    context "when duration is zero or negative" do
      it "returns zero seconds" do
        result = status_widget.format_duration(0)

        expect(result).to eq("0s")
      end

      it "handles negative durations" do
        result = status_widget.format_duration(-5)

        expect(result).to eq("0s")
      end
    end
  end

  private

  def build_sample_status_data
    {
      type: :loading,
      message: "Processing request",
      timestamp: Time.now,
      metadata: {
        progress: 50,
        current_step: 2,
        total_steps: 4
      }
    }
  end
end
