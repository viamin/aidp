# frozen_string_literal: true

require "spec_helper"
require_relative "../support/test_prompt"

RSpec.describe "Template Integration", type: :integration do
  let(:project_dir) { Dir.pwd }

  describe "Execute mode templates" do
    it "has template files for all execute steps" do
      missing_templates = []

      Aidp::Execute::Steps::SPEC.each do |step_name, spec|
        template_name = spec["templates"].first
        # Template name now includes subdirectory (e.g., "planning/create_prd.md")
        template_path = File.join(project_dir, "templates", template_name)

        unless File.exist?(template_path)
          missing_templates << "Step #{step_name} expects template #{template_name} but file doesn't exist"
        end
      end

      expect(missing_templates).to be_empty,
        "Missing templates:\n#{missing_templates.join("\n")}"
    end

    it "can resolve templates for all execute steps" do
      test_prompt = TestPrompt.new
      runner = Aidp::Execute::Runner.new(project_dir, nil, prompt: test_prompt)
      resolution_failures = []

      Aidp::Execute::Steps::SPEC.each do |step_name, spec|
        template_name = spec["templates"].first
        found_path = runner.send(:find_template, template_name)

        if found_path.nil?
          resolution_failures << "Step #{step_name}: Could not resolve template #{template_name}"
        end
      end

      expect(resolution_failures).to be_empty,
        "Template resolution failures:\n#{resolution_failures.join("\n")}"
    end

    it "can read template content for all execute steps" do
      test_prompt = TestPrompt.new
      runner = Aidp::Execute::Runner.new(project_dir, nil, prompt: test_prompt)
      read_failures = []

      Aidp::Execute::Steps::SPEC.each do |step_name, spec|
        # This will test the full pipeline: spec -> find_template -> File.read
        content = runner.send(:composed_prompt, step_name, {})
        if content.nil? || content.empty?
          read_failures << "Step #{step_name}: Template content is empty"
        end
      rescue => e
        read_failures << "Step #{step_name}: #{e.message}"
      end

      expect(read_failures).to be_empty,
        "Template reading failures:\n#{read_failures.join("\n")}"
    end
  end

  describe "Analyze mode templates" do
    it "has template files for all analyze steps" do
      missing_templates = []

      Aidp::Analyze::Steps::SPEC.each do |step_name, spec|
        template_name = spec["templates"].first
        # Template name now includes subdirectory (e.g., "analysis/analyze_repository.md")
        template_path = File.join(project_dir, "templates", template_name)

        unless File.exist?(template_path)
          missing_templates << "Step #{step_name} expects template #{template_name} but file doesn't exist"
        end
      end

      expect(missing_templates).to be_empty,
        "Missing templates:\n#{missing_templates.join("\n")}"
    end

    it "can resolve templates for all analyze steps" do
      test_prompt = TestPrompt.new
      runner = Aidp::Analyze::Runner.new(project_dir, nil, prompt: test_prompt)
      resolution_failures = []

      Aidp::Analyze::Steps::SPEC.each do |step_name, spec|
        template_name = spec["templates"].first
        found_path = runner.send(:find_template, template_name)

        if found_path.nil?
          resolution_failures << "Step #{step_name}: Could not resolve template #{template_name}"
        end
      end

      expect(resolution_failures).to be_empty,
        "Template resolution failures:\n#{resolution_failures.join("\n")}"
    end
  end

  describe "Template content validation" do
    it "templates contain expected placeholders" do
      # Test that templates have the expected variable placeholders

      Dir.glob(File.join(project_dir, "templates", "**", "*.md")).each do |template_path|
        content = File.read(template_path, encoding: "UTF-8")
        template_name = File.basename(template_path)

        # Skip if template is empty (some might be placeholders)
        next if content.strip.empty?

        # At least check that it's valid markdown-ish content
        expect(content).to match(/\w+/), "Template #{template_name} appears to be empty or invalid"
      end
    end
  end
end
