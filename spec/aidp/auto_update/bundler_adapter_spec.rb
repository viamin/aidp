# frozen_string_literal: true

require "spec_helper"
require "aidp/auto_update/bundler_adapter"

RSpec.describe Aidp::AutoUpdate::BundlerAdapter do
  let(:adapter) { described_class.new }

  describe "#latest_version_for" do
    let(:gem_name) { "aidp" }

    context "when bundle outdated succeeds" do
      it "parses and returns the newest version" do
        stdout = "aidp (newest 0.25.0, installed 0.24.0, requested >= 0)\n"
        allow(Open3).to receive(:capture3)
          .with("mise", "exec", "--", "bundle", "outdated", gem_name, "--parseable")
          .and_return([stdout, "", instance_double(Process::Status, success?: true)])

        result = adapter.latest_version_for(gem_name)

        expect(result).to eq(Gem::Version.new("0.25.0"))
      end

      it "returns nil when gem is not outdated" do
        stdout = ""
        allow(Open3).to receive(:capture3)
          .with("mise", "exec", "--", "bundle", "outdated", gem_name, "--parseable")
          .and_return([stdout, "", instance_double(Process::Status, success?: true)])

        result = adapter.latest_version_for(gem_name)

        expect(result).to be_nil
      end

      it "handles version strings with pre-release tags" do
        stdout = "aidp (newest 0.26.0-beta.1, installed 0.25.0)\n"
        allow(Open3).to receive(:capture3)
          .with("mise", "exec", "--", "bundle", "outdated", gem_name, "--parseable")
          .and_return([stdout, "", instance_double(Process::Status, success?: true)])

        result = adapter.latest_version_for(gem_name)

        expect(result).to eq(Gem::Version.new("0.26.0.pre.beta.1"))
      end
    end

    context "when bundle outdated fails" do
      it "returns nil and logs the error" do
        stderr = "Could not find gem 'aidp'"
        allow(Open3).to receive(:capture3)
          .with("mise", "exec", "--", "bundle", "outdated", gem_name, "--parseable")
          .and_return(["", stderr, instance_double(Process::Status, success?: false)])

        expect(Aidp).to receive(:log_debug).with("bundler_adapter", "checking_gem_version", gem: gem_name)
        expect(Aidp).to receive(:log_debug).with("bundler_adapter", "bundle_outdated_failed",
          gem: gem_name,
          stderr: stderr.strip)

        result = adapter.latest_version_for(gem_name)

        expect(result).to be_nil
      end
    end

    context "when an exception occurs" do
      it "rescues and returns nil" do
        allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "mise not found")

        expect(Aidp).to receive(:log_debug).with("bundler_adapter", "checking_gem_version", gem: gem_name)
        expect(Aidp).to receive(:log_error).with("bundler_adapter", "version_check_failed",
          gem: gem_name,
          error: "No such file or directory - mise not found")

        result = adapter.latest_version_for(gem_name)

        expect(result).to be_nil
      end
    end
  end

  describe "#parse_bundle_outdated (private)" do
    let(:gem_name) { "aidp" }

    it "extracts version from standard output" do
      output = "aidp (newest 1.2.3, installed 1.2.0)\n"
      result = adapter.send(:parse_bundle_outdated, output, gem_name)
      expect(result).to eq(Gem::Version.new("1.2.3"))
    end

    it "returns nil when gem line is not found" do
      output = "other-gem (newest 2.0.0, installed 1.0.0)\n"
      result = adapter.send(:parse_bundle_outdated, output, gem_name)
      expect(result).to be_nil
    end

    it "handles version strings without 'newest' keyword" do
      output = "aidp (installed 1.0.0)\n"
      result = adapter.send(:parse_bundle_outdated, output, gem_name)
      expect(result).to be_nil
    end

    it "handles multiple lines of output" do
      output = <<~OUTPUT
        other-gem (newest 2.0.0, installed 1.0.0)
        aidp (newest 0.30.0, installed 0.25.0)
        another-gem (newest 3.0.0, installed 2.0.0)
      OUTPUT

      result = adapter.send(:parse_bundle_outdated, output, gem_name)
      expect(result).to eq(Gem::Version.new("0.30.0"))
    end
  end
end
