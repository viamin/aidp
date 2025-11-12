# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/auto_update"

RSpec.describe Aidp::AutoUpdate::VersionDetector do
  let(:policy) do
    Aidp::AutoUpdate::UpdatePolicy.new(
      enabled: true,
      policy: "minor",
      allow_prerelease: false
    )
  end

  describe "#check_for_update" do
    context "with policy: off" do
      it "returns update_allowed: false even when update available" do
        off_policy = Aidp::AutoUpdate::UpdatePolicy.new(enabled: true, policy: "off")
        bundler = instance_double(Aidp::AutoUpdate::BundlerAdapter,
          latest_version_for: Gem::Version.new("0.25.0"))

        detector = described_class.new(
          current_version: "0.24.0",
          policy: off_policy,
          bundler_adapter: bundler
        )

        result = detector.check_for_update

        expect(result.update_available).to be true
        expect(result.update_allowed).to be false
        expect(result.policy_reason).to include("disabled")
      end
    end

    context "with policy: patch" do
      it "allows patch updates (0.24.0 -> 0.24.1)" do
        patch_policy = Aidp::AutoUpdate::UpdatePolicy.new(enabled: true, policy: "patch")
        bundler = instance_double(Aidp::AutoUpdate::BundlerAdapter,
          latest_version_for: Gem::Version.new("0.24.1"))

        detector = described_class.new(
          current_version: "0.24.0",
          policy: patch_policy,
          bundler_adapter: bundler
        )

        result = detector.check_for_update

        expect(result.update_allowed).to be true
      end

      it "blocks minor updates (0.24.0 -> 0.25.0)" do
        patch_policy = Aidp::AutoUpdate::UpdatePolicy.new(enabled: true, policy: "patch")
        bundler = instance_double(Aidp::AutoUpdate::BundlerAdapter,
          latest_version_for: Gem::Version.new("0.25.0"))

        detector = described_class.new(
          current_version: "0.24.0",
          policy: patch_policy,
          bundler_adapter: bundler
        )

        result = detector.check_for_update

        expect(result.update_allowed).to be false
        expect(result.policy_reason).to include("Minor")
      end
    end

    context "with policy: minor" do
      it "allows minor updates (0.24.0 -> 0.25.0)" do
        minor_policy = Aidp::AutoUpdate::UpdatePolicy.new(enabled: true, policy: "minor")
        bundler = instance_double(Aidp::AutoUpdate::BundlerAdapter,
          latest_version_for: Gem::Version.new("0.25.0"))

        detector = described_class.new(
          current_version: "0.24.0",
          policy: minor_policy,
          bundler_adapter: bundler
        )

        result = detector.check_for_update

        expect(result.update_allowed).to be true
      end

      it "blocks major updates (0.24.0 -> 1.0.0)" do
        minor_policy = Aidp::AutoUpdate::UpdatePolicy.new(enabled: true, policy: "minor")
        bundler = instance_double(Aidp::AutoUpdate::BundlerAdapter,
          latest_version_for: Gem::Version.new("1.0.0"))

        detector = described_class.new(
          current_version: "0.24.0",
          policy: minor_policy,
          bundler_adapter: bundler
        )

        result = detector.check_for_update

        expect(result.update_allowed).to be false
        expect(result.policy_reason).to include("Major")
      end
    end

    context "with policy: major" do
      it "allows major updates (0.24.0 -> 1.0.0)" do
        major_policy = Aidp::AutoUpdate::UpdatePolicy.new(enabled: true, policy: "major")
        bundler = instance_double(Aidp::AutoUpdate::BundlerAdapter,
          latest_version_for: Gem::Version.new("1.0.0"))

        detector = described_class.new(
          current_version: "0.24.0",
          policy: major_policy,
          bundler_adapter: bundler
        )

        result = detector.check_for_update

        expect(result.update_allowed).to be true
      end
    end

    context "with allow_prerelease: false" do
      it "excludes prerelease versions" do
        policy = Aidp::AutoUpdate::UpdatePolicy.new(
          enabled: true,
          policy: "minor",
          allow_prerelease: false
        )
        # Bundler returns stable version
        bundler = instance_double(Aidp::AutoUpdate::BundlerAdapter,
          latest_version_for: Gem::Version.new("0.25.0"))

        detector = described_class.new(
          current_version: "0.24.0",
          policy: policy,
          bundler_adapter: bundler
        )

        result = detector.check_for_update

        expect(result.available_version).to eq("0.25.0")
        expect(result.update_allowed).to be true
      end
    end
  end
end
