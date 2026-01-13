# frozen_string_literal: true

require "spec_helper"
require "aidp/prompts/prompt_template_manager"

RSpec.describe Aidp::Prompts::PromptTemplateManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:project_prompts_dir) { File.join(temp_dir, ".aidp", "prompts") }
  let(:manager) { described_class.new(project_dir: temp_dir) }

  before do
    FileUtils.mkdir_p(project_prompts_dir)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#render" do
    context "with a built-in template" do
      it "renders the template with variable substitution" do
        # Built-in templates should exist
        prompt = manager.render(
          "decision_engine/condition_detection",
          response: "Rate limit exceeded"
        )

        expect(prompt).to include("Rate limit exceeded")
        expect(prompt).not_to include("{{response}}")
      end
    end

    context "with a project-level template" do
      before do
        category_dir = File.join(project_prompts_dir, "test_category")
        FileUtils.mkdir_p(category_dir)

        template_content = {
          "name" => "Test Template",
          "description" => "A test template",
          "version" => "1.0.0",
          "prompt" => "Hello, {{name}}! Your task is: {{task}}"
        }

        File.write(
          File.join(category_dir, "greeting.yml"),
          template_content.to_yaml
        )
      end

      it "renders the project-level template" do
        prompt = manager.render(
          "test_category/greeting",
          name: "Alice",
          task: "write tests"
        )

        expect(prompt).to eq("Hello, Alice! Your task is: write tests")
      end
    end

    context "when template not found" do
      it "raises TemplateNotFoundError" do
        expect {
          manager.render("nonexistent/template", name: "Bob")
        }.to raise_error(Aidp::Prompts::TemplateNotFoundError, /Template not found/)
      end
    end

    context "when template has no prompt" do
      before do
        category_dir = File.join(project_prompts_dir, "invalid")
        FileUtils.mkdir_p(category_dir)
        File.write(
          File.join(category_dir, "no_prompt.yml"),
          {"name" => "No Prompt Template"}.to_yaml
        )
      end

      it "raises TemplateNotFoundError" do
        expect {
          manager.render("invalid/no_prompt")
        }.to raise_error(Aidp::Prompts::TemplateNotFoundError, /has no prompt/)
      end
    end
  end

  describe "#template_exists?" do
    it "returns true for existing built-in template" do
      expect(manager.template_exists?("decision_engine/condition_detection")).to be true
    end

    it "returns false for non-existent template" do
      expect(manager.template_exists?("nonexistent/template")).to be false
    end

    context "with project-level template" do
      before do
        category_dir = File.join(project_prompts_dir, "custom")
        FileUtils.mkdir_p(category_dir)
        File.write(File.join(category_dir, "test.yml"), {"prompt" => "test"}.to_yaml)
      end

      it "returns true for project-level template" do
        expect(manager.template_exists?("custom/test")).to be true
      end
    end
  end

  describe "#list_templates" do
    it "lists all available templates" do
      templates = manager.list_templates

      expect(templates).to be_an(Array)
      expect(templates).not_to be_empty

      # Should include built-in decision_engine templates
      ids = templates.map { |t| t[:id] }
      expect(ids).to include("decision_engine/condition_detection")
      expect(ids).to include("decision_engine/error_classification")
    end

    it "includes metadata for each template" do
      templates = manager.list_templates

      template = templates.find { |t| t[:id] == "decision_engine/condition_detection" }

      expect(template[:name]).to eq("Condition Detection")
      expect(template[:version]).to eq("1.0.0")
      expect(template[:category]).to eq("decision_engine")
    end
  end

  describe "#template_info" do
    it "returns detailed info for existing template" do
      info = manager.template_info("decision_engine/condition_detection")

      expect(info[:id]).to eq("decision_engine/condition_detection")
      expect(info[:name]).to eq("Condition Detection")
      expect(info[:source]).to eq(:builtin)
      expect(info[:variables]).to include("response")
      expect(info[:prompt_preview]).to be_a(String)
    end

    it "returns nil for non-existent template" do
      info = manager.template_info("nonexistent/template")

      expect(info).to be_nil
    end
  end

  describe "#customize_template" do
    it "copies template to project directory" do
      path = manager.customize_template("decision_engine/condition_detection")

      expect(File.exist?(path)).to be true
      expect(path).to start_with(project_prompts_dir)

      content = YAML.safe_load_file(path, permitted_classes: [Symbol])
      expect(content["name"]).to eq("Condition Detection")
    end

    it "raises error for non-existent template" do
      expect {
        manager.customize_template("nonexistent/template")
      }.to raise_error(Aidp::Prompts::TemplateNotFoundError)
    end

    context "when already customized" do
      before do
        manager.customize_template("decision_engine/condition_detection")
      end

      it "returns existing path without overwriting" do
        # Modify the customized template
        path = manager.customize_template("decision_engine/condition_detection")
        original_content = File.read(path)

        File.write(path, original_content + "\n# Modified")

        # Calling customize again should not overwrite
        second_path = manager.customize_template("decision_engine/condition_detection")
        expect(File.read(second_path)).to include("# Modified")
      end
    end
  end

  describe "#reset_template" do
    context "when template is customized" do
      before do
        manager.customize_template("decision_engine/condition_detection")
      end

      it "removes the customized template" do
        result = manager.reset_template("decision_engine/condition_detection")

        expect(result).to be true

        path = File.join(project_prompts_dir, "decision_engine", "condition_detection.yml")
        expect(File.exist?(path)).to be false
      end
    end

    context "when template is not customized" do
      it "returns false" do
        result = manager.reset_template("decision_engine/condition_detection")

        expect(result).to be false
      end
    end
  end

  describe "#clear_cache" do
    it "clears the internal cache" do
      # Load a template to populate cache
      manager.load_template("decision_engine/condition_detection")

      expect(manager.cache).not_to be_empty

      manager.clear_cache

      expect(manager.cache).to be_empty
    end
  end

  describe "template precedence" do
    context "when project template exists" do
      before do
        category_dir = File.join(project_prompts_dir, "decision_engine")
        FileUtils.mkdir_p(category_dir)

        custom_template = {
          "name" => "Custom Condition Detection",
          "description" => "A customized version",
          "version" => "2.0.0",
          "prompt" => "CUSTOM PROMPT: {{response}}"
        }

        File.write(
          File.join(category_dir, "condition_detection.yml"),
          custom_template.to_yaml
        )
      end

      it "uses project template over built-in" do
        # Clear cache to ensure fresh load
        manager.clear_cache

        prompt = manager.render(
          "decision_engine/condition_detection",
          response: "test error"
        )

        expect(prompt).to include("CUSTOM PROMPT")
      end

      it "shows project source in template info" do
        manager.clear_cache

        info = manager.template_info("decision_engine/condition_detection")

        expect(info[:source]).to eq(:project)
        expect(info[:version]).to eq("2.0.0")
      end
    end
  end

  describe "#versionable?" do
    it "returns true for work_loop templates" do
      expect(manager.versionable?("work_loop/decide_whats_next")).to be true
    end

    it "returns false for decision_engine templates" do
      expect(manager.versionable?("decision_engine/condition_detection")).to be false
    end

    it "returns false for unknown categories" do
      expect(manager.versionable?("custom/template")).to be false
    end
  end

  describe "versioned template integration" do
    let(:mock_version_manager) { instance_double("Aidp::Prompts::TemplateVersionManager") }
    let(:manager_with_mock) { described_class.new(project_dir: temp_dir, version_manager: mock_version_manager) }
    let(:work_loop_template_id) { "work_loop/decide_whats_next" }

    describe "#render with versioned templates" do
      context "when versioned template exists" do
        let(:versioned_content) do
          {
            "name" => "Versioned Template",
            "version" => "2.0.0",
            "prompt" => "VERSIONED: {{VARIABLE}}"
          }
        end

        before do
          allow(mock_version_manager).to receive(:active_version)
            .with(template_id: work_loop_template_id)
            .and_return({
              id: 1,
              version_number: 2,
              content: versioned_content.to_yaml
            })
        end

        it "uses versioned template content" do
          prompt = manager_with_mock.render(work_loop_template_id, VARIABLE: "test")

          expect(prompt).to include("VERSIONED: test")
        end
      end

      context "when no versioned template exists" do
        before do
          # Create a file-based template
          category_dir = File.join(project_prompts_dir, "work_loop")
          FileUtils.mkdir_p(category_dir)

          File.write(
            File.join(category_dir, "decide_whats_next.yml"),
            {"name" => "File Template", "prompt" => "FILE: {{VAR}}"}.to_yaml
          )

          allow(mock_version_manager).to receive(:active_version)
            .and_return(nil)
        end

        it "falls back to file-based template" do
          prompt = manager_with_mock.render(work_loop_template_id, VAR: "fallback")

          expect(prompt).to include("FILE: fallback")
        end
      end

      context "with use_versioned: false" do
        before do
          # Create a file-based template
          category_dir = File.join(project_prompts_dir, "work_loop")
          FileUtils.mkdir_p(category_dir)

          File.write(
            File.join(category_dir, "decide_whats_next.yml"),
            {"name" => "File Template", "prompt" => "FILE: {{VAR}}"}.to_yaml
          )
        end

        it "skips versioned lookup" do
          expect(mock_version_manager).not_to receive(:active_version)

          prompt = manager_with_mock.render(work_loop_template_id, use_versioned: false, VAR: "direct")

          expect(prompt).to include("FILE: direct")
        end
      end
    end

    describe "#load_template with versioned templates" do
      context "when versioned template exists" do
        before do
          allow(mock_version_manager).to receive(:active_version)
            .and_return({
              id: 1,
              content: {"name" => "Versioned", "prompt" => "test"}.to_yaml
            })
        end

        it "returns versioned template data" do
          data = manager_with_mock.load_template(work_loop_template_id)

          expect(data["name"]).to eq("Versioned")
        end

        it "caches versioned template" do
          manager_with_mock.load_template(work_loop_template_id)
          expect(manager_with_mock.cache).not_to be_empty
        end
      end
    end

    describe "#render_versioned" do
      context "with valid versioned template" do
        before do
          allow(mock_version_manager).to receive(:active_version)
            .and_return({
              id: 1,
              version_number: 1,
              content: {"prompt" => "Hello {{NAME}}"}.to_yaml
            })
        end

        it "renders with variable substitution" do
          result = manager_with_mock.render_versioned(work_loop_template_id, NAME: "World")

          expect(result).to eq("Hello World")
        end
      end

      context "for non-versionable template" do
        it "returns nil" do
          result = manager_with_mock.render_versioned("decision_engine/condition_detection", foo: "bar")

          expect(result).to be_nil
        end
      end

      context "when version manager fails" do
        before do
          allow(mock_version_manager).to receive(:active_version)
            .and_raise(StandardError.new("DB error"))
        end

        it "returns nil gracefully" do
          result = manager_with_mock.render_versioned(work_loop_template_id, foo: "bar")

          expect(result).to be_nil
        end
      end
    end
  end
end
