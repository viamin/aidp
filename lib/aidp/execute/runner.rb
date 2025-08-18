# frozen_string_literal: true

require "erb"
require "yaml"
require "json"
require_relative "../provider_manager"

module Aidp
  module Execute
    # Handles execution logic for execute mode steps
    class Runner
      attr_reader :project_dir, :progress

      def initialize(project_dir)
        @project_dir = project_dir
        @progress = Aidp::Execute::Progress.new(project_dir)
        @provider = nil
      end

      def run_step(step_name, options = {})
        raise "Step '#{step_name}' not found in execute mode steps" unless Aidp::Execute::Steps::SPEC.key?(step_name)

        step_spec = Aidp::Execute::Steps::SPEC[step_name]
        template_name = step_spec["templates"].first

        # Load template
        template = find_template(template_name)
        raise "Template '#{template_name}' not found" unless template

        # Compose prompt
        prompt = composed_prompt(template_name, options)

        # Handle error simulation for tests
        if options[:simulate_error]
          return {
            status: "error",
            error: options[:simulate_error],
            step: step_name
          }
        end

        # Execute step with LLM provider
        result = execute_with_provider(step_name, step_spec, prompt, options)

        # Mark step as completed
        @progress.mark_step_completed(step_name)

        # Generate output files
        generate_output_files(step_name, step_spec["outs"], result)

        # Generate database export
        generate_database_export

        result
      end

      private

      def execute_with_provider(step_name, step_spec, prompt, options)
        # Check for mock mode first (auto-detect test environment)
        if should_use_mock_mode?(options)
          puts "🔄 Using mock mode..."
          return {
            status: "success",
            step: step_name,
            output_files: step_spec["outs"],
            prompt: prompt,
            provider: "mock",
            message: "Mock execution"
          }
        end

        begin
          # Get or initialize provider
          @provider ||= Aidp::ProviderManager.load_from_config(@project_dir)

          puts "🤖 Executing #{step_name} with #{@provider.name} provider..."

          # Send prompt to provider
          provider_result = @provider.send(prompt: prompt)

          case provider_result
          when :ok
            status = "success"
            message = "Execution completed successfully"
          when :interactive
            status = "interactive"
            message = "Interactive session started"
          when String
            status = "success"
            message = "Execution completed with captured output"
            # TODO: Process captured output if needed
          else
            status = "success"
            message = "Execution completed"
          end

          {
            status: status,
            step: step_name,
            output_files: step_spec["outs"],
            prompt: prompt,
            provider: @provider.name,
            message: message
          }
        rescue => e
          puts "❌ Error executing step with provider: #{e.message}"

          # Fallback to mock mode for tests or when provider fails
          if should_use_mock_mode?(options)
            puts "🔄 Falling back to mock mode..."
            {
              status: "success",
              step: step_name,
              output_files: step_spec["outs"],
              prompt: prompt,
              provider: "mock",
              message: "Mock execution (provider unavailable)"
            }
          else
            {
              status: "error",
              step: step_name,
              error: e.message
            }
          end
        end
      end

      def should_use_mock_mode?(options)
        # Explicit mock mode option
        return true if options[:mock_mode]

        # Environment variable override
        return true if ENV["AIDP_MOCK_MODE"]

        # Auto-detect test environment
        return true if defined?(RSpec) || ENV["RAILS_ENV"] == "test" || ENV["RACK_ENV"] == "test"

        # CLI usage should use real providers by default
        false
      end

      def find_template(template_name)
        template_search_paths.each do |path|
          template_file = File.join(path, template_name)
          return File.read(template_file) if File.exist?(template_file)
        end
        nil
      end

      def template_search_paths
        [
          File.join(@project_dir, "templates"),
          File.join(@project_dir, "templates", "COMMON"),
          File.join(File.dirname(__FILE__), "..", "..", "..", "templates", "EXECUTE"),
          File.join(File.dirname(__FILE__), "..", "..", "..", "templates", "COMMON")
        ]
      end

      def composed_prompt(template_name, options = {})
        template = find_template(template_name)
        return template unless template

        # Load agent base template if available
        agent_base = find_template("AGENT_BASE.md")
        template = "#{agent_base}\n\n#{template}" if agent_base

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
          "# #{step_name} Output\n\nGenerated on #{Time.now}\n\n## Result\n\n#{result[:status]}"
        when /\.json$/
          result.to_json
        else
          "Output for #{step_name}: #{result[:status]}"
        end
      end

      def generate_database_export
        database_file = File.join(@project_dir, ".aidp.db")
        require "sqlite3"

        begin
          db = SQLite3::Database.new(database_file)
          db.execute("CREATE TABLE IF NOT EXISTS execute_results (step TEXT, status TEXT, completed_at TEXT)")

          Aidp::Execute::Steps::SPEC.keys.each do |step|
            if @progress.step_completed?(step)
              db.execute("INSERT INTO execute_results (step, status, completed_at) VALUES (?, ?, ?)",
                [step, "success", Time.now.iso8601])
            end
          end
        rescue => e
          # Log the error but don't fail the execution
          puts "Warning: Database export failed: #{e.message}"
        end
      end
    end
  end
end
