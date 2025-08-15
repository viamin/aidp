# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Shared::Config do
  describe ".load" do
    it "returns empty hash when no config file exists" do
      allow(File).to receive(:exist?).and_return(false)
      expect(Aidp::Shared::Config.load).to eq({})
    end

    it "loads config from file when it exists" do
      config_content = {"provider" => "cursor"}
      allow(File).to receive(:exist?).and_return(true)
      allow(YAML).to receive(:load_file).and_return(config_content)

      expect(Aidp::Shared::Config.load).to eq(config_content)
    end
  end

  describe ".templates_root" do
    it "returns correct templates path" do
      expected_path = File.join(Dir.pwd, "templates")
      expect(Aidp::Shared::Config.templates_root).to eq(expected_path)
    end
  end

  describe ".analyze_templates_root" do
    it "returns correct analyze templates path" do
      expected_path = File.join(Dir.pwd, "templates", "ANALYZE")
      expect(Aidp::Shared::Config.analyze_templates_root).to eq(expected_path)
    end
  end

  describe ".execute_templates_root" do
    it "returns correct execute templates path" do
      expected_path = File.join(Dir.pwd, "templates", "EXECUTE")
      expect(Aidp::Shared::Config.execute_templates_root).to eq(expected_path)
    end
  end

  describe ".common_templates_root" do
    it "returns correct common templates path" do
      expected_path = File.join(Dir.pwd, "templates", "COMMON")
      expect(Aidp::Shared::Config.common_templates_root).to eq(expected_path)
    end
  end
end
