# frozen_string_literal: true

require "spec_helper"
require "aidp/cli/prompts_command"
require "aidp/prompts/prompt_template_manager"

RSpec.describe Aidp::CLI::PromptsCommand do
  let(:temp_dir) { Dir.mktmpdir }
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:command) { described_class.new(prompt: prompt, project_dir: temp_dir) }
  let(:aidp_dir) { File.join(temp_dir, ".aidp") }
  let(:prompts_dir) { File.join(aidp_dir, "prompts") }

  before do
    FileUtils.mkdir_p(prompts_dir)
    allow(prompt).to receive(:yes?).and_return(true)
    allow(prompt).to receive(:say)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#run" do
    context "with no subcommand" do
      it "displays usage" do
        command.run([])
        expect(prompt).to have_received(:say).with(/Usage:.*prompts/, any_args)
      end
    end

    context "with --help" do
      it "displays usage" do
        command.run(["--help"])
        expect(prompt).to have_received(:say).with(/Usage:.*prompts/, any_args)
      end
    end

    context "with -h" do
      it "displays usage" do
        command.run(["-h"])
        expect(prompt).to have_received(:say).with(/Usage:.*prompts/, any_args)
      end
    end

    context "with unknown subcommand" do
      it "displays error and usage" do
        command.run(["unknown"])
        expect(prompt).to have_received(:say).with(/Unknown subcommand/, any_args)
      end
    end
  end

  describe "list subcommand" do
    it "lists available templates" do
      command.run(["list"])
      expect(prompt).to have_received(:say).with(/Available Prompt Templates/, any_args)
    end

    it "lists templates with ls alias" do
      command.run(["ls"])
      expect(prompt).to have_received(:say).with(/Available Prompt Templates/, any_args)
    end

    context "with --help" do
      it "displays list usage" do
        command.run(["list", "--help"])
        expect(prompt).to have_received(:say).with(/Usage:.*list/, any_args)
      end
    end

    context "with category filter" do
      it "filters by category" do
        command.run(["list", "--category", "decision_engine"])
        expect(prompt).to have_received(:say).with(/decision_engine/, any_args)
      end

      it "shows message for non-existent category" do
        command.run(["list", "-c", "nonexistent"])
        expect(prompt).to have_received(:say).with(/No templates found in category/, any_args)
      end
    end
  end

  describe "show subcommand" do
    context "with valid template_id" do
      it "shows template details" do
        command.run(["show", "decision_engine/condition_detection"])
        expect(prompt).to have_received(:say).with(/Template:.*condition_detection/, any_args)
      end
    end

    context "with view alias" do
      it "shows template details" do
        command.run(["view", "decision_engine/condition_detection"])
        expect(prompt).to have_received(:say).with(/Template:.*condition_detection/, any_args)
      end
    end

    context "without template_id" do
      it "displays error" do
        command.run(["show"])
        expect(prompt).to have_received(:say).with(/Template ID required/, any_args)
      end
    end

    context "with non-existent template" do
      it "displays error" do
        command.run(["show", "nonexistent/template"])
        expect(prompt).to have_received(:say).with(/Template not found/, any_args)
      end
    end

    context "with flag instead of template_id" do
      it "displays error" do
        command.run(["show", "--help"])
        expect(prompt).to have_received(:say).with(/Template ID required/, any_args)
      end
    end
  end

  describe "customize subcommand" do
    context "with valid template_id" do
      it "customizes template" do
        command.run(["customize", "decision_engine/condition_detection"])
        expect(prompt).to have_received(:say).with(/Template customized successfully/, any_args)
      end

      it "creates template in project directory" do
        command.run(["customize", "decision_engine/condition_detection"])
        expected_path = File.join(prompts_dir, "decision_engine", "condition_detection.yml")
        expect(File.exist?(expected_path)).to be true
      end
    end

    context "with edit alias" do
      it "customizes template" do
        command.run(["edit", "decision_engine/condition_detection"])
        expect(prompt).to have_received(:say).with(/Template customized successfully/, any_args)
      end
    end

    context "without template_id" do
      it "displays error" do
        command.run(["customize"])
        expect(prompt).to have_received(:say).with(/Template ID required/, any_args)
      end
    end

    context "with non-existent template" do
      it "displays error" do
        command.run(["customize", "nonexistent/template"])
        expect(prompt).to have_received(:say).with(/Template not found/, any_args)
      end
    end
  end

  describe "reset subcommand" do
    context "when template is customized" do
      before do
        # First customize the template
        category_dir = File.join(prompts_dir, "decision_engine")
        FileUtils.mkdir_p(category_dir)
        File.write(File.join(category_dir, "condition_detection.yml"), "test: value")
      end

      it "resets template when confirmed" do
        allow(prompt).to receive(:yes?).and_return(true)
        command.run(["reset", "decision_engine/condition_detection"])
        expect(prompt).to have_received(:say).with(/Template reset to default/, any_args)
      end

      it "cancels when not confirmed" do
        allow(prompt).to receive(:yes?).and_return(false)
        command.run(["reset", "decision_engine/condition_detection"])
        expect(prompt).to have_received(:say).with(/Reset cancelled/, any_args)
      end
    end

    context "when template is not customized" do
      it "displays message" do
        allow(prompt).to receive(:yes?).and_return(true)
        command.run(["reset", "decision_engine/condition_detection"])
        expect(prompt).to have_received(:say).with(/No customization found/, any_args)
      end
    end

    context "without template_id" do
      it "displays error" do
        command.run(["reset"])
        expect(prompt).to have_received(:say).with(/Template ID required/, any_args)
      end
    end
  end

  describe "#determine_source" do
    it "identifies project source" do
      path = File.join(prompts_dir, "test.yml")
      expect(command.send(:determine_source, path)).to eq(:project)
    end

    it "identifies builtin source" do
      path = "/some/other/path/test.yml"
      expect(command.send(:determine_source, path)).to eq(:builtin)
    end
  end

  describe "#truncate" do
    it "returns empty string for nil" do
      expect(command.send(:truncate, nil, 10)).to eq("")
    end

    it "returns text unchanged if shorter than max" do
      expect(command.send(:truncate, "short", 10)).to eq("short")
    end

    it "truncates and adds ellipsis if longer than max" do
      expect(command.send(:truncate, "this is a long text", 10)).to eq("this is...")
    end
  end
end
