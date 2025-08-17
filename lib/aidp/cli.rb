# frozen_string_literal: true

require "thor"

module Aidp
  # CLI interface for both execute and analyze modes
  class CLI < Thor
    desc "execute [STEP]", "Run execute mode step(s)"
    option :force, type: :boolean, desc: "Force execution even if dependencies are not met"
    option :rerun, type: :boolean, desc: "Re-run a completed step"
    def execute(project_dir = Dir.pwd, step_name = nil, custom_options = {})
      if step_name
        runner = Aidp::Execute::Runner.new(project_dir)
        # Merge Thor options with custom options
        all_options = options.merge(custom_options)
        runner.run_step(step_name, all_options)
      else
        puts "Available execute steps:"
        Aidp::Execute::Steps::SPEC.keys.each { |step| puts "  - #{step}" }
        progress = Aidp::Execute::Progress.new(project_dir)
        next_step = progress.next_step
        {status: "success", message: "Available steps listed", next_step: next_step}
      end
    end

    desc "analyze [STEP]", "Run analyze mode step(s)"
    option :force, type: :boolean, desc: "Force execution even if dependencies are not met"
    option :rerun, type: :boolean, desc: "Re-run a completed step"
    def analyze(project_dir = Dir.pwd, step_name = nil, custom_options = {})
      if step_name
        runner = Aidp::Analyze::Runner.new(project_dir)
        # Merge Thor options with custom options
        all_options = options.merge(custom_options)
        runner.run_step(step_name, all_options)
      else
        puts "Available analyze steps:"
        Aidp::Analyze::Steps::SPEC.keys.each { |step| puts "  - #{step}" }
        progress = Aidp::Analyze::Progress.new(project_dir)
        next_step = progress.next_step
        {status: "success", message: "Available steps listed", next_step: next_step,
         completed_steps: progress.completed_steps}
      end
    end

    desc "analyze-approve STEP", "Approve a completed analyze gate step"
    def analyze_approve(project_dir = Dir.pwd, step_name = nil)
      progress = Aidp::Analyze::Progress.new(project_dir)
      progress.mark_step_completed(step_name)
      puts "✅ Approved analyze step: #{step_name}"
      {status: "success", step: step_name}
    end

    desc "analyze-reset", "Reset analyze mode progress"
    def analyze_reset(project_dir = Dir.pwd)
      progress = Aidp::Analyze::Progress.new(project_dir)
      progress.reset
      puts "🔄 Reset analyze mode progress"
      {status: "success", message: "Progress reset"}
    end

    desc "execute-approve STEP", "Approve a completed execute gate step"
    def execute_approve(project_dir = Dir.pwd, step_name = nil)
      progress = Aidp::Execute::Progress.new(project_dir)
      progress.mark_step_completed(step_name)
      puts "✅ Approved execute step: #{step_name}"
      {status: "success", step: step_name}
    end

    desc "execute-reset", "Reset execute mode progress"
    def execute_reset(project_dir = Dir.pwd)
      progress = Aidp::Execute::Progress.new(project_dir)
      progress.reset
      puts "🔄 Reset execute mode progress"
      {status: "success", message: "Progress reset"}
    end

    # Backward compatibility aliases
    desc "approve STEP", "Approve a completed execute gate step (alias for execute-approve)"
    def approve(project_dir = Dir.pwd, step_name = nil)
      execute_approve(project_dir, step_name)
    end

    desc "reset", "Reset execute mode progress (alias for execute-reset)"
    def reset(project_dir = Dir.pwd)
      execute_reset(project_dir)
    end

    desc "status", "Show current progress for both modes"
    def status
      puts "\n📊 AI Dev Pipeline Status"
      puts "=" * 50

      # Execute mode status
      execute_progress = Aidp::Execute::Progress.new(Dir.pwd)
      puts "\n🔧 Execute Mode:"
      Aidp::Execute::Steps::SPEC.keys.each do |step|
        status = execute_progress.step_completed?(step) ? "✅" : "⏳"
        puts "  #{status} #{step}"
      end

      # Analyze mode status
      analyze_progress = Aidp::Analyze::Progress.new(Dir.pwd)
      puts "\n🔍 Analyze Mode:"
      Aidp::Analyze::Steps::SPEC.keys.each do |step|
        status = analyze_progress.step_completed?(step) ? "✅" : "⏳"
        puts "  #{status} #{step}"
      end
    end

    desc "version", "Show version information"
    def version
      puts "Aidp version #{Aidp::VERSION}"
    end
  end
end
