# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "aidp/setup/wizard"

RSpec.describe Aidp::Setup::Wizard do
  let(:tmpdir) { Dir.mktmpdir("aidp-wizard-edit-") }
  after { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

  class EditStubPrompt
    def initialize(script)
      @script = script.dup
      @edit_cycle_done = false
    end
    def say(*) ; end
    def warn(*) ; end
    def ok(*) ; end
    def no?(*) ; false end
    def ask(*) ; nil end
    def yes?(question, default: nil)
      return true if question =~ /Edit provider configuration details/
      default.nil? ? true : default
    end
    def select(question, default: nil)
      # Deterministic script matching
      entry = @script.find { |(pattern, _)| question =~ pattern }
      if entry
        val = entry[1]
        if question =~ /Select a provider to edit:/
          # Return provider once, then :done to exit loop
            return @edit_cycle_done ? :done : begin
              @edit_cycle_done = true
              val
            end
        end
        return val
      end
      # Fallbacks
      return :done if question =~ /Select a provider to edit:/
      default
    end
    def multi_select(question, default: [])
      if question =~ /Select fallback providers/
        ["github_copilot"]
      else
        []
      end
    end
  end

  it "edits fallback provider configuration" do
    # Sequence of select answers:
    # 1. Primary provider selection → cursor
    # 2. Billing model for cursor → subscription
    # 3. Model family for cursor → auto (label handled inside)
    # 4. Provider to edit → github_copilot
    # 5. Billing model for github_copilot edit → usage_based
    # 6. Model family for github_copilot edit → Anthropic Claude (balanced)
    script = [
      [/Select your primary provider:/, "cursor"],
      [/Billing model for cursor:/, "subscription"],
      [/Preferred model family for cursor:/, "Auto (let provider decide)"],
      [/Select a provider to edit:/, "github_copilot"],
      [/Billing model for github_copilot:/, "usage_based"],
      [/Preferred model family for github_copilot:/, "Anthropic Claude (balanced)"],
    ]

    prompt = EditStubPrompt.new(script)
    wizard = described_class.new(tmpdir, prompt: prompt, dry_run: true)
    wizard.run

    providers = wizard.instance_variable_get(:@config)[:providers]
    expect(providers[:cursor][:type]).to eq("subscription")
    expect(providers[:github_copilot][:type]).to eq("usage_based")
    expect(providers[:github_copilot][:model_family]).to eq("claude")
  end
end
