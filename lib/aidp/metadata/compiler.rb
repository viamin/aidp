# frozen_string_literal: true

require "json"
require_relative "../errors"
require_relative "scanner"
require_relative "validator"

module Aidp
  module Metadata
    # Compiles tool metadata into a cached directory structure
    #
    # Aggregates metadata from all tool files, builds indexes, resolves dependencies,
    # and generates a cached tool_directory.json for fast lookups.
    #
    # @example Compiling the tool directory
    #   compiler = Compiler.new(directories: [".aidp/skills", ".aidp/templates"])
    #   compiler.compile(output_path: ".aidp/cache/tool_directory.json")
    class Compiler
      # Compiled directory structure
      attr_reader :tools, :indexes, :dependency_graph

      # Initialize compiler
      #
      # @param directories [Array<String>] Directories to scan
      # @param strict [Boolean] Whether to fail on validation errors
      def initialize(directories: [], strict: false)
        @directories = Array(directories)
        @strict = strict
        @tools = []
        @indexes = {}
        @dependency_graph = {}
      end

      # Compile tool directory
      #
      # @param output_path [String] Path to output JSON file
      # @return [Hash] Compiled directory structure
      def compile(output_path:)
        Aidp.log_info("metadata", "Compiling tool directory", directories: @directories, output: output_path)

        # Scan all directories
        scanner = Scanner.new(@directories, strict: @strict)
        @tools = scanner.scan_all

        # Validate tools
        validator = Validator.new(@tools)
        validation_results = validator.validate_all

        # Handle validation failures
        parse_error_results = scanner.parse_errors.map do |err|
          Validator::ValidationResult.new(
            tool_id: "(unknown)",
            file_path: err[:file],
            valid: false,
            errors: [err[:error]],
            warnings: []
          )
        end

        invalid_results = handle_validation_results(validation_results + parse_error_results)

        # Build indexes and graphs
        build_indexes
        build_dependency_graph

        # Create directory structure
        directory = create_directory_structure(invalid_results: invalid_results)

        # Write to file
        write_directory(directory, output_path)

        Aidp.log_info(
          "metadata",
          "Compilation complete",
          tools: @tools.size,
          output: output_path
        )

        directory
      end

      # Build indexes for fast lookups
      def build_indexes
        Aidp.log_debug("metadata", "Building indexes")

        @indexes = {
          by_id: {},
          by_type: {},
          by_tag: {},
          by_work_unit_type: {}
        }

        @tools.each do |tool|
          # Index by ID
          @indexes[:by_id][tool.id] = tool

          # Index by type
          @indexes[:by_type][tool.type] ||= []
          @indexes[:by_type][tool.type] << tool

          # Index by tags
          tool.applies_to.each do |tag|
            @indexes[:by_tag][tag] ||= []
            @indexes[:by_tag][tag] << tool
          end

          # Index by work unit types
          tool.work_unit_types.each do |wut|
            @indexes[:by_work_unit_type][wut] ||= []
            @indexes[:by_work_unit_type][wut] << tool
          end
        end

        Aidp.log_debug(
          "metadata",
          "Indexes built",
          types: @indexes[:by_type].keys,
          tags: @indexes[:by_tag].keys.size,
          work_unit_types: @indexes[:by_work_unit_type].keys
        )
      end

      # Build dependency graph
      def build_dependency_graph
        Aidp.log_debug("metadata", "Building dependency graph")

        @dependency_graph = {}

        @tools.each do |tool|
          @dependency_graph[tool.id] = {
            dependencies: tool.dependencies,
            dependents: []
          }
        end

        # Build reverse dependencies (dependents)
        @tools.each do |tool|
          tool.dependencies.each do |dep_id|
            next unless @dependency_graph[dep_id]

            @dependency_graph[dep_id][:dependents] << tool.id
          end
        end

        Aidp.log_debug(
          "metadata",
          "Dependency graph built",
          nodes: @dependency_graph.size
        )
      end

      # Create directory structure for serialization
      #
      # @return [Hash] Directory structure
      def create_directory_structure(invalid_results: [])
        {
          "version" => "1.0.0",
          "compiled_at" => Time.now.iso8601,
          "tools" => @tools.map(&:to_h),
          "indexes" => {
            "by_type" => @indexes[:by_type].transform_values { |tools| tools.map(&:id) },
            "by_tags" => @indexes[:by_tag].transform_values { |tools| tools.map(&:id) },
            "by_work_unit_type" => @indexes[:by_work_unit_type].transform_values { |tools| tools.map(&:id) }
          },
          "dependency_graph" => @dependency_graph,
          "errors" => invalid_results.map { |res| {"tool_id" => res.tool_id, "errors" => res.errors, "warnings" => res.warnings} },
          "statistics" => {
            "total_tools" => @tools.size,
            "by_type" => @tools.group_by(&:type).transform_values(&:size),
            "total_tags" => @indexes[:by_tag].size,
            "total_work_unit_types" => @indexes[:by_work_unit_type].size
          }
        }
      end

      # Write directory to JSON file
      #
      # @param directory [Hash] Directory structure
      # @param output_path [String] Output file path
      def write_directory(directory, output_path)
        # Ensure output directory exists
        output_dir = File.dirname(output_path)
        FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)

        # Write with pretty formatting
        File.write(output_path, JSON.pretty_generate(directory))

        Aidp.log_debug("metadata", "Wrote directory", path: output_path, size: File.size(output_path))
      end

      # Handle validation results
      #
      # @param results [Array<ValidationResult>] Validation results
      # @raise [Aidp::Errors::ValidationError] if strict mode and errors found
      def handle_validation_results(results)
        invalid_results = results.reject(&:valid)

        if invalid_results.any?
          Aidp.log_warn(
            "metadata",
            "Validation errors found",
            count: invalid_results.size
          )

          invalid_results.each do |result|
            Aidp.log_error(
              "metadata",
              "Tool validation failed",
              tool_id: result.tool_id,
              file: result.file_path,
              errors: result.errors
            )
          end

          if @strict
            raise Aidp::Errors::ValidationError,
              "#{invalid_results.size} tool(s) failed validation (strict mode enabled)"
          end

          # Remove invalid tools from compilation
          invalid_ids = invalid_results.map(&:tool_id)
          @tools.reject! { |tool| invalid_ids.include?(tool.id) }
        end

        # Log warnings
        results.each do |result|
          next if result.warnings.empty?

          Aidp.log_warn(
            "metadata",
            "Tool validation warnings",
            tool_id: result.tool_id,
            file: result.file_path,
            warnings: result.warnings
          )
        end
        invalid_results
      end
    end
  end
end
