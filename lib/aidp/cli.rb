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
    long_desc <<~DESC
      Run analyze mode steps. STEP can be:
      - A full step name (e.g., 01_REPOSITORY_ANALYSIS)
      - A step number (e.g., 01, 02, 03)
      - 'next' to run the next unfinished step
      - 'current' to run the current step
      - Empty to list available steps
    DESC
    option :force, type: :boolean, desc: "Force execution even if dependencies are not met"
    option :rerun, type: :boolean, desc: "Re-run a completed step"
    def analyze(*args)
      # Handle both old and new calling patterns for backwards compatibility
      case args.length
      when 0
        # analyze() - list steps
        project_dir = Dir.pwd
        step_name = nil
        custom_options = {}
      when 1
        # analyze(step_name) - new CLI pattern
        if args[0].is_a?(String) && Dir.exist?(args[0])
          # analyze(project_dir) - old test pattern
          project_dir = args[0]
          step_name = nil
        else
          # analyze(step_name) - new CLI pattern
          project_dir = Dir.pwd
          step_name = args[0]
        end
        custom_options = {}
      when 2
        # analyze(project_dir, step_name) - old test pattern
        # or analyze(step_name, options) - new CLI pattern
        if Dir.exist?(args[0])
          # analyze(project_dir, step_name)
          project_dir = args[0]
          step_name = args[1]
          custom_options = {}
        else
          # analyze(step_name, options)
          project_dir = Dir.pwd
          step_name = args[0]
          custom_options = args[1] || {}
        end
      when 3
        # analyze(project_dir, step_name, options) - old test pattern
        project_dir = args[0]
        step_name = args[1]
        custom_options = args[2] || {}
      else
        raise ArgumentError, "Wrong number of arguments (given #{args.length}, expected 0..3)"
      end

      progress = Aidp::Analyze::Progress.new(project_dir)

      if step_name
        # Resolve the step name
        resolved_step = resolve_analyze_step(step_name, progress)

        if resolved_step
          runner = Aidp::Analyze::Runner.new(project_dir)
          # Merge Thor options with custom options
          all_options = options.merge(custom_options)
          runner.run_step(resolved_step, all_options)
        else
          puts "❌ Step '#{step_name}' not found or not available"
          puts "\nAvailable steps:"
          Aidp::Analyze::Steps::SPEC.keys.each_with_index do |step, index|
            status = progress.step_completed?(step) ? "✅" : "⏳"
            puts "  #{status} #{sprintf("%02d", index + 1)}: #{step}"
          end
          {status: "error", message: "Step not found"}
        end
      else
        puts "Available analyze steps:"
        Aidp::Analyze::Steps::SPEC.keys.each_with_index do |step, index|
          status = progress.step_completed?(step) ? "✅" : "⏳"
          puts "  #{status} #{sprintf("%02d", index + 1)}: #{step}"
        end

        next_step = progress.next_step
        if next_step
          puts "\n💡 Run 'aidp analyze next' or 'aidp analyze #{next_step.match(/^(\d+)/)[1]}' to run the next step"
        end

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

    private

    def resolve_analyze_step(step_input, progress)
      step_input = step_input.to_s.downcase.strip

      case step_input
      when "next"
        progress.next_step
      when "current"
        progress.current_step || progress.next_step
      else
        # Check if it's a step number (e.g., "01", "02", "1", "2")
        if step_input.match?(/^\d{1,2}$/)
          step_number = sprintf("%02d", step_input.to_i)
          # Find step that starts with this number
          Aidp::Analyze::Steps::SPEC.keys.find { |step| step.start_with?(step_number) }
        else
          # Check if it's a full step name (case insensitive)
          Aidp::Analyze::Steps::SPEC.keys.find { |step| step.downcase == step_input }
        end
      end
    end
  end
end
