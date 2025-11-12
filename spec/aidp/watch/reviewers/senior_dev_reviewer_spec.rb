# frozen_string_literal: true

require "spec_helper"
require "aidp/watch/reviewers/senior_dev_reviewer"

RSpec.describe Aidp::Watch::Reviewers::SeniorDevReviewer do
  let(:reviewer) { described_class.new }
  let(:provider) { instance_double(Aidp::Providers::Anthropic) }
  let(:pr_data) do
    {
      number: 123,
      title: "Add new feature",
      body: "This PR adds a new feature"
    }
  end
  let(:files) do
    [
      {filename: "lib/feature.rb", additions: 50, deletions: 10}
    ]
  end
  let(:diff) { "diff --git a/lib/feature.rb b/lib/feature.rb\n+new code" }

  before do
    allow(Aidp::ProviderManager).to receive(:get_provider).and_return(provider)
  end

  describe "constants" do
    it "defines PERSONA_NAME" do
      expect(described_class::PERSONA_NAME).to eq("Senior Developer")
    end

    it "defines FOCUS_AREAS" do
      expect(described_class::FOCUS_AREAS).to be_an(Array)
      expect(described_class::FOCUS_AREAS).to include(
        "Code correctness and logic errors",
        "Architecture and design patterns"
      )
    end
  end

  describe "#initialize" do
    it "inherits from BaseReviewer" do
      expect(reviewer).to be_a(Aidp::Watch::Reviewers::BaseReviewer)
    end

    it "sets persona_name from constant" do
      expect(reviewer.persona_name).to eq("Senior Developer")
    end

    it "sets focus_areas from constant" do
      expect(reviewer.focus_areas).to eq(described_class::FOCUS_AREAS)
    end
  end

  describe "#review" do
    it "returns review with persona and findings" do
      findings = [
        {"severity" => "major", "category" => "Logic Error", "message" => "Potential bug"}
      ]
      allow(provider).to receive(:send_message).and_return(
        JSON.dump({"findings" => findings})
      )

      result = reviewer.review(pr_data: pr_data, files: files, diff: diff)

      expect(result).to have_key(:persona)
      expect(result[:persona]).to eq("Senior Developer")
      expect(result).to have_key(:findings)
      expect(result[:findings]).to eq(findings)
    end

    it "calls provider with full review prompt" do
      allow(provider).to receive(:send_message).and_return('{"findings": []}')

      reviewer.review(pr_data: pr_data, files: files, diff: diff)

      expect(provider).to have_received(:send_message).with(
        hash_including(prompt: a_string_including("Senior Developer", "PR #123"))
      )
    end

    it "handles provider errors gracefully" do
      allow(provider).to receive(:send_message).and_raise(StandardError.new("API error"))
      allow(Aidp).to receive(:log_error)

      result = reviewer.review(pr_data: pr_data, files: files, diff: diff)

      expect(result[:findings]).to eq([])
    end

    it "handles empty findings" do
      allow(provider).to receive(:send_message).and_return('{"findings": []}')

      result = reviewer.review(pr_data: pr_data, files: files, diff: diff)

      expect(result[:findings]).to eq([])
    end

    it "includes file information in prompt" do
      allow(provider).to receive(:send_message).and_return('{"findings": []}')

      reviewer.review(pr_data: pr_data, files: files, diff: diff)

      expect(provider).to have_received(:send_message).with(
        hash_including(prompt: a_string_including("lib/feature.rb"))
      )
    end

    it "includes diff in prompt" do
      allow(provider).to receive(:send_message).and_return('{"findings": []}')

      reviewer.review(pr_data: pr_data, files: files, diff: diff)

      expect(provider).to have_received(:send_message).with(
        hash_including(prompt: a_string_including("+new code"))
      )
    end
  end

  describe "integration with BaseReviewer" do
    it "uses provider manager to get provider" do
      allow(provider).to receive(:send_message).and_return('{"findings": []}')

      reviewer.review(pr_data: pr_data, files: files, diff: diff)

      expect(Aidp::ProviderManager).to have_received(:get_provider).with(
        String,
        use_harness: false
      )
    end

    it "builds review prompt using base class method" do
      allow(reviewer).to receive(:build_review_prompt).and_call_original
      allow(provider).to receive(:send_message).and_return('{"findings": []}')

      reviewer.review(pr_data: pr_data, files: files, diff: diff)

      expect(reviewer).to have_received(:build_review_prompt).with(
        pr_data: pr_data,
        files: files,
        diff: diff
      )
    end
  end
end
