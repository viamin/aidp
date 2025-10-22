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
  end
end
