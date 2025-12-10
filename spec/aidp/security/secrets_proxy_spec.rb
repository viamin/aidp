# frozen_string_literal: true

require "spec_helper"
require "aidp/security"

RSpec.describe Aidp::Security::SecretsProxy do
  let(:project_dir) { Dir.mktmpdir("aidp_test") }
  let(:registry) { Aidp::Security::SecretsRegistry.new(project_dir: project_dir) }
  subject(:proxy) { described_class.new(registry: registry) }

  before do
    # Set up test env var
    ENV["TEST_SECRET"] = "secret_value_123"
    registry.register(name: "test_secret", env_var: "TEST_SECRET")
  end

  after do
    ENV.delete("TEST_SECRET")
    FileUtils.rm_rf(project_dir)
  end

  describe "#request_token" do
    it "issues a token for registered secret" do
      result = proxy.request_token(secret_name: "test_secret")

      expect(result[:token]).to start_with("aidp_proxy_")
      expect(result[:secret_name]).to eq("test_secret")
      expect(result[:expires_at]).to be_a(String)
    end

    it "raises UnregisteredSecretError for unknown secret" do
      expect {
        proxy.request_token(secret_name: "unknown")
      }.to raise_error(Aidp::Security::UnregisteredSecretError)
    end

    it "accepts custom TTL" do
      result = proxy.request_token(secret_name: "test_secret", ttl: 60)
      expect(result[:ttl]).to eq(60)
    end

    it "accepts scope parameter" do
      result = proxy.request_token(secret_name: "test_secret", scope: "git_push")
      expect(result[:scope]).to eq("git_push")
    end
  end

  describe "#exchange_token" do
    it "returns secret value for valid token" do
      token_result = proxy.request_token(secret_name: "test_secret")
      value = proxy.exchange_token(token_result[:token])

      expect(value).to eq("secret_value_123")
    end

    it "raises error for invalid token" do
      expect {
        proxy.exchange_token("invalid_token")
      }.to raise_error(Aidp::Security::SecretsProxyError)
    end

    it "raises TokenExpiredError for expired token" do
      token_result = proxy.request_token(secret_name: "test_secret", ttl: 0)

      # Wait for expiry
      sleep(0.1)

      expect {
        proxy.exchange_token(token_result[:token])
      }.to raise_error(Aidp::Security::TokenExpiredError)
    end

    it "marks token as used" do
      token_result = proxy.request_token(secret_name: "test_secret")
      proxy.exchange_token(token_result[:token])

      summary = proxy.active_tokens_summary
      token_info = summary.find { |t| t[:secret_name] == "test_secret" }
      expect(token_info[:used]).to be true
    end
  end

  describe "#revoke_token" do
    it "revokes an active token" do
      token_result = proxy.request_token(secret_name: "test_secret")
      result = proxy.revoke_token(token_result[:token])

      expect(result).to be true
      expect {
        proxy.exchange_token(token_result[:token])
      }.to raise_error(Aidp::Security::SecretsProxyError)
    end

    it "returns false for unknown token" do
      expect(proxy.revoke_token("unknown")).to be false
    end
  end

  describe "#revoke_all_for_secret" do
    it "revokes all tokens for a secret" do
      proxy.request_token(secret_name: "test_secret")
      proxy.request_token(secret_name: "test_secret")

      count = proxy.revoke_all_for_secret("test_secret")

      expect(count).to eq(2)
      expect(proxy.active_tokens_summary).to be_empty
    end
  end

  describe "#cleanup_expired!" do
    it "removes expired tokens" do
      proxy.request_token(secret_name: "test_secret", ttl: 0)

      sleep(0.1)
      count = proxy.cleanup_expired!

      expect(count).to eq(1)
    end
  end

  describe "#sanitized_environment" do
    it "strips registered secret env vars" do
      sanitized = proxy.sanitized_environment

      expect(sanitized).not_to have_key("TEST_SECRET")
    end

    it "preserves non-secret env vars" do
      ENV["NOT_A_SECRET"] = "value"
      sanitized = proxy.sanitized_environment

      expect(sanitized["NOT_A_SECRET"]).to eq("value")
      ENV.delete("NOT_A_SECRET")
    end
  end

  describe "#with_sanitized_environment" do
    it "removes secrets during block execution" do
      proxy.with_sanitized_environment do
        expect(ENV["TEST_SECRET"]).to be_nil
      end
    end

    it "restores secrets after block" do
      proxy.with_sanitized_environment { }
      expect(ENV["TEST_SECRET"]).to eq("secret_value_123")
    end

    it "restores secrets even if block raises" do
      expect {
        proxy.with_sanitized_environment { raise "error" }
      }.to raise_error("error")

      expect(ENV["TEST_SECRET"]).to eq("secret_value_123")
    end
  end

  describe "#active_tokens_summary" do
    it "returns summary of active tokens" do
      proxy.request_token(secret_name: "test_secret", scope: "test")

      summary = proxy.active_tokens_summary

      expect(summary.size).to eq(1)
      expect(summary.first[:secret_name]).to eq("test_secret")
      expect(summary.first[:scope]).to eq("test")
      expect(summary.first[:used]).to be false
    end
  end

  describe "#usage_log" do
    it "returns recent token usage" do
      token = proxy.request_token(secret_name: "test_secret")
      proxy.exchange_token(token[:token])

      log = proxy.usage_log

      expect(log.size).to eq(1)
      expect(log.first[:secret_name]).to eq("test_secret")
    end
  end
