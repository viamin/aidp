# frozen_string_literal: true

require "thor"

module Aidp
  module Shared
    # CLI interface for both execute and analyze modes
    class CLI < Thor
      desc "execute [STEP]", "Run execute mode step(s)"
      option :force, type: :boolean, desc: "Force execution even if dependencies are not met"
      option :rerun, type: :boolean, desc: "Re-run a completed step"
      def execute(step_name = nil)
        if step_name
          runner = Aidp::Execute::Runner.new(Dir.pwd)
          runner.run_step(step_name, options)
        else
          puts "Available execute steps:"
          Aidp::Execute::Steps::SPEC.keys.each { |step| puts "  - #{step}" }
        end
      end

      desc "analyze [STEP]", "Run analyze mode step(s)"
      option :force, type: :boolean, desc: "Force execution even if dependencies are not met"
      option :rerun, type: :boolean, desc: "Re-run a completed step"
      def analyze(step_name = nil)
        if step_name
          runner = Aidp::Analyze::Runner.new(Dir.pwd)
          runner.run_step(step_name, options)
        else
          puts "Available analyze steps:"
          Aidp::Analyze::Steps::SPEC.keys.each { |step| puts "  - #{step}" }
        end
      end

      desc "analyze-approve STEP", "Approve a completed analyze gate step"
      def analyze_approve(step_name)
        progress = Aidp::Analyze::Progress.new(Dir.pwd)
        progress.mark_step_completed(step_name)
        puts "✅ Approved analyze step: #{step_name}"
      end

      desc "analyze-reset", "Reset analyze mode progress"
      def analyze_reset
        progress = Aidp::Analyze::Progress.new(Dir.pwd)
        progress.reset
        puts "🔄 Reset analyze mode progress"
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
        puts "Aidp version #{Aidp::Shared::VERSION}"
      end
    end
  end
end
