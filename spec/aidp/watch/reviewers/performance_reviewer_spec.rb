# frozen_string_literal: true

require "spec_helper"
require "aidp/watch/reviewers/performance_reviewer"

RSpec.describe Aidp::Watch::Reviewers::PerformanceReviewer do
  let(:reviewer) { described_class.new }
  let(:provider) { instance_double(Aidp::Providers::Anthropic) }

  before do
    allow(Aidp::ProviderManager).to receive(:get_provider).and_return(provider)
  end

  describe "constants" do
    it "defines PERSONA_NAME" do
      expect(described_class::PERSONA_NAME).to eq("Performance Analyst")
    end

    it "defines performance-focused FOCUS_AREAS" do
      expect(described_class::FOCUS_AREAS).to include(
        "Algorithm complexity and efficiency",
        "Database query optimization (N+1 queries, missing indexes)"
      )
    end
  end

  describe "#review" do
    let(:pr_data) { {number: 1, title: "Test", body: ""} }
    let(:files) { [{filename: "test.rb", additions: 5, deletions: 0}] }
    let(:diff) { "diff content" }

    it "returns review with Performance Analyst persona" do
      allow(provider).to receive(:send_message).and_return('{"findings": []}')

      result = reviewer.review(pr_data: pr_data, files: files, diff: diff)

      expect(result[:persona]).to eq("Performance Analyst")
    end

    it "analyzes code for performance issues" do
      findings = [
        {"severity" => "major", "category" => "N+1 Query", "message" => "Multiple queries in loop"}
      ]
      allow(provider).to receive(:send_message).and_return(
        JSON.dump({"findings" => findings})
      )

      result = reviewer.review(pr_data: pr_data, files: files, diff: diff)

      expect(result[:findings]).to eq(findings)
    end

    it "includes performance focus areas in system prompt" do
      allow(provider).to receive(:send_message).and_return('{"findings": []}')

      reviewer.review(pr_data: pr_data, files: files, diff: diff)

      expect(provider).to have_received(:send_message).with(
        hash_including(prompt: a_string_including("Performance Analyst", "Algorithm complexity"))
      )
    end
  end
end
