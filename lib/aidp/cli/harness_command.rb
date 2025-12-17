# frozen_string_literal: true

require "tty-prompt"
require_relative "../harness/runner"

module Aidp
  class CLI
    # Command handler for `aidp harness status` and `aidp harness reset` subcommands
    #
    # Provides commands for viewing and managing harness state:
    #   - status: Show detailed harness status for all modes
    #   - reset: Reset harness state for a specific mode
    #
    # Usage:
    #   aidp harness status
    #   aidp harness reset --mode analyze
    class HarnessCommand
      include Aidp::MessageDisplay
      include Aidp::RescueLogging

      def initialize(prompt: TTY::Prompt.new, runner_class: nil, project_dir: nil)
        @prompt = prompt
        @runner_class = runner_class || Aidp::Harness::Runner
        @project_dir = project_dir || Dir.pwd
      end

      # Main entry point for harness status/reset subcommands
      def run(args, subcommand:, options: {})
        case subcommand
        when "status"
          run_status_command
        when "reset"
          run_reset_command(options)
        else
          display_message("Unknown harness subcommand: #{subcommand}", type: :error)
          display_help
          1
        end
      end

      private

      def run_status_command
        modes = %i[analyze execute]
        display_message("🔧 Harness Status", type: :highlight)
        modes.each do |mode|
          status = fetch_harness_status(mode)
          print_harness_mode_status(mode, status)
        end
      end

      def run_reset_command(options)
        mode = (options[:mode] || "analyze").to_s
        unless %w[analyze execute].include?(mode)
          display_message("❌ Invalid mode. Use 'analyze' or 'execute'", type: :error)
          return
        end

        # Build a runner to access state manager
        runner = @runner_class.new(@project_dir, mode.to_sym, {})
        state_manager = runner.state_manager
        state_manager.reset_all if state_manager.respond_to?(:reset_all)
        display_message("✅ Reset harness state for #{mode} mode", type: :success)
      end

      def fetch_harness_status(mode)
        runner = @runner_class.new(@project_dir, mode, {})
        if runner.respond_to?(:detailed_status)
          runner.detailed_status
        else
          {harness: {state: "unknown"}}
        end
      rescue => e
        log_rescue(e, component: "harness_command", action: "fetch_harness_status", fallback: {harness: {state: "error"}}, mode: mode)
        {harness: {state: "error", error: e.message}}
      end

      def print_harness_mode_status(mode, status)
        harness = status[:harness] || {}
        display_message("\n📋 #{mode.to_s.capitalize} Mode:", type: :info)
        display_message("   State: #{harness[:state]}", type: :info)
        if harness[:progress]
          prog = harness[:progress]
          display_message("   Progress: #{prog[:completed_steps]}/#{prog[:total_steps]}", type: :success)
          display_message("   Current Step: #{harness[:current_step]}", type: :info) if harness[:current_step]
        end
      end

      def display_help
        display_message("\nUsage: aidp harness <subcommand> [options]", type: :info)
        display_message("\nSubcommands:", type: :info)
        display_message("  status           Show harness status for all modes", type: :info)
        display_message("  reset            Reset harness state for a mode", type: :info)
        display_message("\nOptions:", type: :info)
        display_message("  --mode MODE      Specify mode for reset (analyze|execute)", type: :info)
        display_message("\nExamples:", type: :info)
        display_message("  aidp harness status", type: :info)
        display_message("  aidp harness reset --mode analyze", type: :info)
      end
    end
  end
end
