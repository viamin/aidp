# frozen_string_literal: true

require "tty-prompt"
require_relative "../setup/wizard"

module Aidp
  class CLI
    # Command handler for `aidp config` subcommand
    #
    # Provides commands for managing AIDP configuration:
    #   - Interactive configuration wizard
    #   - Dry-run mode for testing configuration changes
    #
    # Usage:
    #   aidp config --interactive
    #   aidp config --interactive --dry-run
    class ConfigCommand
      include Aidp::MessageDisplay

      def initialize(prompt: TTY::Prompt.new, wizard_class: nil, project_dir: nil)
        @prompt = prompt
        @wizard_class = wizard_class || Aidp::Setup::Wizard
        @project_dir = project_dir || Dir.pwd
      end

      # Main entry point for config command
      def run(args)
        interactive = false
        dry_run = false

        until args.empty?
          token = args.shift
          case token
          when "--interactive"
            interactive = true
          when "--dry-run"
            dry_run = true
          when "-h", "--help"
            display_usage
            return
          else
            display_message("Unknown option: #{token}", type: :error)
            display_usage
            return
          end
        end

        unless interactive
          display_usage
          return
        end

        wizard = @wizard_class.new(@project_dir, prompt: @prompt, dry_run: dry_run)
        wizard.run
      end

      private

      def display_usage
        display_message("\nUsage: aidp config --interactive [--dry-run]", type: :info)
        display_message("\nOptions:", type: :info)
        display_message("  --interactive    Run interactive configuration wizard", type: :info)
        display_message("  --dry-run        Perform a dry run without making changes", type: :info)
        display_message("  -h, --help       Show this help message", type: :info)
        display_message("\nExamples:", type: :info)
        display_message("  aidp config --interactive", type: :info)
        display_message("  aidp config --interactive --dry-run", type: :info)
      end
    end
  end
end
