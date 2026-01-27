# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/temporal"

RSpec.describe Aidp::Temporal::Activities::CreatePromptActivity do
  let(:activity) { described_class.new }

  describe "#build_prompt_content" do
    let(:project_dir) { "/test/project" }
    let(:step_name) { "test-step" }

    it "includes step name" do
      result = activity.send(:build_prompt_content,
        project_dir: project_dir,
        step_name: step_name,
        step_spec: {},
        context: {})

      expect(result).to include("test-step")
      expect(result).to include("Implementation Task")
    end

    it "includes objective when description provided" do
      step_spec = {description: "Fix the bug in module X"}

      result = activity.send(:build_prompt_content,
        project_dir: project_dir,
        step_name: step_name,
        step_spec: step_spec,
        context: {})

      expect(result).to include("## Objective")
      expect(result).to include("Fix the bug in module X")
    end

    it "skips objective when no description" do
      result = activity.send(:build_prompt_content,
        project_dir: project_dir,
        step_name: step_name,
        step_spec: {},
        context: {})

      expect(result).not_to include("## Objective")
    end

    it "includes context from previous steps" do
      context = {previous_output: "Previous work completed successfully"}

      result = activity.send(:build_prompt_content,
        project_dir: project_dir,
        step_name: step_name,
        step_spec: {},
        context: context)

      expect(result).to include("## Context from Previous Steps")
      expect(result).to include("Previous work completed successfully")
    end

    it "skips context when not provided" do
      result = activity.send(:build_prompt_content,
        project_dir: project_dir,
        step_name: step_name,
        step_spec: {},
        context: {})

      expect(result).not_to include("## Context from Previous Steps")
    end

    it "includes requirements when provided" do
      context = {requirements: ["Must be backward compatible", "Must add tests"]}

      result = activity.send(:build_prompt_content,
        project_dir: project_dir,
        step_name: step_name,
        step_spec: {},
        context: context)

      expect(result).to include("## Requirements")
      expect(result).to include("Must be backward compatible")
      expect(result).to include("Must add tests")
    end

    it "skips requirements when empty" do
      context = {requirements: []}

      result = activity.send(:build_prompt_content,
        project_dir: project_dir,
        step_name: step_name,
        step_spec: {},
        context: context)

      expect(result).not_to include("## Requirements")
    end

    it "includes style guide reference when file exists" do
      allow(File).to receive(:exist?).with(/LLM_STYLE_GUIDE\.md/).and_return(true)

      result = activity.send(:build_prompt_content,
        project_dir: project_dir,
        step_name: step_name,
        step_spec: {},
        context: {})

      expect(result).to include("## Style Guide")
      expect(result).to include("LLM_STYLE_GUIDE.md")
    end

    it "skips style guide when file missing" do
      allow(File).to receive(:exist?).with(/LLM_STYLE_GUIDE\.md/).and_return(false)

      result = activity.send(:build_prompt_content,
        project_dir: project_dir,
        step_name: step_name,
        step_spec: {},
        context: {})

      expect(result).not_to include("## Style Guide")
    end

    it "always includes constraints and instructions" do
      result = activity.send(:build_prompt_content,
        project_dir: project_dir,
        step_name: step_name,
        step_spec: {},
        context: {})

      expect(result).to include("## Constraints")
      expect(result).to include("## Instructions")
      expect(result).to include("Follow the existing code style")
      expect(result).to include("Ensure all tests pass")
    end
  end
end
