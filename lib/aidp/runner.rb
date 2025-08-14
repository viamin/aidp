# frozen_string_literal: true

require "fileutils"
require "timeout"
require_relative "config"
require_relative "steps"
require_relative "util"
require_relative "progress"
require_relative "providers/base"
require_relative "providers/cursor"
require_relative "providers/anthropic"
require_relative "providers/gemini"
require_relative "providers/macos_ui"

module Aidp
  class Runner
    PROVIDERS = {
      "cursor" => Providers::Cursor,
      "anthropic" => Providers::Anthropic,
      "gemini" => Providers::Gemini,
      "macos" => Providers::MacOSUI
    }.freeze

    def initialize(project_dir: Dir.pwd, config: Config.load)
      @project_dir = project_dir
      @config = config
    end

    def detect_provider
      explicit = @config["provider"]
      return PROVIDERS[explicit].new if explicit && PROVIDERS[explicit]
      return PROVIDERS["cursor"].new if Providers::Cursor.available?
      return PROVIDERS["anthropic"].new if Providers::Anthropic.available?
      return PROVIDERS["gemini"].new if Providers::Gemini.available?

      raise "No supported provider found. Install Cursor CLI (preferred), Claude CLI, or Gemini CLI."
    end

    def composed_prompt(step_name)
      spec = Steps.for(step_name)
      roots = [Config.templates_root]
      body = +""
      body << "# STEP: #{step_name}\n"
      spec[:templates].each do |t|
        full = File.join(roots.first, t)
        body << "\n--- BEGIN TEMPLATE: #{t} ---\n"
        body << File.read(full)
        body << "\n--- END TEMPLATE: #{t} ---\n"
      end

      # Provide project context and explicit output paths
      outs = @config.dig("outputs", step_name) || spec[:outs] || []
      body << "\n\n# CONTEXT\n"
      body << "Project workspace: #{@project_dir}\n"
      body << "Write outputs to these exact paths (create dirs if missing):\n"
      outs.each { |o| body << "- #{o}\n" }

      # Add gate instructions if this is a gate step
      if spec[:gate]
        body << "\n\n# GATE INSTRUCTIONS\n"
        body << "This is a GATE step that requires human approval. Ask concise questions first, wait for my answers, then proceed.\n"
        body << "After completing this step, mark it as completed in the progress tracker.\n"

        # Include existing questions and answers if available
        questions_file = questions_file_for_step(step_name)
        if File.exist?(questions_file)
          body << "\n\n# EXISTING QUESTIONS AND ANSWERS\n"
          body << "The following questions and answers were provided previously:\n"
          body << "```\n"
          body << File.read(questions_file)
          body << "\n```\n"
          body << "Use these answers to proceed with creating the complete output.\n"
        end
      end

      body
    end

    def run_step(step_name)
      spec = Steps.for(step_name)
      outs = @config.dig("outputs", step_name) || spec[:outs] || []
      Util.ensure_dirs(outs, @project_dir)

      # Mark step as in progress
      Progress.mark_in_progress(step_name, @project_dir)

      # Show current progress
      Progress.display_status(@project_dir)

      provider = detect_provider
      prompt = composed_prompt(step_name)

      puts "\n🚀 Starting step: #{step_name.upcase}"
      puts "Using provider: #{provider.name}"

      # Handle gate steps with enhanced prompts
      if spec[:gate]
        puts "\n🔄 Starting gate step: #{step_name.upcase}"
        puts "This step may require additional information from you."
        puts "If the AI needs more details, it will create a file with questions."
        puts "Review the output and provide any missing information manually."

        begin
          with_progress_indicator do
            provider.send(prompt: prompt)
          end
        rescue Timeout::Error
          puts "\n⏰ Timeout: Step took too long to complete"
          puts "The AI provider may still be working in the background."
          puts "Check your Cursor/IDE for any ongoing processes."
          return
        end

        puts "\n⏸️  GATE STEP: #{step_name.upcase}"
        puts "Review the generated output and ensure all required information is complete."
        puts "Run 'aidp approve #{step_name}' when ready to mark this step complete."
        return
      else
        # Non-gate steps with progress indicator and timeout
        begin
          with_progress_indicator do
            provider.send(prompt: prompt)
          end
        rescue Timeout::Error
          puts "\n⏰ Timeout: Step took too long to complete"
          puts "The AI provider may still be working in the background."
          puts "Check your Cursor/IDE for any ongoing processes."
          return
        end
      end

      if spec[:gate]
        puts "\n⏸️  GATE STEP: #{step_name.upcase}"
        puts "This step requires human approval. Please review the output and approve to continue."
        puts "Run 'aidp approve #{step_name}' when ready to mark this step complete."
      else
        puts "\n✅ Step completed: #{step_name.upcase}"
        Progress.mark_completed(step_name, @project_dir)
        Progress.display_status(@project_dir)
      end
    end

    private

    def questions_file_for_step(step_name)
      case step_name
      when "prd"
        File.join(@project_dir, "PRD_QUESTIONS.md")
      when "arch"
        File.join(@project_dir, "ARCH_QUESTIONS.md")
      when "tasks"
        File.join(@project_dir, "TASKS_QUESTIONS.md")
      when "impl"
        File.join(@project_dir, "IMPL_QUESTIONS.md")
      end
    end

    def with_progress_indicator(timeout_seconds: 300, &block) # 5 minutes default timeout
      puts "⏳ Sending prompt to AI provider..."

      # Start progress animation in a separate thread
      progress_thread = Thread.new do
        loop do
          print "\r⏳ Processing... "
          sleep(0.5)
          print "\r⏳ Processing.. "
          sleep(0.5)
          print "\r⏳ Processing... "
          sleep(0.5)
        end
      end

      # Execute the actual work with timeout
      result = Timeout.timeout(timeout_seconds, &block)

      # Stop progress animation
      progress_thread.kill
      print "\r" + " " * 20 + "\r" # Clear the progress line

      result
    rescue Timeout::Error
      progress_thread&.kill
      print "\r" + " " * 20 + "\r" # Clear the progress line
      raise
    end
  end
end
