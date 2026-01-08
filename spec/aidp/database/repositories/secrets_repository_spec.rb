# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Repositories::SecretsRepository do
  let(:temp_dir) { Dir.mktmpdir("aidp_secrets_repo_test") }
  let(:db_path) { File.join(temp_dir, ".aidp", "aidp.db") }
  let(:repository) { described_class.new(project_dir: temp_dir) }

  before do
    allow(Aidp::ConfigPaths).to receive(:database_file).with(temp_dir).and_return(db_path)
    Aidp::Database::Migrations.run!(temp_dir)
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.remove_entry(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "#register" do
    it "registers a secret" do
      result = repository.register(
        name: "API_KEY",
        env_var: "MY_API_KEY",
        description: "API key for service",
        scopes: ["read", "write"]
      )

      expect(result[:name]).to eq("API_KEY")
      expect(result[:env_var]).to eq("MY_API_KEY")
    end
  end

  describe "#registered?" do
    it "returns false when not registered" do
      expect(repository.registered?("UNKNOWN")).to be false
    end

    it "returns true when registered" do
      repository.register(name: "TEST", env_var: "TEST_VAR")

      expect(repository.registered?("TEST")).to be true
    end
  end

  describe "#find / #get" do
    it "returns registration details" do
      repository.register(name: "SECRET", env_var: "SECRET_VAR", description: "A secret")

      secret = repository.find("SECRET")

      expect(secret[:name]).to eq("SECRET")
      expect(secret[:description]).to eq("A secret")
    end
  end

  describe "#env_var_for" do
    it "returns env var name" do
      repository.register(name: "KEY", env_var: "REAL_KEY")

      expect(repository.env_var_for("KEY")).to eq("REAL_KEY")
    end
  end

  describe "#unregister" do
    it "removes a secret" do
      repository.register(name: "TO_REMOVE", env_var: "X")

      result = repository.unregister(name: "TO_REMOVE")

      expect(result).to be true
      expect(repository.registered?("TO_REMOVE")).to be false
    end

    it "returns false for non-existent secret" do
      expect(repository.unregister(name: "UNKNOWN")).to be false
    end
  end

  describe "#list" do
    it "lists all secrets" do
      repository.register(name: "S1", env_var: "V1")
      repository.register(name: "S2", env_var: "V2")

      secrets = repository.list

      expect(secrets.size).to eq(2)
    end
  end

  describe "#env_vars_to_strip" do
    it "returns env var names" do
      repository.register(name: "A", env_var: "ENV_A")
      repository.register(name: "B", env_var: "ENV_B")

      vars = repository.env_vars_to_strip

      expect(vars).to contain_exactly("ENV_A", "ENV_B")
    end
  end

  describe "#env_var_registered?" do
    it "checks if env var is registered" do
      repository.register(name: "X", env_var: "MY_VAR")

      expect(repository.env_var_registered?("MY_VAR")).to be true
      expect(repository.env_var_registered?("OTHER")).to be false
    end
  end

  describe "#name_for_env_var" do
    it "returns secret name for env var" do
      repository.register(name: "SECRET_NAME", env_var: "THE_VAR")

      expect(repository.name_for_env_var("THE_VAR")).to eq("SECRET_NAME")
    end
  end
end
