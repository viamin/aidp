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
      tooling: {},
      repo_stats: {total_files: 1, total_directories: 1, docs_present: false, has_ci_config: false, has_containerization: false}
    }
  end

  let(:analyzer) { instance_double(Aidp::Init::ProjectAnalyzer, analyze: analysis) }
  let(:doc_generator) { instance_double(Aidp::Init::DocGenerator) }
  let(:prompt) { fake_prompt_class.new([true, false, true]) }

  before do
    allow(doc_generator).to receive(:generate)
  end

  it "runs analysis, gathers preferences, and generates docs" do
    runner = described_class.new("/tmp", prompt: prompt, analyzer: analyzer, doc_generator: doc_generator)
    result = runner.run

    expect(analyzer).to have_received(:analyze)
    expect(doc_generator).to have_received(:generate).with(analysis: analysis, preferences: {
      adopt_new_conventions: true,
      stricter_linters: false,
      migrate_styles: true
    })
    expect(result[:generated_files]).to include("docs/LLM_STYLE_GUIDE.md")
  end
end
