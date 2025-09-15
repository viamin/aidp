# frozen_string_literal: true

require "thor"
require_relative "harness/runner"
require_relative "execute/workflow_selector"

module Aidp
  # CLI interface for both execute and analyze modes
  class CLI < Thor
    desc "execute [STEP]", "Run execute mode step(s) or all steps with harness"
    option :force, type: :boolean, desc: "Force execution even if dependencies are not met"
    option :rerun, type: :boolean, desc: "Re-run a completed step"
    option :approve, type: :string, desc: "Approve a completed execute gate step"
    option :reset, type: :boolean, desc: "Reset execute mode progress"
    option :harness, type: :boolean, desc: "Use harness mode (default when no step specified)"
    option :no_harness, type: :boolean, desc: "Disable harness mode and use traditional step-by-step execution"
    def execute(project_dir = Dir.pwd, step_name = nil, custom_options = {})
      # Merge Thor options with custom options
      all_options = options.merge(custom_options)

      # Handle reset flag
      if all_options[:reset] || all_options["reset"]
        progress = Aidp::Execute::Progress.new(project_dir)
        progress.reset
        puts "🔄 Reset execute mode progress"
        return {status: "success", message: "Progress reset"}
      end

      # Handle approve flag
      if all_options[:approve] || all_options["approve"]
        step_name = all_options[:approve] || all_options["approve"]
        progress = Aidp::Execute::Progress.new(project_dir)
        progress.mark_step_completed(step_name)
        puts "✅ Approved execute step: #{step_name}"
        return {status: "success", step: step_name}
      end

      if step_name
        # Run specific step - check if harness mode is requested
        if should_use_harness?(all_options)
          puts "🚀 Running execute step '#{step_name}' with harness..."
          harness_runner = Aidp::Harness::Runner.new(project_dir, :execute, all_options)
          result = harness_runner.run
          display_harness_result(result)
          result
        else
          # Traditional step-by-step execution
          runner = Aidp::Execute::Runner.new(project_dir)
          runner.run_step(step_name, all_options)
        end
      elsif should_use_harness?(all_options)
        # No step specified - start interactive workflow selection
        workflow_selector = Aidp::Execute::WorkflowSelector.new
        workflow_config = workflow_selector.select_workflow

        puts "\n🚀 Starting harness with #{workflow_config[:workflow_type]} workflow..."
        puts "   Press Ctrl+C to stop, or use --no-harness for traditional mode\n"

        # Pass workflow configuration to harness
        harness_options = all_options.merge(
          workflow_type: workflow_config[:workflow_type],
          selected_steps: workflow_config[:steps],
          user_input: workflow_config[:user_input]
        )

        harness_runner = Aidp::Harness::Runner.new(project_dir, :execute, harness_options)
        result = harness_runner.run
        display_harness_result(result)
        result
      else
        # Traditional mode - list available steps
        puts "Available execute steps:"
        Aidp::Execute::Steps::SPEC.keys.each { |step| puts "  - #{step}" }
        progress = Aidp::Execute::Progress.new(project_dir)
        next_step = progress.next_step
        puts "\n💡 Use 'aidp execute' without arguments to run all steps with harness mode"
        {status: "success", message: "Available steps listed", next_step: next_step}
      end
    end

    desc "analyze [STEP]", "Run analyze mode step(s) or all steps with harness"
    long_desc <<~DESC
      Run analyze mode steps. STEP can be:
      - A full step name (e.g., 01_REPOSITORY_ANALYSIS)
      - A step number (e.g., 01, 02, 03)
      - 'next' to run the next unfinished step
      - 'current' to run the current step
      - Empty to run all steps with harness mode (default)
    DESC
    option :force, type: :boolean, desc: "Force execution even if dependencies are not met"
    option :rerun, type: :boolean, desc: "Re-run a completed step"
    option :background, type: :boolean, desc: "Run analysis in background jobs (requires database setup)"
    option :approve, type: :string, desc: "Approve a completed analyze gate step"
    option :reset, type: :boolean, desc: "Reset analyze mode progress"
    option :harness, type: :boolean, desc: "Use harness mode (default when no step specified)"
    option :no_harness, type: :boolean, desc: "Disable harness mode and use traditional step-by-step execution"
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

      # Merge Thor options with custom options
      all_options = options.merge(custom_options)

      # Handle reset flag
      if all_options[:reset] || all_options["reset"]
        progress = Aidp::Analyze::Progress.new(project_dir)
        progress.reset
        puts "🔄 Reset analyze mode progress"
        return {status: "success", message: "Progress reset"}
      end

      # Handle approve flag
      if all_options[:approve] || all_options["approve"]
        step_name = all_options[:approve] || all_options["approve"]
        progress = Aidp::Analyze::Progress.new(project_dir)
        progress.mark_step_completed(step_name)
        puts "✅ Approved analyze step: #{step_name}"
        return {status: "success", step: step_name}
      end

      progress = Aidp::Analyze::Progress.new(project_dir)

      if step_name
        # Resolve the step name
        resolved_step = resolve_analyze_step(step_name, progress)

        if resolved_step
          # Check if harness mode is requested
          if should_use_harness?(all_options)
            puts "🚀 Running analyze step '#{resolved_step}' with harness..."
            harness_options = all_options.merge(step_name: resolved_step)
            harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze, harness_options)
            result = harness_runner.run
            display_harness_result(result)
          else
            # Traditional step-by-step execution
            runner = Aidp::Analyze::Runner.new(project_dir)
            result = runner.run_step(resolved_step, all_options)

            # Display the result
            if result[:status] == "completed"
              puts "✅ Step '#{resolved_step}' completed successfully"
              puts "   Provider: #{result[:provider]}"
              puts "   Message: #{result[:message]}" if result[:message]
            elsif result[:status] == "error"
              puts "❌ Step '#{resolved_step}' failed"
              puts "   Error: #{result[:error]}" if result[:error]
            end

          end
          result
        else
          puts "❌ Step '#{step_name}' not found or not available"
          puts "\nAvailable steps:"
          Aidp::Analyze::Steps::SPEC.keys.each_with_index do |step, index|
            status = progress.step_completed?(step) ? "✅" : "⏳"
            puts "  #{status} #{sprintf("%02d", index + 1)}: #{step}"
          end
          {status: "error", message: "Step not found"}
        end
      elsif should_use_harness?(all_options)
        # No step specified - use harness by default
        puts "🚀 Starting analyze mode harness - will run all steps automatically..."
        puts "   Press Ctrl+C to stop, or use --no-harness for traditional mode"
        harness_runner = Aidp::Harness::Runner.new(project_dir, :analyze, all_options)
        result = harness_runner.run
        display_harness_result(result)
        result
      else
        # Traditional mode - list available steps
        puts "Available analyze steps:"
        Aidp::Analyze::Steps::SPEC.keys.each_with_index do |step, index|
          status = progress.step_completed?(step) ? "✅" : "⏳"
          puts "  #{status} #{sprintf("%02d", index + 1)}: #{step}"
        end

        next_step = progress.next_step
        if next_step
          puts "\n💡 Run 'aidp analyze next' or 'aidp analyze #{next_step.match(/^(\d+)/)[1]}' to run the next step"
        end
        puts "\n💡 Use 'aidp analyze' without arguments to run all steps with harness mode"

        {status: "success", message: "Available steps listed", next_step: next_step,
         completed_steps: progress.completed_steps}
      end
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

    desc "jobs", "Show and manage background jobs"
    def jobs
      require_relative "cli/jobs_command"
      command = Aidp::CLI::JobsCommand.new
      command.run
    end

    desc "analyze code", "Run Tree-sitter static analysis to build knowledge base"
    option :langs, type: :string, desc: "Comma-separated list of languages to analyze (default: ruby)"
    option :threads, type: :numeric, desc: "Number of threads for parallel processing (default: CPU count)"
    option :rebuild, type: :boolean, desc: "Rebuild knowledge base from scratch"
    option :kb_dir, type: :string, desc: "Knowledge base directory (default: .aidp/kb)"
    def analyze_code
      require_relative "analysis/tree_sitter_scan"

      langs = options[:langs] ? options[:langs].split(",").map(&:strip) : %w[ruby]
      threads = options[:threads] || Etc.nprocessors
      kb_dir = options[:kb_dir] || ".aidp/kb"

      if options[:rebuild]
        kb_path = File.expand_path(kb_dir, Dir.pwd)
        FileUtils.rm_rf(kb_path) if File.exist?(kb_path)
        puts "🗑️  Rebuilt knowledge base directory"
      end

      scanner = Aidp::Analysis::TreeSitterScan.new(
        root: Dir.pwd,
        kb_dir: kb_dir,
        langs: langs,
        threads: threads
      )

      scanner.run
    end

    desc "kb show [TYPE]", "Show knowledge base contents"
    option :format, type: :string, desc: "Output format (json, table, summary)"
    option :kb_dir, type: :string, desc: "Knowledge base directory (default: .aidp/kb)"
    def kb_show(type = "summary")
      require_relative "analysis/kb_inspector"

      kb_dir = options[:kb_dir] || ".aidp/kb"
      format = options[:format] || "summary"

      inspector = Aidp::Analysis::KBInspector.new(kb_dir)
      inspector.show(type, format: format)
    end

    desc "kb graph [TYPE]", "Generate graph visualization from knowledge base"
    option :format, type: :string, desc: "Graph format (dot, json, mermaid)"
    option :output, type: :string, desc: "Output file path"
    option :kb_dir, type: :string, desc: "Knowledge base directory (default: .aidp/kb)"
    def kb_graph(type = "imports")
      require_relative "analysis/kb_inspector"

      kb_dir = options[:kb_dir] || ".aidp/kb"
      format = options[:format] || "dot"
      output = options[:output]

      inspector = Aidp::Analysis::KBInspector.new(kb_dir)
      inspector.generate_graph(type, format: format, output: output)
    end

    desc "harness status", "Show detailed harness status and configuration"
    option :mode, type: :string, desc: "Show status for specific mode (analyze or execute)"
    def harness_status
      puts "\n🔧 Harness Status"
      puts "=" * 50

      modes = options[:mode] ? [options[:mode].to_sym] : [:analyze, :execute]

      modes.each do |mode|
        puts "\n📋 #{mode.to_s.capitalize} Mode:"

        begin
          harness_runner = Aidp::Harness::Runner.new(Dir.pwd, mode)
          status = harness_runner.detailed_status

          puts "   State: #{status[:harness][:state]}"
          puts "   Current Step: #{status[:harness][:current_step] || "None"}"
          puts "   Current Provider: #{status[:harness][:current_provider] || "None"}"
          puts "   Duration: #{format_duration(status[:harness][:duration])}"
          puts "   User Input Count: #{status[:harness][:user_input_count]}"

          progress = status[:harness][:progress]
          puts "   Progress: #{progress[:completed_steps]}/#{progress[:total_steps]} steps completed"
          puts "   Next Step: #{progress[:next_step] || "All completed"}"

          puts "   Configuration:"
          puts "     Default Provider: #{status[:configuration][:default_provider]}"
          puts "     Fallback Providers: #{status[:configuration][:fallback_providers].join(", ")}"
          puts "     Max Retries: #{status[:configuration][:max_retries]}"

          provider_status = status[:provider_manager]
          puts "   Provider Status:"
          puts "     Current: #{provider_status[:current_provider]}"
          puts "     Available: #{provider_status[:available_providers].join(", ")}"
          puts "     Rate Limited: #{provider_status[:rate_limited_providers].join(", ") || "None"}"
          puts "     Total Switches: #{provider_status[:total_switches]}"
        rescue => e
          puts "   Error: #{e.message}"
        end
      end
    end

    desc "harness reset", "Reset harness state for specified mode"
    option :mode, type: :string, desc: "Mode to reset (analyze or execute)", required: true
    def harness_reset
      mode = options[:mode]&.to_sym

      unless [:analyze, :execute].include?(mode)
        puts "❌ Invalid mode. Use 'analyze' or 'execute'"
        return
      end

      begin
        harness_runner = Aidp::Harness::Runner.new(Dir.pwd, mode)
        state_manager = harness_runner.instance_variable_get(:@state_manager)
        state_manager.reset_all

        puts "✅ Reset harness state for #{mode} mode"
        puts "   All progress and state cleared"
      rescue => e
        puts "❌ Error resetting harness: #{e.message}"
      end
    end

    desc "version", "Show version information"
    def version
      puts "Aidp version #{Aidp::VERSION}"
    end

    private

    # Determine if harness mode should be used
    def should_use_harness?(options)
      # Use harness by default unless explicitly disabled
      return false if options[:no_harness] || options["no_harness"]
      return true if options[:harness] || options["harness"]

      # Default to harness mode
      true
    end

    # Display harness execution result
    def display_harness_result(result)
      case result[:status]
      when "completed"
        puts "\n✅ Harness completed successfully!"
        puts "   All steps finished automatically"
      when "stopped"
        puts "\n⏹️  Harness stopped by user"
        puts "   Execution terminated manually"
      when "error"
        puts "\n❌ Harness encountered an error"
        puts "   Error: #{result[:message]}" if result[:message]
      else
        puts "\n🔄 Harness finished"
        puts "   Status: #{result[:status]}"
        puts "   Message: #{result[:message]}" if result[:message]
      end
    end

    # Format duration in human-readable format
    def format_duration(seconds)
      return "0s" if seconds <= 0

      hours = (seconds / 3600).to_i
      minutes = ((seconds % 3600) / 60).to_i
      secs = (seconds % 60).to_i

      parts = []
      parts << "#{hours}h" if hours > 0
      parts << "#{minutes}m" if minutes > 0
      parts << "#{secs}s" if secs > 0 || parts.empty?

      parts.join(" ")
    end

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
