# frozen_string_literal: true

require_relative "../errors"
require_relative "parser"

module Aidp
  module Metadata
    # Scans directories for tool files and extracts metadata
    #
    # Recursively finds all .md files in configured directories,
    # parses their metadata, and returns a collection of ToolMetadata objects.
    #
    # @example Scanning directories
    #   scanner = Scanner.new([".aidp/skills", ".aidp/templates"])
    #   tools = scanner.scan_all
    class Scanner
      # Initialize scanner with directory paths
      #
      # @param directories [Array<String>] Directories to scan
      def initialize(directories = [])
        @directories = Array(directories)
      end

      # Scan all configured directories
      #
      # @return [Array<ToolMetadata>] All discovered tool metadata
      def scan_all
        Aidp.log_debug("metadata", "Scanning directories", directories: @directories)

        all_tools = []
        @directories.each do |dir|
          tools = scan_directory(dir)
          all_tools.concat(tools)
        end

        Aidp.log_info(
          "metadata",
          "Scan complete",
          directories: @directories.size,
          tools_found: all_tools.size
        )

        all_tools
      end

      # Scan a single directory
      #
      # @param directory [String] Directory path to scan
      # @param type [String, nil] Tool type filter or nil for all
      # @return [Array<ToolMetadata>] Discovered tool metadata
      def scan_directory(directory, type: nil)
        unless Dir.exist?(directory)
          Aidp.log_warn("metadata", "Directory not found", directory: directory)
          return []
        end

        Aidp.log_debug("metadata", "Scanning directory", directory: directory, type: type)

        tools = []
        md_files = find_markdown_files(directory)

        md_files.each do |file_path|
          tool = Parser.parse_file(file_path, type: type)
          tools << tool if type.nil? || tool.type == type
        rescue Aidp::Errors::ValidationError => e
          Aidp.log_warn(
            "metadata",
            "Failed to parse file",
            file: file_path,
            error: e.message
          )
        end

        Aidp.log_debug(
          "metadata",
          "Directory scan complete",
          directory: directory,
          files_found: md_files.size,
          tools_parsed: tools.size
        )

        tools
      end

      # Find all markdown files in directory recursively
      #
      # @param directory [String] Directory path
      # @return [Array<String>] Paths to .md files
      def find_markdown_files(directory)
        pattern = File.join(directory, "**", "*.md")
        files = Dir.glob(pattern)

        Aidp.log_debug(
          "metadata",
          "Found markdown files",
          directory: directory,
          count: files.size
        )

        files
      end

      # Scan with file filtering
      #
      # @param directory [String] Directory path
      # @param filter [Proc] Filter proc that receives file_path and returns boolean
      # @return [Array<ToolMetadata>] Filtered tool metadata
      def scan_with_filter(directory, &filter)
        unless Dir.exist?(directory)
          Aidp.log_warn("metadata", "Directory not found", directory: directory)
          return []
        end

        tools = []
        md_files = find_markdown_files(directory)

        md_files.each do |file_path|
          next unless filter.call(file_path)

          begin
            tool = Parser.parse_file(file_path)
            tools << tool
          rescue Aidp::Errors::ValidationError => e
            Aidp.log_warn(
              "metadata",
              "Failed to parse file",
              file: file_path,
              error: e.message
            )
          end
        end

        tools
      end

      # Scan for changes since last scan
      #
      # Compares file hashes to detect changes
      #
      # @param directory [String] Directory path
      # @param previous_hashes [Hash<String, String>] Map of file_path => file_hash
      # @return [Hash] Hash with :added, :modified, :removed keys
      def scan_changes(directory, previous_hashes = {})
        Aidp.log_debug("metadata", "Scanning for changes", directory: directory)

        current_files = find_markdown_files(directory)
        current_hashes = {}

        changes = {
          added: [],
          modified: [],
          removed: [],
          unchanged: []
        }

        # Check for added and modified files
        current_files.each do |file_path|
          content = File.read(file_path, encoding: "UTF-8")
          file_hash = Parser.compute_file_hash(content)
          current_hashes[file_path] = file_hash

          if previous_hashes.key?(file_path)
            if previous_hashes[file_path] != file_hash
              changes[:modified] << file_path
            else
              changes[:unchanged] << file_path
            end
          else
            changes[:added] << file_path
          end
        end

        # Check for removed files
        previous_hashes.keys.each do |file_path|
          changes[:removed] << file_path unless current_hashes.key?(file_path)
        end

        Aidp.log_info(
          "metadata",
          "Change detection complete",
          added: changes[:added].size,
          modified: changes[:modified].size,
          removed: changes[:removed].size,
          unchanged: changes[:unchanged].size
        )

        changes
      end
    end
  end
end
