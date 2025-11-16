# frozen_string_literal: true

require "spec_helper"
require "aidp/cli/config_command"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::CLI::ConfigCommand do
  let(:temp_dir) { Dir.mktmpdir("aidp_config_command_test") }
  let(:prompt) { instance_double(TTY::Prompt) }

  # Mock classes for dependency injection
  let(:wizard_double) { instance_double(Aidp::Setup::Wizard, run: true) }
  let(:wizard_class) do
    class_double(Aidp::Setup::Wizard).tap do |klass|
      allow(klass).to receive(:new).and_return(wizard_double)
    end
  end

  let(:command) do
    described_class.new(
      prompt: prompt,
      wizard_class: wizard_class,
      project_dir: temp_dir
    )
  end

  before do
    allow(prompt).to receive(:say)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#run with --interactive flag" do
    it "creates and runs the wizard" do
      expect(wizard_class).to receive(:new).with(temp_dir, prompt: prompt, dry_run: false).and_return(wizard_double)
      expect(wizard_double).to receive(:run)

      command.run(["--interactive"])
    end

    it "passes dry_run flag to wizard when specified" do
      expect(wizard_class).to receive(:new).with(temp_dir, prompt: prompt, dry_run: true).and_return(wizard_double)
      expect(wizard_double).to receive(:run)

      command.run(["--interactive", "--dry-run"])
    end

    it "handles flags in any order" do
      expect(wizard_class).to receive(:new).with(temp_dir, prompt: prompt, dry_run: true).and_return(wizard_double)
      expect(wizard_double).to receive(:run)

      command.run(["--dry-run", "--interactive"])
    end
  end

  describe "#run without --interactive flag" do
    it "shows usage message" do
      expect(prompt).to receive(:say).with(/Usage: aidp config --interactive/, color: :blue)
      allow(prompt).to receive(:say) # Allow other usage lines

      command.run([])
    end

    it "does not create wizard" do
      expect(wizard_class).not_to receive(:new)
      allow(prompt).to receive(:say)

      command.run([])
    end
  end

  describe "#run with --help flag" do
    it "shows usage message" do
      expect(prompt).to receive(:say).with(/Usage: aidp config --interactive/, color: :blue)
      allow(prompt).to receive(:say) # Allow other usage lines

      command.run(["--help"])
    end

    it "does not create wizard" do
      expect(wizard_class).not_to receive(:new)
      allow(prompt).to receive(:say)

      command.run(["--help"])
    end
  end

  describe "#run with -h flag" do
    it "shows usage message" do
      expect(prompt).to receive(:say).with(/Usage: aidp config --interactive/, color: :blue)
      allow(prompt).to receive(:say)

      command.run(["-h"])
    end
  end

  describe "#run with unknown option" do
    it "shows error message" do
      expect(prompt).to receive(:say).with("Unknown option: --unknown", color: :red)
      allow(prompt).to receive(:say) # Allow usage display

      command.run(["--unknown"])
    end

    it "shows usage after error" do
      allow(prompt).to receive(:say).with("Unknown option: --unknown", color: :red)
      expect(prompt).to receive(:say).with(/Usage: aidp config --interactive/, color: :blue)
      allow(prompt).to receive(:say)

      command.run(["--unknown"])
    end

    it "does not create wizard" do
      expect(wizard_class).not_to receive(:new)
      allow(prompt).to receive(:say)

      command.run(["--unknown"])
    end
  end

  describe "usage message content" do
    it "includes all required information" do
      messages = []
      allow(prompt).to receive(:say) { |msg, **_opts| messages << msg }

      command.run([])

      usage_text = messages.join("\n")
      expect(usage_text).to include("Usage: aidp config --interactive")
      expect(usage_text).to include("--interactive")
      expect(usage_text).to include("--dry-run")
      expect(usage_text).to include("--help")
      expect(usage_text).to include("Examples:")
    end
  end
end
