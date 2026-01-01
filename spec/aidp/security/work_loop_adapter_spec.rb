# frozen_string_literal: true

require "spec_helper"
require "aidp/security"

RSpec.describe Aidp::Security::WorkLoopAdapter do
  let(:project_dir) { Dir.mktmpdir("work_loop_adapter_spec") }
  let(:mock_enforcer) { instance_double(Aidp::Security::RuleOfTwoEnforcer) }
  let(:mock_proxy) { instance_double(Aidp::Security::SecretsProxy) }
  let(:mock_state) { instance_double(Aidp::Security::TrifectaState) }
  let(:config) { {rule_of_two: {enabled: true}} }

  subject(:adapter) do
    described_class.new(
      project_dir: project_dir,
      config: config,
      enforcer: mock_enforcer,
      secrets_proxy: mock_proxy
    )
  end

  after do
    FileUtils.rm_rf(project_dir) if project_dir && Dir.exist?(project_dir)
  end

  describe "#initialize" do
    it "sets project_dir" do
      expect(adapter.project_dir).to eq(project_dir)
    end

    it "sets config" do
      expect(adapter.config).to eq(config)
    end

    it "initializes with nil work unit" do
      expect(adapter.current_work_unit_id).to be_nil
      expect(adapter.current_state).to be_nil
    end
  end

  describe "#enabled?" do
    context "when rule_of_two.enabled is true" do
      let(:config) { {rule_of_two: {enabled: true}} }

      it "returns true" do
        expect(adapter.enabled?).to be true
      end
    end

    context "when rule_of_two.enabled is false" do
      let(:config) { {rule_of_two: {enabled: false}} }

      it "returns false" do
        expect(adapter.enabled?).to be false
      end
    end

    context "when rule_of_two config is empty" do
      let(:config) { {rule_of_two: {}} }

      it "defaults to true" do
        expect(adapter.enabled?).to be true
      end
    end

    context "when config is empty" do
      let(:config) { {} }

      it "defaults to true" do
        expect(adapter.enabled?).to be true
      end
    end
  end

  describe "#begin_work_unit" do
    before do
      allow(mock_enforcer).to receive(:begin_work_unit).and_return(mock_state)
      allow(mock_state).to receive(:to_h).and_return({})
    end

    context "when enabled" do
      it "begins a work unit with the enforcer" do
        expect(mock_enforcer).to receive(:begin_work_unit).with(work_unit_id: "unit_1")
        adapter.begin_work_unit(work_unit_id: "unit_1")
      end

      it "sets current_work_unit_id" do
        adapter.begin_work_unit(work_unit_id: "unit_1")
        expect(adapter.current_work_unit_id).to eq("unit_1")
      end

      it "sets current_state" do
        adapter.begin_work_unit(work_unit_id: "unit_1")
        expect(adapter.current_state).to eq(mock_state)
      end

      it "returns the state" do
        result = adapter.begin_work_unit(work_unit_id: "unit_1")
        expect(result).to eq(mock_state)
      end
    end

    context "when disabled" do
      let(:config) { {rule_of_two: {enabled: false}} }

      it "returns nil without calling enforcer" do
        expect(mock_enforcer).not_to receive(:begin_work_unit)
        result = adapter.begin_work_unit(work_unit_id: "unit_1")
        expect(result).to be_nil
      end
    end

    context "with untrusted input context" do
      before do
        allow(mock_state).to receive(:enable)
      end

      it "detects github issue source" do
        expect(mock_state).to receive(:enable).with(:untrusted_input, source: "github_issue")
        adapter.begin_work_unit(work_unit_id: "unit_1", context: {issue_number: 123})
      end

      it "detects github PR source" do
        expect(mock_state).to receive(:enable).with(:untrusted_input, source: "github_pr")
        adapter.begin_work_unit(work_unit_id: "unit_1", context: {pr_number: 456})
      end

      it "detects external URL source" do
        expect(mock_state).to receive(:enable).with(:untrusted_input, source: "external_url")
        adapter.begin_work_unit(work_unit_id: "unit_1", context: {external_url: "http://example.com"})
      end

      it "detects webhook payload source" do
        expect(mock_state).to receive(:enable).with(:untrusted_input, source: "webhook_payload")
        adapter.begin_work_unit(work_unit_id: "unit_1", context: {webhook_payload: {}})
      end

      it "detects watch mode workflow" do
        expect(mock_state).to receive(:enable).with(:untrusted_input, source: "watch_mode_untrusted_content")
        adapter.begin_work_unit(work_unit_id: "unit_1", context: {workflow_type: "watch_mode"})
      end

      it "detects multiple sources" do
        expect(mock_state).to receive(:enable).with(:untrusted_input, source: "github_issue, github_pr")
        adapter.begin_work_unit(work_unit_id: "unit_1", context: {issue_number: 123, pr_number: 456})
      end
    end
  end

  describe "#end_work_unit" do
    let(:summary) { {work_unit_id: "unit_1", flags_enabled: 2} }

    before do
      allow(mock_enforcer).to receive(:begin_work_unit).and_return(mock_state)
      allow(mock_enforcer).to receive(:end_work_unit).and_return(summary)
      allow(mock_state).to receive(:to_h).and_return({})
    end

    context "when enabled with active work unit" do
      before do
        adapter.begin_work_unit(work_unit_id: "unit_1")
      end

      it "ends the work unit with enforcer" do
        expect(mock_enforcer).to receive(:end_work_unit).with("unit_1")
        adapter.end_work_unit
      end

      it "clears current_work_unit_id" do
        adapter.end_work_unit
        expect(adapter.current_work_unit_id).to be_nil
      end

      it "clears current_state" do
        adapter.end_work_unit
        expect(adapter.current_state).to be_nil
      end

      it "returns summary" do
        result = adapter.end_work_unit
        expect(result).to eq(summary)
      end
    end

    context "when disabled" do
      let(:config) { {rule_of_two: {enabled: false}} }

      it "returns nil" do
        result = adapter.end_work_unit
        expect(result).to be_nil
      end
    end

    context "when no active work unit" do
      it "returns nil" do
        result = adapter.end_work_unit
        expect(result).to be_nil
      end
    end
  end

  describe "#check_agent_call_allowed!" do
    before do
      allow(mock_enforcer).to receive(:begin_work_unit).and_return(mock_state)
      allow(mock_state).to receive(:to_h).and_return({})
      allow(mock_state).to receive(:enable)
    end

    context "with active work unit" do
      before do
        adapter.begin_work_unit(work_unit_id: "unit_1")
      end

      it "enables egress for egress operations" do
        expect(mock_state).to receive(:enable).with(:egress, source: "agent_operation:git_push")
        adapter.check_agent_call_allowed!(operation: :git_push)
      end

      it "enables egress for git_ prefixed operations" do
        expect(mock_state).to receive(:enable).with(:egress, source: "agent_operation:git_fetch")
        adapter.check_agent_call_allowed!(operation: "git_fetch")
      end

      it "enables egress for api_ prefixed operations" do
        expect(mock_state).to receive(:enable).with(:egress, source: "agent_operation:api_request")
        adapter.check_agent_call_allowed!(operation: "api_request")
      end

      it "enables egress for http_ prefixed operations" do
        expect(mock_state).to receive(:enable).with(:egress, source: "agent_operation:http_get")
        adapter.check_agent_call_allowed!(operation: "http_get")
      end

      it "enables private_data when requires_credentials is true" do
        expect(mock_state).to receive(:enable).with(:egress, source: "agent_operation:git_push")
        expect(mock_state).to receive(:enable).with(:private_data, source: "credential_access:git_push")
        adapter.check_agent_call_allowed!(operation: :git_push, requires_credentials: true)
      end

      it "raises PolicyViolation when egress would create trifecta" do
        allow(mock_state).to receive(:enable).with(:egress, source: anything)
          .and_raise(Aidp::Security::PolicyViolation.new(flag: :egress, source: "test", current_state: {}))
        expect {
          adapter.check_agent_call_allowed!(operation: :git_push)
        }.to raise_error(Aidp::Security::PolicyViolation)
      end

      it "raises PolicyViolation when private_data would create trifecta" do
        allow(mock_state).to receive(:enable).with(:private_data, source: anything)
          .and_raise(Aidp::Security::PolicyViolation.new(flag: :private_data, source: "test", current_state: {}))
        expect {
          adapter.check_agent_call_allowed!(operation: :read_file, requires_credentials: true)
        }.to raise_error(Aidp::Security::PolicyViolation)
      end
    end

    context "when disabled" do
      let(:config) { {rule_of_two: {enabled: false}} }

      it "returns current_state without checking" do
        expect(mock_enforcer).not_to receive(:begin_work_unit)
        result = adapter.check_agent_call_allowed!(operation: :git_push)
        expect(result).to be_nil
      end
    end

    context "without active work unit" do
      it "returns nil" do
        result = adapter.check_agent_call_allowed!(operation: :git_push)
        expect(result).to be_nil
      end
    end
  end

  describe "#request_credential" do
    let(:mock_registry) { instance_double(Aidp::Security::SecretsRegistry) }
    let(:token_result) { {token: "proxy_token_123", expires_at: Time.now + 300} }

    before do
      allow(mock_proxy).to receive(:registry).and_return(mock_registry)
      allow(mock_proxy).to receive(:request_token).and_return(token_result)
      allow(mock_enforcer).to receive(:begin_work_unit).and_return(mock_state)
      allow(mock_state).to receive(:to_h).and_return({})
      allow(mock_state).to receive(:would_create_trifecta?).and_return(false)
      allow(mock_state).to receive(:enable)
    end

    context "when enabled with active work unit" do
      before do
        adapter.begin_work_unit(work_unit_id: "unit_1")
      end

      it "requests token from secrets proxy" do
        expect(mock_proxy).to receive(:request_token).with(secret_name: "my_secret", scope: nil)
        adapter.request_credential(secret_name: "my_secret")
      end

      it "enables private_data flag" do
        expect(mock_state).to receive(:enable).with(:private_data, source: "secrets_proxy:my_secret")
        adapter.request_credential(secret_name: "my_secret")
      end

      it "raises PolicyViolation when would create trifecta" do
        allow(mock_state).to receive(:would_create_trifecta?).with(:private_data).and_return(true)
        expect {
          adapter.request_credential(secret_name: "my_secret")
        }.to raise_error(Aidp::Security::PolicyViolation)
      end
    end

    context "when disabled" do
      let(:config) { {rule_of_two: {enabled: false}} }

      it "returns direct access token when env var exists" do
        allow(mock_registry).to receive(:env_var_for).with("my_secret").and_return("MY_SECRET")
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("MY_SECRET").and_return("real_secret_value")

        result = adapter.request_credential(secret_name: "my_secret")
        expect(result[:token]).to eq("real_secret_value")
        expect(result[:direct_access]).to be true
      end

      it "raises UnregisteredSecretError when secret not registered" do
        allow(mock_registry).to receive(:env_var_for).with("unknown").and_return(nil)
        expect {
          adapter.request_credential(secret_name: "unknown")
        }.to raise_error(Aidp::Security::UnregisteredSecretError)
      end
    end
  end

  describe "#would_allow?" do
    before do
      allow(mock_enforcer).to receive(:begin_work_unit).and_return(mock_state)
      allow(mock_state).to receive(:to_h).and_return({})
      allow(mock_state).to receive(:would_create_trifecta?)
      allow(mock_state).to receive(:enabled_count).and_return(1)
    end

    context "when disabled" do
      let(:config) { {rule_of_two: {enabled: false}} }

      it "returns allowed with security disabled reason" do
        result = adapter.would_allow?(:egress)
        expect(result[:allowed]).to be true
        expect(result[:reason]).to eq("Security disabled")
      end
    end

    context "without active work unit" do
      it "returns allowed with no work unit reason" do
        result = adapter.would_allow?(:egress)
        expect(result[:allowed]).to be true
        expect(result[:reason]).to eq("No active work unit")
      end
    end

    context "with active work unit" do
      before do
        adapter.begin_work_unit(work_unit_id: "unit_1")
      end

      it "returns not allowed when would create trifecta" do
        allow(mock_state).to receive(:would_create_trifecta?).with(:egress).and_return(true)
        result = adapter.would_allow?(:egress)
        expect(result[:allowed]).to be false
        expect(result[:reason]).to eq("Would create lethal trifecta")
      end

      it "returns allowed when would not create trifecta" do
        allow(mock_state).to receive(:would_create_trifecta?).with(:egress).and_return(false)
        result = adapter.would_allow?(:egress)
        expect(result[:allowed]).to be true
        expect(result[:reason]).to eq("Operation allowed")
      end
    end
  end

  describe "#status" do
    before do
      allow(mock_enforcer).to receive(:begin_work_unit).and_return(mock_state)
      allow(mock_state).to receive(:to_h).and_return({untrusted_input: true})
      allow(mock_state).to receive(:status_string).and_return("1 of 3 flags enabled")
    end

    context "when disabled" do
      let(:config) { {rule_of_two: {enabled: false}} }

      it "returns enabled: false" do
        result = adapter.status
        expect(result).to eq({enabled: false})
      end
    end

    context "when enabled with active work unit" do
      before do
        adapter.begin_work_unit(work_unit_id: "unit_1")
      end

      it "returns full status" do
        result = adapter.status
        expect(result[:enabled]).to be true
        expect(result[:active_work_unit]).to eq("unit_1")
        expect(result[:state]).to eq({untrusted_input: true})
        expect(result[:status_string]).to eq("1 of 3 flags enabled")
      end
    end

    context "when enabled without active work unit" do
      it "returns status with no work unit message" do
        result = adapter.status
        expect(result[:enabled]).to be true
        expect(result[:active_work_unit]).to be_nil
        expect(result[:status_string]).to eq("No active work unit")
      end
    end
  end

  describe "#sanitized_environment" do
    it "delegates to secrets proxy" do
      sanitized = {"PATH" => "/usr/bin"}
      expect(mock_proxy).to receive(:sanitized_environment).and_return(sanitized)
      expect(adapter.sanitized_environment).to eq(sanitized)
    end
  end

  describe "#with_sanitized_environment" do
    it "delegates to secrets proxy" do
      expect(mock_proxy).to receive(:with_sanitized_environment).and_yield
      called = false
      adapter.with_sanitized_environment { called = true }
      expect(called).to be true
    end
  end
end
