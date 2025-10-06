# frozen_string_literal: true

require "thor"
require_relative "../execute/checkpoint"
require_relative "../execute/checkpoint_display"

module Aidp
  module CLI
    # CLI command for viewing checkpoint data and progress reports
    class CheckpointCommand < Thor
      desc "show", "Show the latest checkpoint data"
      def show
        checkpoint = Aidp::Execute::Checkpoint.new(Dir.pwd)
        display = Aidp::Execute::CheckpointDisplay.new

        latest = checkpoint.latest_checkpoint
        if latest
          display.display_checkpoint(latest, show_details: true)
        else
          puts "No checkpoint data found."
        end
      end

      desc "summary", "Show progress summary with trends"
      def summary
        checkpoint = Aidp::Execute::Checkpoint.new(Dir.pwd)
        display = Aidp::Execute::CheckpointDisplay.new

        summary = checkpoint.progress_summary
        if summary
          display.display_progress_summary(summary)
        else
          puts "No checkpoint data found."
        end
      end

      desc "history [LIMIT]", "Show checkpoint history (default: last 10)"
      def history(limit = "10")
        checkpoint = Aidp::Execute::Checkpoint.new(Dir.pwd)
        display = Aidp::Execute::CheckpointDisplay.new

        history = checkpoint.checkpoint_history(limit: limit.to_i)
        if history.any?
          display.display_checkpoint_history(history, limit: limit.to_i)
        else
          puts "No checkpoint history found."
        end
      end

      desc "clear", "Clear all checkpoint data"
      option :force, type: :boolean, default: false, desc: "Skip confirmation"
      def clear
        unless options[:force]
          prompt = TTY::Prompt.new
          confirm = prompt.yes?("Are you sure you want to clear all checkpoint data?")
          return unless confirm
        end

        checkpoint = Aidp::Execute::Checkpoint.new(Dir.pwd)
        checkpoint.clear
        puts "✓ Checkpoint data cleared."
      end

      desc "metrics", "Show detailed metrics for the latest checkpoint"
      def metrics
        checkpoint = Aidp::Execute::Checkpoint.new(Dir.pwd)
        latest = checkpoint.latest_checkpoint

        unless latest
          puts "No checkpoint data found."
          return
        end

        puts
        puts "📊 Detailed Metrics"
        puts "=" * 60

        metrics = latest[:metrics]
        puts "Lines of Code: #{metrics[:lines_of_code]}"
        puts "File Count: #{metrics[:file_count]}"
        puts "Test Coverage: #{metrics[:test_coverage]}%"
        puts "Code Quality: #{metrics[:code_quality]}%"
        puts "PRD Task Progress: #{metrics[:prd_task_progress]}%"

        if metrics[:tests_passing]
          puts "Tests: #{metrics[:tests_passing] ? "✓ Passing" : "✗ Failing"}"
        end

        if metrics[:linters_passing]
          puts "Linters: #{metrics[:linters_passing] ? "✓ Passing" : "✗ Failing"}"
        end

        puts "=" * 60
        puts
      end
    end
  end
end
