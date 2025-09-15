# frozen_string_literal: true

require "thor"
require_relative "harness/runner_new"
require_relative "execute/workflow_selector"

module Aidp
  # Enhanced CLI interface with TUI integration
  class CLINew < Thor
    desc "execute [STEP]", "Run execute mode step(s) with enhanced TUI harness"
    option :force, type: :boolean, desc: "Force execution even if dependencies are not met"
    option :rerun, type: :boolean, desc: "Re-run a completed step"
    option :approve, type: :string, desc: "Approve a completed execute gate step"
    option :reset, type: :boolean, desc: "Reset execute mode progress"
    option :harness, type: :boolean, desc: "Use enhanced harness mode (default)"
    option :no_harness, type: :boolean, desc: "Disable harness mode and use traditional execution"
    option :dashboard, type: :boolean, desc: "Show TUI dashboard during execution"
    def execute(project_dir = Dir.pwd, step_name = nil, custom_options = {})
      all_options = options.merge(custom_options)

      if all_options[:reset] || all_options["reset"]
        return handle_reset_execute(project_dir)
      end

      if all_options[:approve] || all_options["approve"]
        return handle_approve_execute(project_dir, all_options)
      end

      if step_name
        execute_single_step(project_dir, step_name, all_options)
      elsif should_use_harness?(all_options)
        execute_workflow(project_dir, all_options)
      else
        list_execute_steps(project_dir)
      end
    end

    desc "analyze [STEP]", "Run analyze mode step(s) with enhanced TUI harness"
    long_desc <<~DESC
      Run analyze mode steps with enhanced TUI. STEP can be:
      - A full step name (e.g., 01_REPOSITORY_ANALYSIS)
      - A step number (e.g., 01, 02, 03)
      - 'next' to run the next unfinished step
      - 'current' to run the current step
      - Empty to run all steps with enhanced harness mode (default)
    DESC
    option :force, type: :boolean, desc: "Force execution even if dependencies are not met"
    option :rerun, type: :boolean, desc: "Re-run a completed step"
    option :background, type: :boolean, desc: "Run analysis in background jobs"
    option :approve, type: :string, desc: "Approve a completed analyze gate step"
    option :reset, type: :boolean, desc: "Reset analyze mode progress"
    option :harness, type: :boolean, desc: "Use enhanced harness mode (default)"
    option :no_harness, type: :boolean, desc: "Disable harness mode and use traditional execution"
    option :dashboard, type: :boolean, desc: "Show TUI dashboard during execution"
    def analyze(*args)
      project_dir, step_name, custom_options = parse_analyze_args(args)
      all_options = options.merge(custom_options)

      if all_options[:reset] || all_options["reset"]
        return handle_reset_analyze(project_dir)
      end

      if all_options[:approve] || all_options["approve"]
        return handle_approve_analyze(project_dir, all_options)
      end

      if step_name
        analyze_single_step(project_dir, step_name, all_options)
      elsif should_use_harness?(all_options)
        analyze_workflow(project_dir, all_options)
      else
        list_analyze_steps(project_dir)
      end
    end

    desc "dashboard [VIEW]", "Show TUI dashboard for monitoring"
    option :view, type: :string, desc: "Dashboard view (overview, jobs, metrics, errors, history, settings)"
    def dashboard(project_dir = Dir.pwd, view = nil)
      view ||= options[:view] || :overview
      show_tui_dashboard(project_dir, view.to_sym)
    end

    desc "status", "Show current progress with enhanced TUI display"
    def status
      show_enhanced_status
    end

    desc "jobs", "Show and manage background jobs with TUI"
    def jobs
      require_relative "cli/jobs_command"
      command = Aidp::CLI::JobsCommand.new
      command.run
    end

    desc "analyze code", "Run Tree-sitter static analysis with TUI progress"
    option :langs, type: :string, desc: "Comma-separated list of languages to analyze"
    option :threads, type: :numeric, desc: "Number of threads for parallel processing"
    option :rebuild, type: :boolean, desc: "Rebuild knowledge base from scratch"
    option :kb_dir, type: :string, desc: "Knowledge base directory"
    def analyze_code
      run_tree_sitter_analysis
    end

    desc "kb show [TYPE]", "Show knowledge base contents with TUI formatting"
    option :format, type: :string, desc: "Output format (json, table, summary)"
    option :kb_dir, type: :string, desc: "Knowledge base directory"
    def kb_show(type = "summary")
      show_knowledge_base(type)
    end

    desc "kb graph [TYPE]", "Generate graph visualization with TUI progress"
    option :format, type: :string, desc: "Graph format (dot, json, mermaid)"
    option :output, type: :string, desc: "Output file path"
    option :kb_dir, type: :string, desc: "Knowledge base directory"
    def kb_graph(type = "imports")
      generate_knowledge_graph(type)
    end

    desc "harness status", "Show detailed harness status with TUI dashboard"
    option :mode, type: :string, desc: "Show status for specific mode (analyze or execute)"
    def harness_status
      show_enhanced_harness_status
    end

    desc "harness reset", "Reset harness state with TUI confirmation"
    option :mode, type: :string, desc: "Mode to reset (analyze or execute)", required: true
    def harness_reset
      reset_harness_with_confirmation
    end

    desc "version", "Show version information"
    def version
      puts "Aidp version #{Aidp::VERSION}"
    end

    private

    def parse_analyze_args(args)
      case args.length
      when 0
        [Dir.pwd, nil, {}]
      when 1
        if Dir.exist?(args[0])
          [args[0], nil, {}]
        else
          [Dir.pwd, args[0], {}]
        end
      when 2
        if Dir.exist?(args[0])
          [args[0], args[1], {}]
        else
          [Dir.pwd, args[0], args[1] || {}]
        end
      when 3
        [args[0], args[1], args[2] || {}]
      else
        raise ArgumentError, "Wrong number of arguments (given #{args.length}, expected 0..3)"
      end
    end

    def handle_reset_execute(project_dir)
      progress = Aidp::Execute::Progress.new(project_dir)
      progress.reset
      puts "🔄 Reset execute mode progress"
      {status: "success", message: "Progress reset"}
    end

    def handle_approve_execute(project_dir, all_options)
      step_name = all_options[:approve] || all_options["approve"]
      progress = Aidp::Execute::Progress.new(project_dir)
      progress.mark_step_completed(step_name)
      puts "✅ Approved execute step: #{step_name}"
      {status: "success", step: step_name}
    end

    def handle_reset_analyze(project_dir)
      progress = Aidp::Analyze::Progress.new(project_dir)
      progress.reset
      puts "🔄 Reset analyze mode progress"
      {status: "success", message: "Progress reset"}
    end

    def handle_approve_analyze(project_dir, all_options)
      step_name = all_options[:approve] || all_options["approve"]
      progress = Aidp::Analyze::Progress.new(project_dir)
      progress.mark_step_completed(step_name)
      puts "✅ Approved analyze step: #{step_name}"
      {status: "success", step: step_name}
    end

    def execute_single_step(project_dir, step_name, all_options)
      if should_use_harness?(all_options)
        puts "🚀 Running execute step '#{step_name}' with enhanced TUI harness..."
        harness_runner = Aidp::Harness::RunnerNew.new(project_dir, :execute, all_options)
        result = harness_runner.run
        display_enhanced_harness_result(result)
        result
      else
        runner = Aidp::Execute::Runner.new(project_dir)
        runner.run_step(step_name, all_options)
      end
    end

    def execute_workflow(project_dir, all_options)
      workflow_selector = Aidp::Execute::WorkflowSelector.new
      workflow_config = workflow_selector.select_workflow

      puts "\n🚀 Starting enhanced TUI harness with #{workflow_config[:workflow_type]} workflow..."
      puts "   Press Ctrl+C to stop, or use --no-harness for traditional mode\n"

      harness_options = all_options.merge(
        workflow_type: workflow_config[:workflow_type],
        selected_steps: workflow_config[:steps],
        user_input: workflow_config[:user_input]
      )

      harness_runner = Aidp::Harness::RunnerNew.new(project_dir, :execute, harness_options)
      result = harness_runner.run
      display_enhanced_harness_result(result)
      result
    end

    def list_execute_steps(project_dir)
      puts "Available execute steps:"
      Aidp::Execute::Steps::SPEC.keys.each { |step| puts "  - #{step}" }
      progress = Aidp::Execute::Progress.new(project_dir)
      next_step = progress.next_step
      puts "\n💡 Use 'aidp execute' without arguments to run all steps with enhanced TUI harness"
      {status: "success", message: "Available steps listed", next_step: next_step}
    end

    def analyze_single_step(project_dir, step_name, all_options)
      progress = Aidp::Analyze::Progress.new(project_dir)
      resolved_step = resolve_analyze_step(step_name, progress)

      if resolved_step
        if should_use_harness?(all_options)
          puts "🚀 Running analyze step '#{resolved_step}' with enhanced TUI harness..."
          harness_options = all_options.merge(step_name: resolved_step)
          harness_runner = Aidp::Harness::RunnerNew.new(project_dir, :analyze, harness_options)
          result = harness_runner.run
          display_enhanced_harness_result(result)
        else
          runner = Aidp::Analyze::Runner.new(project_dir)
          result = runner.run_step(resolved_step, all_options)
          display_step_result(resolved_step, result)
        end
        result
      else
        puts "❌ Step '#{step_name}' not found or not available"
        list_available_analyze_steps(progress)
        {status: "error", message: "Step not found"}
      end
    end

    def analyze_workflow(project_dir, all_options)
      puts "🚀 Starting analyze mode with enhanced TUI harness..."
      puts "   Press Ctrl+C to stop, or use --no-harness for traditional mode"
      harness_runner = Aidp::Harness::RunnerNew.new(project_dir, :analyze, all_options)
      result = harness_runner.run
      display_enhanced_harness_result(result)
      result
    end

    def list_analyze_steps(project_dir)
      progress = Aidp::Analyze::Progress.new(project_dir)
      list_available_analyze_steps(progress)
      next_step = progress.next_step
      if next_step
        puts "\n💡 Run 'aidp analyze next' or 'aidp analyze #{next_step.match(/^(\d+)/)[1]}' to run the next step"
      end
      puts "\n💡 Use 'aidp analyze' without arguments to run all steps with enhanced TUI harness"
      {status: "success", message: "Available steps listed", next_step: next_step,
       completed_steps: progress.completed_steps}
    end

    def show_tui_dashboard(project_dir, view)
      puts "🎮 Starting TUI Dashboard..."
      puts "   View: #{view}"
      puts "   Project: #{project_dir}"
      puts "\n💡 Use the dashboard to monitor job progress and system status"

      # In a real implementation, this would start the interactive dashboard
      # For now, we'll show a placeholder
      puts "\n📊 TUI Dashboard would be displayed here"
      puts "   - Real-time job monitoring"
      puts "   - Progress tracking"
      puts "   - Error handling"
      puts "   - Performance metrics"
    end

    def show_enhanced_status
      puts "\n📊 AI Dev Pipeline Enhanced Status"
      puts "=" * 50

      show_execute_mode_status
      show_analyze_mode_status
    end

    def show_execute_mode_status
      execute_progress = Aidp::Execute::Progress.new(Dir.pwd)
      puts "\n🔧 Execute Mode:"
      Aidp::Execute::Steps::SPEC.keys.each do |step|
        status = execute_progress.step_completed?(step) ? "✅" : "⏳"
        puts "  #{status} #{step}"
      end
    end

    def show_analyze_mode_status
      analyze_progress = Aidp::Analyze::Progress.new(Dir.pwd)
      puts "\n🔍 Analyze Mode:"
      Aidp::Analyze::Steps::SPEC.keys.each do |step|
        status = analyze_progress.step_completed?(step) ? "✅" : "⏳"
        puts "  #{status} #{step}"
      end
    end

    def run_tree_sitter_analysis
      require_relative "analysis/tree_sitter_scan"

      langs = options[:langs] ? options[:langs].split(",").map(&:strip) : %w[ruby]
      threads = options[:threads] || Etc.nprocessors
      kb_dir = options[:kb_dir] || ".aidp/kb"

      if options[:rebuild]
        kb_path = File.expand_path(kb_dir, Dir.pwd)
        FileUtils.rm_rf(kb_path) if File.exist?(kb_path)
        puts "🗑️  Rebuilt knowledge base directory"
      end

      puts "🔍 Starting Tree-sitter analysis with TUI progress..."
      scanner = Aidp::Analysis::TreeSitterScan.new(
        root: Dir.pwd,
        kb_dir: kb_dir,
        langs: langs,
        threads: threads
      )

      scanner.run
    end

    def show_knowledge_base(type)
      require_relative "analysis/kb_inspector"

      kb_dir = options[:kb_dir] || ".aidp/kb"
      format = options[:format] || "summary"

      puts "📚 Showing knowledge base with TUI formatting..."
      inspector = Aidp::Analysis::KBInspector.new(kb_dir)
      inspector.show(type, format: format)
    end

    def generate_knowledge_graph(type)
      require_relative "analysis/kb_inspector"

      kb_dir = options[:kb_dir] || ".aidp/kb"
      format = options[:format] || "dot"
      output = options[:output]

      puts "📊 Generating knowledge graph with TUI progress..."
      inspector = Aidp::Analysis::KBInspector.new(kb_dir)
      inspector.generate_graph(type, format: format, output: output)
    end

    def show_enhanced_harness_status
      puts "\n🔧 Enhanced Harness Status"
      puts "=" * 50

      modes = options[:mode] ? [options[:mode].to_sym] : [:analyze, :execute]

      modes.each do |mode|
        puts "\n📋 #{mode.to_s.capitalize} Mode:"

        begin
          harness_runner = Aidp::Harness::RunnerNew.new(Dir.pwd, mode)
          status = harness_runner.detailed_status

          display_harness_status_details(status)
        rescue => e
          puts "   Error: #{e.message}"
        end
      end
    end

    def display_harness_status_details(status)
      harness_status = status[:harness]
      puts "   State: #{harness_status[:state]}"
      puts "   Current Step: #{harness_status[:current_step] || "None"}"
      puts "   Current Provider: #{harness_status[:current_provider] || "None"}"
      puts "   Duration: #{format_duration(harness_status[:duration])}"
      puts "   User Input Count: #{harness_status[:user_input_count]}"

      progress = harness_status[:progress]
      puts "   Progress: #{progress[:completed_steps]}/#{progress[:total_steps]} steps completed"
      puts "   Next Step: #{progress[:next_step] || "All completed"}"

      display_configuration_details(status[:configuration])
      display_provider_details(status[:provider_manager])
      display_tui_details(status[:tui_components]) if status[:tui_components]
    end

    def display_configuration_details(config)
      puts "   Configuration:"
      puts "     Default Provider: #{config[:default_provider]}"
      puts "     Fallback Providers: #{config[:fallback_providers].join(", ")}"
      puts "     Max Retries: #{config[:max_retries]}"
    end

    def display_provider_details(provider_status)
      puts "   Provider Status:"
      puts "     Current: #{provider_status[:current_provider]}"
      puts "     Available: #{provider_status[:available_providers].join(", ")}"
      puts "     Rate Limited: #{provider_status[:rate_limited_providers].join(", ") || "None"}"
      puts "     Total Switches: #{provider_status[:total_switches]}"
    end

    def display_tui_details(tui_components)
      puts "   TUI Components:"
      puts "     Workflow Controller: #{tui_components[:workflow_controller][:state]}"
      puts "     Job Monitor: #{tui_components[:job_monitor][:monitoring_active] ? "Active" : "Inactive"}"
      puts "     Dashboard: #{tui_components[:dashboard][:active] ? "Active" : "Inactive"}"
    end

    def reset_harness_with_confirmation
      mode = options[:mode]&.to_sym

      unless [:analyze, :execute].include?(mode)
        puts "❌ Invalid mode. Use 'analyze' or 'execute'"
        return
      end

      begin
        puts "⚠️  This will reset all harness state for #{mode} mode"
        puts "   All progress and state will be cleared"

        # In a real implementation, this would use TUI confirmation
        harness_runner = Aidp::Harness::RunnerNew.new(Dir.pwd, mode)
        state_manager = harness_runner.instance_variable_get(:@state_manager)
        state_manager.reset_all

        puts "✅ Reset harness state for #{mode} mode"
        puts "   All progress and state cleared"
      rescue => e
        puts "❌ Error resetting harness: #{e.message}"
      end
    end

    def should_use_harness?(options)
      return false if options[:no_harness] || options["no_harness"]
      return true if options[:harness] || options["harness"]
      true
    end

    def display_enhanced_harness_result(result)
      case result[:status]
      when "completed"
        puts "\n✅ Enhanced TUI harness completed successfully!"
        puts "   All steps finished automatically with full monitoring"
      when "stopped"
        puts "\n⏹️  Enhanced TUI harness stopped by user"
        puts "   Execution terminated manually with graceful shutdown"
      when "error"
        puts "\n❌ Enhanced TUI harness encountered an error"
        puts "   Error: #{result[:message]}" if result[:message]
      else
        puts "\n🔄 Enhanced TUI harness finished"
        puts "   Status: #{result[:status]}"
        puts "   Message: #{result[:message]}" if result[:message]
      end
    end

    def display_step_result(step_name, result)
      if result[:status] == "completed"
        puts "✅ Step '#{step_name}' completed successfully"
        puts "   Provider: #{result[:provider]}"
        puts "   Message: #{result[:message]}" if result[:message]
      elsif result[:status] == "error"
        puts "❌ Step '#{step_name}' failed"
        puts "   Error: #{result[:error]}" if result[:error]
      end
    end

    def list_available_analyze_steps(progress)
      puts "\nAvailable steps:"
      Aidp::Analyze::Steps::SPEC.keys.each_with_index do |step, index|
        status = progress.step_completed?(step) ? "✅" : "⏳"
        puts "  #{status} #{sprintf("%02d", index + 1)}: #{step}"
      end
    end

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
        if step_input.match?(/^\d{1,2}$/)
          step_number = sprintf("%02d", step_input.to_i)
          Aidp::Analyze::Steps::SPEC.keys.find { |step| step.start_with?(step_number) }
        else
          Aidp::Analyze::Steps::SPEC.keys.find { |step| step.downcase == step_input }
        end
      end
    end
  end
end
