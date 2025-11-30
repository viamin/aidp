# frozen_string_literal: true

RSpec.describe Aidp::Harness::AIFilterFactory do
  let(:mock_provider_factory) { instance_double(Aidp::Harness::ProviderFactory) }
  let(:mock_provider) { instance_double("Provider") }
  let(:mock_config) do
    instance_double("Config",
      default_provider: "anthropic",
      respond_to?: true)
  end

  let(:valid_ai_response) do
    <<~JSON
      {
        "tool_name": "pytest",
        "summary_patterns": ["\\\\d+ passed", "\\\\d+ failed"],
        "failure_section_start": "=+ FAILURES =+",
        "failure_section_end": "=+ short test summary",
        "error_section_start": null,
        "error_section_end": null,
        "error_patterns": ["AssertionError", "Error:"],
        "location_patterns": ["([\\\\w/]+\\\\.py:\\\\d+)"],
        "noise_patterns": ["^platform ", "^cachedir:"],
        "important_patterns": ["assert\\\\s+"]
      }
    JSON
  end

  before do
    allow(mock_provider_factory).to receive(:create_provider).and_return(mock_provider)
    allow(mock_provider).to receive(:send_message).and_return(valid_ai_response)

    # Mock ThinkingDepthManager
    thinking_manager = instance_double(Aidp::Harness::ThinkingDepthManager)
    allow(Aidp::Harness::ThinkingDepthManager).to receive(:new).and_return(thinking_manager)
    allow(thinking_manager).to receive(:select_model_for_tier).and_return(["anthropic", "claude-3-haiku", {}])
  end

  describe "#initialize" do
    it "accepts configuration and optional provider factory" do
      factory = described_class.new(mock_config, provider_factory: mock_provider_factory)

      expect(factory.config).to eq(mock_config)
      expect(factory.provider_factory).to eq(mock_provider_factory)
    end
  end

  describe "#generate_filter" do
    let(:factory) { described_class.new(mock_config, provider_factory: mock_provider_factory) }

    it "generates a FilterDefinition from AI response" do
      definition = factory.generate_filter(
        tool_name: "pytest",
        tool_command: "pytest -v",
        sample_output: "test output",
        tier: "mini"
      )

      expect(definition).to be_a(Aidp::Harness::FilterDefinition)
      expect(definition.tool_name).to eq("pytest")
      expect(definition.summary_patterns).not_to be_empty
      expect(definition.has_failure_section?).to be true
    end

    it "passes the correct prompt to AI" do
      expect(mock_provider).to receive(:send_message) do |args|
        expect(args[:prompt]).to include("pytest")
        expect(args[:prompt]).to include("pytest -v")
        expect(args[:prompt]).to include("sample output")
        valid_ai_response
      end

      factory.generate_filter(
        tool_name: "pytest",
        tool_command: "pytest -v",
        sample_output: "sample output",
        tier: "mini"
      )
    end

    it "handles missing sample_output gracefully" do
      expect(mock_provider).to receive(:send_message) do |args|
        expect(args[:prompt]).to include("No sample output provided")
        valid_ai_response
      end

      definition = factory.generate_filter(
        tool_name: "pytest",
        tool_command: "pytest -v",
        sample_output: nil,
        tier: "mini"
      )

      expect(definition).to be_a(Aidp::Harness::FilterDefinition)
    end

    it "truncates very long sample output" do
      long_output = "x" * 10_000

      expect(mock_provider).to receive(:send_message) do |args|
        expect(args[:prompt]).to include("[truncated]")
        expect(args[:prompt].length).to be < 15_000
        valid_ai_response
      end

      factory.generate_filter(
        tool_name: "pytest",
        tool_command: "pytest -v",
        sample_output: long_output,
        tier: "mini"
      )
    end

    context "when AI returns invalid JSON" do
      it "raises GenerationError" do
        allow(mock_provider).to receive(:send_message).and_return("not valid json at all")

        expect {
          factory.generate_filter(
            tool_name: "pytest",
            tool_command: "pytest -v",
            tier: "mini"
          )
        }.to raise_error(Aidp::Harness::GenerationError, /No JSON found/)
      end
    end

    context "when AI returns invalid regex patterns" do
      it "raises GenerationError" do
        invalid_response = '{"tool_name": "test", "summary_patterns": ["[invalid regex"]}'
        allow(mock_provider).to receive(:send_message).and_return(invalid_response)

        expect {
          factory.generate_filter(
            tool_name: "test",
            tool_command: "test",
            tier: "mini"
          )
        }.to raise_error(Aidp::Harness::GenerationError, /Invalid regex/)
      end
    end

    context "when AI returns response without summary_patterns" do
      it "raises GenerationError" do
        no_summary_response = '{"tool_name": "test", "summary_patterns": []}'
        allow(mock_provider).to receive(:send_message).and_return(no_summary_response)

        expect {
          factory.generate_filter(
            tool_name: "test",
            tool_command: "test",
            tier: "mini"
          )
        }.to raise_error(Aidp::Harness::GenerationError, /No summary patterns/)
      end
    end

    context "when AI call fails" do
      it "raises GenerationError with context" do
        allow(mock_provider).to receive(:send_message).and_raise(StandardError.new("API error"))

        expect {
          factory.generate_filter(
            tool_name: "pytest",
            tool_command: "pytest -v",
            tier: "mini"
          )
        }.to raise_error(Aidp::Harness::GenerationError, /Failed to generate filter for pytest/)
      end
    end
  end

  describe "#generate_from_command" do
    let(:factory) { described_class.new(mock_config, provider_factory: mock_provider_factory) }

    before do
      allow(factory).to receive(:capture_sample_output).and_return("sample output")
    end

    it "extracts tool name from command" do
      expect(factory).to receive(:generate_filter).with(
        tool_name: "pytest",
        tool_command: "pytest -v tests/",
        sample_output: anything,
        tier: "mini"
      ).and_call_original

      factory.generate_from_command(
        tool_command: "pytest -v tests/",
        project_dir: Dir.pwd,
        tier: "mini"
      )
    end

    it "strips common prefixes from tool name" do
      expect(factory).to receive(:generate_filter).with(
        tool_name: "rspec",
        tool_command: "bundle exec rspec",
        sample_output: anything,
        tier: "mini"
      ).and_call_original

      factory.generate_from_command(
        tool_command: "bundle exec rspec",
        project_dir: Dir.pwd,
        tier: "mini"
      )
    end

    it "handles npm run commands" do
      expect(factory).to receive(:generate_filter).with(
        tool_name: "test",
        tool_command: "npm run test",
        sample_output: anything,
        tier: "mini"
      ).and_call_original

      factory.generate_from_command(
        tool_command: "npm run test",
        project_dir: Dir.pwd,
        tier: "mini"
      )
    end
  end

  describe "GENERATION_PROMPT" do
    it "includes placeholders for tool information" do
      prompt = described_class::GENERATION_PROMPT

      expect(prompt).to include("{{tool_name}}")
      expect(prompt).to include("{{tool_command}}")
      expect(prompt).to include("{{sample_output}}")
    end

    it "requests JSON response format" do
      prompt = described_class::GENERATION_PROMPT

      expect(prompt).to include("JSON")
      expect(prompt).to include("summary_patterns")
      expect(prompt).to include("failure_section_start")
      expect(prompt).to include("error_patterns")
    end
  end

  describe "RESPONSE_SCHEMA" do
    it "defines required fields" do
      schema = described_class::RESPONSE_SCHEMA

      expect(schema[:required]).to include("tool_name")
      expect(schema[:required]).to include("summary_patterns")
    end

    it "defines all pattern fields" do
      properties = described_class::RESPONSE_SCHEMA[:properties]

      expect(properties).to have_key(:summary_patterns)
      expect(properties).to have_key(:failure_section_start)
      expect(properties).to have_key(:error_patterns)
      expect(properties).to have_key(:location_patterns)
      expect(properties).to have_key(:noise_patterns)
    end
  end
end
