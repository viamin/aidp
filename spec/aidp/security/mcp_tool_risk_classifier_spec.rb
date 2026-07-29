# frozen_string_literal: true

require "spec_helper"
require "aidp/security"

RSpec.describe Aidp::Security::McpToolRiskClassifier do
  let(:project_dir) { Dir.mktmpdir("mcp_tool_risk_classifier_spec") }
  let(:provider_factory) { instance_double(Aidp::Harness::ProviderFactory) }
  let(:provider) { instance_double("Provider") }
  let(:config) do
    instance_double("Config",
      configured_providers: ["anthropic"],
      default_provider: "anthropic",
      respond_to?: true)
  end
  let(:provider_info_class) { class_double(Aidp::Harness::ProviderInfo) }
  let(:provider_info) { instance_double(Aidp::Harness::ProviderInfo) }
  let(:time_source) { class_double(Time, now: Time.utc(2026, 7, 29, 12, 0, 0)) }
  let(:ai_response) do
    <<~JSON
      {
        "tools": [
          {
            "name": "filesystem",
            "flags": ["private_data"],
            "risk_level": "medium",
            "rationale": "Can read local files."
          },
          {
            "name": "web",
            "flags": ["egress"],
            "risk_level": "medium",
            "rationale": "Makes external HTTP requests."
          }
        ]
      }
    JSON
  end

  subject(:classifier) do
    described_class.new(
      config,
      project_dir: project_dir,
      provider_factory: provider_factory,
      provider_info_class: provider_info_class,
      time_source: time_source
    )
  end

  before do
    allow(provider_info_class).to receive(:new).and_return(provider_info)
    allow(provider_info).to receive(:info).and_return({
      mcp_support: true,
      mcp_servers: [
        {name: "filesystem", description: "Local file access"},
        {name: "web", description: "Web requests"}
      ]
    })
    allow(provider_factory).to receive(:create_provider).and_return(provider)
    allow(provider).to receive(:send_message).and_return(ai_response)

    thinking_manager = instance_double(Aidp::Harness::ThinkingDepthManager)
    allow(Aidp::Harness::ThinkingDepthManager).to receive(:new).and_return(thinking_manager)
    allow(thinking_manager).to receive(:select_model_for_tier).and_return(["anthropic", "claude-3-5-sonnet", {}])
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#collect_tools" do
    it "deduplicates tools across providers and keeps descriptions" do
      allow(config).to receive(:configured_providers).and_return(%w[anthropic cursor])
      allow(provider_info).to receive(:info).and_return({
        mcp_support: true,
        mcp_servers: [
          {name: "filesystem", description: "Local file access", enabled: true},
          {name: "filesystem", description: "Local file access", enabled: true},
          {name: "git", description: "Git operations", enabled: true},
          {name: "disabled-tool", description: "Unavailable", enabled: false}
        ]
      })

      tools = classifier.collect_tools

      expect(tools).to eq([
        {name: "filesystem", descriptions: ["Local file access"], providers: %w[anthropic cursor]},
        {name: "git", descriptions: ["Git operations"], providers: %w[anthropic cursor]}
      ])
    end

    it "skips disabled MCP servers when collecting tools" do
      allow(provider_info).to receive(:info).and_return({
        mcp_support: true,
        mcp_servers: [
          {name: "filesystem", description: "Local file access", enabled: true},
          {name: "disabled-tool", description: "Unavailable", enabled: false}
        ]
      })

      tools = classifier.collect_tools

      expect(tools).to eq([
        {name: "filesystem", descriptions: ["Local file access"], providers: ["anthropic"]}
      ])
    end

    it "only force-refreshes the requested providers when rebuilding a full profile" do
      anthropic_info = instance_double(Aidp::Harness::ProviderInfo)
      cursor_info = instance_double(Aidp::Harness::ProviderInfo)
      allow(provider_info_class).to receive(:new).with("anthropic", project_dir).and_return(anthropic_info)
      allow(provider_info_class).to receive(:new).with("cursor", project_dir).and_return(cursor_info)
      allow(config).to receive(:configured_providers).and_return(%w[anthropic cursor])

      allow(anthropic_info).to receive(:info).with(force_refresh: true).and_return({
        mcp_support: true,
        mcp_servers: [{name: "filesystem", description: "Local file access", enabled: true}]
      })
      allow(cursor_info).to receive(:info).with(force_refresh: false).and_return({
        mcp_support: true,
        mcp_servers: [{name: "web", description: "Web requests", enabled: true}]
      })

      tools = classifier.collect_tools(
        providers: %w[anthropic cursor],
        force_refresh_providers: ["anthropic"]
      )

      expect(tools).to eq([
        {name: "filesystem", descriptions: ["Local file access"], providers: ["anthropic"]},
        {name: "web", descriptions: ["Web requests"], providers: ["cursor"]}
      ])
    end
  end

  describe "#generate!" do
    it "generates and saves a risk profile" do
      profile = classifier.generate!

      expect(profile.generator_model).to eq("claude-3-5-sonnet")
      expect(profile.flags_for("filesystem")).to eq(["private_data"])
      expect(profile.flags_for("web")).to eq(["egress"])

      saved = Aidp::Security::McpRiskProfile.load(project_dir)
      expect(saved.flags_for("web")).to eq(["egress"])
    end

    it "writes an empty profile without calling AI when no tools are available" do
      allow(provider_info).to receive(:info).and_return({mcp_support: true, mcp_servers: []})

      expect(provider_factory).not_to receive(:create_provider)
      profile = classifier.generate!

      expect(profile).to be_empty
      expect(profile.generator_model).to eq("none")
    end

    it "conservatively classifies tools omitted from the model response" do
      allow(provider).to receive(:send_message).and_return(<<~JSON)
        {
          "tools": [
            {
              "name": "filesystem",
              "flags": ["private_data"],
              "risk_level": "medium",
              "rationale": "Can read local files."
            }
          ]
        }
      JSON

      profile = classifier.generate!

      expect(profile.flags_for("filesystem")).to eq(["private_data"])
      expect(profile.flags_for("web")).to match_array(%w[untrusted_input private_data egress])
      expect(profile.risk_level_for("web")).to eq("high")
    end

    it "conservatively classifies malformed tool entries" do
      allow(provider).to receive(:send_message).and_return(<<~JSON)
        {
          "tools": [
            {
              "name": "filesystem",
              "risk_level": "medium",
              "rationale": "Can read local files."
            },
            {
              "name": "web",
              "flags": ["egress"],
              "risk_level": "medium",
              "rationale": "Makes external HTTP requests."
            }
          ]
        }
      JSON

      profile = classifier.generate!

      expect(profile.flags_for("filesystem")).to match_array(%w[untrusted_input private_data egress])
      expect(profile.risk_level_for("filesystem")).to eq("high")
      expect(profile.flags_for("web")).to eq(["egress"])
    end

    it "conservatively classifies tools whose non-empty flag list normalizes to nothing" do
      allow(provider).to receive(:send_message).and_return(<<~JSON)
        {
          "tools": [
            {
              "name": "filesystem",
              "flags": ["privateData"],
              "risk_level": "medium",
              "rationale": "Can read local files."
            },
            {
              "name": "web",
              "flags": [],
              "risk_level": "low",
              "rationale": "Explicitly no rule-of-two flags."
            }
          ]
        }
      JSON

      profile = classifier.generate!

      expect(profile.flags_for("filesystem")).to match_array(%w[untrusted_input private_data egress])
      expect(profile.risk_level_for("filesystem")).to eq("high")
      expect(profile.flags_for("web")).to eq([])
      expect(profile.risk_level_for("web")).to eq("low")
    end
  end
end
