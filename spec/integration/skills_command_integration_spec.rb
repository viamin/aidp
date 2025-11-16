# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "Skills Command Integration", type: :integration do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    # Set up a minimal project structure
    FileUtils.mkdir_p(File.join(tmpdir, ".aidp", "skills"))

    # Create a test skill file
    skill_file = File.join(tmpdir, ".aidp", "skills", "test_skill.md")
    File.write(skill_file, <<~SKILL)
      ---
      id: test_skill
      version: "1.0.0"
      name: Test Skill
      description: A test skill for integration testing
      ---

      Test prompt content for the skill
    SKILL

    # Stub Dir.pwd to return tmpdir (external boundary)
    allow(Dir).to receive(:pwd).and_return(tmpdir)
  end

  after do
    FileUtils.rm_rf(tmpdir) if tmpdir && Dir.exist?(tmpdir)
  end

  describe "CLI.run_skill_command" do
    before do
      # Stub display_message to capture output
      allow(Aidp::CLI).to receive(:display_message)
    end

    it "lists skills when no subcommand provided" do
      Aidp::CLI.send(:run_skill_command, [])

      # Should display messages about skills
      expect(Aidp::CLI).to have_received(:display_message).at_least(:once)
    end

    it "lists skills with 'list' subcommand" do
      Aidp::CLI.send(:run_skill_command, ["list"])

      expect(Aidp::CLI).to have_received(:display_message).at_least(:once)
    end

    it "shows skill details with 'show' subcommand" do
      Aidp::CLI.send(:run_skill_command, ["show", "test_skill"])

      expect(Aidp::CLI).to have_received(:display_message).at_least(:once)
    end

    it "handles missing skill ID for 'show' subcommand" do
      Aidp::CLI.send(:run_skill_command, ["show"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage/, type: :info)
    end

    it "searches skills with 'search' subcommand" do
      Aidp::CLI.send(:run_skill_command, ["search", "test"])

      expect(Aidp::CLI).to have_received(:display_message).at_least(:once)
    end

    it "handles missing query for 'search' subcommand" do
      Aidp::CLI.send(:run_skill_command, ["search"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage/, type: :info)
    end

    it "validates specific skill file with 'validate' subcommand" do
      skill_file = File.join(tmpdir, "valid_skill.md")
      File.write(skill_file, <<~SKILL)
        ---
        id: valid_skill
        version: "2.0.0"
        name: Valid Skill
        description: Valid test skill
        ---

        Skill content
      SKILL

      Aidp::CLI.send(:run_skill_command, ["validate", skill_file])

      expect(Aidp::CLI).to have_received(:display_message).with(/Valid skill file/, type: :success)
    end

    it "validates all skills when no file provided to 'validate'" do
      Aidp::CLI.send(:run_skill_command, ["validate"])

      expect(Aidp::CLI).to have_received(:display_message).at_least(:once)
    end

    it "handles nonexistent file for 'validate' subcommand" do
      Aidp::CLI.send(:run_skill_command, ["validate", "/nonexistent/file.md"])

      expect(Aidp::CLI).to have_received(:display_message).with(/File not found/, type: :error)
    end

    it "handles invalid skill file for 'validate' subcommand" do
      invalid_file = File.join(tmpdir, "invalid_skill.md")
      File.write(invalid_file, "Not a valid skill file")

      Aidp::CLI.send(:run_skill_command, ["validate", invalid_file])

      expect(Aidp::CLI).to have_received(:display_message).with(/Invalid skill file/, type: :error)
    end

    it "previews skill with 'preview' subcommand" do
      Aidp::CLI.send(:run_skill_command, ["preview", "test_skill"])

      expect(Aidp::CLI).to have_received(:display_message).at_least(:once)
    end

    it "handles missing skill ID for 'preview' subcommand" do
      Aidp::CLI.send(:run_skill_command, ["preview"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage/, type: :info)
    end

    it "handles 'delete' subcommand with missing skill ID" do
      Aidp::CLI.send(:run_skill_command, ["delete"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage/, type: :info)
    end

    it "handles 'new' subcommand with --yes flag" do
      # Stub the wizard controller to avoid interactive prompts
      controller = instance_double(Aidp::Skills::Wizard::Controller, run: true)
      allow(Aidp::Skills::Wizard::Controller).to receive(:new).and_return(controller)

      Aidp::CLI.send(:run_skill_command, ["new", "--yes"])

      expect(Aidp::Skills::Wizard::Controller).to have_received(:new).with(
        project_dir: tmpdir,
        options: hash_including(yes: true)
      )
    end

    it "handles 'new' subcommand with unknown option" do
      Aidp::CLI.send(:run_skill_command, ["new", "--invalid-option"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Unknown option/, type: :error)
    end

    it "handles 'edit' subcommand with missing skill ID" do
      Aidp::CLI.send(:run_skill_command, ["edit"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage/, type: :info)
    end

    it "handles 'diff' subcommand with missing skill ID" do
      Aidp::CLI.send(:run_skill_command, ["diff"])

      expect(Aidp::CLI).to have_received(:display_message).with(/Usage/, type: :info)
    end
  end
end
