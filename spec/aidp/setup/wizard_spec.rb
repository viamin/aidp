# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Setup::Wizard do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:prompt) { TestPrompt.new(responses: {ask: "", yes?: false, multi_select: []}) }

  before do
    FileUtils.mkdir_p(tmp_dir)
    File.write(File.join(tmp_dir, "Gemfile"), "source 'https://rubygems.org'")
    allow(Aidp::Util).to receive(:which).and_return("/usr/bin/fake")
  end

  after { FileUtils.rm_rf(tmp_dir) }

  it "runs in dry run mode without writing" do
    wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
    expect(wizard.run).to be true
    expect(File).not_to exist(File.join(tmp_dir, ".aidp", "aidp.yml"))
  end

  it "generates yaml with helpful comments" do
    wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
    wizard.run
    yaml = wizard.send(:generate_yaml)
    expect(yaml).to include("# Provider configuration")
    expect(yaml).to include("schema_version:")
  end

  it "produces unified diff when existing config differs" do
    config_dir = Aidp::ConfigPaths.config_dir(tmp_dir)
    FileUtils.mkdir_p(config_dir)
    File.write(Aidp::ConfigPaths.config_file(tmp_dir), "schema_version: 1\nproviders:\n  llm:\n    name: cursor\n")

    wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
    yaml = wizard.send(:generate_yaml)
    diff = wizard.send(:line_diff, File.read(Aidp::ConfigPaths.config_file(tmp_dir)), yaml)
    expect(diff.any? { |line| line.start_with?("+") }).to be true
  end
end
