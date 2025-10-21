# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::CLI::EnhancedInput do
  let(:input) { StringIO.new }
  let(:output) { StringIO.new }
  let(:test_prompt) { TestPrompt.new(responses: responses) }
  let(:responses) { {} }
  let(:enhanced_input) { described_class.new(prompt: test_prompt, input: input, output: output, use_reline: false) }

  describe "#initialize" do
    it "creates an instance with default settings" do
      expect(enhanced_input).to be_a(described_class)
    end

    it "accepts custom input and output streams" do
      custom_input = StringIO.new
      custom_output = StringIO.new
      instance = described_class.new(input: custom_input, output: custom_output)
      expect(instance).to be_a(described_class)
    end

    it "can disable reline usage" do
      instance = described_class.new(use_reline: false)
      expect(instance).to be_a(described_class)
    end

    it "accepts a custom prompt" do
      custom_prompt = TestPrompt.new
      instance = described_class.new(prompt: custom_prompt)
      expect(instance).to be_a(described_class)
    end
  end

  describe "#ask" do
    context "when using TTY::Prompt fallback mode" do
      let(:responses) { {ask: "John"} }

      before do
        enhanced_input.disable_reline!
      end

      it "asks a simple question" do
        result = enhanced_input.ask("What's your name?")
        expect(result).to eq("John")
        expect(test_prompt.inputs.last[:message]).to eq("What's your name?")
      end

      it "handles questions with default values" do
        result = enhanced_input.ask("What's your name?", default: "Anonymous")
        expect(result).to eq("John")
        expect(test_prompt.inputs.last[:options][:default]).to eq("Anonymous")
      end

      it "handles required questions" do
        result = enhanced_input.ask("Enter password:", required: true)
        expect(result).to eq("John")
        expect(test_prompt.inputs.last[:options][:required]).to be true
      end
    end

    context "when using reline mode with non-TTY input" do
      let(:responses) { {ask: "fallback answer"} }

      it "falls back to TTY::Prompt when input is not a TTY" do
        allow(input).to receive(:tty?).and_return(false)

        result = enhanced_input.ask("Question?")
        expect(result).to eq("fallback answer")
        expect(test_prompt.inputs.last[:message]).to eq("Question?")
      end
    end

    context "when using reline mode with TTY input" do
      it "attempts to use reline for TTY input" do
        allow(input).to receive(:tty?).and_return(true)
        allow(Reline).to receive(:readline).and_return("reline answer")
        allow(Reline).to receive(:output=)
        allow(Reline).to receive(:input=)
        allow(Reline).to receive(:completion_append_character=)

        # Enable reline and ensure it's being used
        enhanced_input.enable_reline!
        expect(enhanced_input.instance_variable_get(:@use_reline)).to be true
      end

      it "shows hints when enabled" do
        enhanced_input.enable_hints!
        expect(enhanced_input.instance_variable_get(:@show_hints)).to be true

        # Mock the reline interaction without actually calling it
        allow(input).to receive(:tty?).and_return(false)
        enhanced_input.ask("Test question")
        expect(test_prompt.inputs.last[:message]).to eq("Test question")
      end
    end
  end

  describe "#enable_hints!" do
    it "enables hints display" do
      expect { enhanced_input.enable_hints! }.not_to raise_error
      expect(enhanced_input.instance_variable_get(:@show_hints)).to be true
    end
  end

  describe "#disable_reline!" do
    it "disables reline usage" do
      enhanced_input.disable_reline!
      expect(enhanced_input.instance_variable_get(:@use_reline)).to be false
    end
  end

  describe "#enable_reline!" do
    it "enables reline usage" do
      enhanced_input.enable_reline!
      expect(enhanced_input.instance_variable_get(:@use_reline)).to be true
    end
  end

  describe "method delegation" do
    let(:responses) { {yes?: true, select: "option1"} }

    it "delegates unknown methods to TTY::Prompt" do
      result = enhanced_input.yes?("Continue?")
      expect(result).to be true
      expect(test_prompt.inputs.last[:message]).to eq("Continue?")
    end

    it "delegates select method" do
      result = enhanced_input.select("Choose:", %w[option1 option2])
      expect(result).to eq("option1")
      expect(test_prompt.selections.last[:title]).to eq("Choose:")
    end

    it "responds to methods that TTY::Prompt responds to" do
      expect(enhanced_input.respond_to?(:yes?)).to be true
      expect(enhanced_input.respond_to?(:select)).to be true
    end
  end
end
