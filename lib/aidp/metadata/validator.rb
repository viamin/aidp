# frozen_string_literal: true

require_relative "../errors"

module Aidp
  module Metadata
    # Validates tool metadata and detects issues
    #
    # Performs validation checks on tool metadata including:
    # - Required field presence
    # - Field type validation
    # - Duplicate ID detection
    # - Dependency resolution
    # - Version format validation
    #
    # @example Validating a collection of tools
    #   validator = Validator.new(tools)
    #   results = validator.validate_all
    #   results.each { |r| puts "#{r[:file]}: #{r[:errors].join(", ")}" }
    class Validator
      # Validation result structure
      ValidationResult = Struct.new(:tool_id, :file_path, :valid, :errors, :warnings, keyword_init: true)

      # Initialize validator with tool metadata collection
      #
      # @param tools [Array<ToolMetadata>] Tools to validate
      def initialize(tools = [])
        @tools = tools
        @errors_by_id = {}
        @warnings_by_id = {}
      end

      # Validate all tools
      #
      # @return [Array<ValidationResult>] Validation results for each tool
      def validate_all
        Aidp.log_debug("metadata", "Validating all tools", count: @tools.size)

        results = @tools.map do |tool|
          validate_tool(tool)
        end

        # Cross-tool validations
        validate_duplicate_ids(results)
        validate_dependencies(results)

        Aidp.log_info(
          "metadata",
          "Validation complete",
          total: results.size,
          valid: results.count(&:valid),
          invalid: results.count { |r| !r.valid }
        )

        results
      end

      # Validate a single tool
      #
      # @param tool [ToolMetadata] Tool to validate
      # @return [ValidationResult] Validation result
      def validate_tool(tool)
        errors = []
        warnings = []

        # Tool metadata validates itself on initialization
        # Here we add additional cross-cutting validations

        # Check for empty arrays in key fields
        if tool.applies_to.empty? && tool.work_unit_types.empty?
          warnings << "No applies_to tags or work_unit_types specified (tool may not be discoverable)"
        end

        # Check for deprecated fields or patterns
        validate_deprecated_patterns(tool, warnings)

        # Check for experimental tools
        if tool.experimental
          warnings << "Tool is marked as experimental"
        end

        # Check content length
        if tool.content.length < 100
          warnings << "Tool content is very short (#{tool.content.length} characters)"
        end

        unless valid_version_format?(tool.version)
          warnings << "Version '#{tool.version}' is not in semver format (MAJOR.MINOR.PATCH)"
        end

        ValidationResult.new(
          tool_id: tool.id,
          file_path: tool.source_path,
          valid: errors.empty?,
          errors: errors,
          warnings: warnings
        )
      rescue Aidp::Errors::ValidationError => e
        # Catch validation errors from tool initialization
        ValidationResult.new(
          tool_id: tool&.id || "unknown",
          file_path: tool&.source_path || "unknown",
          valid: false,
          errors: [e.message],
          warnings: []
        )
      end

      # Validate for duplicate IDs across tools
      #
      # @param results [Array<ValidationResult>] Validation results
      def validate_duplicate_ids(results)
        ids = @tools.map(&:id)
        duplicates = ids.tally.select { |_, count| count > 1 }.keys

        return if duplicates.empty?

        duplicates.each do |dup_id|
          matching_tools = @tools.select { |t| t.id == dup_id }
          matching_tools.each do |tool|
            result = results.find { |r| r.tool_id == tool.id && r.file_path == tool.source_path }
            next unless result

            paths = matching_tools.map(&:source_path).join(", ")
            result.errors << "Duplicate ID '#{dup_id}' found in: #{paths}"
            result.valid = false
          end
        end

        Aidp.log_warn("metadata", "Duplicate IDs detected", duplicates: duplicates)
      end

      # Validate tool dependencies are satisfied
      #
      # @param results [Array<ValidationResult>] Validation results
      def validate_dependencies(results)
        available_ids = @tools.map(&:id).to_set

        @tools.each do |tool|
          next if tool.dependencies.empty?

          tool.dependencies.each do |dep_id|
            next if available_ids.include?(dep_id)

            result = results.find { |r| r.tool_id == tool.id && r.file_path == tool.source_path }
            next unless result

            result.errors << "Missing dependency: '#{dep_id}'"
            result.valid = false
          end
        end
      end

      # Check for deprecated patterns in tool metadata
      #
      # @param tool [ToolMetadata] Tool to check
      # @param warnings [Array<String>] Warnings array to append to
      def validate_deprecated_patterns(tool, warnings)
        # Check for legacy field usage (this would be expanded based on actual deprecations)
        # For now, this is a placeholder for future deprecation warnings
      end

      def valid_version_format?(version)
        version.to_s.match?(/\A\d+\.\d+\.\d+\z/)
      rescue
        false
      end

      # Write validation errors to log file
      #
      # @param results [Array<ValidationResult>] Validation results
      # @param log_path [String] Path to error log file
      def write_error_log(results, log_path)
        Aidp.log_debug("metadata", "Writing error log", path: log_path)

        errors = results.reject(&:valid)
        return if errors.empty?

        File.open(log_path, "w") do |f|
          f.puts "# Metadata Validation Errors"
          f.puts "# Generated: #{Time.now.iso8601}"
          f.puts

          errors.each do |result|
            f.puts "## #{result.tool_id} (#{result.file_path})"
            f.puts
            result.errors.each { |err| f.puts "- ERROR: #{err}" }
            result.warnings.each { |warn| f.puts "- WARNING: #{warn}" }
            f.puts
          end
        end

        Aidp.log_info("metadata", "Wrote error log", path: log_path, error_count: errors.size)
      end
    end
  end
end
