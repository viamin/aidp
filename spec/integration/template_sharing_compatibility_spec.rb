# frozen_string_literal: true

require "spec_helper"
require "aidp/cli"
require "aidp/runner"
require "aidp/analyze_runner"

RSpec.describe "Template Sharing Compatibility", type: :integration do
  let(:project_dir) { Dir.mktmpdir("aidp_template_test") }
  let(:cli) { Aidp::CLI.new }
  let(:execute_runner) { Aidp::Runner.new(project_dir) }
  let(:analyze_runner) { Aidp::AnalyzeRunner.new(project_dir) }

  before do
    setup_template_structure
    setup_mock_project
  end

  after do
    FileUtils.remove_entry(project_dir)
  end

  describe "Template Resolution and Sharing" do
    it "execute mode finds templates in correct order" do
      # Execute mode should prioritize templates/ over COMMON/
      template = execute_runner.send(:find_template, "00_PRD.md")
      expect(template).to include("EXECUTE_MODE_SPECIFIC")
      expect(template).not_to include("COMMON_TEMPLATE")
    end

    it "analyze mode finds templates in correct order" do
      # Analyze mode should prioritize templates/ANALYZE/ and templates/COMMON/ over templates/
      template = analyze_runner.send(:find_template, "01_REPOSITORY_ANALYSIS.md")
      expect(template).to include("ANALYZE_MODE_SPECIFIC")
      expect(template).not_to include("EXECUTE_MODE_SPECIFIC")
    end

    it "shared templates are accessible to both modes" do
      # Both modes should be able to access COMMON templates
      execute_template = execute_runner.send(:find_template, "COMMON_TEMPLATE.md")
      analyze_template = analyze_runner.send(:find_template, "COMMON_TEMPLATE.md")

      expect(execute_template).to include("COMMON_TEMPLATE")
      expect(analyze_template).to include("COMMON_TEMPLATE")
      expect(execute_template).to eq(analyze_template)
    end

    it "mode-specific templates take precedence over shared templates" do
      # When both mode-specific and shared templates exist, mode-specific wins
      execute_template = execute_runner.send(:find_template, "SHARED_OVERRIDE.md")
      analyze_template = analyze_runner.send(:find_template, "SHARED_OVERRIDE.md")

      expect(execute_template).to include("EXECUTE_OVERRIDE")
      expect(analyze_template).to include("ANALYZE_OVERRIDE")
      expect(execute_template).not_to eq(analyze_template)
    end

    it "fallback to default templates when mode-specific not found" do
      # When mode-specific template doesn't exist, fall back to default
      execute_template = execute_runner.send(:find_template, "FALLBACK_TEMPLATE.md")
      analyze_template = analyze_runner.send(:find_template, "FALLBACK_TEMPLATE.md")

      expect(execute_template).to include("DEFAULT_TEMPLATE")
      expect(analyze_template).to include("DEFAULT_TEMPLATE")
      expect(execute_template).to eq(analyze_template)
    end
  end

  describe "Agent Base Template Integration" do
    it "execute mode includes agent base template when available" do
      # Execute mode should include AGENT_BASE.md if available
      template = execute_runner.send(:composed_prompt, "00_PRD.md", {})
      expect(template).to include("EXECUTE_AGENT_BASE")
    end

    it "analyze mode includes agent base template when available" do
      # Analyze mode should include AGENT_BASE.md if available
      template = analyze_runner.send(:composed_prompt, "01_REPOSITORY_ANALYSIS.md", {})
      expect(template).to include("ANALYZE_AGENT_BASE")
    end

    it "agent base templates are mode-specific" do
      # Each mode should have its own agent base template
      execute_template = execute_runner.send(:composed_prompt, "00_PRD.md", {})
      analyze_template = analyze_runner.send(:composed_prompt, "01_REPOSITORY_ANALYSIS.md", {})

      expect(execute_template).to include("EXECUTE_AGENT_BASE")
      expect(analyze_template).to include("ANALYZE_AGENT_BASE")
      expect(execute_template).not_to eq(analyze_template)
    end
  end

  describe "Template Inheritance and Composition" do
    it "templates can inherit from shared base templates" do
      # Templates should be able to inherit from COMMON templates
      execute_template = execute_runner.send(:find_template, "INHERITED_TEMPLATE.md")
      analyze_template = analyze_runner.send(:find_template, "INHERITED_TEMPLATE.md")

      expect(execute_template).to include("INHERITED_CONTENT")
      expect(execute_template).to include("COMMON_BASE")
      expect(analyze_template).to include("INHERITED_CONTENT")
      expect(analyze_template).to include("COMMON_BASE")
    end

    it "template composition works correctly for both modes" do
      # Template composition should work for both execute and analyze modes
      execute_prompt = execute_runner.send(:composed_prompt, "00_PRD.md", {project_name: "Test Project"})
      analyze_prompt = analyze_runner.send(:composed_prompt, "01_REPOSITORY_ANALYSIS.md",
        {project_name: "Test Project"})

      expect(execute_prompt).to include("Test Project")
      expect(execute_prompt).to include("EXECUTE_MODE_SPECIFIC")
      expect(analyze_prompt).to include("Test Project")
      expect(analyze_prompt).to include("ANALYZE_MODE_SPECIFIC")
    end
  end

  describe "Backward Compatibility" do
    it "existing execute mode templates continue to work" do
      # Existing execute mode templates should work exactly as before
      template = execute_runner.send(:find_template, "00_PRD.md")
      expect(template).to include("EXECUTE_MODE_SPECIFIC")

      # Template should contain expected content
      expect(template).to include("Product Requirements Document")
      expect(template).to include("{{project_name}}")
    end

    it "execute mode template resolution order is preserved" do
      # Execute mode should still look in templates/ first, then COMMON/
      template = execute_runner.send(:find_template, "00_PRD.md")
      expect(template).to include("EXECUTE_MODE_SPECIFIC")

      # If we remove the execute-specific template, it should fall back to COMMON
      File.delete(File.join(project_dir, "templates", "00_PRD.md"))
      template = execute_runner.send(:find_template, "00_PRD.md")
      expect(template).to include("COMMON_TEMPLATE")
    end

    it "analyze mode does not interfere with execute mode templates" do
      # Analyze mode should not affect execute mode template resolution
      execute_template_before = execute_runner.send(:find_template, "00_PRD.md")

      # Run analyze mode
      analyze_runner.send(:find_template, "01_REPOSITORY_ANALYSIS.md")

      execute_template_after = execute_runner.send(:find_template, "00_PRD.md")
      expect(execute_template_before).to eq(execute_template_after)
    end
  end

  describe "Template Path Resolution" do
    it "correctly resolves template paths for execute mode" do
      paths = execute_runner.send(:template_search_paths)
      expect(paths).to include(File.join(project_dir, "templates"))
      expect(paths).to include(File.join(project_dir, "templates", "COMMON"))
      expect(paths.first).to eq(File.join(project_dir, "templates"))
    end

    it "correctly resolves template paths for analyze mode" do
      paths = analyze_runner.send(:template_search_paths)
      expect(paths).to include(File.join(project_dir, "templates", "ANALYZE"))
      expect(paths).to include(File.join(project_dir, "templates", "COMMON"))
      expect(paths).to include(File.join(project_dir, "templates"))
      expect(paths.first).to eq(File.join(project_dir, "templates", "ANALYZE"))
    end

    it "template search paths are isolated between modes" do
      execute_paths = execute_runner.send(:template_search_paths)
      analyze_paths = analyze_runner.send(:template_search_paths)

      expect(execute_paths).not_to eq(analyze_paths)
      expect(execute_paths.first).to eq(File.join(project_dir, "templates"))
      expect(analyze_paths.first).to eq(File.join(project_dir, "templates", "ANALYZE"))
    end
  end

  describe "Template Content Validation" do
    it "execute mode templates contain expected placeholders" do
      template = execute_runner.send(:find_template, "00_PRD.md")
      expect(template).to include("{{project_name}}")
      expect(template).to include("{{project_description}}")
      expect(template).to include("{{goals}}")
    end

    it "analyze mode templates contain expected placeholders" do
      template = analyze_runner.send(:find_template, "01_REPOSITORY_ANALYSIS.md")
      expect(template).to include("{{project_context}}")
      expect(template).to include("{{analysis_focus}}")
      expect(template).to include("{{expected_output}}")
    end

    it "shared templates contain generic placeholders" do
      template = execute_runner.send(:find_template, "COMMON_TEMPLATE.md")
      expect(template).to include("{{content}}")
      expect(template).to include("{{metadata}}")
    end
  end

  describe "Template Loading Performance" do
    it "template loading is efficient for both modes" do
      # Template loading should be fast and not cause performance issues
      start_time = Time.current

      100.times do
        execute_runner.send(:find_template, "00_PRD.md")
        analyze_runner.send(:find_template, "01_REPOSITORY_ANALYSIS.md")
      end

      duration = Time.current - start_time
      expect(duration).to be < 1.0 # Should complete in under 1 second
    end

    it "template caching works correctly" do
      # Second template lookup should be faster due to caching
      first_lookup = measure_template_lookup_time(execute_runner, "00_PRD.md")
      second_lookup = measure_template_lookup_time(execute_runner, "00_PRD.md")

      expect(second_lookup).to be <= first_lookup
    end
  end

  describe "Error Handling in Template Resolution" do
    it "handles missing templates gracefully" do
      # Should return nil or default content for missing templates
      template = execute_runner.send(:find_template, "NONEXISTENT_TEMPLATE.md")
      expect(template).to be_nil
    end

    it "handles malformed templates gracefully" do
      # Should handle templates with syntax errors
      create_malformed_template

      template = execute_runner.send(:find_template, "MALFORMED_TEMPLATE.md")
      expect(template).to be_a(String)
      expect(template).to include("MALFORMED_CONTENT")
    end

    it "handles empty templates gracefully" do
      # Should handle empty template files
      create_empty_template

      template = execute_runner.send(:find_template, "EMPTY_TEMPLATE.md")
      expect(template).to eq("")
    end
  end

  private

  def setup_template_structure
    # Create template directories
    FileUtils.mkdir_p(File.join(project_dir, "templates"))
    FileUtils.mkdir_p(File.join(project_dir, "templates", "COMMON"))
    FileUtils.mkdir_p(File.join(project_dir, "templates", "ANALYZE"))

    # Create execute mode specific templates
    File.write(File.join(project_dir, "templates", "00_PRD.md"), <<~TEMPLATE)
      # Product Requirements Document

      EXECUTE_MODE_SPECIFIC

      ## Project Information
      **Project Name**: {{project_name}}
      **Description**: {{project_description}}

      ## Goals
      {{goals}}
    TEMPLATE

    File.write(File.join(project_dir, "templates", "AGENT_BASE.md"), <<~TEMPLATE)
      # Agent Base Template

      EXECUTE_AGENT_BASE

      You are an AI assistant helping with project development.
    TEMPLATE

    # Create analyze mode specific templates
    File.write(File.join(project_dir, "templates", "ANALYZE", "01_REPOSITORY_ANALYSIS.md"), <<~TEMPLATE)
      # Repository Analysis

      ANALYZE_MODE_SPECIFIC

      ## Analysis Context
      {{project_context}}

      ## Analysis Focus
      {{analysis_focus}}

      ## Expected Output
      {{expected_output}}
    TEMPLATE

    File.write(File.join(project_dir, "templates", "ANALYZE", "AGENT_BASE.md"), <<~TEMPLATE)
      # Analyze Agent Base Template

      ANALYZE_AGENT_BASE

      You are an AI assistant specializing in code analysis.
    TEMPLATE

    # Create shared templates
    File.write(File.join(project_dir, "templates", "COMMON", "COMMON_TEMPLATE.md"), <<~TEMPLATE)
      # Common Template

      COMMON_TEMPLATE

      {{content}}

      {{metadata}}
    TEMPLATE

    # Create template override scenarios
    File.write(File.join(project_dir, "templates", "SHARED_OVERRIDE.md"), <<~TEMPLATE)
      # Shared Override Template

      EXECUTE_OVERRIDE

      This is the execute mode override.
    TEMPLATE

    File.write(File.join(project_dir, "templates", "ANALYZE", "SHARED_OVERRIDE.md"), <<~TEMPLATE)
      # Shared Override Template

      ANALYZE_OVERRIDE

      This is the analyze mode override.
    TEMPLATE

    # Create fallback template
    File.write(File.join(project_dir, "templates", "FALLBACK_TEMPLATE.md"), <<~TEMPLATE)
      # Fallback Template

      DEFAULT_TEMPLATE

      This is the default fallback template.
    TEMPLATE

    # Create inherited template
    File.write(File.join(project_dir, "templates", "INHERITED_TEMPLATE.md"), <<~TEMPLATE)
      # Inherited Template

      INHERITED_CONTENT

      {{> COMMON_TEMPLATE.md}}
    TEMPLATE

    File.write(File.join(project_dir, "templates", "COMMON", "COMMON_BASE.md"), <<~TEMPLATE)
      # Common Base Template

      COMMON_BASE

      This is the common base content.
    TEMPLATE
  end

  def setup_mock_project
    # Create basic project structure
    FileUtils.mkdir_p(File.join(project_dir, "app"))
    File.write(File.join(project_dir, "README.md"), "# Test Project")
  end

  def create_malformed_template
    File.write(File.join(project_dir, "templates", "MALFORMED_TEMPLATE.md"), <<~TEMPLATE)
      # Malformed Template

      MALFORMED_CONTENT

      {{unclosed_placeholder

      This template has syntax issues.
    TEMPLATE
  end

  def create_empty_template
    File.write(File.join(project_dir, "templates", "EMPTY_TEMPLATE.md"), "")
  end

  def measure_template_lookup_time(runner, template_name)
    start_time = Time.current
    runner.send(:find_template, template_name)
    Time.current - start_time
  end
end
