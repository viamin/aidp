# frozen_string_literal: true

require "fileutils"
require "timeout"
require_relative "config"
require_relative "analyze_steps"
require_relative "util"
require_relative "analyze_progress"
require_relative "providers/base"
require_relative "providers/cursor"
require_relative "providers/anthropic"
require_relative "providers/gemini"
require_relative "providers/macos_ui"
require_relative "analyze_dependencies"

module Aidp
  class AnalyzeRunner
    PROVIDERS = {
      "cursor" => Providers::Cursor,
      "anthropic" => Providers::Anthropic,
      "gemini" => Providers::Gemini,
      "macos" => Providers::MacOSUI
    }.freeze

    def initialize(project_dir: Dir.pwd, config: Config.load)
      @project_dir = project_dir
      @config = config
      @dependencies = AnalyzeDependencies.new(project_dir)
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
      spec = AnalyzeSteps.for(step_name)
      roots = [
        File.join(Config.templates_root, "COMMON"),
        File.join(Config.templates_root, "ANALYZE"),
        Config.templates_root
      ]
      body = +""
      body << "# ANALYZE STEP: #{step_name}\n"
      body << "# AGENT: #{spec[:agent]}\n"

      # Add base agent template if available
      base_template = find_template("AGENT_BASE.md", roots)
      if base_template
        body << "\n--- BEGIN BASE TEMPLATE ---\n"
        body << File.read(base_template)
        body << "\n--- END BASE TEMPLATE ---\n"
      end

      spec[:templates].each do |t|
        template_path = find_template(t, roots)
        if template_path
          body << "\n--- BEGIN TEMPLATE: #{t} ---\n"
          body << File.read(template_path)
          body << "\n--- END TEMPLATE: #{t} ---\n"
        else
          warn "Warning: Template file not found: #{t}"
        end
      end

      # Provide project context and explicit output paths
      outs = @config.dig("analyze_outputs", step_name) || spec[:outs] || []
      body << "\n\n# CONTEXT\n"
      body << "Project workspace: #{@project_dir}\n"
      body << "Analysis mode: Legacy code analysis and documentation generation\n"
      body << "Write outputs to these exact paths (create dirs if missing):\n"
      outs.each { |o| body << "- #{o}\n" }

      # Add gate instructions if this is a gate step
      if spec[:gate]
        body << "\n\n# GATE INSTRUCTIONS\n"
        body << "This is an ANALYZE GATE step that requires human approval. Ask concise questions first, wait for my answers, then proceed.\n"
        body << "After completing this step, mark it as completed in the analyze progress tracker.\n"

        # Include existing questions and answers if available
        questions_file = questions_file_for_step(step_name)
        if File.exist?(questions_file)
          body << "\n\n# EXISTING QUESTIONS AND ANSWERS\n"
          body << "The following questions and answers were provided previously:\n"
          body << "```\n"
          body << File.read(questions_file)
          body << "\n```\n"
          body << "Use these answers to proceed with creating the complete analysis output.\n"
        end
      end

      body
    end

    def run_step(step_name, force: false, rerun: false)
      spec = AnalyzeSteps.for(step_name)
      outs = @config.dig("analyze_outputs", step_name) || spec[:outs] || []
      Util.ensure_dirs(outs, @project_dir)

      # Check dependencies and handle force/rerun scenarios
      completed_steps = AnalyzeProgress.completed_steps(@project_dir)

      if rerun
        handle_rerun_step(step_name, spec)
      elsif force
        handle_force_step(step_name, spec)
      else
        handle_normal_step(step_name, spec, completed_steps)
      end
    end

    def handle_normal_step(step_name, spec, completed_steps)
      # Check if step can be executed
      unless @dependencies.can_execute_step?(step_name, completed_steps)
        blocking_steps = @dependencies.get_blocking_steps(step_name, completed_steps)
        puts "\n❌ Cannot execute step '#{step_name}': missing dependencies"
        puts "Blocking steps: #{blocking_steps.join(", ")}"
        puts "Use 'aidp analyze #{step_name} --force' to override dependencies"
        return
      end

      execute_step(step_name, spec)
    end

    def handle_force_step(step_name, spec)
      completed_steps = AnalyzeProgress.completed_steps(@project_dir)
      impact = @dependencies.get_force_impact(step_name, completed_steps)

      puts "\n⚠️  FORCING STEP: #{step_name.upcase}"
      puts "Missing dependencies: #{impact[:missing_dependencies].join(", ")}"

      if impact[:risks].any?
        puts "\n⚠️  Risks:"
        impact[:risks].each { |risk| puts "  - #{risk}" }
      end

      if impact[:recommendations].any?
        puts "\n💡 Recommendations:"
        impact[:recommendations].each { |rec| puts "  - #{rec}" }
      end

      puts "\nProceeding with forced execution..."
      execute_step(step_name, spec, force: true)
    end

    def handle_rerun_step(step_name, spec)
      completed_steps = AnalyzeProgress.completed_steps(@project_dir)

      if completed_steps.include?(step_name)
        puts "\n🔄 RERUNNING STEP: #{step_name.upcase}"
        puts "This step was previously completed and will be re-executed."

        # Check if rerunning this step might affect dependent steps
        dependent_steps = @dependencies.get_dependent_steps(step_name)
        if dependent_steps.any?
          puts "\n⚠️  Note: The following steps depend on this one:"
          dependent_steps.each { |dep| puts "  - #{dep}" }
          puts "Consider rerunning dependent steps after this completes."
        end
      else
        puts "\n⚠️  Step '#{step_name}' has not been completed yet."
        puts "Running as normal execution..."
      end

      execute_step(step_name, spec, rerun: true)
    end

    def execute_step(step_name, spec, force: false, rerun: false)
      # Mark step as in progress
      AnalyzeProgress.mark_in_progress(step_name, @project_dir)

      # Show current progress
      AnalyzeProgress.display_status(@project_dir)

      provider = detect_provider
      prompt = composed_prompt(step_name)

      puts "\n🔍 Starting analyze step: #{step_name.upcase}"
      puts "Using provider: #{provider.name}"
      puts "Agent: #{spec[:agent]}"
      puts "Mode: #{if force
                      "FORCED"
                    else
                      rerun ? "RERUN" : "NORMAL"
                    end}"

      # Handle gate steps with enhanced prompts
      if spec[:gate]
        puts "\n🔄 Starting analyze gate step: #{step_name.upcase}"
        puts "This step may require additional information from you."
        puts "If the AI needs more details, it will create a file with questions."
        puts "Review the output and provide any missing information manually."

        begin
          with_progress_indicator do
            provider.send(prompt: prompt)
          end
        rescue Timeout::Error
          puts "\n⏰ Timeout: Analyze step took too long to complete"
          puts "The AI provider may still be working in the background."
          puts "Check your Cursor/IDE for any ongoing processes."
          return
        end

        puts "\n⏸️  ANALYZE GATE STEP: #{step_name.upcase}"
        puts "Review the generated analysis and ensure all required information is complete."
        puts "Run 'aidp analyze-approve #{step_name}' when ready to mark this step complete."
        return
      else
        # Non-gate steps with progress indicator and timeout
        begin
          with_progress_indicator do
            provider.send(prompt: prompt)
          end
        rescue Timeout::Error
          puts "\n⏰ Timeout: Analyze step took too long to complete"
          puts "The AI provider may still be working in the background."
          puts "Check your Cursor/IDE for any ongoing processes."
          return
        end
      end

      if spec[:gate]
        puts "\n⏸️  ANALYZE GATE STEP: #{step_name.upcase}"
        puts "This step requires human approval. Please review the analysis and approve to continue."
        puts "Run 'aidp analyze-approve #{step_name}' when ready to mark this step complete."
      else
        puts "\n✅ Analyze step completed: #{step_name.upcase}"
        AnalyzeProgress.mark_completed(step_name, @project_dir)
        AnalyzeProgress.display_status(@project_dir)
      end
    end

    private

    def find_template(template_name, roots)
      roots.each do |root|
        full_path = File.join(root, template_name)
        return full_path if File.exist?(full_path)
      end
      nil
    end

    def questions_file_for_step(step_name)
      case step_name
      when "repository"
        File.join(@project_dir, "REPOSITORY_ANALYSIS_QUESTIONS.md")
      when "architecture"
        File.join(@project_dir, "ARCHITECTURE_ANALYSIS_QUESTIONS.md")
      when "functionality"
        File.join(@project_dir, "FUNCTIONALITY_ANALYSIS_QUESTIONS.md")
      when "refactoring"
        File.join(@project_dir, "REFACTORING_ANALYSIS_QUESTIONS.md")
      end
    end

    def with_progress_indicator(timeout_seconds: 300, &block) # 5 minutes default timeout
      puts "⏳ Sending analyze prompt to AI provider..."

      # Start progress animation in a separate thread
      progress_thread = Thread.new do
        loop do
          print "\r⏳ Analyzing... "
          sleep(0.5)
          print "\r⏳ Analyzing.. "
          sleep(0.5)
          print "\r⏳ Analyzing... "
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
