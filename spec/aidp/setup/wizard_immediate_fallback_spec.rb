# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "aidp/setup/wizard"
require_relative "../../support/test_prompt"

RSpec.describe Aidp::Setup::Wizard do
  let(:tmpdir) { Dir.mktmpdir("aidp-wizard-immediate-fallback-") }
  after { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

  it "configures selected fallback provider immediately without edit loop" do
    prompt = TestPrompt.new(responses: {
      select_map: {
        "Select your primary provider:" => "cursor",
        "Billing model for cursor:" => "subscription",
        "Preferred model family for cursor:" => "Auto (let provider decide)",
        "Billing model for github_copilot:" => "usage_based",
        "Preferred model family for github_copilot:" => "Anthropic Claude (balanced)"
      },
      multi_select_map: {
        "Select fallback providers (used if primary fails):" => ["github_copilot"]
      },
      yes_map: {
        "Add another fallback provider?" => false,
        "Edit provider configuration details (billing/model family)?" => false
      }
    })
    wizard = described_class.new(tmpdir, prompt: prompt, dry_run: true)

    # Inject provider discovery to include github_copilot and cursor if not auto-detected
    allow(wizard).to receive(:discover_available_providers).and_return({
      "Cursor AI" => "cursor",
      "GitHub Copilot" => "github_copilot"
    })

    wizard.run

    providers = wizard.instance_variable_get(:@config)[:providers]
    expect(providers[:cursor][:type]).to eq("subscription")
    expect(providers[:cursor][:model_family]).to eq("auto")
    expect(providers[:github_copilot][:type]).to eq("usage_based")
    expect(providers[:github_copilot][:model_family]).to eq("claude")
  end
end
