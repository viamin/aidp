#!/usr/bin/env ruby
# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Aidp::CLI::FirstRunWizard do
  let(:temp_dir) { Dir.mktmpdir }
  let(:test_prompt) { TestPrompt.new }

  after { FileUtils.rm_rf(temp_dir) }

  describe ".ensure_config" do
    context "when config exists" do
      it "returns true and does nothing" do
        # Create config in the correct location (.aidp/aidp.yml)
        FileUtils.mkdir_p(File.join(temp_dir, ".aidp"))
        File.write(File.join(temp_dir, ".aidp", "aidp.yml"), "harness: {}\n")
        result = described_class.ensure_config(temp_dir, prompt: test_prompt)
        expect(result).to be true
      end
    end

    context "non-interactive" do
      it "creates minimal config automatically" do
        result = described_class.ensure_config(temp_dir, non_interactive: true, prompt: test_prompt)
        expect(result).to be true
        config_path = File.join(temp_dir, ".aidp", "aidp.yml")
        expect(File.exist?(config_path)).to be true
        yaml = YAML.load_file(config_path)
        expect(yaml.dig(:harness, :default_provider) || yaml.dig("harness", "default_provider")).to eq("cursor")
        expect(test_prompt.messages.any? { |msg| msg[:message].include?("Created minimal configuration") }).to be true
      end
    end

    context "non-interactive with defaults" do
      it "creates minimal config automatically" do
        result = described_class.ensure_config(temp_dir, non_interactive: true, prompt: test_prompt)
        expect(result).to be true
        yaml = YAML.load_file(File.join(temp_dir, ".aidp", "aidp.yml"))
        harness = yaml["harness"] || yaml[:harness]
        expect(harness["default_provider"] || harness[:default_provider]).to eq("cursor")
      end
    end
  end
end
