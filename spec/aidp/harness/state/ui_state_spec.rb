# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/state/ui_state"

RSpec.describe Aidp::Harness::State::UIState do
  let(:persistence) { instance_double("Persistence") }
  let(:ui_state) { described_class.new(persistence) }
  let(:empty_state) { {} }
  let(:populated_state) do
    {
      user_input: {key1: "value1"},
      current_step: "step1",
      mode: "interactive",
      saved_at: Time.now,
      state: "running",
      last_updated: Time.now
    }
  end

  before do
    allow(persistence).to receive(:load_state).and_return(empty_state)
    allow(persistence).to receive(:save_state)
    allow(persistence).to receive(:has_state?).and_return(false)
  end

  describe "#initialize" do
    it "initializes with persistence" do
      expect(ui_state).to be_a(described_class)
    end
  end

  describe "#user_input" do
    context "when no user input exists" do
      it "returns empty hash" do
        expect(ui_state.user_input).to eq({})
      end
    end

    context "when user input exists" do
      before do
        allow(persistence).to receive(:load_state).and_return(user_input: {key: "value"})
      end

      it "returns the user input" do
        expect(ui_state.user_input).to eq({key: "value"})
      end
    end
  end

  describe "#add_user_input" do
    it "adds user input and saves state" do
      expect(persistence).to receive(:save_state) do |state|
        expect(state[:user_input]).to eq({"test_key" => "test_value"})
        expect(state[:last_updated]).to be_a(Time)
      end

      ui_state.add_user_input("test_key", "test_value")
    end

    it "merges with existing user input" do
      allow(persistence).to receive(:load_state).and_return(user_input: {existing: "data"})

      expect(persistence).to receive(:save_state) do |state|
        expect(state[:user_input]).to include(existing: "data")
        expect(state[:user_input]["new_key"]).to eq("new_value")
      end

      ui_state.add_user_input("new_key", "new_value")
    end
  end

  describe "#current_step" do
    context "when no current step exists" do
      it "returns nil" do
        expect(ui_state.current_step).to be_nil
      end
    end

    context "when current step exists" do
      before do
        allow(persistence).to receive(:load_state).and_return(current_step: "initialization")
      end

      it "returns the current step" do
        expect(ui_state.current_step).to eq("initialization")
      end
    end
  end

  describe "#set_current_step" do
    it "sets current step and saves state" do
      expect(persistence).to receive(:save_state) do |state|
        expect(state[:current_step]).to eq("new_step")
        expect(state[:last_updated]).to be_a(Time)
      end

      ui_state.set_current_step("new_step")
    end
  end

  describe "#state_metadata" do
    context "when no state exists" do
      before do
        allow(persistence).to receive(:has_state?).and_return(false)
      end

      it "returns empty hash" do
        expect(ui_state.state_metadata).to eq({})
      end
    end

    context "when state exists" do
      before do
        allow(persistence).to receive(:has_state?).and_return(true)
        allow(persistence).to receive(:load_state).and_return(populated_state)
      end

      it "returns state metadata" do
        metadata = ui_state.state_metadata
        expect(metadata).to include(
          mode: "interactive",
          current_step: "step1",
          state: "running"
        )
        expect(metadata[:saved_at]).to be_a(Time)
        expect(metadata[:last_updated]).to be_a(Time)
      end
    end
  end
end
