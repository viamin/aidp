# frozen_string_literal: true

require_relative "../config_paths"

module Aidp
  module Evaluations
    # Captures rich context for evaluation records
    #
    # Gathers information about:
    # - Prompt metadata (template, persona, skills, provider, model, tokens, settings)
    # - Work-loop data (unit count, checkpoints, retries, file modifications)
    # - Environment details (devcontainer status, Ruby version, branch info)
    #
    # @example Capturing context
    #   context = ContextCapture.new(project_dir: Dir.pwd)
    #   data = context.capture(step_name: "01_INIT", iteration: 3)
    class ContextCapture
      def initialize(project_dir: Dir.pwd, config: nil)
        @project_dir = project_dir
        @config = config

        Aidp.log_debug("context_capture", "initialize", project_dir: project_dir)
      end

      # Capture full context for an evaluation
      #
      # @param step_name [String, nil] Current work loop step
      # @param iteration [Integer, nil] Current iteration number
      # @param provider [String, nil] AI provider being used
      # @param model [String, nil] AI model being used
      # @param additional [Hash] Additional context to include
      # @return [Hash] Captured context
      def capture(step_name: nil, iteration: nil, provider: nil, model: nil, additional: {})
        Aidp.log_debug("context_capture", "capture",
          step_name: step_name, iteration: iteration, provider: provider)

        {
          prompt: capture_prompt_context(step_name),
          work_loop: capture_work_loop_context(step_name, iteration),
          environment: capture_environment_context,
          provider: {
            name: provider,
            model: model
          },
          timestamp: Time.now.iso8601
        }.merge(additional)
      end

      # Capture minimal context (for quick evaluations)
      #
      # @return [Hash] Minimal context with timestamp and environment basics
      def capture_minimal
        Aidp.log_debug("context_capture", "capture_minimal")

        {
          environment: {
            ruby_version: RUBY_VERSION,
            branch: current_git_branch,
            aidp_version: aidp_version
          },
          timestamp: Time.now.iso8601
        }
      end

      private

      def capture_prompt_context(step_name)
        prompt_file = File.join(@project_dir, ".aidp", "PROMPT.md")
        return {} unless File.exist?(prompt_file)

        content = File.read(prompt_file)
        {
          step_name: step_name,
          prompt_length: content.length,
          has_prompt: true
        }
      rescue => e
        Aidp.log_error("context_capture", "capture_prompt_context failed", error: e.message)
        {}
      end

      def capture_work_loop_context(step_name, iteration)
        checkpoint_file = ConfigPaths.checkpoint_file(@project_dir)
        checkpoint_data = if File.exist?(checkpoint_file)
          require "yaml"
          YAML.safe_load_file(checkpoint_file, permitted_classes: [Time, Date, Symbol])
        end

        {
          step_name: step_name,
          iteration: iteration,
          checkpoint: checkpoint_data ? {
            status: checkpoint_data["status"] || checkpoint_data[:status],
            metrics: checkpoint_data["metrics"] || checkpoint_data[:metrics]
          } : nil
        }
      rescue => e
        Aidp.log_error("context_capture", "capture_work_loop_context failed", error: e.message)
        {step_name: step_name, iteration: iteration}
      end

      def capture_environment_context
        {
          ruby_version: RUBY_VERSION,
          platform: RUBY_PLATFORM,
          branch: current_git_branch,
          commit: current_git_commit,
          devcontainer: in_devcontainer?,
          aidp_version: aidp_version
        }
      end

      def current_git_branch
        Dir.chdir(@project_dir) do
          `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
        end
      rescue
        nil
      end

      def current_git_commit
        Dir.chdir(@project_dir) do
          `git rev-parse --short HEAD 2>/dev/null`.strip
        end
      rescue
        nil
      end

      def in_devcontainer?
        File.exist?("/.dockerenv") || ENV["REMOTE_CONTAINERS"] == "true"
      end

      def aidp_version
        Aidp::VERSION if defined?(Aidp::VERSION)
      rescue
        nil
      end
    end
  end
end
