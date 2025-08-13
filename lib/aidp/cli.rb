# frozen_string_literal: true

require "thor"
require_relative "steps"
require_relative "runner"
require_relative "progress"

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

    private

    def determine_next_step
      all_steps = Aidp::Steps.list
      completed_steps = Aidp::Progress.completed_steps
      in_progress_steps = Aidp::Progress.in_progress_steps

      # If there are steps in progress, return the first one
      if in_progress_steps.any?
        return in_progress_steps.first
      end

      # Find the first step that hasn't been completed
      all_steps.each do |step|
        unless completed_steps.include?(step)
          return step
        end
      end

      # All steps completed
      nil
    end
  end
end
