# frozen_string_literal: true

require "erb"
require "yaml"
require "json"

module Aidp
  module Analyze
    # Handles execution logic for analyze mode steps
    class Runner
      attr_reader :project_dir, :progress

      def initialize(project_dir)
        @project_dir = project_dir
        @progress = Aidp::Analyze::Progress.new(project_dir)
      end

      def run_step(step_name, options = {})
        unless Aidp::Analyze::Steps::SPEC.key?(step_name)
          raise "Step '#{step_name}' not found in analyze mode steps"
        end

        step_spec = Aidp::Analyze::Steps::SPEC[step_name]
        template_name = step_spec["templates"].first

        # Load template
        template = find_template(template_name)
        raise "Template '#{template_name}' not found" unless template

        # Compose prompt with agent persona
        prompt = composed_prompt(template_name, step_spec["agent"], options)

        # Execute step (mock for now)
        result = {
          status: "success",
          step: step_name,
          output_files: step_spec["outs"],
          prompt: prompt,
          agent: step_spec["agent"]
        }

        # Mark step as completed
        @progress.mark_step_completed(step_name)

        # Generate output files
        generate_output_files(step_name, step_spec["outs"], result)

        result
      end

      private

      def find_template(template_name)
        template_search_paths.each do |path|
          template_file = File.join(path, template_name)
          return File.read(template_file) if File.exist?(template_file)
        end
        nil
      end

      def template_search_paths
        [
          File.join(@project_dir, "templates", "ANALYZE"),
          File.join(@project_dir, "templates", "COMMON"),
          File.join(@project_dir, "templates")
        ]
      end

      def composed_prompt(template_name, agent_persona, options = {})
        template = find_template(template_name)
        return template unless template

        # Load agent base template if available
        agent_base = find_template("AGENT_BASE.md")
        if agent_base
          template = "#{agent_base}\n\n#{template}"
        end

        # Add agent persona context
        persona = Aidp::Analyze::AgentPersonas.get_persona(agent_persona)
        if persona
          template = "# Agent Persona: #{persona["name"]}\n#{persona["description"]}\n\n#{template}"
        end

        # Replace placeholders
        options.each do |key, value|
          template = template.gsub("{{#{key}}}", value.to_s)
        end

        template
      end

      def generate_output_files(step_name, output_files, result)
        output_files.each do |output_file|
          file_path = File.join(@project_dir, output_file)
          content = generate_output_content(step_name, output_file, result)
          File.write(file_path, content)
        end
      end

      def generate_output_content(step_name, output_file, result)
        case output_file
        when /\.md$/
          "# #{step_name} Analysis\n\nGenerated on #{Time.current}\n\n## Result\n\n#{result[:status]}\n\n## Agent\n\n#{result[:agent]}"
        when /\.json$/
          result.to_json
        else
          "Analysis output for #{step_name}: #{result[:status]}"
        end
      end
    end
  end
end
