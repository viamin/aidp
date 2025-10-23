# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::PlanGenerator do
  let(:plan_generator) { described_class.new }
  let(:sample_issue) do
    {
      title: "Add user authentication",
      url: "https://github.com/example/repo/issues/123",
      body: "We need to implement user authentication.\n\n- Add login form\n- Implement password validation\n- Add user sessions",
      comments: [
        {
          "author" => "developer1",
          "body" => "This should include OAuth2 support",
          "createdAt" => "2023-01-01T00:00:00Z"
        },
        {
          "author" => "designer",
          "body" => "Make sure the UI follows our design system",
          "createdAt" => "2023-01-02T00:00:00Z"
        }
      ]
    }
  end

  describe "#initialize" do
    it "creates instance with default provider" do
      generator = described_class.new
      expect(generator).to be_a(described_class)
    end

    it "creates instance with specified provider" do
      generator = described_class.new(provider_name: "anthropic")
      expect(generator).to be_a(described_class)
    end
  end

  describe "#generate" do
    context "when provider is available" do
      let(:mock_provider) { double("provider") }
      let(:provider_response) do
        '{"plan_summary": "Implement authentication system", "plan_tasks": ["Add login", "Add validation"], "clarifying_questions": ["Which OAuth provider?"]}'
      end

      before do
        allow(plan_generator).to receive(:resolve_provider).and_return(mock_provider)
        allow(mock_provider).to receive(:send_message).and_return(provider_response)
      end

      it "generates plan using provider" do
        result = plan_generator.generate(sample_issue)

        expect(result[:summary]).to eq("Implement authentication system")
        expect(result[:tasks]).to eq(["Add login", "Add validation"])
        expect(result[:questions]).to eq(["Which OAuth provider?"])
      end

      it "calls provider with correct prompt" do
        expect(mock_provider).to receive(:send_message) do |args|
          expect(args[:prompt]).to include("Add user authentication")
          expect(args[:prompt]).to include("OAuth2 support")
          provider_response
        end

        plan_generator.generate(sample_issue)
      end
    end

    context "when provider is not available" do
      before do
        allow(plan_generator).to receive(:resolve_provider).and_return(nil)
        allow(plan_generator).to receive(:display_message)
      end

      it "falls back to heuristic plan" do
        result = plan_generator.generate(sample_issue)

        expect(result[:summary]).to include("implement user authentication")
        expect(result[:tasks]).to include("Add login form")
        expect(result[:questions]).not_to be_empty
      end

      it "displays warning message" do
        expect(plan_generator).to receive(:display_message).with(
          /No active provider available.*heuristic/,
          type: :warn
        )

        plan_generator.generate(sample_issue)
      end
    end

    context "when provider raises error" do
      before do
        allow(plan_generator).to receive(:resolve_provider).and_raise(StandardError, "Connection failed")
        allow(plan_generator).to receive(:display_message)
      end

      it "falls back to heuristic plan" do
        result = plan_generator.generate(sample_issue)

        expect(result[:summary]).to be_a(String)
        expect(result[:tasks]).to be_an(Array)
        expect(result[:questions]).to be_an(Array)
      end

      it "displays error message" do
        expect(plan_generator).to receive(:display_message).with(
          /Plan generation failed.*heuristic/,
          type: :warn
        )

        plan_generator.generate(sample_issue)
      end
    end
  end

  describe "#resolve_provider" do
    it "returns nil when provider name is nil" do
      allow(plan_generator).to receive(:detect_default_provider).and_return(nil)

      result = plan_generator.send(:resolve_provider)
      expect(result).to be_nil
    end

    it "returns provider when available" do
      mock_provider = double("provider", available?: true)
      allow(plan_generator).to receive(:detect_default_provider).and_return("cursor")
      allow(Aidp::ProviderManager).to receive(:get_provider).and_return(mock_provider)

      result = plan_generator.send(:resolve_provider)
      expect(result).to eq(mock_provider)
    end

    it "returns nil when provider is not available" do
      mock_provider = double("provider", available?: false)
      allow(plan_generator).to receive(:detect_default_provider).and_return("cursor")
      allow(Aidp::ProviderManager).to receive(:get_provider).and_return(mock_provider)

      result = plan_generator.send(:resolve_provider)
      expect(result).to be_nil
    end

    it "handles provider manager errors" do
      allow(plan_generator).to receive(:detect_default_provider).and_return("cursor")
      allow(Aidp::ProviderManager).to receive(:get_provider).and_raise(StandardError, "Provider error")
      allow(plan_generator).to receive(:display_message)

      result = plan_generator.send(:resolve_provider)
      expect(result).to be_nil
    end
  end

  describe "#detect_default_provider" do
    it "returns configured default provider" do
      mock_config = double("config_manager", default_provider: "anthropic")
      allow(Aidp::Harness::ConfigManager).to receive(:new).and_return(mock_config)

      result = plan_generator.send(:detect_default_provider)
      expect(result).to eq("anthropic")
    end

    it "returns cursor when no config" do
      mock_config = double("config_manager", default_provider: nil)
      allow(Aidp::Harness::ConfigManager).to receive(:new).and_return(mock_config)

      result = plan_generator.send(:detect_default_provider)
      expect(result).to eq("cursor")
    end

    it "returns cursor when config manager fails" do
      allow(Aidp::Harness::ConfigManager).to receive(:new).and_raise(StandardError)

      result = plan_generator.send(:detect_default_provider)
      expect(result).to eq("cursor")
    end
  end

  describe "#build_prompt" do
    it "includes issue details" do
      prompt = plan_generator.send(:build_prompt, sample_issue)

      expect(prompt).to include("Add user authentication")
      expect(prompt).to include("https://github.com/example/repo/issues/123")
      expect(prompt).to include("implement user authentication")
    end

    it "includes sorted comments" do
      prompt = plan_generator.send(:build_prompt, sample_issue)

      expect(prompt).to include("developer1:\nThis should include OAuth2 support")
      expect(prompt).to include("designer:\nMake sure the UI follows")
    end

    it "includes provider prompt template" do
      prompt = plan_generator.send(:build_prompt, sample_issue)

      expect(prompt).to include("planning specialist")
      expect(prompt).to include("plan_summary")
      expect(prompt).to include("plan_tasks")
    end
  end

  describe "#parse_structured_response" do
    it "parses valid JSON response" do
      response = '{"plan_summary": "Test summary", "plan_tasks": ["task1"], "clarifying_questions": ["q1"]}'

      result = plan_generator.send(:parse_structured_response, response)

      expect(result[:summary]).to eq("Test summary")
      expect(result[:tasks]).to eq(["task1"])
      expect(result[:questions]).to eq(["q1"])
    end

    it "handles JSON in code blocks" do
      response = '```json\n{"plan_summary": "Test", "plan_tasks": [], "clarifying_questions": []}\n```'

      result = plan_generator.send(:parse_structured_response, response)

      expect(result[:summary]).to eq("Test")
      expect(result[:tasks]).to eq([])
    end

    it "extracts JSON from mixed content" do
      response = 'Here is the plan: {"plan_summary": "Test", "plan_tasks": [], "clarifying_questions": []} and more text'

      result = plan_generator.send(:parse_structured_response, response)

      expect(result[:summary]).to eq("Test")
    end

    it "returns nil for invalid JSON" do
      response = "Not JSON at all"

      result = plan_generator.send(:parse_structured_response, response)

      expect(result).to be_nil
    end

    it "handles missing fields gracefully" do
      response = '{"plan_summary": "Test"}'

      result = plan_generator.send(:parse_structured_response, response)

      expect(result[:summary]).to eq("Test")
      expect(result[:tasks]).to eq([])
      expect(result[:questions]).to eq([])
    end
  end

  describe "#extract_json_payload" do
    it "returns text if already JSON" do
      text = '{"key": "value"}'

      result = plan_generator.send(:extract_json_payload, text)

      expect(result).to eq(text)
    end

    it "extracts from code blocks" do
      text = "```json\n{\"key\": \"value\"}\n```"

      result = plan_generator.send(:extract_json_payload, text)

      expect(result).to eq('{"key": "value"}')
    end

    it "finds JSON in mixed content" do
      text = 'Some text {"key": "value"} more text'

      result = plan_generator.send(:extract_json_payload, text)

      expect(result).to eq('{"key": "value"}')
    end

    it "returns nil when no JSON found" do
      text = "No JSON here"

      result = plan_generator.send(:extract_json_payload, text)

      expect(result).to be_nil
    end
  end

  describe "#heuristic_plan" do
    it "extracts bullet points as tasks" do
      result = plan_generator.send(:heuristic_plan, sample_issue)

      expect(result[:tasks]).to include("Add login form")
      expect(result[:tasks]).to include("Implement password validation")
      expect(result[:tasks]).to include("Add user sessions")
    end

    it "uses first paragraphs as summary" do
      result = plan_generator.send(:heuristic_plan, sample_issue)

      expect(result[:summary]).to include("implement user authentication")
    end

    it "provides default tasks when no bullets" do
      issue_without_bullets = {
        title: "Fix bug",
        body: "There is a bug that needs fixing.",
        comments: []
      }

      result = plan_generator.send(:heuristic_plan, issue_without_bullets)

      expect(result[:tasks]).to include("Review the repository context and identify impacted components.")
      expect(result[:tasks]).to include("Implement the necessary code changes and add tests.")
    end

    it "provides default summary when body is empty" do
      empty_issue = {title: "Empty", body: "", comments: []}

      result = plan_generator.send(:heuristic_plan, empty_issue)

      expect(result[:summary]).to eq("Implement the requested changes described in the issue.")
    end

    it "includes standard clarifying questions" do
      result = plan_generator.send(:heuristic_plan, sample_issue)

      expect(result[:questions]).to include(/constraints/)
      expect(result[:questions]).to include(/existing tests/)
      expect(result[:questions]).to include(/additional context/)
    end

    it "limits bullet tasks to 5" do
      many_bullets_issue = {
        title: "Many tasks",
        body: (1..10).map { |i| "- Task #{i}" }.join("\n"),
        comments: []
      }

      result = plan_generator.send(:heuristic_plan, many_bullets_issue)

      expect(result[:tasks].length).to eq(5)
    end
  end
end