end

RSpec.describe Aidp::Security::SecretsRegistry do
  let(:project_dir) { Dir.mktmpdir("aidp_test") }
  subject(:registry) { described_class.new(project_dir: project_dir) }

  before do
    ENV["TEST_VAR"] = "test_value"
  end

  after do
    ENV.delete("TEST_VAR")
    FileUtils.rm_rf(project_dir)
  end

  describe "#register" do
    it "registers a secret" do
      result = registry.register(name: "my_secret", env_var: "TEST_VAR")

      expect(result[:name]).to eq("my_secret")
      expect(result[:env_var]).to eq("TEST_VAR")
      expect(result[:id]).to be_a(String)
    end

    it "persists registration to disk" do
      registry.register(name: "my_secret", env_var: "TEST_VAR")

      # Verify file was created
      registry_file = File.join(project_dir, ".aidp", "security", "secrets_registry.json")
      expect(File.exist?(registry_file)).to be true

      # Debug: check file contents
      content = JSON.parse(File.read(registry_file))
      expect(content).to have_key("my_secret")

      # Force new registry to load from disk (no cached state)
      new_registry = described_class.new(project_dir: project_dir)
      expect(new_registry.registered?("my_secret")).to be true
    end

    it "accepts optional description" do
      registry.register(name: "my_secret", env_var: "TEST_VAR", description: "Test desc")
      secret = registry.get("my_secret")
      expect(secret[:description]).to eq("Test desc")
    end

    it "accepts optional scopes" do
      registry.register(name: "my_secret", env_var: "TEST_VAR", scopes: ["git_push", "api_call"])
      secret = registry.get("my_secret")
      expect(secret[:scopes]).to eq(["git_push", "api_call"])
    end
  end

  describe "#unregister" do
    it "removes a registered secret" do
      registry.register(name: "my_secret", env_var: "TEST_VAR")
      result = registry.unregister(name: "my_secret")

      expect(result).to be true
      expect(registry.registered?("my_secret")).to be false
    end

    it "returns false for unknown secret" do
      expect(registry.unregister(name: "unknown")).to be false
    end
  end

  describe "#registered?" do
    it "returns true for registered secret" do
      registry.register(name: "my_secret", env_var: "TEST_VAR")
      expect(registry.registered?("my_secret")).to be true
    end

    it "returns false for unregistered secret" do
      expect(registry.registered?("unknown")).to be false
    end
  end

  describe "#get" do
    it "returns secret details" do
      registry.register(name: "my_secret", env_var: "TEST_VAR")
      secret = registry.get("my_secret")

      expect(secret[:name]).to eq("my_secret")
      expect(secret[:env_var]).to eq("TEST_VAR")
    end

    it "returns nil for unknown secret" do
      expect(registry.get("unknown")).to be_nil
    end
  end

  describe "#list" do
    it "returns all registered secrets" do
      registry.register(name: "secret1", env_var: "TEST_VAR")
      registry.register(name: "secret2", env_var: "TEST_VAR")

      list = registry.list
      expect(list.size).to eq(2)
    end

    it "includes has_value flag" do
      registry.register(name: "my_secret", env_var: "TEST_VAR")
      list = registry.list
      expect(list.first[:has_value]).to be true
    end
  end

  describe "#env_vars_to_strip" do
    it "returns list of env vars to remove from agent environment" do
      registry.register(name: "secret1", env_var: "VAR1")
      registry.register(name: "secret2", env_var: "VAR2")

      vars = registry.env_vars_to_strip
      expect(vars).to contain_exactly("VAR1", "VAR2")
    end
  end

  describe "#env_var_registered?" do
    it "returns true if env var is registered" do
      registry.register(name: "my_secret", env_var: "TEST_VAR")
      expect(registry.env_var_registered?("TEST_VAR")).to be true
    end

    it "returns false if env var is not registered" do
      expect(registry.env_var_registered?("UNREGISTERED")).to be false
    end
  end
end
