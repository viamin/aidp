# frozen_string_literal: true

require "thor"
require_relative "steps"
require_relative "runner"
require_relative "progress"
require_relative "analyze_steps"
require_relative "analyze_runner"
require_relative "analyze_progress"

module Aidp
  class CLI < Thor
    desc "detect", "Detect which provider will be used"
    def detect
      runner = Aidp::Runner.new
      puts "Provider: #{runner.detect_provider.name}"
    rescue => e
      warn e.message
      exit 1
    end

    desc "execute STEP", "Run a single step (e.g., prd, nfrs, arch, next, …)"
    def execute(step)
      # Handle the 'next' alias
      if step == "next"
        next_step = determine_next_step
        if next_step
          puts "🎯 Next step: #{next_step.upcase}"
          step = next_step
        else
          puts "🎉 All steps completed! No more steps to run."
          return
        end
      end

      Aidp::Runner.new.run_step(step)
    rescue => e
      warn e.message
      exit 1
    end

    desc "status", "Show current progress of all steps"
    def status
      Aidp::Progress.display_status
    end

    desc "approve STEP", "Mark a gate step as approved and complete (e.g., prd, arch, current, …)"
    def approve(step)
      # Handle the 'current' alias
      if step == "current"
        in_progress_steps = Aidp::Progress.in_progress_steps
        if in_progress_steps.any?
          step = in_progress_steps.first
          puts "🎯 Approving current step: #{step.upcase}"
        else
          puts "❌ Error: No step currently in progress"
          exit 1
        end
      end

      spec = Aidp::Steps.for(step)
      unless spec[:gate]
        puts "❌ Error: '#{step}' is not a gate step"
        exit 1
      end

      Aidp::Progress.mark_completed(step)
      puts "✅ Approved: #{step.upcase}"
      Aidp::Progress.display_status
    end

    desc "reset [STEP]", "Reset progress for a step (or all steps if no step specified)"
    def reset(step = nil)
      if step
        progress = Aidp::Progress.load
        progress.delete(step)
        Aidp::Progress.save(progress)
        puts "🔄 Reset progress for: #{step}"
      else
        File.delete(Aidp::Progress.tracker_file) if File.exist?(Aidp::Progress.tracker_file)
        puts "🔄 Reset progress for all steps"
      end
    end

    # Analyze Mode Commands
    desc "analyze [STEP]", "Run analyze mode step (e.g., repository, architecture, next, current, status)"
    option :force, type: :boolean, desc: "Force execution even if dependencies are not satisfied"
    option :rerun, type: :boolean, desc: "Rerun step even if already completed"
    def analyze(step = "next")
      # Handle the 'next' alias
      if step == "next"
        next_step = determine_next_analyze_step
        if next_step
          puts "🎯 Next analyze step: #{next_step.upcase}"
          step = next_step
        else
          puts "🎉 All analyze steps completed! No more steps to run."
          return
        end
      end

      # Handle the 'current' alias
      if step == "current"
        in_progress_steps = Aidp::AnalyzeProgress.in_progress_steps
        if in_progress_steps.any?
          step = in_progress_steps.first
          puts "🎯 Running current analyze step: #{step.upcase}"
        else
          puts "❌ Error: No analyze step currently in progress"
          exit 1
        end
      end

      # Handle the 'status' alias
      if step == "status"
        Aidp::AnalyzeProgress.display_status
        return
      end

      # Validate force and rerun options
      if options[:force] && options[:rerun]
        puts "❌ Error: Cannot use both --force and --rerun options together"
        exit 1
      end

      Aidp::AnalyzeRunner.new.run_step(step, force: options[:force], rerun: options[:rerun])
    rescue => e
      warn e.message
      exit 1
    end

    desc "analyze-approve STEP", "Mark an analyze gate step as approved and complete"
    def analyze_approve(step)
      # Handle the 'current' alias
      if step == "current"
        in_progress_steps = Aidp::AnalyzeProgress.in_progress_steps
        if in_progress_steps.any?
          step = in_progress_steps.first
          puts "🎯 Approving current analyze step: #{step.upcase}"
        else
          puts "❌ Error: No analyze step currently in progress"
          exit 1
        end
      end

      spec = Aidp::AnalyzeSteps.for(step)
      unless spec[:gate]
        puts "❌ Error: '#{step}' is not an analyze gate step"
        exit 1
      end

      Aidp::AnalyzeProgress.mark_completed(step)
      puts "✅ Approved analyze step: #{step.upcase}"
      Aidp::AnalyzeProgress.display_status
    end

    desc "analyze-reset [STEP]", "Reset analyze progress for a step (or all steps if no step specified)"
    def analyze_reset(step = nil)
      if step
        progress = Aidp::AnalyzeProgress.load
        progress.delete(step)
        Aidp::AnalyzeProgress.save(progress)
        puts "🔄 Reset analyze progress for: #{step}"
      else
        File.delete(Aidp::AnalyzeProgress.tracker_file) if File.exist?(Aidp::AnalyzeProgress.tracker_file)
        puts "🔄 Reset analyze progress for all steps"
      end
    end

    private

    def determine_next_step
      all_steps = Aidp::Steps.list
      completed_steps = Aidp::Progress.completed_steps
      in_progress_steps = Aidp::Progress.in_progress_steps

      # If there are steps in progress, return the first one
      return in_progress_steps.first if in_progress_steps.any?

      # Find the first step that hasn't been completed
      all_steps.each do |step|
        return step unless completed_steps.include?(step)
      end

      # All steps completed
      nil
    end

    def determine_next_analyze_step
      all_steps = Aidp::AnalyzeSteps.list
      completed_steps = Aidp::AnalyzeProgress.completed_steps
      in_progress_steps = Aidp::AnalyzeProgress.in_progress_steps

      # If there are steps in progress, return the first one
      return in_progress_steps.first if in_progress_steps.any?

      # Find the first step that hasn't been completed
      all_steps.each do |step|
        return step unless completed_steps.include?(step)
      end

      # All steps completed
      nil
    end
  end
end
