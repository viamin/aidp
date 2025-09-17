# frozen_string_literal: true
# encoding: utf-8

require "optparse"
require_relative "harness/runner"
require_relative "execute/workflow_selector"
require_relative "harness/ui/enhanced_tui"
require_relative "harness/ui/enhanced_workflow_selector"
require_relative "harness/enhanced_runner"

module Aidp
  # CLI interface for AIDP
  class CLI
    def self.run(args = ARGV)
      options = parse_options(args)

      if options[:help]
        puts options[:parser]
        return 0
      end

      if options[:version]
        puts "Aidp version #{Aidp::VERSION}"
        return 0
      end

      # Start the interactive TUI
      puts "   Press Ctrl+C to stop\n"

      # Initialize the enhanced TUI
      tui = Aidp::Harness::UI::EnhancedTUI.new
      workflow_selector = Aidp::Harness::UI::EnhancedWorkflowSelector.new(tui)

      # Start TUI display loop
      tui.start_display_loop

      begin
        # First question: Choose mode
        mode = select_mode_interactive(tui)

        # Get workflow configuration (no spinner - may wait for user input)
        workflow_config = workflow_selector.select_workflow(harness_mode: false, mode: mode)

        # Pass workflow configuration to harness
        harness_options = {
          mode: mode,
          workflow_type: workflow_config[:workflow_type],
          selected_steps: workflow_config[:steps],
          user_input: workflow_config[:user_input]
        }

        # Create and run the enhanced harness
        harness_runner = Aidp::Harness::EnhancedRunner.new(Dir.pwd, mode, harness_options)
        result = harness_runner.run
        display_harness_result(result)
        0
      rescue Interrupt
        puts "\n\n⏹️  Interrupted by user"
        1
      rescue => e
        puts "\n❌ Error: #{e.message}"
        1
      ensure
        tui.stop_display_loop
      end
    end

    private

    def self.parse_options(args)
      options = {}

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: aidp [options]"
        opts.separator ""
        opts.separator "Start the interactive TUI (default)"
        opts.separator ""
        opts.separator "Options:"

        opts.on("-h", "--help", "Show this help message") do
          options[:help] = true
        end

        opts.on("-v", "--version", "Show version information") do
          options[:version] = true
        end
      end

      parser.parse!(args)
      options[:parser] = parser
      options
    end

    def self.select_mode_interactive(tui)
      mode_options = [
        "🔬 Analyze Mode - Analyze your codebase for insights and recommendations",
        "🏗️ Execute Mode - Build new features with guided development workflow"
      ]

      selected = tui.single_select("Welcome to AI Dev Pipeline! Choose your mode", mode_options, default: 1)

      if selected == mode_options[0]
        :analyze
      elsif selected == mode_options[1]
        :execute
      else
        :analyze
      end
    end

    def self.display_harness_result(result)
      case result[:status]
      when "completed"
        puts "\n✅ Harness completed successfully!"
        puts "   All steps finished automatically"
      when "stopped"
        puts "\n⏹️  Harness stopped by user"
        puts "   Execution terminated manually"
      when "error"
        # Error message already displayed by harness - don't duplicate
      else
        puts "\n🔄 Harness finished"
        puts "   Status: #{result[:status]}"
        puts "   Message: #{result[:message]}" if result[:message]
      end
    end
  end
end
