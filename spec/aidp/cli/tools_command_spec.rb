# frozen_string_literal: true

require "spec_helper"
require "stringio"

# Load necessary files
require_relative "../../../lib/aidp/config"
require_relative "../../../lib/aidp/metadata/cache"
require_relative "../../../lib/aidp/metadata/query"
require_relative "../../../lib/aidp/metadata/validator"

# Now load the command (CLI is defined as a class in cli.rb)
require_relative "../../../lib/aidp/cli/tools_command"

RSpec.describe Aidp::CLI::ToolsCommand do
  let(:test_dir) { Dir.mktmpdir }
  let(:skills_dir) { File.join(test_dir, "skills") }
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:mock_query) { instance_double(Aidp::Metadata::Query) }
  let(:mock_query_class) do
    klass = Class.new
    allow(klass).to receive(:new).and_return(mock_query)
    klass
  end
  let(:command) { described_class.new(project_dir: test_dir, prompt: prompt, query_class: mock_query_class) }

  before do
    FileUtils.mkdir_p(skills_dir)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  def create_skill_file(filename, **metadata)
    file_path = File.join(skills_dir, filename)

    frontmatter = {
      "id" => metadata[:id] || "test_skill",
      "title" => metadata[:title] || "Test Skill",
      "summary" => metadata[:summary] || "A test skill",
      "version" => metadata[:version] || "1.0.0",
      "applies_to" => metadata[:applies_to] || ["ruby"],
      "work_unit_types" => metadata[:work_unit_types] || ["implementation"]
    }.merge(metadata[:extra] || {})

    content = <<~MD
      ---
      #{YAML.dump(frontmatter).sub(/^---\n/, "")}---

      # Test Skill Content

      This is the skill content.
    MD

    File.write(file_path, content)
    file_path
  end

  describe "#initialize" do
    it "initializes with project_dir and prompt" do
      expect(command).to be_a(Aidp::CLI::ToolsCommand)
    end

    it "uses default project_dir when not provided" do
      cmd = described_class.new(prompt: prompt)
      expect(cmd).to be_a(Aidp::CLI::ToolsCommand)
    end
  end

  describe "#run" do
    it "shows help with no subcommand" do
      expect(prompt).to receive(:say).at_least(:once)
      result = command.run([])
      expect(result).to eq(0)
    end

    it "shows help with help subcommand" do
      expect(prompt).to receive(:say).at_least(:once)
      result = command.run(["help"])
      expect(result).to eq(0)
    end

    it "shows help with --help flag" do
      expect(prompt).to receive(:say).at_least(:once)
      result = command.run(["--help"])
      expect(result).to eq(0)
    end

    it "returns error for unknown subcommand" do
      expect(prompt).to receive(:say).with(/Unknown subcommand/)
      expect(prompt).to receive(:say).at_least(:once)
      result = command.run(["unknown"])
      expect(result).to eq(1)
    end

    it "handles list subcommand" do
      create_skill_file("test.md", id: "test_skill")

      # Mock the statistics and find_by_type methods using injected query
      allow(mock_query).to receive(:directory)
      allow(mock_query).to receive(:statistics).and_return({
        "total_tools" => 1,
        "by_type" => {"skill" => 1}
      })
      allow(mock_query).to receive(:find_by_type).and_return([])
      allow(prompt).to receive(:say)
      allow(Aidp::Config).to receive(:load_from_project).and_return(
        double(skill_directories: [skills_dir])
      )

      result = command.run(["list"])
      expect(result).to eq(0)
    end

    it "handles lint subcommand" do
      create_skill_file("test.md", id: "test_skill")

      allow(mock_query).to receive(:directory)
      allow(prompt).to receive(:say)
      allow(prompt).to receive(:ok)
      allow(Aidp::Config).to receive(:load_from_project).and_return(
        double(skill_directories: [skills_dir])
      )

      result = command.run(["lint"])
      expect(result).to eq(0)
    end

    it "handles reload subcommand" do
      allow(prompt).to receive(:say)
      allow(prompt).to receive(:ok)
      allow(Aidp::Config).to receive(:load_from_project).and_return(
        double(skill_directories: [skills_dir])
      )

      result = command.run(["reload"])
      expect(result).to eq(0)
    end

    it "requires tool_id for info subcommand" do
      expect(prompt).to receive(:say).with(/Error: tool ID required/)
      expect(prompt).to receive(:say).with(/Usage:/)

      result = command.run(["info"])
      expect(result).to eq(1)
    end

    it "handles info subcommand when tool not found" do
      create_skill_file("test.md", id: "test_skill")

      # Mock find_by_id to return nil using injected query
      allow(mock_query).to receive(:find_by_id).with("nonexistent").and_return(nil)
      expect(prompt).to receive(:error).with(/not found/)
      allow(Aidp::Config).to receive(:load_from_project).and_return(
        double(skill_directories: [skills_dir])
      )

      result = command.run(["info", "nonexistent"])
      expect(result).to eq(1) # Tool not found returns error
    end
  end

  describe "#show_help" do
    it "displays help information" do
      expect(prompt).to receive(:say).with(/AIDP Tools Management/).ordered
      expect(prompt).to receive(:say).with(/Usage:/).ordered
      expect(prompt).to receive(:say).at_least(:once)

      command.show_help
    end
  end
end
