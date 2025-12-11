# frozen_string_literal: true

require "spec_helper"
require "aidp/security"

RSpec.describe Aidp::Security::WatchModeHandler do
  let(:mock_repository_client) { instance_double("RepositoryClient") }
  let(:config) { {} }

  subject(:handler) do
    described_class.new(repository_client: mock_repository_client, config: config)
  end

  let(:violation) do
    Aidp::Security::PolicyViolation.new(
      flag: :egress,
      source: "git_push",
      current_state: {untrusted_input: true, private_data: true, egress: false},
      message: "Would create lethal trifecta"
    )
  end

  let(:context) do
    {
      work_unit_id: "unit_123",
      issue_number: 42,
      operation: "git_push"
    }
  end

  describe "#initialize" do
    it "normalizes config with defaults" do
      expect(handler.config[:max_retry_attempts]).to eq(3)
      expect(handler.config[:fail_forward_enabled]).to be true
      expect(handler.config[:needs_input_label]).to eq("aidp-needs-input")
    end

    it "accepts custom config values" do
      custom = described_class.new(
        repository_client: mock_repository_client,
        config: {max_retry_attempts: 5, needs_input_label: "custom-label"}
      )
      expect(custom.config[:max_retry_attempts]).to eq(5)
      expect(custom.config[:needs_input_label]).to eq("custom-label")
    end

    it "accepts string keys in config" do
      custom = described_class.new(
        repository_client: mock_repository_client,
        config: {"max_retry_attempts" => 7, "needs_input_label" => "string-label"}
      )
      expect(custom.config[:max_retry_attempts]).to eq(7)
      expect(custom.config[:needs_input_label]).to eq("string-label")
    end
  end

  describe "#enabled?" do
    it "returns true by default" do
      expect(handler.enabled?).to be true
    end

    it "returns false when fail_forward_enabled is false" do
      disabled = described_class.new(
        repository_client: mock_repository_client,
        config: {fail_forward_enabled: false}
      )
      expect(disabled.enabled?).to be false
    end
  end

  describe "#handle_violation" do
    context "first attempt" do
      it "returns retry action" do
        result = handler.handle_violation(violation, context: context)
        expect(result[:recovered]).to be false
        expect(result[:action]).to eq(:retry)
        expect(result[:retry_count]).to eq(1)
      end

      it "includes retry message" do
        result = handler.handle_violation(violation, context: context)
        expect(result[:message]).to include("1/3")
      end
    end

    context "second attempt" do
      before do
        handler.handle_violation(violation, context: context)
      end

      it "returns retry action with updated count" do
        result = handler.handle_violation(violation, context: context)
        expect(result[:action]).to eq(:retry)
        expect(result[:retry_count]).to eq(2)
        expect(result[:message]).to include("2/3")
      end
    end

    context "third attempt" do
      before do
        2.times { handler.handle_violation(violation, context: context) }
      end

      it "still returns retry for third attempt" do
        result = handler.handle_violation(violation, context: context)
        expect(result[:action]).to eq(:retry)
        expect(result[:retry_count]).to eq(3)
      end
    end

    context "fourth attempt (exceeds max)" do
      before do
        3.times { handler.handle_violation(violation, context: context) }
        allow(mock_repository_client).to receive(:add_issue_comment)
        allow(mock_repository_client).to receive(:add_labels)
      end

      it "returns fail action" do
        result = handler.handle_violation(violation, context: context)
        expect(result[:recovered]).to be false
        expect(result[:action]).to eq(:fail)
        expect(result[:needs_input]).to be true
      end

      it "adds comment and label to issue" do
        expect(mock_repository_client).to receive(:add_issue_comment).with(42, anything)
        expect(mock_repository_client).to receive(:add_labels).with(42, ["aidp-needs-input"])
        handler.handle_violation(violation, context: context)
      end

      it "clears retry count after failure" do
        handler.handle_violation(violation, context: context)
        # Next attempt should start at 1 again
        result = handler.handle_violation(violation, context: context)
        expect(result[:retry_count]).to eq(1)
      end
    end

    context "with PR context" do
      let(:pr_context) do
        {
          work_unit_id: "unit_456",
          pr_number: 99,
          operation: "git_push"
        }
      end

      before do
        3.times { handler.handle_violation(violation, context: pr_context) }
        allow(mock_repository_client).to receive(:add_pr_comment)
        allow(mock_repository_client).to receive(:add_labels)
      end

      it "adds PR comment instead of issue comment" do
        expect(mock_repository_client).to receive(:add_pr_comment).with(99, anything)
        expect(mock_repository_client).not_to receive(:add_issue_comment)
        handler.handle_violation(violation, context: pr_context)
      end
    end

    context "without issue or PR number" do
      let(:no_number_context) do
        {work_unit_id: "unit_789", operation: "git_push"}
      end

      before do
        3.times { handler.handle_violation(violation, context: no_number_context) }
      end

      it "does not try to add comment" do
        expect(mock_repository_client).not_to receive(:add_issue_comment)
        expect(mock_repository_client).not_to receive(:add_pr_comment)
        handler.handle_violation(violation, context: no_number_context)
      end
    end

    context "when repository client fails" do
      before do
        3.times { handler.handle_violation(violation, context: context) }
        allow(mock_repository_client).to receive(:add_issue_comment).and_raise(StandardError, "API error")
        allow(mock_repository_client).to receive(:add_labels)
      end

      it "handles error gracefully" do
        expect { handler.handle_violation(violation, context: context) }.not_to raise_error
      end

      it "still returns fail result" do
        result = handler.handle_violation(violation, context: context)
        expect(result[:action]).to eq(:fail)
      end
    end

    context "with custom max_retry_attempts" do
      let(:config) { {max_retry_attempts: 1} }

      before do
        handler.handle_violation(violation, context: context)
        allow(mock_repository_client).to receive(:add_issue_comment)
        allow(mock_repository_client).to receive(:add_labels)
      end

      it "fails after custom limit" do
        result = handler.handle_violation(violation, context: context)
        expect(result[:action]).to eq(:fail)
      end
    end
  end

  describe "#reset_retry_count" do
    before do
      handler.handle_violation(violation, context: context)
    end

    it "resets count for specific work unit" do
      handler.reset_retry_count("unit_123")
      result = handler.handle_violation(violation, context: context)
      expect(result[:retry_count]).to eq(1)
    end

    it "does not affect other work units" do
      other_context = context.merge(work_unit_id: "other_unit")
      handler.handle_violation(violation, context: other_context)

      handler.reset_retry_count("unit_123")

      result = handler.handle_violation(violation, context: other_context)
      expect(result[:retry_count]).to eq(2)
    end
  end

  describe "mitigation strategies" do
    context "for private_data violation" do
      let(:private_data_violation) do
        Aidp::Security::PolicyViolation.new(
          flag: :private_data,
          source: "credential_access",
          current_state: {untrusted_input: true, egress: true}
        )
      end

      it "tries secrets proxy strategy first" do
        result = handler.handle_violation(private_data_violation, context: context)
        expect(result[:recovered]).to be false
        # The strategy was tried but not yet implemented
      end
    end

    context "for egress violation" do
      it "tries defer egress strategy" do
        result = handler.handle_violation(violation, context: context)
        expect(result[:recovered]).to be false
      end
    end

    context "for untrusted_input violation" do
      let(:untrusted_violation) do
        Aidp::Security::PolicyViolation.new(
          flag: :untrusted_input,
          source: "github_issue",
          current_state: {private_data: true, egress: true}
        )
      end

      it "tries sanitize input strategy" do
        result = handler.handle_violation(untrusted_violation, context: context)
        expect(result[:recovered]).to be false
      end
    end
  end

  describe "security comment generation" do
    before do
      3.times { handler.handle_violation(violation, context: context) }
      allow(mock_repository_client).to receive(:add_labels)
    end

    it "includes violation flag in comment" do
      expect(mock_repository_client).to receive(:add_issue_comment) do |_number, body|
        expect(body).to include("egress")
      end
      handler.handle_violation(violation, context: context)
    end

    it "includes current state in comment" do
      expect(mock_repository_client).to receive(:add_issue_comment) do |_number, body|
        expect(body).to include("untrusted_input")
        expect(body).to include("private_data")
      end
      handler.handle_violation(violation, context: context)
    end

    it "includes work unit id in comment" do
      expect(mock_repository_client).to receive(:add_issue_comment) do |_number, body|
        expect(body).to include("unit_123")
      end
      handler.handle_violation(violation, context: context)
    end

    it "includes remediation suggestions" do
      expect(mock_repository_client).to receive(:add_issue_comment) do |_number, body|
        expect(body).to include("Secrets Proxy")
        expect(body).to include("Sanitize input")
      end
      handler.handle_violation(violation, context: context)
    end
  end
end
