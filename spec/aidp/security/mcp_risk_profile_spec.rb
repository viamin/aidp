# frozen_string_literal: true

require "spec_helper"
require "aidp/security"

RSpec.describe Aidp::Security::McpRiskProfile do
  let(:project_dir) { Dir.mktmpdir("mcp_risk_profile_spec") }

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe ".load" do
    it "returns an empty profile when the file is missing" do
      profile = described_class.load(project_dir)

      expect(profile).to be_empty
      expect(profile.flags_for("filesystem")).to eq([])
    end

    it "loads and normalizes a saved profile" do
      Aidp::ConfigPaths.ensure_security_dir(project_dir)
      File.write(Aidp::ConfigPaths.mcp_risk_profile_file(project_dir), {
        generated_at: "2026-07-29T00:00:00Z",
        generator_model: "claude-sonnet",
        version: 1,
        tools: {
          filesystem: {
            flags: ["private_data", "private_data", "invalid_flag"],
            risk_level: "medium",
            rationale: "Reads files"
          }
        }
      }.to_yaml)

      profile = described_class.load(project_dir)

      expect(profile.generator_model).to eq("claude-sonnet")
      expect(profile.flags_for("filesystem")).to eq(["private_data"])
      expect(profile.risk_level_for("filesystem")).to eq("medium")
    end
  end

  describe "#save!" do
    it "persists the profile to the configured path" do
      profile = described_class.new(
        generated_at: "2026-07-29T00:00:00Z",
        generator_model: "claude-sonnet",
        tools: {
          "git" => {
            flags: ["egress"],
            risk_level: "medium",
            rationale: "Pushes to remotes"
          }
        }
      )

      profile.save!(project_dir)
      saved = YAML.safe_load_file(Aidp::ConfigPaths.mcp_risk_profile_file(project_dir), symbolize_names: true)

      expect(saved[:tools][:git][:flags]).to eq(["egress"])
      expect(saved[:tools][:git][:risk_level]).to eq("medium")
    end
  end
end
