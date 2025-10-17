# frozen_string_literal: true

require "spec_helper"
require "aidp/providers/opencode"

RSpec.describe Aidp::Providers::Opencode do
  let(:provider) { described_class.new }

  describe ".available?" do
    it "returns false if opencode binary missing" do
      allow(Aidp::Util).to receive(:which).with("opencode").and_return(nil)
      expect(described_class.available?).to be false
    end

    it "returns true if opencode binary found" do
      allow(Aidp::Util).to receive(:which).with("opencode").and_return("/usr/local/bin/opencode")
      expect(described_class.available?).to be true
    end
  end

  describe "basic attributes" do
    it "has name and display_name" do
      expect(provider.name).to eq("opencode")
      expect(provider.display_name).to eq("OpenCode")
    end
  end

  describe "timeout calculation" do
    before do
      allow(provider).to receive(:display_message) # silence output
    end

    it "uses quick mode timeout when AIDP_QUICK_MODE set" do
      stub_const("Aidp::Providers::TIMEOUT_QUICK_MODE", 30)
      stub_const("Aidp::Providers::TIMEOUT_DEFAULT", 600)
      ENV["AIDP_QUICK_MODE"] = "1"
      expect(provider.__send__(:calculate_timeout)).to eq(30)
      ENV.delete("AIDP_QUICK_MODE")
    end

    it "uses env override timeout when set" do
      stub_const("Aidp::Providers::TIMEOUT_DEFAULT", 600)
      ENV["AIDP_OPENCODE_TIMEOUT"] = "42"
      expect(provider.__send__(:calculate_timeout)).to eq(42)
      ENV.delete("AIDP_OPENCODE_TIMEOUT")
    end

    it "falls back to default timeout" do
      stub_const("Aidp::Providers::TIMEOUT_DEFAULT", 600)
      expect(provider.__send__(:calculate_timeout)).to eq(600)
    end
  end

  describe "adaptive timeout" do
    before do
      stub_const("Aidp::Providers::TIMEOUT_REPOSITORY_ANALYSIS", 100)
      stub_const("Aidp::Providers::TIMEOUT_ARCHITECTURE_ANALYSIS", 200)
      stub_const("Aidp::Providers::TIMEOUT_TEST_ANALYSIS", 300)
      stub_const("Aidp::Providers::TIMEOUT_FUNCTIONALITY_ANALYSIS", 400)
      stub_const("Aidp::Providers::TIMEOUT_DOCUMENTATION_ANALYSIS", 500)
      stub_const("Aidp::Providers::TIMEOUT_STATIC_ANALYSIS", 600)
      stub_const("Aidp::Providers::TIMEOUT_REFACTORING_RECOMMENDATIONS", 700)
    end

    it "returns repository analysis timeout" do
      ENV["AIDP_CURRENT_STEP"] = "REPOSITORY_ANALYSIS"
      expect(provider.__send__(:adaptive_timeout)).to eq(100)
      ENV.delete("AIDP_CURRENT_STEP")
    end

    it "returns architecture analysis timeout" do
      ENV["AIDP_CURRENT_STEP"] = "ARCHITECTURE_ANALYSIS"
      expect(provider.__send__(:adaptive_timeout)).to eq(200)
      ENV.delete("AIDP_CURRENT_STEP")
    end

    it "returns test analysis timeout" do
      ENV["AIDP_CURRENT_STEP"] = "TEST_ANALYSIS"
      expect(provider.__send__(:adaptive_timeout)).to eq(300)
      ENV.delete("AIDP_CURRENT_STEP")
    end

    it "returns nil for unknown step" do
      ENV["AIDP_CURRENT_STEP"] = "UNKNOWN_STEP"
      expect(provider.__send__(:adaptive_timeout)).to be_nil
      ENV.delete("AIDP_CURRENT_STEP")
    end
  end

  describe "activity callbacks" do
    it "transitions states" do
      allow(provider).to receive(:display_message)
      provider.__send__(:setup_activity_monitoring, "opencode", provider.method(:activity_callback))
      provider.__send__(:record_activity, "start")
      provider.__send__(:mark_completed)
      expect(provider.instance_variable_get(:@activity_state)).to eq(:completed)
    end
  end
end
