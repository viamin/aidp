# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "aidp/setup/wizard"
require_relative "../../support/test_prompt"

RSpec.describe Aidp::Setup::Wizard do
  let(:tmpdir) { Dir.mktmpdir("aidp-wizard-force-fallback-") }
  after { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

  it "reconfigures existing fallback provider with force" do
    # Prepare existing config file to simulate rerun
    existing_yaml = <<~YML
      providers:
        github_copilot:
          type: subscription
          model_family: Auto (let provider decide)
    YML
    config_path = File.join(tmpdir, ".aidp.yml")
    File.write(config_path, existing_yaml)

    prompt = TestPrompt.new(responses: {
      select_map: {
        "Select your primary provider:" => "cursor",
        "Billing model for cursor:" => "usage_based",
        "Preferred model family for cursor:" => "Anthropic Claude (balanced)",
        "Billing model for github_copilot:" => "usage_based",
        "Preferred model family for github_copilot:" => "OpenAI o-series (reasoning models)"
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
    allow(wizard).to receive(:discover_available_providers).and_return({
      "Cursor AI" => "cursor",
      "GitHub Copilot" => "github_copilot"
    })

    wizard.run

    providers = wizard.instance_variable_get(:@config)[:providers]
    expect(providers[:github_copilot][:type]).to eq("usage_based")
    expect(providers[:github_copilot][:model_family]).to eq("openai_o")
  end
end
