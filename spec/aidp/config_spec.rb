# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Config do
  let(:temp_dir) { Dir.mktmpdir("aidp_test") }
  let(:config_file) { File.join(temp_dir, "aidp.yml") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe ".load" do
    it "returns default configuration when no config files exist" do
      config = described_class.load(temp_dir)
      expect(config["provider"]).to be_nil
      expect(config["outputs"]["prd"]).to eq(["docs/PRD.md"])
    end

    it "loads configuration from project aidp.yml" do
      File.write(config_file, "provider: test\noutputs:\n  prd:\n    - custom/path.md")
      config = described_class.load(temp_dir)
      expect(config["provider"]).to eq("test")
      expect(config["outputs"]["prd"]).to eq(["custom/path.md"])
    end

    it "respects AIDP_PROVIDER environment variable" do
      ENV["AIDP_PROVIDER"] = "cursor"
      config = described_class.load(temp_dir)
      expect(config["provider"]).to eq("cursor")
      ENV.delete("AIDP_PROVIDER")
    end
  end

  describe ".templates_root" do
    it "returns path to templates directory" do
      root = described_class.templates_root
      expect(root).to be_a(String)
      expect(File.exist?(root)).to be true
    end
  end

  describe ".deep_merge" do
    it "merges nested hashes correctly" do
      a = {"a" => {"b" => 1, "c" => 2}}
      b = {"a" => {"b" => 3, "d" => 4}}
      result = described_class.deep_merge(a, b)
      expect(result["a"]["b"]).to eq(3)
      expect(result["a"]["c"]).to eq(2)
      expect(result["a"]["d"]).to eq(4)
    end
  end
end
