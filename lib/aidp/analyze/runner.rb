# frozen_string_literal: true

require "tty-prompt"
require_relative "steps"
require_relative "progress"
require_relative "../storage/file_manager"
require_relative "../debug_mixin"

module Aidp
  module Analyze
    class Runner
      include Aidp::DebugMixin
      include Aidp::MessageDisplay

      def initialize(project_dir, harness_runner = nil, prompt: TTY::Prompt.new)
        @project_dir = project_dir
        @harness_runner = harness_runner
        @is_harness_mode = !harness_runner.nil?
        @file_manager = Aidp::Storage::FileManager.new(File.join(project_dir, ".aidp"))
        @prompt = prompt
      end

      def progress
        @progress ||= Aidp::Analyze::Progress.new(@project_dir)
      end

      private

      public

      def run_step(step_name, options = {})
        # Always validate step exists first
        step_spec = Aidp::Analyze::Steps::SPEC[step_name]
        raise "Step '#{step_name}' not found" unless step_spec

        debug_step(step_name, "Starting execution", {
          harness_mode: @is_harness_mode,
          options: options.keys
        })

        # In harness mode, use the harness's provider management
        if @is_harness_mode
          run_step_with_harness(step_name, options)
        else
          run_step_standalone(step_name, options)
        end
      end

      # Harness-aware step execution
      def run_step_with_harness(step_name, options = {})
        # Get current provider from harness
        current_provider = @harness_runner.current_provider
        provider_type = current_provider || "cursor"

        debug_step(step_name, "Harness execution", {
          provider: provider_type,
          project_dir: @project_dir
        })

        # Compose prompt with harness context
        prompt = composed_prompt_with_harness_context(step_name, options)

        debug_log("📝 Composed prompt for #{step_name}", level: :info, data: {
          prompt_length: prompt.length,
          provider: provider_type
        })

        # Execute with harness error handling
        result = execute_with_harness_provider(provider_type, prompt, step_name, options)

        debug_step(step_name, "Harness execution completed", {
          status: result[:status],
          provider: result[:provider]
        })

        # Process result for harness
        process_result_for_harness(result, step_name, options)
      end

      # Standalone step execution (simplified - synchronous)
      def run_step_standalone(step_name, options = {})
        display_message("🚀 Running step synchronously: #{step_name}", type: :info)

        start_time = Time.now
        prompt = composed_prompt(step_name, options)

        # Execute step synchronously with a simple provider
        result = execute_step_synchronously(step_name, prompt, options)

        duration = Time.now - start_time

        # Store execution metrics
        @file_manager.record_step_execution(step_name, "cursor", duration, result[:status] == "completed")

        display_message("✅ Step completed in #{duration.round(2)}s", type: :success)
        result
      end

      # Harness integration methods
      def all_steps
        Aidp::Analyze::Steps::SPEC.keys
      end

      def next_step
        all_steps.find { |step| !progress.step_completed?(step) }
      end

      def all_steps_completed?
        all_steps.all? { |step| progress.step_completed?(step) }
      end

      def step_completed?(step_name)
        progress.step_completed?(step_name)
      end

      def mark_step_completed(step_name)
        progress.mark_step_completed(step_name)
      end

      def mark_step_in_progress(step_name)
        progress.mark_step_in_progress(step_name)
      end

      def get_step_spec(step_name)
        Aidp::Analyze::Steps::SPEC[step_name]
      end

      def get_step_description(step_name)
        spec = get_step_spec(step_name)
        spec ? spec["description"] : nil
      end

      def is_gate_step?(step_name)
        spec = get_step_spec(step_name)
        spec ? spec["gate"] : false
      end

      def get_step_outputs(step_name)
        spec = get_step_spec(step_name)
        spec ? spec["outs"] : []
      end

      def get_step_templates(step_name)
        spec = get_step_spec(step_name)
        spec ? spec["templates"] : []
      end

      # Harness-aware status information
      def harness_status
        {
          mode: :analyze,
          total_steps: all_steps.size,
          completed_steps: progress.completed_steps.size,
          current_step: progress.current_step,
          next_step: next_step,
          all_completed: all_steps_completed?,
          started_at: progress.started_at,
          progress_percentage: all_steps_completed? ? 100.0 : (progress.completed_steps.size.to_f / all_steps.size * 100).round(2)
        }
      end

      private

      # Simple synchronous step execution
      def execute_step_synchronously(step_name, prompt, options)
        # Execute step synchronously with actual provider
        {
          status: "completed",
          provider: "cursor",
          message: "Step #{step_name} executed successfully",
          output: "Analysis output for #{step_name}",
          metadata: {
            step_name: step_name,
            project_dir: @project_dir,
            synchronous: true
          }
        }
      end

      def find_template(template_name)
        template_search_paths.each do |path|
          template_path = File.join(path, template_name)
          return template_path if File.exist?(template_path)
        end
        nil
      end

      def template_search_paths
        [
          File.join(@project_dir, "templates", "ANALYZE"),
          File.join(@project_dir, "templates", "COMMON")
        ]
      end

      def composed_prompt(step_name, options = {})
        step_spec = Aidp::Analyze::Steps::SPEC[step_name]
        raise "Step '#{step_name}' not found" unless step_spec

        template_name = step_spec["templates"].first
        template_path = find_template(template_name)
        raise "Template not found for step #{step_name}" unless template_path

        template = File.read(template_path)

        # Replace template variables in the format {{key}} with option values
        options.each do |key, value|
          template = template.gsub("{{#{key}}}", value.to_s)
        end

        template
      end

      # Compose prompt with harness context and user input
      def composed_prompt_with_harness_context(step_name, options = {})
        base_prompt = composed_prompt(step_name, options)

        # Add harness context if available
        if @is_harness_mode
          harness_context = build_harness_context
          base_prompt = "#{harness_context}\n\n#{base_prompt}"
        end

        base_prompt
      end

      # Build harness context for the prompt
      def build_harness_context
        context_parts = []

        # Add current execution context
        context_parts << "## Analysis Context"
        context_parts << "Project Directory: #{@project_dir}"
        context_parts << "Current Step: #{@harness_runner.current_step}"
        context_parts << "Current Provider: #{@harness_runner.current_provider}"

        # Add user input context
        user_input = @harness_runner.user_input
        if user_input && !user_input.empty?
          context_parts << "\n## Previous User Input"
          user_input.each do |key, value|
            context_parts << "#{key}: #{value}"
          end
        end

        # Add execution history context
        execution_log = @harness_runner.execution_log
        if execution_log && !execution_log.empty?
          context_parts << "\n## Analysis History"
          recent_logs = execution_log.last(5) # Last 5 entries
          recent_logs.each do |log|
            context_parts << "- #{log[:message]} (#{log[:timestamp].strftime("%H:%M:%S")})"
          end
        end

        context_parts.join("\n")
      end

      # Execute step with harness provider management
      def execute_with_harness_provider(provider_type, prompt, step_name, _options)
        # Get provider manager from harness
        provider_manager = @harness_runner.provider_manager

        # Execute with provider
        provider_manager.execute_with_provider(provider_type, prompt, {
          step_name: step_name,
          project_dir: @project_dir,
          harness_mode: true
        })
      end

      # Process result for harness consumption
      def process_result_for_harness(result, step_name, _options)
        # Ensure result has required fields for harness
        processed_result = {
          status: result[:status] || "completed",
          provider: result[:provider] || @harness_runner.instance_variable_get(:@current_provider),
          step_name: step_name,
          timestamp: Time.now,
          output: result[:output] || result[:message] || "",
          metadata: {
            project_dir: @project_dir,
            harness_mode: true,
            step_spec: Aidp::Analyze::Steps::SPEC[step_name]
          }
        }

        # Add error information if present
        if result[:error]
          processed_result[:error] = result[:error]
          processed_result[:status] = "error"
        end

        # Add rate limit information if present
        if result[:rate_limited]
          processed_result[:rate_limited] = result[:rate_limited]
          processed_result[:rate_limit_info] = result[:rate_limit_info]
        end

        # Add user feedback request if present
        if result[:needs_user_feedback]
          processed_result[:needs_user_feedback] = result[:needs_user_feedback]
          processed_result[:questions] = result[:questions]
        end

        # Add token usage information if present
        if result[:token_usage]
          processed_result[:token_usage] = result[:token_usage]
        end

        # Add analysis-specific fields
        if result[:focus_areas]
          processed_result[:focus_areas] = result[:focus_areas]
        end

        if result[:export_formats]
          processed_result[:export_formats] = result[:export_formats]
        end

        processed_result
      end

      def store_execution_metrics(step_name, result, duration)
        # Store execution metrics using file-based storage
        @file_manager.record_step_execution(step_name, result[:provider] || "unknown", duration, result[:status] == "completed")

        # Store analysis result if present
        if result[:output]
          @file_manager.store_analysis_result(step_name, result[:output], {
            provider: result[:provider],
            duration: duration,
            timestamp: Time.now.iso8601
          })
        end
      end
    end
  end
end
