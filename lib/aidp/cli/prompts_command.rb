# frozen_string_literal: true

require "tty-prompt"
require "tty-table"
require_relative "../prompts/prompt_template_manager"
require_relative "../message_display"

module Aidp
  class CLI
    # Command handler for `aidp prompts` subcommand
    #
    # Provides commands for managing prompt templates:
    #   - List all available templates
    #   - Show template details
    #   - Customize templates for project
    #   - Reset customized templates
    #
    # Usage:
    #   aidp prompts list
    #   aidp prompts show <template_id>
    #   aidp prompts customize <template_id>
    #   aidp prompts reset <template_id>
    class PromptsCommand
      include Aidp::MessageDisplay

      def initialize(prompt: TTY::Prompt.new, project_dir: Dir.pwd)
        @prompt = prompt
        @project_dir = project_dir
        @template_manager = Prompts::PromptTemplateManager.new(project_dir: project_dir)
      end

      # Main entry point for prompts command
      def run(args)
        subcommand = args.shift

        case subcommand
        when "list", "ls"
          list_templates(args)
        when "show", "view"
          show_template(args)
        when "customize", "edit"
          customize_template(args)
        when "reset"
          reset_template(args)
        when "-h", "--help", nil
          display_usage
        else
          display_message("Unknown subcommand: #{subcommand}", type: :error)
          display_usage
        end
      end

      private

      def list_templates(args)
        category_filter = nil

        # Parse options
        until args.empty?
          token = args.shift
          case token
          when "--category", "-c"
            category_filter = args.shift
          when "-h", "--help"
            display_list_usage
            return
          end
        end

        templates = @template_manager.list_templates

        if templates.empty?
          display_message("No prompt templates found.", type: :info)
          return
        end

        # Filter by category if specified
        if category_filter
          templates = templates.select { |t| t[:category] == category_filter }
          if templates.empty?
            display_message("No templates found in category: #{category_filter}", type: :info)
            return
          end
        end

        # Group by category
        grouped = templates.group_by { |t| t[:category] }

        display_message("\nAvailable Prompt Templates", type: :highlight)
        display_message("=" * 50, type: :muted)

        grouped.each do |category, category_templates|
          display_message("\n#{category}/", type: :info)

          table_data = category_templates.map do |t|
            source_badge = case determine_source(t[:path])
            when :project then "[project]"
            when :user then "[user]"
            else "[builtin]"
            end
            [
              "  #{File.basename(t[:id])}",
              t[:version] || "1.0.0",
              source_badge,
              truncate(t[:description] || "", 40)
            ]
          end

          table = TTY::Table.new(
            header: ["Template", "Version", "Source", "Description"],
            rows: table_data
          )
          display_message(table.render(:unicode, padding: [0, 1]), type: :info)
        end

        display_message("\nUse 'aidp prompts show <template_id>' to view details", type: :muted)
      end

      def show_template(args)
        template_id = args.shift

        if template_id.nil? || template_id.start_with?("-")
          display_message("Error: Template ID required", type: :error)
          display_show_usage
          return
        end

        info = @template_manager.template_info(template_id)

        if info.nil?
          display_message("Template not found: #{template_id}", type: :error)
          display_message("Use 'aidp prompts list' to see available templates", type: :muted)
          return
        end

        display_message("\nTemplate: #{info[:id]}", type: :highlight)
        display_message("=" * 50, type: :muted)
        display_message("Name: #{info[:name]}", type: :info)
        display_message("Description: #{info[:description]}", type: :info) if info[:description]
        display_message("Version: #{info[:version]}", type: :info) if info[:version]
        display_message("Source: #{info[:source]}", type: :info)
        display_message("Path: #{info[:path]}", type: :muted)

        if info[:variables]&.any?
          display_message("\nVariables:", type: :highlight)
          info[:variables].each { |v| display_message("  - {{#{v}}}", type: :info) }
        end

        display_message("\nPrompt Preview:", type: :highlight)
        display_message("-" * 50, type: :muted)
        display_message(info[:prompt_preview] || "(empty)", type: :info)
        display_message("-" * 50, type: :muted)

        if info[:source] != :project
          display_message("\nTo customize this template for your project:", type: :muted)
          display_message("  aidp prompts customize #{template_id}", type: :muted)
        end
      end

      def customize_template(args)
        template_id = args.shift

        if template_id.nil? || template_id.start_with?("-")
          display_message("Error: Template ID required", type: :error)
          display_customize_usage
          return
        end

        begin
          path = @template_manager.customize_template(template_id)
          display_message("Template customized successfully!", type: :success)
          display_message("Edit the template at: #{path}", type: :info)
          display_message("\nThe template will now be loaded from your project directory.", type: :muted)
          display_message("Use 'aidp prompts reset #{template_id}' to restore the default.", type: :muted)
        rescue Prompts::TemplateNotFoundError
          display_message("Template not found: #{template_id}", type: :error)
          display_message("Use 'aidp prompts list' to see available templates", type: :muted)
        rescue => e
          display_message("Failed to customize template: #{e.message}", type: :error)
        end
      end

      def reset_template(args)
        template_id = args.shift

        if template_id.nil? || template_id.start_with?("-")
          display_message("Error: Template ID required", type: :error)
          display_reset_usage
          return
        end

        # Confirm reset
        unless @prompt.yes?("Reset #{template_id} to default? This will delete your customizations.")
          display_message("Reset cancelled", type: :info)
          return
        end

        if @template_manager.reset_template(template_id)
          display_message("Template reset to default successfully!", type: :success)
        else
          display_message("No customization found for: #{template_id}", type: :info)
        end
      end

      def determine_source(path)
        project_prompts_dir = File.join(@project_dir, ".aidp", "prompts")
        user_prompts_dir = File.join(Dir.home, ".aidp", "prompts")

        if path.start_with?(project_prompts_dir)
          :project
        elsif path.start_with?(user_prompts_dir)
          :user
        else
          :builtin
        end
      end

      def truncate(text, max_length)
        return "" if text.nil?
        return text if text.length <= max_length

        "#{text[0, max_length - 3]}..."
      end

      def display_usage
        display_message("\nUsage: aidp prompts <subcommand> [options]", type: :info)
        display_message("\nSubcommands:", type: :info)
        display_message("  list, ls              List all available prompt templates", type: :info)
        display_message("  show, view <id>       Show template details", type: :info)
        display_message("  customize, edit <id>  Copy template to project for customization", type: :info)
        display_message("  reset <id>            Reset customized template to default", type: :info)
        display_message("\nExamples:", type: :info)
        display_message("  aidp prompts list", type: :info)
        display_message("  aidp prompts list --category decision_engine", type: :info)
        display_message("  aidp prompts show decision_engine/condition_detection", type: :info)
        display_message("  aidp prompts customize decision_engine/condition_detection", type: :info)
        display_message("  aidp prompts reset decision_engine/condition_detection", type: :info)
      end

      def display_list_usage
        display_message("\nUsage: aidp prompts list [options]", type: :info)
        display_message("\nOptions:", type: :info)
        display_message("  --category, -c <name>  Filter by category", type: :info)
        display_message("  -h, --help            Show this help", type: :info)
      end

      def display_show_usage
        display_message("\nUsage: aidp prompts show <template_id>", type: :info)
        display_message("\nExamples:", type: :info)
        display_message("  aidp prompts show decision_engine/condition_detection", type: :info)
      end

      def display_customize_usage
        display_message("\nUsage: aidp prompts customize <template_id>", type: :info)
        display_message("\nExamples:", type: :info)
        display_message("  aidp prompts customize decision_engine/condition_detection", type: :info)
      end

      def display_reset_usage
        display_message("\nUsage: aidp prompts reset <template_id>", type: :info)
        display_message("\nExamples:", type: :info)
        display_message("  aidp prompts reset decision_engine/condition_detection", type: :info)
      end
    end
  end
end
