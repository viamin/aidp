# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/provider_type_checker"

RSpec.describe Aidp::Harness::ProviderTypeChecker do
  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include Aidp::Harness::ProviderTypeChecker

      # Mock methods that the module expects
      def provider_config(provider_name, options = {})
        @configs ||= {}
        @configs[provider_name]
      end

      def set_provider_config(provider_name, config)
        @configs ||= {}
        @configs[provider_name] = config
      end

      def get_config(options = {})
        options
      end

      def type(options = {})
        options[:type] || options["type"] || "subscription"
      end
    end
  end

  let(:instance) { test_class.new }

  describe "#usage_based_provider?" do
    context "with ConfigManager signature (provider_name, options)" do
      it "returns true for usage_based provider" do
        instance.set_provider_config("anthropic", {type: "usage_based"})
        expect(instance.usage_based_provider?("anthropic")).to be true
      end

      it "returns false for subscription provider" do
        instance.set_provider_config("claude", {type: "subscription"})
        expect(instance.usage_based_provider?("claude")).to be false
      end

      it "returns false for passthrough provider" do
        instance.set_provider_config("cursor", {type: "passthrough"})
        expect(instance.usage_based_provider?("cursor")).to be false
      end
    end

    context "with ProviderConfig signature (options)" do
      it "returns true when options specify usage_based" do
        expect(instance.usage_based_provider?({type: "usage_based"})).to be true
      end

      it "returns false when options specify subscription" do
        expect(instance.usage_based_provider?({type: "subscription"})).to be false
      end

      it "handles string keys" do
        expect(instance.usage_based_provider?({"type" => "usage_based"})).to be true
      end
    end

    it "works with symbol provider names" do
      instance.set_provider_config(:openai, {type: "usage_based"})
      expect(instance.usage_based_provider?(:openai)).to be true
    end
  end

  describe "#subscription_provider?" do
    context "with ConfigManager signature" do
      it "returns true for subscription provider" do
        instance.set_provider_config("claude", {type: "subscription"})
        expect(instance.subscription_provider?("claude")).to be true
      end

      it "returns false for usage_based provider" do
        instance.set_provider_config("anthropic", {type: "usage_based"})
        expect(instance.subscription_provider?("anthropic")).to be false
      end

      it "returns false for passthrough provider" do
        instance.set_provider_config("cursor", {type: "passthrough"})
        expect(instance.subscription_provider?("cursor")).to be false
      end
    end

    context "with ProviderConfig signature" do
      it "returns true when options specify subscription" do
        expect(instance.subscription_provider?({type: "subscription"})).to be true
      end

      it "returns false when options specify usage_based" do
        expect(instance.subscription_provider?({type: "usage_based"})).to be false
      end
    end
  end

  describe "#passthrough_provider?" do
    context "with ConfigManager signature" do
      it "returns true for passthrough provider" do
        instance.set_provider_config("cursor", {type: "passthrough"})
        expect(instance.passthrough_provider?("cursor")).to be true
      end

      it "returns false for usage_based provider" do
        instance.set_provider_config("anthropic", {type: "usage_based"})
        expect(instance.passthrough_provider?("anthropic")).to be false
      end

      it "returns false for subscription provider" do
        instance.set_provider_config("claude", {type: "subscription"})
        expect(instance.passthrough_provider?("claude")).to be false
      end
    end

    context "with ProviderConfig signature" do
      it "returns true when options specify passthrough" do
        expect(instance.passthrough_provider?({type: "passthrough"})).to be true
      end

      it "returns false when options specify subscription" do
        expect(instance.passthrough_provider?({type: "subscription"})).to be false
      end
    end
  end

  describe "#get_provider_type" do
    it "returns type from provider config with symbol key" do
      instance.set_provider_config("test", {type: "usage_based"})
      expect(instance.get_provider_type("test")).to eq("usage_based")
    end

    it "returns type from provider config with string key" do
      instance.set_provider_config("test", {"type" => "passthrough"})
      expect(instance.get_provider_type("test")).to eq("passthrough")
    end

    it "defaults to subscription when provider not found" do
      expect(instance.get_provider_type("nonexistent")).to eq("subscription")
    end

    it "defaults to subscription when type not specified" do
      instance.set_provider_config("test", {})
      expect(instance.get_provider_type("test")).to eq("subscription")
    end
  end

  describe "#requires_api_key?" do
    it "returns true for usage_based providers" do
      instance.set_provider_config("anthropic", {type: "usage_based"})
      expect(instance.requires_api_key?("anthropic")).to be true
    end

    it "returns false for subscription providers" do
      instance.set_provider_config("claude", {type: "subscription"})
      expect(instance.requires_api_key?("claude")).to be false
    end

    it "returns false for passthrough providers" do
      instance.set_provider_config("cursor", {type: "passthrough"})
      expect(instance.requires_api_key?("cursor")).to be false
    end

    context "with ProviderConfig signature" do
      it "returns true for usage_based" do
        expect(instance.requires_api_key?({type: "usage_based"})).to be true
      end

      it "returns false for subscription" do
        expect(instance.requires_api_key?({type: "subscription"})).to be false
      end
    end
  end

  describe "#has_underlying_service?" do
    context "with ConfigManager signature" do
      it "returns true when passthrough has underlying service" do
        instance.set_provider_config("cursor", {type: "passthrough", underlying_service: "anthropic"})
        expect(instance.has_underlying_service?("cursor")).to be true
      end

      it "returns false when passthrough has no underlying service" do
        instance.set_provider_config("cursor", {type: "passthrough"})
        expect(instance.has_underlying_service?("cursor")).to be false
      end

      it "returns false for non-passthrough providers" do
        instance.set_provider_config("claude", {type: "subscription"})
        expect(instance.has_underlying_service?("claude")).to be false
      end

      it "handles string keys for underlying_service" do
        instance.set_provider_config("cursor", {:type => "passthrough", "underlying_service" => "openai"})
        expect(instance.has_underlying_service?("cursor")).to be true
      end
    end

    context "with ProviderConfig signature" do
      it "returns true when passthrough has underlying service" do
        expect(instance.has_underlying_service?({type: "passthrough", underlying_service: "anthropic"})).to be true
      end

      it "returns false when passthrough has empty underlying service" do
        expect(instance.has_underlying_service?({type: "passthrough", underlying_service: ""})).to be false
      end
    end
  end

  describe "#get_underlying_service" do
    context "with ConfigManager signature" do
      it "returns underlying service for passthrough provider" do
        instance.set_provider_config("cursor", {type: "passthrough", underlying_service: "anthropic"})
        expect(instance.get_underlying_service("cursor")).to eq("anthropic")
      end

      it "returns nil for non-passthrough provider" do
        instance.set_provider_config("claude", {type: "subscription"})
        expect(instance.get_underlying_service("claude")).to be_nil
      end

      it "handles string keys" do
        instance.set_provider_config("cursor", {:type => "passthrough", "underlying_service" => "openai"})
        expect(instance.get_underlying_service("cursor")).to eq("openai")
      end

      it "returns nil when no underlying service specified" do
        instance.set_provider_config("cursor", {type: "passthrough"})
        expect(instance.get_underlying_service("cursor")).to be_nil
      end
    end

    context "with ProviderConfig signature" do
      it "returns underlying service when specified" do
        expect(instance.get_underlying_service({type: "passthrough", underlying_service: "anthropic"})).to eq("anthropic")
      end

      it "returns nil for non-passthrough" do
        expect(instance.get_underlying_service({type: "subscription"})).to be_nil
      end
    end
  end

  describe "edge cases" do
    it "handles empty provider config" do
      instance.set_provider_config("test", {})
      expect(instance.usage_based_provider?("test")).to be false
      expect(instance.subscription_provider?("test")).to be true
    end

    it "handles nil provider config" do
      expect(instance.get_provider_type("nonexistent")).to eq("subscription")
    end

    it "handles both symbol and string provider names" do
      instance.set_provider_config("anthropic", {type: "usage_based"})
      instance.set_provider_config(:openai, {type: "usage_based"})

      expect(instance.usage_based_provider?("anthropic")).to be true
      expect(instance.usage_based_provider?(:openai)).to be true
    end
  end
end
