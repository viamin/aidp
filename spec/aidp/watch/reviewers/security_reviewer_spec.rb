# frozen_string_literal: true

require "spec_helper"
require "aidp/watch/reviewers/security_reviewer"

RSpec.describe Aidp::Watch::Reviewers::SecurityReviewer do
  let(:reviewer) { described_class.new }
  let(:provider) { instance_double(Aidp::Providers::AnthropicProvider) }

  before do
    allow(Aidp::ProviderManager).to receive(:get_provider).and_return(provider)
  end

  describe "constants" do
    it "defines PERSONA_NAME" do
      expect(described_class::PERSONA_NAME).to eq("Security Specialist")
    end

    it "defines security-focused FOCUS_AREAS" do
      expect(described_class::FOCUS_AREAS).to include(
        "Injection vulnerabilities (SQL, XSS, Command Injection)",
        "Authentication and authorization issues"
      )
    end
  end

  describe "#review" do
    let(:pr_data) { {number: 1, title: "Test", body: ""} }
    let(:files) { [{filename: "test.rb", additions: 5, deletions: 0}] }
    let(:diff) { "diff content" }

    it "returns review with Security Specialist persona" do
      allow(provider).to receive(:send_message).and_return('{"findings": []}')

      result = reviewer.review(pr_data: pr_data, files: files, diff: diff)

      expect(result[:persona]).to eq("Security Specialist")
    end

    it "analyzes code for security issues" do
      findings = [
        {"severity" => "high", "category" => "SQL Injection", "message" => "Unsafe query"}
      ]
      allow(provider).to receive(:send_message).and_return(
        JSON.dump({"findings" => findings})
      )

      result = reviewer.review(pr_data: pr_data, files: files, diff: diff)

      expect(result[:findings]).to eq(findings)
    end

    it "includes security focus areas in system prompt" do
      allow(provider).to receive(:send_message).and_return('{"findings": []}')

      reviewer.review(pr_data: pr_data, files: files, diff: diff)

      expect(provider).to have_received(:send_message).with(
        hash_including(prompt: a_string_including("Security Specialist", "Injection vulnerabilities"))
      )
    end
  end
end
