# frozen_string_literal: true

require "spec_helper"
require "aidp/setup/wizard"
require_relative "../../support/test_prompt"
require "fileutils"

RSpec.describe Aidp::Setup::Wizard do
  let(:tmpdir) { Dir.mktmpdir("aidp-wizard-added-fallback-") }
  after { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

  it "includes newly added fallback in edit menu" do
    prompt = TestPrompt.new(responses: {
      select_map: {
        "Select your primary provider:" => "cursor",
        "Billing model for cursor:" => "subscription",
        "Preferred model family for cursor:" => "Auto (let provider decide)",
        "Select additional fallback provider:" => ["anthropic", :done],
        "Billing model for anthropic:" => "usage_based",
        "Preferred model family for anthropic:" => "Auto (let provider decide)",
        "Select a provider to edit:" => ["anthropic", :done]
      },
      yes_map: {
        "Add another fallback provider?" => true,
        "Edit provider configuration details (billing/model family)?" => true
      }
    })

    wizard = described_class.new(tmpdir, prompt: prompt, dry_run: true)
    allow(wizard).to receive(:discover_available_providers).and_return({
      "Cursor AI" => "cursor",
      "Anthropic Claude CLI" => "anthropic"
    })

    wizard.run

    # Find the edit selection log
    edit_selection = prompt.selections.find { |sel| sel[:title] == "Select a provider to edit:" }
    expect(edit_selection).not_to be_nil
    labels = edit_selection[:items].map { |c| c[:value] }
    expect(labels).to include("anthropic")
  end
end
