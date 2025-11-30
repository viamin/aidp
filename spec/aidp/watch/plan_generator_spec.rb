# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::PlanGenerator do
  let(:issue) do
    {
      number: 42,
      title: "Test issue",
      url: "https://example.com/issues/42",
      body: "Do the thing",
      comments: [
        {"body" => "first", "author" => "alice", "createdAt" => "2024-01-01"},
        {"body" => "second", "author" => "bob", "createdAt" => "2024-01-02"}
      ]
    }
  end

  let(:provider) do
    instance_double("Provider",
      available?: true,
      send_message: %({"plan_summary":"s","plan_tasks":["t1"],"clarifying_questions":["q1"]}))
  end

  before do
    allow(Aidp).to receive(:log_debug)
    allow(Aidp).to receive(:log_warn)
    allow(Aidp).to receive(:log_info)
    allow(Aidp).to receive(:log_error)
    allow(Aidp::ProviderManager).to receive(:get_provider).and_return(provider)
  end

  describe "#generate" do
    it "returns parsed plan when provider succeeds" do
      generator = described_class.new(provider_name: "cursor")
      plan = generator.generate(issue)

      expect(plan[:summary]).to eq("s")
      expect(plan[:tasks]).to eq(["t1"])
      expect(plan[:questions]).to eq(["q1"])
    end

    it "falls back when provider returns nil" do
      bad_provider = instance_double("Provider", available?: true, send_message: nil)
      allow(Aidp::ProviderManager).to receive(:get_provider).and_return(bad_provider, provider)

      generator = described_class.new(provider_name: "cursor")
      allow(generator).to receive(:build_provider_fallback_chain).and_return(%w[cursor backup])
      plan = generator.generate(issue)

      expect(plan[:summary]).to eq("s")
      expect(Aidp).to have_received(:log_warn).with("plan_generator", "provider_returned_nil", provider: "cursor")
    end

    it "swallows provider errors and continues" do
      error_provider = instance_double("Provider", available?: true)
      allow(error_provider).to receive(:send_message).and_raise(StandardError, "boom")
      allow(Aidp::ProviderManager).to receive(:get_provider).and_return(error_provider, provider)

      generator = described_class.new(provider_name: "cursor")
      allow(generator).to receive(:build_provider_fallback_chain).and_return(%w[cursor backup])
      plan = generator.generate(issue)

      expect(plan[:summary]).to eq("s")
      expect(Aidp).to have_received(:log_warn).with("plan_generator", "provider_failed", hash_including(provider: "cursor"))
    end

    it "returns nil when all providers fail" do
      allow(Aidp::ProviderManager).to receive(:get_provider).and_return(nil)
      generator = described_class.new(provider_name: "cursor")

      expect(generator.generate(issue)).to be_nil
    end
  end

  describe "#parse_structured_response" do
    let(:generator) { described_class.new }

    it "parses plain JSON" do
      json = %({"plan_summary":"sum","plan_tasks":["a"],"clarifying_questions":["b"]})
      result = generator.send(:parse_structured_response, json)
      expect(result[:summary]).to eq("sum")
      expect(result[:tasks]).to eq(["a"])
      expect(result[:questions]).to eq(["b"])
    end

    it "parses fenced JSON" do
      fenced = <<~TXT
        ```json
        {"plan_summary":"s","plan_tasks":["t"],"clarifying_questions":[]}
        ```
      TXT
      result = generator.send(:parse_structured_response, fenced)
      expect(result[:tasks]).to eq(["t"])
    end

    it "returns nil on invalid JSON" do
      expect(generator.send(:parse_structured_response, "nope")).to be_nil
    end

    it "extracts first json payload from mixed text" do
      text = "prefix {\"plan_summary\":\"x\"} suffix"
      expect(generator.send(:parse_structured_response, text)[:summary]).to eq("x")
    end
  end

  describe "provider resolution and fallback chain" do
    let(:config_manager) { instance_double(Aidp::Harness::ConfigManager, fallback_providers: ["extra"], default_provider: "primary") }

    it "builds fallback chain with unique providers" do
      allow(Aidp::Harness::ConfigManager).to receive(:new).and_return(config_manager)
      generator = described_class.new(provider_name: "primary")
      chain = generator.send(:build_provider_fallback_chain)
      expect(chain).to eq(%w[primary extra])
    end

    it "detects default provider when none given" do
      allow(Aidp::Harness::ConfigManager).to receive(:new).and_return(config_manager)
      generator = described_class.new
      expect(generator.send(:detect_default_provider)).to eq("primary")
    end

    it "returns nil when provider unavailable" do
      unavailable = instance_double("Provider", available?: false)
      allow(Aidp::ProviderManager).to receive(:get_provider).and_return(unavailable)
      generator = described_class.new(provider_name: "cursor")
      expect(generator.send(:resolve_provider, "cursor")).to be_nil
    end

    it "handles provider raising during resolve" do
      allow(Aidp::ProviderManager).to receive(:get_provider).and_raise(StandardError.new("boom"))
      generator = described_class.new(provider_name: "cursor")
      expect(generator.send(:resolve_provider, "cursor")).to be_nil
    end
  end
end
