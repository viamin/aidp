# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Init::DevcontainerGenerator do
  let(:temp_dir) { Dir.mktmpdir }
  let(:generator) { described_class.new(temp_dir) }
  let(:analysis) do
    {
      languages: {"Ruby" => 1000, "JavaScript" => 500},
      frameworks: [{name: "Rails", confidence: 0.9}],
      test_frameworks: [{name: "RSpec", confidence: 0.8}],
      tooling: [],
      config_files: [".rubocop.yml"],
      key_directories: ["lib", "spec"],
      repo_stats: {
        total_files: 50,
        total_directories: 10,
        docs_present: true,
        has_ci_config: true,
        has_containerization: false
      }
    }
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "#exists?" do
    it "returns false when .devcontainer directory doesn't exist" do
      expect(generator.exists?).to be false
    end

    it "returns true when .devcontainer directory exists" do
      FileUtils.mkdir_p(File.join(temp_dir, ".devcontainer"))
      expect(generator.exists?).to be true
    end
  end

  describe "#generate" do
    it "creates all devcontainer files" do
      files = generator.generate(analysis: analysis)

      expect(files).to be_an(Array)
      expect(files.size).to eq(4)
      expect(files).to all(be_a(String))
    end

    it "creates .devcontainer directory" do
      generator.generate(analysis: analysis)

      devcontainer_dir = File.join(temp_dir, ".devcontainer")
      expect(Dir.exist?(devcontainer_dir)).to be true
    end

    it "creates Dockerfile" do
      generator.generate(analysis: analysis)

      dockerfile = File.join(temp_dir, ".devcontainer", "Dockerfile")
      expect(File.exist?(dockerfile)).to be true
      expect(File.read(dockerfile)).to include("FROM")
    end

    it "creates devcontainer.json" do
      generator.generate(analysis: analysis)

      json_file = File.join(temp_dir, ".devcontainer", "devcontainer.json")
      expect(File.exist?(json_file)).to be true

      content = JSON.parse(File.read(json_file))
      expect(content).to have_key("name")
      expect(content).to have_key("build")
      expect(content).to have_key("capAdd")
    end

    it "creates init-firewall.sh" do
      generator.generate(analysis: analysis)

      firewall_script = File.join(temp_dir, ".devcontainer", "init-firewall.sh")
      expect(File.exist?(firewall_script)).to be true
      expect(File.executable?(firewall_script)).to be true
    end

    it "creates README.md" do
      generator.generate(analysis: analysis)

      readme = File.join(temp_dir, ".devcontainer", "README.md")
      expect(File.exist?(readme)).to be true
      expect(File.read(readme)).to include("Development Container")
    end

    it "accepts preferences" do
      preferences = {timezone: "America/New_York"}
      generator.generate(analysis: analysis, preferences: preferences)

      json_file = File.join(temp_dir, ".devcontainer", "devcontainer.json")
      content = JSON.parse(File.read(json_file))
      expect(content.dig("build", "args", "TZ")).to eq("America/New_York")
    end

    it "uses UTC as default timezone" do
      generator.generate(analysis: analysis)

      json_file = File.join(temp_dir, ".devcontainer", "devcontainer.json")
      content = JSON.parse(File.read(json_file))
      expect(content.dig("build", "args", "TZ")).to eq("UTC")
    end

    it "includes minimal VS Code extensions" do
      generator.generate(analysis: analysis)

      json_file = File.join(temp_dir, ".devcontainer", "devcontainer.json")
      content = JSON.parse(File.read(json_file))
      extensions = content.dig("customizations", "vscode", "extensions")

      expect(extensions).to include("editorconfig.editorconfig")
      expect(extensions).to include("eamodio.gitlens")
    end

    it "customizes project name in README" do
      generator.generate(analysis: analysis)

      readme = File.join(temp_dir, ".devcontainer", "README.md")
      content = File.read(readme)
      expect(content).to include(File.basename(temp_dir))
    end
  end

  describe "configuration" do
    it "sets correct capabilities" do
      generator.generate(analysis: analysis)

      json_file = File.join(temp_dir, ".devcontainer", "devcontainer.json")
      content = JSON.parse(File.read(json_file))

      expect(content["capAdd"]).to include("NET_ADMIN", "NET_RAW")
    end

    it "sets remote user" do
      generator.generate(analysis: analysis)

      json_file = File.join(temp_dir, ".devcontainer", "devcontainer.json")
      content = JSON.parse(File.read(json_file))

      expect(content["remoteUser"]).to eq("aidp")
    end

    it "configures volume mounts" do
      generator.generate(analysis: analysis)

      json_file = File.join(temp_dir, ".devcontainer", "devcontainer.json")
      content = JSON.parse(File.read(json_file))

      expect(content["mounts"]).to be_an(Array)
      expect(content["mounts"].size).to be > 0
    end
  end
end
