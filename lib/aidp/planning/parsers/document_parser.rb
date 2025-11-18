# frozen_string_literal: true

require_relative "../../logger"

module Aidp
  module Planning
    module Parsers
      # Parses existing documentation files to extract structured information
      # Uses Zero Framework Cognition (ZFC) for semantic analysis
      class DocumentParser
        def initialize(ai_decision_engine: nil)
          @ai_decision_engine = ai_decision_engine
        end

        # Parse a single file and detect its structure
        # @param file_path [String] Path to the markdown file
        # @return [Hash] Parsed document with type and sections
        def parse_file(file_path)
          Aidp.log_debug("document_parser", "parse_file", path: file_path)

          unless File.exist?(file_path)
            Aidp.log_error("document_parser", "file_not_found", path: file_path)
            raise ArgumentError, "File not found: #{file_path}"
          end

          content = File.read(file_path)
          Aidp.log_debug("document_parser", "read_content", size: content.length)

          {
            path: file_path,
            type: detect_document_type(content),
            sections: extract_sections(content),
            raw_content: content
          }
        end

        # Parse all markdown files in a directory
        # @param dir_path [String] Directory path
        # @return [Array<Hash>] Array of parsed documents
        def parse_directory(dir_path)
          Aidp.log_debug("document_parser", "parse_directory", path: dir_path)

          unless Dir.exist?(dir_path)
            Aidp.log_error("document_parser", "directory_not_found", path: dir_path)
            raise ArgumentError, "Directory not found: #{dir_path}"
          end

          markdown_files = Dir.glob(File.join(dir_path, "**", "*.md"))
          Aidp.log_debug("document_parser", "found_files", count: markdown_files.size)

          markdown_files.map { |file| parse_file(file) }
        end

        private

        # Detect document type using ZFC (AI decision engine)
        # Returns :prd, :design, :adr, :task_list, or :unknown
        def detect_document_type(content)
          Aidp.log_debug("document_parser", "detect_document_type")

          # Use AI decision engine if available (ZFC pattern)
          if @ai_decision_engine
            decision = @ai_decision_engine.decide(
              context: "document classification",
              prompt: "Classify this document as PRD, technical design, ADR, task list, or unknown",
              data: {content: content.slice(0, 2000)}, # First 2000 chars
              schema: {
                type: "string",
                enum: ["prd", "design", "adr", "task_list", "unknown"]
              }
            )
            Aidp.log_debug("document_parser", "ai_classification", type: decision)
            return decision.to_sym
          end

          # Fallback: simple heuristics when AI not available
          # This is acceptable as fallback, but ZFC is preferred
          type = classify_by_heuristics(content)
          Aidp.log_debug("document_parser", "heuristic_classification", type: type)
          type
        end

        # Fallback classification using basic heuristics
        def classify_by_heuristics(content)
          lower_content = content.downcase

          return :prd if lower_content.include?("product requirements") ||
            lower_content.include?("user stories") ||
            lower_content.include?("success criteria")

          return :design if lower_content.include?("technical design") ||
            lower_content.include?("system architecture") ||
            lower_content.include?("component design")

          return :adr if lower_content.include?("decision record") ||
            lower_content.include?("adr") ||
            lower_content.match?(/##?\s+status/i)

          return :task_list if lower_content.include?("task list") ||
            lower_content.include?("- [ ]") ||
            lower_content.match?(/\d+\.\s+\[[ x]\]/i)

          :unknown
        end

        # Extract markdown sections from content
        # Returns hash of section_name => section_content
        def extract_sections(content)
          Aidp.log_debug("document_parser", "extract_sections")

          sections = {}
          current_section = nil
          current_content = []

          content.each_line do |line|
            if line.match?(/^##?\s+(.+)/)
              # Save previous section
              if current_section
                sections[current_section] = current_content.join.strip
              end

              # Start new section
              current_section = line.match(/^##?\s+(.+)/)[1].strip.downcase.gsub(/\s+/, "_")
              current_content = []
            elsif current_section
              current_content << line
            end
          end

          # Save last section
          if current_section
            sections[current_section] = current_content.join.strip
          end

          Aidp.log_debug("document_parser", "extracted_sections", count: sections.size)
          sections
        end
      end
    end
  end
end
