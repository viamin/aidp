# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Init::Runner do
  let(:fake_prompt_class) do
    Class.new do
      def initialize(responses)
        @responses = responses.dup
      end

      def yes?(_question)
        if block_given?
          config = Object.new
          config.define_singleton_method(:default) { |_value| }
          yield config
        end
        @responses.shift
      end

      def say(_message, color: nil)
        nil
      end
    end
  end

  let(:analysis) do
    {
      languages: {"Ruby" => 100},
      frameworks: [],
      key_directories: ["lib"],
      config_files: [".editorconfig"],
      test_frameworks: [],
      tooling: [],
      repo_stats: {total_files: 1, total_directories: 1, docs_present: false, has_ci_config: false, has_containerization: false}
    }
  end

  let(:analysis_with_detections) do
    {
      languages: {"Ruby" => 1000},
      frameworks: [
        {name: "Rails", confidence: 0.9, evidence: ["Found files: config/application.rb", "Found pattern /rails/i in config/application.rb"]}
      ],
      key_directories: ["lib", "spec", "config"],
      config_files: [".rubocop.yml", "Gemfile"],
      test_frameworks: [
        {name: "RSpec", confidence: 0.8, evidence: ["Found directories: spec", "Found dependency pattern /rspec/ in Gemfile"]}
      ],
      tooling: [
        {tool: :rubocop, confidence: 0.8, evidence: ["Found config files: .rubocop.yml"]}
      ],
      repo_stats: {total_files: 10, total_directories: 5, docs_present: true, has_ci_config: true, has_containerization: false}
    }
  end

  let(:analyzer) { instance_double(Aidp::Init::ProjectAnalyzer) }
  let(:doc_generator) { instance_double(Aidp::Init::DocGenerator) }
  let(:devcontainer_generator) { instance_double(Aidp::Init::DevcontainerGenerator) }
  let(:prompt) { fake_prompt_class.new([true, false, true, false]) }

  before do
    allow(analyzer).to receive(:analyze).and_return(analysis)
    allow(doc_generator).to receive(:generate)
    allow(devcontainer_generator).to receive(:exists?).and_return(false)
  end

  it "runs analysis, gathers preferences, and generates docs" do
    runner = described_class.new("/tmp", prompt: prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator)
    result = runner.run

    expect(analyzer).to have_received(:analyze).with(explain_detection: nil)
    expect(doc_generator).to have_received(:generate).with(analysis: analysis, preferences: {
      adopt_new_conventions: true,
      stricter_linters: false,
      migrate_styles: true,
      generate_devcontainer: false
    })
    expect(result[:generated_files]).to include("docs/LLM_STYLE_GUIDE.md")
  end

  describe "with options" do
    it "passes explain_detection option to analyzer" do
      runner = described_class.new("/tmp", prompt: prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator, options: {explain_detection: true})
      runner.run

      expect(analyzer).to have_received(:analyze).with(explain_detection: true)
    end

    it "skips preferences and generation in dry_run mode" do
      runner = described_class.new("/tmp", prompt: prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator, options: {dry_run: true})
      result = runner.run

      expect(doc_generator).not_to have_received(:generate)
      expect(result[:generated_files]).to be_empty
    end
  end

  describe "display formatting" do
    before do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)
    end

    it "displays high-confidence frameworks" do
      runner = described_class.new("/tmp", prompt: prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator)
      # Just verify it runs without error - actual display testing would require capturing output
      expect { runner.run }.not_to raise_error
    end
  end
end
