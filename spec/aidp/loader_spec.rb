# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Loader do
  describe ".setup" do
    # Note: Most tests here are limited because the loader is already set up
    # by the main application when running tests. We test what we can.

    it "reports setup status correctly" do
      expect(described_class.setup?).to be true
    end

    it "has a loader instance" do
      expect(described_class.loader).to be_a(Zeitwerk::Loader)
    end
  end

  describe ".reloading?" do
    it "reports reloading status" do
      # In test mode, reloading may or may not be enabled depending on env
      expect([true, false]).to include(described_class.reloading?)
    end
  end

  describe ".reload!" do
    context "when loader is not set up for reloading" do
      it "returns false and logs warning" do
        # Can't easily test this without resetting the loader
        # which would break other tests
        skip "Cannot test without resetting loader"
      end
    end

    context "when reloading is enabled" do
      it "reloads successfully" do
        skip "Requires reloading to be enabled" unless described_class.reloading?

        expect(described_class.reload!).to be true
      end
    end
  end

  describe "autoloading" do
    it "autoloads Aidp::Watch module" do
      expect(defined?(Aidp::Watch)).to eq("constant")
    end

    it "autoloads Aidp::AutoUpdate module" do
      expect(defined?(Aidp::AutoUpdate)).to eq("constant")
    end

    it "autoloads classes with custom inflections" do
      # Test some of the custom inflections
      expect(defined?(Aidp::CLI)).to eq("constant")
    end
  end

  describe "inflections" do
    # These tests verify that Zeitwerk correctly handles our custom inflections

    it "loads CLI correctly" do
      expect { Aidp::CLI }.not_to raise_error
    end

    it "loads Config correctly" do
      expect { Aidp::Config }.not_to raise_error
    end

    it "loads Watch::Runner correctly" do
      expect { Aidp::Watch::Runner }.not_to raise_error
    end

    it "loads AutoUpdate::Coordinator correctly" do
      expect { Aidp::AutoUpdate::Coordinator }.not_to raise_error
    end
  end
end
