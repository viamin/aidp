# frozen_string_literal: true

require "spec_helper"
require "aidp/watch/reviewers/base_reviewer"

RSpec.describe Aidp::Watch::Reviewers::BaseReviewer do
  # Create a concrete test class since BaseReviewer is abstract
  let(:test_reviewer_class) do
    Class.new(described_class) do
      PERSONA_NAME = "Test Reviewer"
      FOCUS_AREAS = ["Testing", "Quality"].freeze

      def review(pr_data:, files:, diff:)
        {persona: PERSONA_NAME, findings: []}
      end
    end
  end

  let(:reviewer) { test_reviewer_class.new }
  let(:provider) { instance_double(Aidp::Providers::Anthropic) }

  before do
    allow(Aidp::ProviderManager).to receive(:get_provider).and_return(provider)
  end

  describe "#initialize" do
    it "sets persona_name from class constant" do
      expect(reviewer.persona_name).to eq("Test Reviewer")
    end

    it "sets focus_areas from class constant" do
      expect(reviewer.focus_areas).to eq(["Testing", "Quality"])
    end

    it "accepts custom provider_name" do
      custom_reviewer = test_reviewer_class.new(provider_name: "openai")
      expect(custom_reviewer.provider_name).to eq("openai")
    end
  end

  describe "#review" do
    it "raises NotImplementedError in base class" do
      base_reviewer = described_class.new
      expect {
        base_reviewer.review(pr_data: {}, files: [], diff: "")
      }.to raise_error(NotImplementedError, "Subclasses must implement #review")
    end

    it "can be implemented by subclasses" do
      result = reviewer.review(pr_data: {}, files: [], diff: "")
      expect(result).to have_key(:persona)
      expect(result).to have_key(:findings)
    end
  end

  describe "#extract_json" do
    it "returns text as-is if it's already valid JSON object" do
      json = '{"findings": []}'
      result = reviewer.send(:extract_json, json)
      expect(result).to eq(json)
    end

    it "extracts JSON from markdown code fence" do
      text = "Here's the result:\n```json\n{\"findings\": []}\n```\nDone!"
      result = reviewer.send(:extract_json, text)
      expect(result).to eq('{"findings": []}')
    end

    it "extracts JSON object from surrounding text" do
      text = "Analysis complete: {\"findings\": []} that's it"
      result = reviewer.send(:extract_json, text)
      expect(result).to eq('{"findings": []}')
    end

    it "returns text if no JSON structure found" do
      text = "No JSON here"
      result = reviewer.send(:extract_json, text)
      expect(result).to eq(text)
    end

    it "handles nested braces correctly" do
      text = 'Some text {"findings": [{"nested": "value"}]} more text'
      result = reviewer.send(:extract_json, text)
      expect(result).to eq('{"findings": [{"nested": "value"}]}')
    end

    it "handles malformed code fence" do
      text = "```json\nNo closing brace"
      result = reviewer.send(:extract_json, text)
      expect(result).to eq(text)
    end
  end

  describe "#truncate_diff" do
    it "returns diff unchanged if under max_lines" do
      diff = "line1\nline2\nline3"
      result = reviewer.send(:truncate_diff, diff, max_lines: 10)
      expect(result).to eq(diff)
    end

    it "truncates diff if over max_lines" do
      diff = (1..100).map { |i| "line#{i}" }.join("\n")
      result = reviewer.send(:truncate_diff, diff, max_lines: 50)
      lines = result.lines
      expect(lines.length).to eq(51) # 50 lines + truncation message
      expect(result).to include("... (diff truncated, 50 more lines)")
    end

    it "uses default max_lines of 500" do
      diff = (1..600).map { |i| "line#{i}" }.join("\n")
      result = reviewer.send(:truncate_diff, diff)
      expect(result).to include("... (diff truncated, 100 more lines)")
    end
  end

  describe "#build_review_prompt" do
    it "includes PR metadata" do
      pr_data = {number: 123, title: "Fix bug", body: "This fixes the issue"}
      files = [{filename: "test.rb", additions: 5, deletions: 2}]
      diff = "diff content"

      prompt = reviewer.send(:build_review_prompt, pr_data: pr_data, files: files, diff: diff)

      expect(prompt).to include("PR #123: Fix bug")
      expect(prompt).to include("This fixes the issue")
      expect(prompt).to include("test.rb (+5/-2)")
      expect(prompt).to include("diff content")
    end

    it "handles multiple files" do
      pr_data = {number: 1, title: "Test", body: ""}
      files = [
        {filename: "file1.rb", additions: 3, deletions: 1},
        {filename: "file2.rb", additions: 10, deletions: 5}
      ]
      diff = ""

      prompt = reviewer.send(:build_review_prompt, pr_data: pr_data, files: files, diff: diff)

      expect(prompt).to include("Changed Files (2)")
      expect(prompt).to include("file1.rb (+3/-1)")
      expect(prompt).to include("file2.rb (+10/-5)")
    end
  end

  describe "#system_prompt" do
    it "includes persona name" do
      prompt = reviewer.send(:system_prompt)
      expect(prompt).to include("Test Reviewer")
    end

    it "includes focus areas" do
      prompt = reviewer.send(:system_prompt)
      expect(prompt).to include("- Testing")
      expect(prompt).to include("- Quality")
    end

    it "includes JSON format instructions" do
      prompt = reviewer.send(:system_prompt)
      expect(prompt).to include('"findings"')
      expect(prompt).to include('"severity"')
      expect(prompt).to include('high|major|minor|nit')
    end

    it "includes severity level definitions" do
      prompt = reviewer.send(:system_prompt)
      expect(prompt).to include("high: Critical issues")
      expect(prompt).to include("major: Significant problems")
      expect(prompt).to include("minor: Improvements")
      expect(prompt).to include("nit: Stylistic")
    end
  end

  describe "#analyze_with_provider" do
    it "sends prompt to provider and parses JSON response" do
      response = '{"findings": [{"severity": "major", "message": "Issue found"}]}'
      allow(provider).to receive(:send_message).and_return(response)

      result = reviewer.send(:analyze_with_provider, "Review this")

      expect(provider).to have_received(:send_message).with(hash_including(prompt: String))
      expect(result).to eq([{"severity" => "major", "message" => "Issue found"}])
    end

    it "extracts JSON from code fence in response" do
      response = "Here's my analysis:\n```json\n{\"findings\": []}\n```"
      allow(provider).to receive(:send_message).and_return(response)

      result = reviewer.send(:analyze_with_provider, "Review this")

      expect(result).to eq([])
    end

    it "returns empty array on JSON parse error" do
      allow(provider).to receive(:send_message).and_return("invalid json")
      allow(Aidp).to receive(:log_error)

      result = reviewer.send(:analyze_with_provider, "Review this")

      expect(result).to eq([])
      expect(Aidp).to have_received(:log_error).with(
        "reviewer",
        "Failed to parse provider response",
        hash_including(persona: "Test Reviewer")
      )
    end

    it "returns empty array on provider error" do
      allow(provider).to receive(:send_message).and_raise(StandardError.new("Provider failed"))
      allow(Aidp).to receive(:log_error)

      result = reviewer.send(:analyze_with_provider, "Review this")

      expect(result).to eq([])
      expect(Aidp).to have_received(:log_error).with(
        "reviewer",
        "Review failed",
        hash_including(persona: "Test Reviewer", error: "Provider failed")
      )
    end

    it "handles response without findings key" do
      response = '{"some_other_key": "value"}'
      allow(provider).to receive(:send_message).and_return(response)

      result = reviewer.send(:analyze_with_provider, "Review this")

      expect(result).to eq([])
    end
  end

  describe "#detect_default_provider" do
    it "returns provider from config manager" do
      config_manager = instance_double(Aidp::Harness::ConfigManager)
      allow(Aidp::Harness::ConfigManager).to receive(:new).and_return(config_manager)
      allow(config_manager).to receive(:default_provider).and_return("openai")

      result = reviewer.send(:detect_default_provider)

      expect(result).to eq("openai")
    end

    it "returns anthropic as fallback if config fails" do
      allow(Aidp::Harness::ConfigManager).to receive(:new).and_raise(StandardError)

      result = reviewer.send(:detect_default_provider)

      expect(result).to eq("anthropic")
    end

    it "returns anthropic if config returns nil" do
      config_manager = instance_double(Aidp::Harness::ConfigManager)
      allow(Aidp::Harness::ConfigManager).to receive(:new).and_return(config_manager)
      allow(config_manager).to receive(:default_provider).and_return(nil)

      result = reviewer.send(:detect_default_provider)

      expect(result).to eq("anthropic")
    end
  end

  describe "#provider" do
    it "initializes provider with detected default" do
      reviewer_instance = test_reviewer_class.new

      reviewer_instance.send(:provider)

      expect(Aidp::ProviderManager).to have_received(:get_provider).with(
        String,
        use_harness: false
      )
    end

    it "uses specified provider_name if provided" do
      reviewer_instance = test_reviewer_class.new(provider_name: "openai")

      reviewer_instance.send(:provider)

      expect(Aidp::ProviderManager).to have_received(:get_provider).with(
        "openai",
        use_harness: false
      )
    end

    it "caches provider instance" do
      reviewer_instance = test_reviewer_class.new

      reviewer_instance.send(:provider)
      reviewer_instance.send(:provider)

      expect(Aidp::ProviderManager).to have_received(:get_provider).once
    end
  end
end
