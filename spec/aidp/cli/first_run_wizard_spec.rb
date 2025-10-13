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
        expect(yaml["schema_version"]).to eq(Aidp::Setup::Wizard::SCHEMA_VERSION)
        expect(yaml.dig("providers", "llm", "name")).to eq("cursor")
        expect(test_prompt.messages.any? { |msg| msg[:message].include?("Created minimal configuration") }).to be true
      end
    end

    context "interactive" do
      it "invokes the setup wizard" do
        wizard = instance_double(Aidp::Setup::Wizard)
        expect(Aidp::Setup::Wizard).to receive(:new)
          .with(temp_dir, prompt: test_prompt)
          .and_return(wizard)
        expect(wizard).to receive(:run).and_return(true)

        described_class.ensure_config(temp_dir, prompt: test_prompt)
      end
    end
  end

  describe ".setup_config" do
    it "runs the wizard interactively" do
      wizard = instance_double(Aidp::Setup::Wizard)
      expect(Aidp::Setup::Wizard).to receive(:new)
        .with(temp_dir, prompt: test_prompt)
        .and_return(wizard)
      expect(wizard).to receive(:run).and_return(true)

      described_class.setup_config(temp_dir, prompt: test_prompt)
    end

    it "skips in non-interactive mode" do
      expect(described_class.setup_config(temp_dir, non_interactive: true, prompt: test_prompt)).to be true
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("skipped") }).to be true
    end
  end
end
