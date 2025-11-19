# frozen_string_literal: true

require "tty-prompt"
require "tty-table"
require_relative "../config"
require_relative "../metadata/cache"
require_relative "../metadata/query"
require_relative "../metadata/validator"

module Aidp
  module CLI
    # CLI commands for managing tool metadata
    #
    # Provides commands for:
    # - aidp tools lint - Validate all metadata
    # - aidp tools info <id> - Display tool details
    # - aidp tools reload - Force cache regeneration
    # - aidp tools list - List all tools
    class ToolsCommand
      # Initialize tools command
      #
      # @param project_dir [String] Project directory path
      # @param prompt [TTY::Prompt] TTY prompt instance
      def initialize(project_dir: Dir.pwd, prompt: TTY::Prompt.new)
        @project_dir = project_dir
        @prompt = prompt
      end

      # Run tools command
      #
      # @param args [Array<String>] Command arguments
      # @return [Integer] Exit code
      def run(args)
        subcommand = args.shift

        case subcommand
        when "lint"
          run_lint
        when "info"
          tool_id = args.shift
          unless tool_id
            @prompt.say("Error: tool ID required")
            @prompt.say("Usage: aidp tools info <tool_id>")
            return 1
          end
          run_info(tool_id)
        when "reload"
          run_reload
        when "list"
          run_list
        when nil, "help", "--help", "-h"
          show_help
        else
          @prompt.say("Unknown subcommand: #{subcommand}")
          show_help
          return 1
        end

        0
      end

      # Show help message
      def show_help
        @prompt.say("\nAIDP Tools Management")
        @prompt.say("\nUsage:")
        @prompt.say("  aidp tools lint           Validate all tool metadata")
        @prompt.say("  aidp tools info <id>      Show detailed tool information")
        @prompt.say("  aidp tools reload         Force regenerate tool directory cache")
        @prompt.say("  aidp tools list           List all available tools")
        @prompt.say("\nExamples:")
        @prompt.say("  aidp tools lint")
        @prompt.say("  aidp tools info ruby_rspec_tdd")
        @prompt.say("  aidp tools reload")
      end

      # Run lint command
      def run_lint
        Aidp.log_info("tools", "Running tool metadata lint")

        @prompt.say("\nValidating tool metadata...")

        cache = create_cache
        query = Metadata::Query.new(cache: cache)

        begin
          query.directory
        rescue => e
          @prompt.error("Failed to load tool directory: #{e.message}")
          Aidp.log_error("tools", "Lint failed", error: e.message)
          return 1
        end

        # Reload to get fresh validation
        tools = load_all_tools

        validator = Metadata::Validator.new(tools)
        results = validator.validate_all

        # Display results
        display_lint_results(results)

        # Write error log if there are errors
        invalid_results = results.reject(&:valid)
        if invalid_results.any?
          log_path = File.join(@project_dir, ".aidp", "logs", "metadata_errors.log")
          validator.write_error_log(results, log_path)
          @prompt.warn("\nError log written to: #{log_path}")
        end

        invalid_results.empty? ? 0 : 1
      end

      # Run info command
      #
      # @param tool_id [String] Tool ID
      def run_info(tool_id)
        Aidp.log_info("tools", "Showing tool info", tool_id: tool_id)

        cache = create_cache
        query = Metadata::Query.new(cache: cache)

        tool = query.find_by_id(tool_id)

        unless tool
          @prompt.error("Tool not found: #{tool_id}")
          return 1
        end

        display_tool_details(tool)

        0
      end

      # Run reload command
      def run_reload
        Aidp.log_info("tools", "Reloading tool directory")

        @prompt.say("\nRegenerating tool directory cache...")

        cache = create_cache

        begin
          cache.reload
          @prompt.ok("Tool directory cache regenerated successfully")
        rescue => e
          @prompt.error("Failed to reload cache: #{e.message}")
          Aidp.log_error("tools", "Reload failed", error: e.message)
          return 1
        end

        0
      end

      # Run list command
      def run_list
        Aidp.log_info("tools", "Listing all tools")

        cache = create_cache
        query = Metadata::Query.new(cache: cache)

        query.directory
        stats = query.statistics

        @prompt.say("\nTool Directory Statistics:")
        @prompt.say("  Total tools: #{stats["total_tools"]}")
        @prompt.say("  By type:")
        stats["by_type"].each do |type, count|
          @prompt.say("    #{type}: #{count}")
        end

        @prompt.say("\nAll Tools:")

        # Group by type
        %w[skill persona template].each do |type|
          tools = query.find_by_type(type)
          next if tools.empty?

          @prompt.say("\n#{type.capitalize}s (#{tools.size}):")
          display_tools_table(tools)
        end

        0
      end

      private

      # Create metadata cache instance
      #
      # @return [Metadata::Cache] Cache instance
      def create_cache
        tool_config = Aidp::Config.tool_metadata_config(@project_dir)

        directories = tool_config[:directories] || default_directories
        cache_file = tool_config[:cache_file] || default_cache_file
        strict = tool_config[:strict] || false

        Metadata::Cache.new(
          cache_path: cache_file,
          directories: directories,
          strict: strict
        )
      end

      # Get default directories to scan
      #
      # @return [Array<String>] Default directories
      def default_directories
        [
          File.join(@project_dir, ".aidp", "skills"),
          File.join(@project_dir, ".aidp", "personas"),
          File.join(@project_dir, ".aidp", "templates"),
          # Also include gem templates
          File.expand_path("../../templates/skills", __dir__),
          File.expand_path("../../templates", __dir__)
        ].select { |dir| Dir.exist?(dir) }
      end

      # Get default cache file path
      #
      # @return [String] Cache file path
      def default_cache_file
        File.join(@project_dir, ".aidp", "cache", "tool_directory.json")
      end

      # Load all tools from directories
      #
      # @return [Array<Metadata::ToolMetadata>] All tools
      def load_all_tools
        directories = default_directories
        scanner = Metadata::Scanner.new(directories)
        scanner.scan_all
      end

      # Display lint results
      #
      # @param results [Array<Metadata::Validator::ValidationResult>] Results
      def display_lint_results(results)
        valid_count = results.count(&:valid)
        invalid_count = results.count { |r| !r.valid }
        warning_count = results.sum { |r| r.warnings.size }

        @prompt.say("\nValidation Results:")
        @prompt.say("  Total tools: #{results.size}")
        @prompt.ok("  Valid: #{valid_count}") if valid_count > 0
        @prompt.error("  Invalid: #{invalid_count}") if invalid_count > 0
        @prompt.warn("  Warnings: #{warning_count}") if warning_count > 0

        # Show errors
        invalid_results = results.reject(&:valid)
        if invalid_results.any?
          @prompt.say("\nErrors:")
          invalid_results.each do |result|
            @prompt.error("\n  #{result.tool_id} (#{result.file_path}):")
            result.errors.each { |err| @prompt.say("    - #{err}") }
          end
        end

        # Show warnings
        warnings = results.select { |r| r.warnings.any? }
        if warnings.any?
          @prompt.say("\nWarnings:")
          warnings.each do |result|
            @prompt.warn("\n  #{result.tool_id} (#{result.file_path}):")
            result.warnings.each { |warn| @prompt.say("    - #{warn}") }
          end
        end

        if invalid_count.zero? && warning_count.zero?
          @prompt.ok("\nAll tools validated successfully!")
        end
      end

      # Display tool details
      #
      # @param tool [Hash] Tool metadata
      def display_tool_details(tool)
        @prompt.say("\nTool: #{tool["title"]}")
        @prompt.say("=" * 60)
        @prompt.say("ID:          #{tool["id"]}")
        @prompt.say("Type:        #{tool["type"]}")
        @prompt.say("Version:     #{tool["version"]}")
        @prompt.say("Summary:     #{tool["summary"]}")
        @prompt.say("Priority:    #{tool["priority"]}")
        @prompt.say("Experimental: #{tool["experimental"]}")

        if tool["applies_to"]&.any?
          @prompt.say("\nApplies To:")
          tool["applies_to"].each { |tag| @prompt.say("  - #{tag}") }
        end

        if tool["work_unit_types"]&.any?
          @prompt.say("\nWork Unit Types:")
          tool["work_unit_types"].each { |wut| @prompt.say("  - #{wut}") }
        end

        if tool["capabilities"]&.any?
          @prompt.say("\nCapabilities:")
          tool["capabilities"].each { |cap| @prompt.say("  - #{cap}") }
        end

        if tool["dependencies"]&.any?
          @prompt.say("\nDependencies:")
          tool["dependencies"].each { |dep| @prompt.say("  - #{dep}") }
        end

        @prompt.say("\nSource: #{tool["source_path"]}")
      end

      # Display tools in a table
      #
      # @param tools [Array<Hash>] Tools to display
      def display_tools_table(tools)
        return if tools.empty?

        rows = tools.map do |tool|
          [
            tool["id"],
            tool["title"],
            tool["version"],
            tool["priority"],
            (tool["applies_to"] || []).join(", ")
          ]
        end

        table = TTY::Table.new(
          header: ["ID", "Title", "Version", "Priority", "Tags"],
          rows: rows
        )

        @prompt.say(table.render(:unicode))
      end
    end
  end
end
