# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::AutoUpdate do
  let(:project_dir) { "/tmp/auto-update-test" }
  let(:config_hash) { {auto_update: {enabled: true, policy: "minor"}} }

  before do
    allow(Aidp::Config).to receive(:load_harness_config).with(project_dir).and_return(config_hash)
  end

  describe ".coordinator" do
    it "builds coordinator from configuration" do
      coordinator = instance_double(Aidp::AutoUpdate::Coordinator)
      expect(Aidp::AutoUpdate::Coordinator).to receive(:from_config).with(
        config_hash[:auto_update],
        project_dir: project_dir
      ).and_return(coordinator)

      expect(described_class.coordinator(project_dir: project_dir)).to eq(coordinator)
    end
  end

  describe ".enabled?" do
    it "returns true when policy is not disabled" do
      policy = instance_double(Aidp::AutoUpdate::UpdatePolicy, disabled?: false)
      expect(Aidp::AutoUpdate::UpdatePolicy).to receive(:from_config).with(config_hash[:auto_update]).and_return(policy)

      expect(described_class.enabled?(project_dir: project_dir)).to be true
    end

    it "returns false when policy is disabled" do
      policy = instance_double(Aidp::AutoUpdate::UpdatePolicy, disabled?: true)
      expect(Aidp::AutoUpdate::UpdatePolicy).to receive(:from_config).and_return(policy)

      expect(described_class.enabled?(project_dir: project_dir)).to be false
    end
  end

  describe ".policy" do
    it "returns update policy" do
      policy = instance_double(Aidp::AutoUpdate::UpdatePolicy)
      expect(Aidp::AutoUpdate::UpdatePolicy).to receive(:from_config).with(config_hash[:auto_update]).and_return(policy)

      expect(described_class.policy(project_dir: project_dir)).to eq(policy)
    end
  end
end
