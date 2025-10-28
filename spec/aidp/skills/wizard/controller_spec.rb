# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../../lib/aidp/skills/wizard/controller"

RSpec.describe Aidp::Skills::Wizard::Controller do
  let(:temp_dir) { Dir.mktmpdir }
  let(:controller) { described_class.new(project_dir: temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "initializes with project_dir" do
      expect(controller.project_dir).to eq(temp_dir)
    end

    it "initializes with empty options by default" do
      expect(controller.options).to eq({})
    end

    it "initializes with provided options" do
      opts = {id: "test", dry_run: true}
      ctrl = described_class.new(project_dir: temp_dir, options: opts)
      expect(ctrl.options).to eq(opts)
    end

    it "creates a template library" do
      expect(controller.template_library).to be_a(Aidp::Skills::Wizard::TemplateLibrary)
    end

    it "creates a prompter" do
      expect(controller.prompter).to be_a(Aidp::Skills::Wizard::Prompter)
    end

    it "creates a writer" do
      expect(controller.writer).to be_a(Aidp::Skills::Wizard::Writer)
    end
  end

  describe "#run" do
    it "returns nil on interrupt" do
      allow(controller.prompter).to receive(:gather_responses).and_raise(Interrupt)
      expect(controller.run).to be_nil
    end

    it "returns nil on error" do
      allow(controller.prompter).to receive(:gather_responses).and_raise(StandardError, "test error")
      expect(controller.run).to be_nil
    end

    it "writes skill and shows success when confirmed" do
      # Stub gather_responses
      responses = {
        id: "demo_skill",
        name: "Demo Skill",
        description: "A demo",
        expertise: ["ruby"],
        keywords: ["demo"],
        when_to_use: ["test"],
        when_not_to_use: [],
        compatible_providers: ["anthropic"],
        content: "# Demo Content"
      }
      allow(controller.prompter).to receive(:gather_responses).and_return(responses)

      # Stub prompt confirmation
      prompt_double = controller.prompter.prompt
      allow(prompt_double).to receive(:yes?).and_return(true)
      allow(prompt_double).to receive(:say)

      # Auto confirm save via prompt
      allow(controller).to receive(:confirm_save).and_return(true)

      result_path = controller.run
      expect(result_path).to be_a(String)
      expect(result_path).to match(/demo_skill\/SKILL\.md/) # path format
    end

    it "skips preview when minimal option set" do
      mini_controller = described_class.new(project_dir: temp_dir, options: {minimal: true})
      responses = {id: "mini", name: "Mini", description: "Desc", content: "Content"}
      allow(mini_controller.prompter).to receive(:gather_responses).and_return(responses)
      prompt_double = mini_controller.prompter.prompt
      allow(prompt_double).to receive(:yes?).and_return(true)
      allow(prompt_double).to receive(:say)
      expect(mini_controller).not_to receive(:show_preview)
      mini_controller.run
    end

    it "auto-confirms when yes option set" do
      yes_controller = described_class.new(project_dir: temp_dir, options: {yes: true})
      responses = {id: "auto", name: "Auto", description: "Desc", content: "Content"}
      allow(yes_controller.prompter).to receive(:gather_responses).and_return(responses)
      prompt_double = yes_controller.prompter.prompt
      allow(prompt_double).to receive(:say)
      expect(prompt_double).not_to receive(:yes?)
      yes_controller.run
    end

    it "warns on overwrite when skill exists" do
      overwrite_controller = described_class.new(project_dir: temp_dir)
      responses = {id: "exists", name: "Exists", description: "Desc", content: "Content"}
      allow(overwrite_controller.prompter).to receive(:gather_responses).and_return(responses)
      prompt_double = overwrite_controller.prompter.prompt
      allow(prompt_double).to receive(:yes?).and_return(true)
      allow(prompt_double).to receive(:say)
      allow(prompt_double).to receive(:warn)
      allow(overwrite_controller.writer).to receive(:exists?).with("exists").and_return(true)
      overwrite_controller.run
      expect(prompt_double).to have_received(:warn).with(/already exists/)
    end

    it "returns path in dry_run mode without success message" do
      dry_controller = described_class.new(project_dir: temp_dir, options: {dry_run: true})
      responses = {id: "dry", name: "Dry", description: "Desc", content: "Content"}
      allow(dry_controller.prompter).to receive(:gather_responses).and_return(responses)
      prompt_double = dry_controller.prompter.prompt
      allow(prompt_double).to receive(:say)
      allow(prompt_double).to receive(:yes?) # should not be called
      # Writer#write signature: (skill, content:, dry_run:, backup: true)
      expect(dry_controller.writer).to receive(:write).with(instance_of(Aidp::Skills::Skill), hash_including(content: /Dry/, dry_run: true, backup: true)).and_call_original
      path = dry_controller.run
      expect(path).to match(/dry\/SKILL\.md/)
    end
  end
end
