# frozen_string_literal: true

require "tty-prompt"
require_relative "../execute/checkpoint"
require_relative "../execute/checkpoint_display"

module Aidp
  class CLI
    # Command handler for `aidp checkpoint` subcommand
    #
    # Provides commands for managing workflow checkpoints:
    #   - show: Display latest checkpoint data
    #   - summary: Show progress summary with trends
    #   - history: Show last N checkpoints
    #   - metrics: Show detailed metrics
    #   - clear: Clear all checkpoint data
    #
    # Usage:
    #   aidp checkpoint show
    #   aidp checkpoint summary --watch
    #   aidp checkpoint history 10
    #   aidp checkpoint metrics
    #   aidp checkpoint clear --force
    class CheckpointCommand
      include Aidp::MessageDisplay

      def initialize(prompt: TTY::Prompt.new, checkpoint_class: nil, display_class: nil, project_dir: nil)
        @prompt = prompt
        @checkpoint_class = checkpoint_class || Aidp::Execute::Checkpoint
        @display_class = display_class || Aidp::Execute::CheckpointDisplay
        @project_dir = project_dir || Dir.pwd
      end

      # Main entry point for checkpoint subcommands
      def run(args)
        sub = args.shift || "summary"
        checkpoint = @checkpoint_class.new(@project_dir)
        display = @display_class.new

        case sub
        when "show"
          run_show_command(checkpoint, display)
        when "summary"
          run_summary_command(checkpoint, display, args)
        when "history"
          run_history_command(checkpoint, display, args)
        when "metrics"
          run_metrics_command(checkpoint)
        when "clear"
          run_clear_command(checkpoint, args)
        else
          display_usage
        end
      end

      private

      def run_show_command(checkpoint, display)
        latest = checkpoint.latest_checkpoint
        if latest
          display.display_checkpoint(latest, show_details: true)
        else
          display_message("No checkpoint data found.", type: :info)
        end
      end

      def run_summary_command(checkpoint, display, args)
        watch = args.include?("--watch")
        interval = extract_interval_option(args) || 5

        if watch
          watch_checkpoint_summary(checkpoint, display, interval)
        else
          summary = checkpoint.progress_summary
          if summary
            display.display_progress_summary(summary)
          else
            display_message("No checkpoint data found.", type: :info)
          end
        end
      end

      def run_history_command(checkpoint, display, args)
        limit = args.shift || "10"
        history = checkpoint.checkpoint_history(limit: limit.to_i)
        if history.any?
          display.display_checkpoint_history(history, limit: limit.to_i)
        else
          display_message("No checkpoint history found.", type: :info)
        end
      end

      def run_metrics_command(checkpoint)
        latest = checkpoint.latest_checkpoint
        unless latest
          display_message("No checkpoint data found.", type: :info)
          return
        end

        display_message("", type: :info)
        display_message("📊 Detailed Metrics", type: :info)
        display_message("=" * 60, type: :muted)

        metrics = latest[:metrics]
        display_message("Lines of Code: #{metrics[:lines_of_code]}", type: :info)
        display_message("File Count: #{metrics[:file_count]}", type: :info)
        display_message("Test Coverage: #{metrics[:test_coverage]}%", type: :info)
        display_message("Code Quality: #{metrics[:code_quality]}%", type: :info)
        display_message("PRD Task Progress: #{metrics[:prd_task_progress]}%", type: :info)

        if metrics.key?(:tests_passing)
          status = metrics[:tests_passing] ? "✓ Passing" : "✗ Failing"
          display_message("Tests: #{status}", type: :info)
        end

        if metrics.key?(:linters_passing)
          status = metrics[:linters_passing] ? "✓ Passing" : "✗ Failing"
          display_message("Linters: #{status}", type: :info)
        end

        display_message("=" * 60, type: :muted)
        display_message("", type: :info)
      end

      def run_clear_command(checkpoint, args)
        force = args.include?("--force")
        unless force
          confirm = @prompt.yes?("Are you sure you want to clear all checkpoint data?")
          return unless confirm
        end

        checkpoint.clear
        display_message("✓ Checkpoint data cleared.", type: :success)
      end

      def watch_checkpoint_summary(checkpoint, display, interval)
        display_message("Watching checkpoint summary (refresh: #{interval}s, Ctrl+C to exit)...", type: :info)
        display_message("", type: :info)

        begin
          loop do
            # Clear screen
            print "\e[2J\e[H"

            summary = checkpoint.progress_summary
            if summary
              display.display_progress_summary(summary)

              # Show last update time
              if summary[:current] && summary[:current][:timestamp]
                last_update = Time.parse(summary[:current][:timestamp])
                age = Time.now - last_update
                display_message("", type: :info)
                display_message("Last update: #{format_time_ago_simple(age)} | Refreshing in #{interval}s...", type: :muted)
              end
            else
              display_message("No checkpoint data found. Waiting for data...", type: :info)
            end

            sleep interval
          end
        rescue Interrupt
          display_message("\nStopped watching checkpoint summary", type: :info)
        end
      end

      def format_time_ago_simple(seconds)
        if seconds < 60
          "#{seconds.to_i}s ago"
        elsif seconds < 3600
          "#{(seconds / 60).to_i}m ago"
        else
          "#{(seconds / 3600).to_i}h ago"
        end
      end

      def extract_interval_option(args)
        args.each_with_index do |arg, i|
          if arg == "--interval" && args[i + 1]
            return args[i + 1].to_i
          elsif arg.start_with?("--interval=")
            return arg.split("=")[1].to_i
          end
        end
        nil
      end

      def display_usage
        display_message("Usage: aidp checkpoint <show|summary|history|metrics|clear>", type: :info)
        display_message("  show              - Show the latest checkpoint data", type: :info)
        display_message("  summary [--watch] - Show progress summary with trends", type: :info)
        display_message("  history [N]       - Show last N checkpoints", type: :info)
        display_message("  metrics           - Show detailed metrics", type: :info)
        display_message("  clear [--force]   - Clear all checkpoint data", type: :info)
      end
    end
  end
end
