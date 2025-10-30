# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "aidp/setup/wizard"

class StubPrompt
  attr_reader :select_calls

  def initialize(choices_map = {})
    @choices_map = choices_map # question => value to return
    @select_calls = []
  end

  def say(*)
  end

  def warn(*)
  end

  def ok(*)
  end

  def yes?(*)
    true
  end

  def no?(*)
    false
  end

  def ask(*)
    nil
  end

  def select(question, default: nil)
    container = []
    yield(container) if block_given?
    @select_calls << {question: question, default: default, choices: container}
    # Return configured answer or fall back to first value
    @choices_map.fetch(question) { container.first.last }
  end

  def multi_select(*)
    []
  end
end

RSpec.describe Aidp::Setup::Wizard do
  let(:tmpdir) { Dir.mktmpdir("aidp-wizard-mf-") }
  after { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

  describe "model family normalization" do
    it "normalizes legacy label values to canonical value" do
      prompt = StubPrompt.new(
        "Preferred model family for cursor:" => "Anthropic Claude (balanced)" # returning the LABEL not the value
      )
      wizard = described_class.new(tmpdir, prompt: prompt, dry_run: true)

      # Inject an existing config with a legacy label stored (simulating previous bug)
      wizard.instance_variable_get(:@config)[:providers] = {
        cursor: {type: "usage_based", model_family: "Anthropic Claude (balanced)"}
      }

      # Run normalization
      wizard.send(:normalize_existing_model_families!)

      providers = wizard.instance_variable_get(:@config)[:providers]
      expect(providers[:cursor][:model_family]).to eq("claude")
    end

    it "falls back to auto for unknown entries" do
      prompt = StubPrompt.new
      wizard = described_class.new(tmpdir, prompt: prompt, dry_run: true)
      wizard.instance_variable_get(:@config)[:providers] = {
        foo: {type: "usage_based", model_family: "Totally Unknown"}
      }
      wizard.send(:normalize_existing_model_families!)
      providers = wizard.instance_variable_get(:@config)[:providers]
      expect(providers[:foo][:model_family]).to eq("auto")
    end

    it "leaves canonical values unchanged" do
      prompt = StubPrompt.new
      wizard = described_class.new(tmpdir, prompt: prompt, dry_run: true)
      wizard.instance_variable_get(:@config)[:providers] = {
        cursor: {type: "usage_based", model_family: "claude"},
        mistral: {type: "usage_based", model_family: "mistral"}
      }
      wizard.send(:normalize_existing_model_families!)
      providers = wizard.instance_variable_get(:@config)[:providers]
      expect(providers[:cursor][:model_family]).to eq("claude")
      expect(providers[:mistral][:model_family]).to eq("mistral")
    end
  end
end
