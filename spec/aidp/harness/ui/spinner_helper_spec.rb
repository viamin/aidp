# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::UI::SpinnerHelper do
  let(:helper) { described_class.new }
  let(:spinner_double) {
    double("Spinner",
      start: nil,
      success: nil,
      error: nil,
      stop: nil,
      update_title: nil,
      spinning?: false)
  }

  before do
    allow(TTY::Spinner).to receive(:new).and_return(spinner_double)
  end

  describe "#initialize" do
    it "creates a new instance" do
      expect(helper).to be_a(described_class)
    end
  end

  describe "#with_spinner" do
    it "requires a block" do
      expect {
        helper.with_spinner("Test")
      }.to raise_error(ArgumentError, "Block required for with_spinner")
    end

    it "executes block and returns result" do
      result = helper.with_spinner("Test") { "result" }
      expect(result).to eq("result")
    end

    it "starts and stops spinner" do
      helper.with_spinner("Test") { "done" }

      expect(spinner_double).to have_received(:start)
      expect(spinner_double).to have_received(:success)
    end

    it "handles errors and displays error message" do
      expect {
        helper.with_spinner("Test") { raise StandardError, "test error" }
      }.to raise_error(StandardError, "test error")

      expect(spinner_double).to have_received(:error)
    end

    it "uses custom success message" do
      helper.with_spinner("Test", success_message: "Custom success") { "done" }

      expect(spinner_double).to have_received(:success)
    end

    it "uses custom error message" do
      expect {
        helper.with_spinner("Test", error_message: "Custom error") { raise "test" }
      }.to raise_error

      expect(spinner_double).to have_received(:error)
    end

    it "cleans up spinner after execution" do
      helper.with_spinner("Test") { "done" }

      expect(helper.instance_variable_get(:@active_spinners)).not_to include(spinner_double)
    end
  end

  describe "convenience methods" do
    describe "#with_loading_spinner" do
      it "delegates to with_spinner with loading emoji" do
        result = helper.with_loading_spinner("Loading") { "loaded" }
        expect(result).to eq("loaded")
        expect(TTY::Spinner).to have_received(:new).with(
          "⏳ Loading :spinner",
          hash_including(format: :dots)
        )
      end
    end

    describe "#with_processing_spinner" do
      it "delegates to with_spinner with processing emoji" do
        result = helper.with_processing_spinner("Processing") { "processed" }
        expect(result).to eq("processed")
        expect(TTY::Spinner).to have_received(:new).with(
          "🔄 Processing :spinner",
          hash_including(format: :pulse)
        )
      end
    end

    describe "#with_saving_spinner" do
      it "delegates to with_spinner with save emoji" do
        result = helper.with_saving_spinner("Saving") { "saved" }
        expect(result).to eq("saved")
        expect(TTY::Spinner).to have_received(:new).with(
          "💾 Saving :spinner",
          hash_including(format: :dots)
        )
      end
    end

    describe "#with_analyzing_spinner" do
      it "delegates to with_spinner with analyze emoji" do
        result = helper.with_analyzing_spinner("Analyzing") { "analyzed" }
        expect(result).to eq("analyzed")
        expect(TTY::Spinner).to have_received(:new).with(
          "🔍 Analyzing :spinner",
          hash_including(format: :dots)
        )
      end
    end

    describe "#with_building_spinner" do
      it "delegates to with_spinner with build emoji" do
        result = helper.with_building_spinner("Building") { "built" }
        expect(result).to eq("built")
        expect(TTY::Spinner).to have_received(:new).with(
          "🏗️ Building :spinner",
          hash_including(format: :dots)
        )
      end
    end

    describe "#with_long_operation_spinner" do
      it "delegates to with_spinner with hourglass emoji and pulse format" do
        result = helper.with_long_operation_spinner("Long task") { "completed" }
        expect(result).to eq("completed")
        expect(TTY::Spinner).to have_received(:new).with(
          "⏳ Long task :spinner",
          hash_including(format: :pulse)
        )
      end
    end

    describe "#with_quick_spinner" do
      it "delegates to with_spinner with lightning emoji" do
        result = helper.with_quick_spinner("Quick task") { "done" }
        expect(result).to eq("done")
        expect(TTY::Spinner).to have_received(:new).with(
          "⚡ Quick task :spinner",
          hash_including(format: :dots)
        )
      end
    end
  end

  describe "#update_spinner_message" do
    it "updates the spinner title" do
      helper.with_spinner("Test") do |spinner|
        helper.update_spinner_message(spinner, "Updated message")
      end

      expect(spinner_double).to have_received(:update_title).with("Updated message")
    end
  end

  describe "#any_active?" do
    it "returns false when no spinners are active" do
      expect(helper.any_active?).to be false
    end

    it "returns true when spinners are active" do
      allow(spinner_double).to receive(:spinning?).and_return(true)

      helper.instance_variable_set(:@active_spinners, [spinner_double])
      expect(helper.any_active?).to be true
    end
  end

  describe "#active_count" do
    it "returns 0 when no spinners are active" do
      expect(helper.active_count).to eq(0)
    end

    it "returns count of active spinners" do
      allow(spinner_double).to receive(:spinning?).and_return(true)
      helper.instance_variable_set(:@active_spinners, [spinner_double, spinner_double])

      expect(helper.active_count).to eq(2)
    end
  end

  describe "#stop_all" do
    it "stops all active spinners" do
      allow(spinner_double).to receive(:spinning?).and_return(true)
      helper.instance_variable_set(:@active_spinners, [spinner_double])

      helper.stop_all

      expect(spinner_double).to have_received(:stop)
      expect(helper.instance_variable_get(:@active_spinners)).to be_empty
    end

    it "skips non-spinning spinners" do
      allow(spinner_double).to receive(:spinning?).and_return(false)
      helper.instance_variable_set(:@active_spinners, [spinner_double])

      helper.stop_all

      expect(spinner_double).not_to have_received(:stop)
    end
  end

  describe "global convenience methods" do
    before do
      # Reset the global SPINNER instance for each test
      allow(Aidp::Harness::UI::SPINNER).to receive(:with_spinner).and_call_original
      allow(Aidp::Harness::UI::SPINNER).to receive(:with_loading_spinner).and_call_original
      allow(Aidp::Harness::UI::SPINNER).to receive(:with_processing_spinner).and_call_original
      allow(Aidp::Harness::UI::SPINNER).to receive(:with_saving_spinner).and_call_original
      allow(Aidp::Harness::UI::SPINNER).to receive(:with_analyzing_spinner).and_call_original
      allow(Aidp::Harness::UI::SPINNER).to receive(:with_building_spinner).and_call_original
    end

    it ".with_spinner delegates to global SPINNER" do
      Aidp::Harness::UI.with_spinner("Test") { "result" }
      expect(Aidp::Harness::UI::SPINNER).to have_received(:with_spinner)
    end

    it ".with_loading_spinner delegates to global SPINNER" do
      Aidp::Harness::UI.with_loading_spinner("Loading") { "result" }
      expect(Aidp::Harness::UI::SPINNER).to have_received(:with_loading_spinner)
    end

    it ".with_processing_spinner delegates to global SPINNER" do
      Aidp::Harness::UI.with_processing_spinner("Processing") { "result" }
      expect(Aidp::Harness::UI::SPINNER).to have_received(:with_processing_spinner)
    end

    it ".with_saving_spinner delegates to global SPINNER" do
      Aidp::Harness::UI.with_saving_spinner("Saving") { "result" }
      expect(Aidp::Harness::UI::SPINNER).to have_received(:with_saving_spinner)
    end

    it ".with_analyzing_spinner delegates to global SPINNER" do
      Aidp::Harness::UI.with_analyzing_spinner("Analyzing") { "result" }
      expect(Aidp::Harness::UI::SPINNER).to have_received(:with_analyzing_spinner)
    end

    it ".with_building_spinner delegates to global SPINNER" do
      Aidp::Harness::UI.with_building_spinner("Building") { "result" }
      expect(Aidp::Harness::UI::SPINNER).to have_received(:with_building_spinner)
    end
  end
end
