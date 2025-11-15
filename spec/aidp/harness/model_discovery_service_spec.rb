# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/model_discovery_service"
require "aidp/harness/model_cache"
require "aidp/harness/model_registry"

RSpec.describe Aidp::Harness::ModelDiscoveryService do
  let(:mock_cache) { instance_double(Aidp::Harness::ModelCache) }
  let(:mock_registry) { instance_double(Aidp::Harness::ModelRegistry) }
  let(:service) { described_class.new(cache: mock_cache, registry: mock_registry) }

  let(:sample_models) do
    [
      {name: "claude-3-5-sonnet-20241022", family: "claude-3-5-sonnet", tier: "standard", provider: "anthropic"},
      {name: "claude-3-5-haiku-20241022", family: "claude-3-5-haiku", tier: "mini", provider: "anthropic"}
    ]
  end

  describe "#initialize" do
    it "initializes with default cache and registry" do
      service = described_class.new
      expect(service.cache).to be_a(Aidp::Harness::ModelCache)
      expect(service.registry).to be_a(Aidp::Harness::ModelRegistry)
    end

    it "initializes with custom cache and registry" do
      expect(service.cache).to eq(mock_cache)
      expect(service.registry).to eq(mock_registry)
    end
  end

  describe "#discover_models" do
    let(:mock_discoverer) { instance_double(Aidp::Harness::ModelDiscoverers::Anthropic) }

    before do
      allow(service).to receive(:instance_variable_get).with(:@discoverers).and_return(
        {"anthropic" => mock_discoverer}
      )
      allow(mock_discoverer).to receive(:available?).and_return(true)
      allow(mock_discoverer).to receive(:discover_models).and_return(sample_models)
    end

    context "when cache is enabled and has data" do
      it "returns cached models" do
        allow(mock_cache).to receive(:get_cached_models).with("anthropic").and_return(sample_models)

        models = service.discover_models("anthropic", use_cache: true)
        expect(models).to eq(sample_models)
        expect(mock_discoverer).not_to have_received(:discover_models)
      end
    end

    context "when cache is empty" do
      before do
        allow(mock_cache).to receive(:get_cached_models).with("anthropic").and_return(nil)
        allow(mock_cache).to receive(:cache_models)
      end

      it "performs discovery" do
        models = service.discover_models("anthropic", use_cache: true)
        expect(models).to eq(sample_models)
        expect(mock_discoverer).to have_received(:discover_models)
      end

      it "caches the discovered models" do
        service.discover_models("anthropic", use_cache: true)
        expect(mock_cache).to have_received(:cache_models).with("anthropic", sample_models)
      end
    end

    context "when cache is disabled" do
      before do
        allow(mock_cache).to receive(:cache_models)
      end

      it "performs discovery even with cache available" do
        allow(mock_cache).to receive(:get_cached_models).with("anthropic").and_return(sample_models)

        models = service.discover_models("anthropic", use_cache: false)
        expect(mock_discoverer).to have_received(:discover_models)
      end
    end

    context "when provider is not available" do
      before do
        allow(mock_discoverer).to receive(:available?).and_return(false)
        allow(mock_cache).to receive(:get_cached_models).with("anthropic").and_return(nil)
      end

      it "returns empty array" do
        models = service.discover_models("anthropic", use_cache: true)
        expect(models).to eq([])
      end
    end

    context "when discovery fails" do
      before do
        allow(mock_cache).to receive(:get_cached_models).with("anthropic").and_return(nil)
        allow(mock_discoverer).to receive(:discover_models).and_raise(StandardError, "Discovery failed")
      end

      it "returns empty array gracefully" do
        models = service.discover_models("anthropic", use_cache: false)
        expect(models).to eq([])
      end
    end
  end

  describe "#discover_all_models" do
    let(:anthropic_discoverer) { instance_double(Aidp::Harness::ModelDiscoverers::Anthropic) }
    let(:cursor_discoverer) { instance_double(Aidp::Harness::ModelDiscoverers::Cursor) }

    before do
      allow(service).to receive(:instance_variable_get).with(:@discoverers).and_return(
        {
          "anthropic" => anthropic_discoverer,
          "cursor" => cursor_discoverer
        }
      )
      allow(anthropic_discoverer).to receive(:available?).and_return(true)
      allow(cursor_discoverer).to receive(:available?).and_return(true)
      allow(anthropic_discoverer).to receive(:discover_models).and_return(sample_models)
      allow(cursor_discoverer).to receive(:discover_models).and_return([])
      allow(mock_cache).to receive(:get_cached_models).and_return(nil)
      allow(mock_cache).to receive(:cache_models)
    end

    it "discovers models from all providers" do
      results = service.discover_all_models(use_cache: false)
      expect(results).to be_a(Hash)
      expect(results).to have_key("anthropic")
      expect(results["anthropic"]).to eq(sample_models)
    end

    it "excludes providers with no models" do
      results = service.discover_all_models(use_cache: false)
      expect(results).not_to have_key("cursor")
    end
  end

  describe "#providers_supporting" do
    before do
      allow(Aidp::Providers::Anthropic).to receive(:supports_model_family?).with("claude-3-5-sonnet").and_return(true)
      allow(Aidp::Providers::Cursor).to receive(:supports_model_family?).with("claude-3-5-sonnet").and_return(true)
      allow(Aidp::Providers::Gemini).to receive(:supports_model_family?).with("claude-3-5-sonnet").and_return(false)
    end

    it "returns providers that support a model family" do
      providers = service.providers_supporting("claude-3-5-sonnet")
      expect(providers).to include("anthropic")
      expect(providers).to include("cursor")
      expect(providers).not_to include("gemini")
    end
  end

  describe "#refresh_cache" do
    let(:mock_discoverer) { instance_double(Aidp::Harness::ModelDiscoverers::Anthropic) }

    before do
      allow(service).to receive(:instance_variable_get).with(:@discoverers).and_return(
        {"anthropic" => mock_discoverer}
      )
      allow(mock_discoverer).to receive(:available?).and_return(true)
      allow(mock_discoverer).to receive(:discover_models).and_return(sample_models)
      allow(mock_cache).to receive(:invalidate)
      allow(mock_cache).to receive(:cache_models)
    end

    it "invalidates and rediscovers for specific provider" do
      service.refresh_cache("anthropic")
      expect(mock_cache).to have_received(:invalidate).with("anthropic")
      expect(mock_discoverer).to have_received(:discover_models)
    end
  end

  describe "#refresh_all_caches" do
    let(:anthropic_discoverer) { instance_double(Aidp::Harness::ModelDiscoverers::Anthropic) }
    let(:cursor_discoverer) { instance_double(Aidp::Harness::ModelDiscoverers::Cursor) }

    before do
      allow(service).to receive(:instance_variable_get).with(:@discoverers).and_return(
        {
          "anthropic" => anthropic_discoverer,
          "cursor" => cursor_discoverer
        }
      )
      allow(anthropic_discoverer).to receive(:available?).and_return(true)
      allow(cursor_discoverer).to receive(:available?).and_return(false)
      allow(anthropic_discoverer).to receive(:discover_models).and_return(sample_models)
      allow(mock_cache).to receive(:invalidate_all)
      allow(mock_cache).to receive(:cache_models)
    end

    it "invalidates all caches and rediscovers" do
      service.refresh_all_caches
      expect(mock_cache).to have_received(:invalidate_all)
      expect(anthropic_discoverer).to have_received(:discover_models)
    end
  end
end
