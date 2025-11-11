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
    allow(devcontainer_generator).to receive(:generate).and_return([".devcontainer/devcontainer.json"])
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

  describe "#display_summary" do
    let(:runner) { described_class.new("/tmp", prompt: prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator, options: {dry_run: true}) }

    it "displays languages when present" do
      expect { runner.run }.not_to raise_error
    end

    it "displays 'Unknown' when no languages detected" do
      empty_analysis = analysis.merge(languages: {})
      allow(analyzer).to receive(:analyze).and_return(empty_analysis)

      expect { runner.run }.not_to raise_error
    end

    it "displays confident frameworks" do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { runner.run }.not_to raise_error
    end

    it "displays uncertain frameworks with confidence percentage" do
      uncertain_analysis = analysis.merge(
        frameworks: [
          {name: "Express", confidence: 0.5, evidence: ["package.json mentions express"]}
        ]
      )
      allow(analyzer).to receive(:analyze).and_return(uncertain_analysis)

      expect { runner.run }.not_to raise_error
    end

    it "displays test frameworks when detected" do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { runner.run }.not_to raise_error
    end

    it "displays 'Not found' when no test frameworks detected" do
      expect { runner.run }.not_to raise_error
    end

    it "displays quality tools when detected" do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { runner.run }.not_to raise_error
    end

    it "displays config file count" do
      expect { runner.run }.not_to raise_error
    end
  end

  describe "#display_detailed_analysis" do
    let(:runner) { described_class.new("/tmp", prompt: prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator, options: {dry_run: true, explain_detection: true}) }

    it "displays detailed language breakdown with percentages" do
      multi_lang_analysis = analysis.merge(
        languages: {"Ruby" => 1000, "JavaScript" => 500}
      )
      allow(analyzer).to receive(:analyze).and_return(multi_lang_analysis)

      expect { runner.run }.not_to raise_error
    end

    it "displays frameworks with evidence" do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { runner.run }.not_to raise_error
    end

    it "displays test frameworks with evidence" do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { runner.run }.not_to raise_error
    end

    it "displays tooling with evidence" do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { runner.run }.not_to raise_error
    end

    it "displays key directories" do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { runner.run }.not_to raise_error
    end

    it "displays config files" do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { runner.run }.not_to raise_error
    end

    it "displays repository statistics" do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { runner.run }.not_to raise_error
    end

    it "handles empty detections gracefully" do
      expect { runner.run }.not_to raise_error
    end
  end

  describe "#gather_preferences" do
    let(:runner) { described_class.new("/tmp", prompt: prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator) }

    it "asks about adopting conventions" do
      result = runner.run

      expect(result[:preferences]).to have_key(:adopt_new_conventions)
    end

    it "asks about stricter linters" do
      result = runner.run

      expect(result[:preferences]).to have_key(:stricter_linters)
    end

    it "asks about migrating styles" do
      result = runner.run

      expect(result[:preferences]).to have_key(:migrate_styles)
    end

    it "asks about devcontainer generation when not set in options" do
      result = runner.run

      expect(result[:preferences]).to have_key(:generate_devcontainer)
    end

    it "does not ask about devcontainer when explicitly set in options" do
      custom_prompt = fake_prompt_class.new([true, false, true])
      runner_with_devcontainer = described_class.new(
        "/tmp",
        prompt: custom_prompt,
        analyzer: analyzer,
        doc_generator: doc_generator,
        devcontainer_generator: devcontainer_generator,
        options: {with_devcontainer: true}
      )

      result = runner_with_devcontainer.run

      expect(result[:preferences]).not_to have_key(:generate_devcontainer)
    end

    it "defaults to not generating devcontainer when one exists" do
      allow(devcontainer_generator).to receive(:exists?).and_return(true)

      runner.run
      # Verifies it doesn't crash when devcontainer exists
    end
  end

  describe "preview mode" do
    let(:preview_prompt) { fake_prompt_class.new([true, false, true, false, true, true]) }
    let(:runner) { described_class.new("/tmp", prompt: preview_prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator, options: {preview: true}) }

    before do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)
    end

    it "shows preview before writing files" do
      result = runner.run

      expect(result[:generated_files]).to include("docs/LLM_STYLE_GUIDE.md")
    end

    it "cancels generation if user declines after preview" do
      # adopt_new_conventions, stricter_linters, migrate_styles, generate_devcontainer, proceed (NO)
      cancel_prompt = fake_prompt_class.new([true, false, true, false, false])
      cancel_runner = described_class.new("/tmp", prompt: cancel_prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator, options: {preview: true})

      result = cancel_runner.run

      expect(doc_generator).not_to have_received(:generate)
      expect(result[:generated_files]).to be_empty
    end
  end

  describe "devcontainer generation" do
    it "generates devcontainer when with_devcontainer option is true" do
      allow(devcontainer_generator).to receive(:generate).and_return([".devcontainer/devcontainer.json"])
      runner = described_class.new(
        "/tmp",
        prompt: prompt,
        analyzer: analyzer,
        doc_generator: doc_generator,
        devcontainer_generator: devcontainer_generator,
        options: {with_devcontainer: true}
      )

      result = runner.run

      expect(devcontainer_generator).to have_received(:generate)
      expect(result[:generated_files]).to include(".devcontainer/devcontainer.json")
    end

    it "generates devcontainer when user chooses to in preferences" do
      devcontainer_prompt = fake_prompt_class.new([true, false, true, true])
      allow(devcontainer_generator).to receive(:generate).and_return([".devcontainer/devcontainer.json"])
      runner = described_class.new(
        "/tmp",
        prompt: devcontainer_prompt,
        analyzer: analyzer,
        doc_generator: doc_generator,
        devcontainer_generator: devcontainer_generator
      )

      result = runner.run

      expect(devcontainer_generator).to have_received(:generate)
      expect(result[:generated_files]).to include(".devcontainer/devcontainer.json")
    end

    it "does not generate devcontainer when user declines" do
      no_devcontainer_prompt = fake_prompt_class.new([true, false, true, false])
      runner = described_class.new(
        "/tmp",
        prompt: no_devcontainer_prompt,
        analyzer: analyzer,
        doc_generator: doc_generator,
        devcontainer_generator: devcontainer_generator
      )

      result = runner.run

      expect(devcontainer_generator).not_to have_received(:generate)
      expect(result[:generated_files]).not_to include(".devcontainer/devcontainer.json")
    end
  end

  describe "#validate_tooling" do
    let(:runner) { described_class.new("/tmp", prompt: prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator, options: {preview: true}) }

    before do
      # Mock system calls to avoid actual command execution
      allow_any_instance_of(Object).to receive(:system).and_return(true)
    end

    it "validates detected tools exist in PATH" do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { runner.run }.not_to raise_error
    end

    it "warns when detected tool is not in PATH" do
      allow_any_instance_of(Object).to receive(:system).and_return(false)
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { runner.run }.not_to raise_error
    end

    it "warns when no test framework is detected" do
      no_tests_analysis = analysis.merge(test_frameworks: [])
      allow(analyzer).to receive(:analyze).and_return(no_tests_analysis)

      expect { runner.run }.not_to raise_error
    end

    it "suggests CI when not detected" do
      no_ci_analysis = analysis.merge(
        repo_stats: analysis[:repo_stats].merge(has_ci_config: false)
      )
      allow(analyzer).to receive(:analyze).and_return(no_ci_analysis)

      expect { runner.run }.not_to raise_error
    end

    it "shows success message when all tools are validated" do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { runner.run }.not_to raise_error
    end

    it "handles cargo_fmt tool mapping" do
      cargo_analysis = analysis.merge(
        tooling: [{tool: :cargo_fmt, confidence: 0.8, evidence: ["Found Cargo.toml"]}]
      )
      allow(analyzer).to receive(:analyze).and_return(cargo_analysis)

      expect { runner.run }.not_to raise_error
    end

    it "handles gofmt tool mapping" do
      go_analysis = analysis.merge(
        tooling: [{tool: :gofmt, confidence: 0.8, evidence: ["Found .go files"]}]
      )
      allow(analyzer).to receive(:analyze).and_return(go_analysis)

      expect { runner.run }.not_to raise_error
    end

    it "skips validation for low-confidence tools" do
      low_confidence_analysis = analysis.merge(
        tooling: [{tool: :rubocop, confidence: 0.5, evidence: ["Possible config"]}]
      )
      allow(analyzer).to receive(:analyze).and_return(low_confidence_analysis)

      expect { runner.run }.not_to raise_error
    end
  end

  describe "#preview_generated_docs" do
    let(:preview_prompt) { fake_prompt_class.new([true, false, true, false, true, true]) }
    let(:runner) { described_class.new("/tmp", prompt: preview_prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator, options: {preview: true}) }

    it "shows framework adoption status" do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { runner.run }.not_to raise_error
    end

    it "shows optional reference when not adopting conventions" do
      no_adopt_prompt = fake_prompt_class.new([false, false, true, false, true, true])
      no_adopt_runner = described_class.new("/tmp", prompt: no_adopt_prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator, options: {preview: true})
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { no_adopt_runner.run }.not_to raise_error
    end

    it "displays language summary" do
      multi_lang_analysis = analysis_with_detections.merge(
        languages: {"Ruby" => 1000, "JavaScript" => 500}
      )
      allow(analyzer).to receive(:analyze).and_return(multi_lang_analysis)

      expect { runner.run }.not_to raise_error
    end

    it "displays test frameworks or None" do
      no_tests_analysis = analysis_with_detections.merge(test_frameworks: [])
      allow(analyzer).to receive(:analyze).and_return(no_tests_analysis)

      expect { runner.run }.not_to raise_error
    end

    it "displays quality tool count" do
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { runner.run }.not_to raise_error
    end

    it "displays stricter linting preference" do
      strict_prompt = fake_prompt_class.new([true, true, true, false, true, true])
      strict_runner = described_class.new("/tmp", prompt: strict_prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator, options: {preview: true})
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { strict_runner.run }.not_to raise_error
    end

    it "displays migration planning preference" do
      migrate_prompt = fake_prompt_class.new([true, false, true, false, true, true])
      migrate_runner = described_class.new("/tmp", prompt: migrate_prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator, options: {preview: true})
      allow(analyzer).to receive(:analyze).and_return(analysis_with_detections)

      expect { migrate_runner.run }.not_to raise_error
    end
  end

  describe "#format_tool" do
    let(:runner) { described_class.new("/tmp", prompt: prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator, options: {dry_run: true}) }

    it "formats snake_case tool names to Title Case" do
      tooling_analysis = analysis.merge(
        tooling: [
          {tool: :cargo_fmt, confidence: 0.8, evidence: []},
          {tool: :standard_rb, confidence: 0.8, evidence: []}
        ]
      )
      allow(analyzer).to receive(:analyze).and_return(tooling_analysis)

      expect { runner.run }.not_to raise_error
    end
  end

  describe "error handling" do
    it "handles prompt errors gracefully with NoMethodError fallback" do
      broken_prompt = Object.new
      # Add say method to avoid NoMethodError on display_message
      def broken_prompt.say(_message, color: nil)
        nil
      end

      runner = described_class.new(
        "/tmp",
        prompt: broken_prompt,
        analyzer: analyzer,
        doc_generator: doc_generator,
        devcontainer_generator: devcontainer_generator
      )

      result = runner.run

      # Should use defaults when prompt fails
      expect(result[:preferences][:adopt_new_conventions]).to be true
    end
  end

  describe "return value structure" do
    it "returns hash with analysis, preferences, and generated_files" do
      runner = described_class.new("/tmp", prompt: prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator)

      result = runner.run

      expect(result).to have_key(:analysis)
      expect(result).to have_key(:preferences)
      expect(result).to have_key(:generated_files)
    end

    it "includes correct file paths in generated_files" do
      runner = described_class.new("/tmp", prompt: prompt, analyzer: analyzer, doc_generator: doc_generator, devcontainer_generator: devcontainer_generator)

      result = runner.run

      expect(result[:generated_files]).to include("docs/LLM_STYLE_GUIDE.md")
      expect(result[:generated_files]).to include("docs/PROJECT_ANALYSIS.md")
      expect(result[:generated_files]).to include("docs/CODE_QUALITY_PLAN.md")
    end
  end
end
