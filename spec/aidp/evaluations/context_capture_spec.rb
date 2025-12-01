# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "aidp/evaluations/context_capture"

RSpec.describe Aidp::Evaluations::ContextCapture do
  let(:temp_dir) { Dir.mktmpdir }
  let(:capture) { described_class.new(project_dir: temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#capture" do
    it "returns a context hash" do
      context = capture.capture

      expect(context).to be_a(Hash)
      expect(context[:timestamp]).to be_a(String)
    end

    it "captures environment context" do
      context = capture.capture

      expect(context[:environment]).to be_a(Hash)
      expect(context[:environment][:ruby_version]).to eq(RUBY_VERSION)
      expect(context[:environment][:platform]).to eq(RUBY_PLATFORM)
    end

    it "captures step_name when provided" do
      context = capture.capture(step_name: "01_INIT")

      expect(context[:work_loop][:step_name]).to eq("01_INIT")
    end

    it "captures iteration when provided" do
      context = capture.capture(iteration: 3)

      expect(context[:work_loop][:iteration]).to eq(3)
    end

    it "captures provider info when provided" do
      context = capture.capture(provider: "cursor", model: "cursor-default")

      expect(context[:provider][:name]).to eq("cursor")
      expect(context[:provider][:model]).to eq("cursor-default")
    end

    it "merges additional context" do
      context = capture.capture(additional: {custom: "value"})

      expect(context[:custom]).to eq("value")
    end
  end

  describe "#capture_minimal" do
    it "returns minimal context" do
      context = capture.capture_minimal

      expect(context).to be_a(Hash)
      expect(context[:timestamp]).to be_a(String)
      expect(context[:environment]).to be_a(Hash)
    end

    it "includes ruby version" do
      context = capture.capture_minimal

      expect(context[:environment][:ruby_version]).to eq(RUBY_VERSION)
    end

    it "does not include full context" do
      context = capture.capture_minimal

      expect(context).not_to have_key(:prompt)
      expect(context).not_to have_key(:work_loop)
      expect(context).not_to have_key(:provider)
    end
  end

  context "with existing prompt file" do
    before do
      FileUtils.mkdir_p(File.join(temp_dir, ".aidp"))
      File.write(File.join(temp_dir, ".aidp", "PROMPT.md"), "Test prompt content")
    end

    it "captures prompt context" do
      context = capture.capture

      expect(context[:prompt]).to be_a(Hash)
      expect(context[:prompt][:has_prompt]).to be true
      expect(context[:prompt][:prompt_length]).to eq(19)
    end
  end

  context "with existing checkpoint" do
    before do
      FileUtils.mkdir_p(File.join(temp_dir, ".aidp"))
      checkpoint_data = {
        "status" => "PASS",
        "metrics" => {"test_coverage" => 85}
      }
      File.write(File.join(temp_dir, ".aidp", "checkpoint.yml"), YAML.dump(checkpoint_data))
    end

    it "captures checkpoint context" do
      context = capture.capture

      expect(context[:work_loop][:checkpoint]).to be_a(Hash)
      expect(context[:work_loop][:checkpoint][:status]).to eq("PASS")
    end
  end
end
