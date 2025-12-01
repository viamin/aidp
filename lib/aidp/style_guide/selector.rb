# frozen_string_literal: true

module Aidp
  module StyleGuide
    # Deterministic selector for STYLE_GUIDE sections based on task context
    #
    # This class provides intelligent section selection from STYLE_GUIDE.md
    # based on keywords in the task context. For providers with their own
    # instruction files (Claude, GitHub Copilot), it skips style guide injection.
    #
    # @example Basic usage
    #   selector = Selector.new(project_dir: "/path/to/project")
    #   content = selector.select_sections(keywords: ["testing", "error"])
    #
    # @example Check if provider needs style guide
    #   selector.provider_needs_style_guide?("cursor")    # => true
    #   selector.provider_needs_style_guide?("claude")    # => false
    class Selector
      # Providers that have their own instruction files and don't need
      # the style guide injected into prompts
      PROVIDERS_WITH_INSTRUCTION_FILES = %w[
        claude
        anthropic
        github_copilot
      ].freeze

      # Mapping of keywords/topics to STYLE_GUIDE.md line ranges
      # Each entry is [start_line, end_line, description]
      SECTION_MAPPING = {
        # Core Engineering
        "code_organization" => [[25, 117, "Code Organization"]],
        "class" => [[25, 117, "Code Organization"], [217, 236, "Sandi Metz Rules"]],
        "method" => [[224, 229, "Method Design"], [217, 236, "Sandi Metz Rules"]],
        "composition" => [[29, 35, "Composition over Inheritance"]],
        "inheritance" => [[29, 35, "Composition over Inheritance"]],
        "small_objects" => [[25, 117, "Code Organization"]],
        "single_responsibility" => [[25, 117, "Code Organization"]],

        # Sandi Metz
        "sandi_metz" => [[217, 236, "Sandi Metz Rules"]],
        "parameter" => [[231, 236, "Parameter Limits"]],

        # Ruby Conventions
        "ruby" => [[259, 278, "Ruby Conventions"], [446, 498, "Ruby Version Management"]],
        "naming" => [[51, 56, "Naming Conventions"]],
        "convention" => [[259, 278, "Ruby Conventions"]],
        "style" => [[259, 278, "Ruby Conventions"]],
        "require" => [[263, 266, "Require Practices"]],
        "mise" => [[446, 498, "Ruby Version Management"]],
        "version" => [[446, 498, "Ruby Version Management"]],

        # Feature Organization
        "feature" => [[58, 116, "Feature Organization by Purpose"]],
        "workflow" => [[58, 116, "Feature Organization by Purpose"]],
        "template" => [[118, 210, "Template/Skill Separation"]],
        "skill" => [[118, 210, "Template/Skill Separation"]],

        # Logging
        "logging" => [[287, 430, "Logging Practices"]],
        "log" => [[287, 430, "Logging Practices"]],
        "debug" => [[287, 430, "Logging Practices"]],

        # ZFC - Zero Framework Cognition
        "zfc" => [[500, 797, "Zero Framework Cognition (ZFC)"]],
        "zero_framework" => [[500, 797, "Zero Framework Cognition (ZFC)"]],
        "ai_decision" => [[500, 797, "Zero Framework Cognition (ZFC)"]],
        "decision_engine" => [[500, 797, "Zero Framework Cognition (ZFC)"]],

        # AGD - AI-Generated Determinism
        "agd" => [[798, 855, "AI-Generated Determinism (AGD)"]],
        "determinism" => [[798, 855, "AI-Generated Determinism (AGD)"]],
        "config_time" => [[798, 855, "AI-Generated Determinism (AGD)"]],

        # TTY / TUI
        "tty" => [[856, 1105, "TTY Toolkit Guidelines"]],
        "tui" => [[856, 1105, "TTY Toolkit Guidelines"]],
        "ui" => [[856, 1105, "TTY Toolkit Guidelines"]],
        "prompt" => [[856, 1105, "TTY Toolkit Guidelines"], [936, 972, "TTY Output Practices"]],
        "progress" => [[856, 1105, "TTY Toolkit Guidelines"]],
        "spinner" => [[856, 1105, "TTY Toolkit Guidelines"]],
        "table" => [[856, 1105, "TTY Toolkit Guidelines"]],
        "select" => [[856, 1105, "TTY Toolkit Guidelines"]],

        # Testing
        "testing" => [[1873, 2112, "Testing Guidelines"]],
        "test" => [[1873, 2112, "Testing Guidelines"], [1550, 1800, "Test Coverage Philosophy"]],
        "spec" => [[1873, 2112, "Testing Guidelines"]],
        "rspec" => [[1873, 2112, "Testing Guidelines"]],
        "mock" => [[1873, 2112, "Testing Guidelines"], [1930, 2012, "Dependency Injection"]],
        "stub" => [[1873, 2112, "Testing Guidelines"]],
        "coverage" => [[1550, 1800, "Test Coverage Philosophy"]],
        "pending" => [[1816, 1870, "Pending Specs Policy"]],
        "expect_script" => [[1173, 1234, "expect Scripts for TUI"]],
        "tmux" => [[1203, 1295, "tmux Testing"]],
        "time_test" => [[1656, 1690, "Time-based Testing"]],
        "fork" => [[1718, 1778, "Forked Process Testing"]],
        "encoding" => [[1780, 1813, "String Encoding"]],
        "dependency_injection" => [[1930, 2012, "Dependency Injection"]],

        # Error Handling
        "error" => [[2113, 2168, "Error Handling"], [280, 286, "Error Handling Basics"]],
        "exception" => [[2113, 2168, "Error Handling"], [2130, 2140, "Error Class Pattern"]],
        "rescue" => [[280, 286, "Error Handling Basics"], [2113, 2168, "Error Handling"]],

        # Concurrency
        "concurrency" => [[2170, 2185, "Concurrency & Threads"]],
        "thread" => [[2170, 2185, "Concurrency & Threads"]],
        "async" => [[2170, 2185, "Concurrency & Threads"]],

        # Performance
        "performance" => [[2206, 2232, "Performance"]],
        "optimization" => [[2206, 2232, "Performance"]],
        "cache" => [[2206, 2232, "Performance"]],

        # Security
        "security" => [[2233, 2272, "Security & Safety"]],
        "safety" => [[2233, 2272, "Security & Safety"]],
        "validation" => [[2233, 2272, "Security & Safety"]],

        # Backward Compatibility / Pre-release
        "backward_compatibility" => [[2273, 2472, "Backward Compatibility"]],
        "deprecation" => [[2273, 2472, "Backward Compatibility"]],
        "legacy" => [[2273, 2472, "Backward Compatibility"]],

        # Commit Hygiene
        "commit" => [[2476, 2482, "Commit Hygiene"]],
        "git" => [[2476, 2482, "Commit Hygiene"]],

        # Prompt Optimization
        "prompt_optimization" => [[2523, 2854, "Prompt Optimization"]],
        "fragment" => [[2523, 2854, "Prompt Optimization"]],

        # Task Filing
        "task" => [[2856, 2890, "Task Filing"]],
        "tasklist" => [[2856, 2890, "Task Filing"]]
      }.freeze

      # Default sections to always include (core rules)
      CORE_SECTIONS = [
        [25, 117, "Code Organization"],
        [217, 236, "Sandi Metz Rules"],
        [287, 430, "Logging Practices"]
      ].freeze

      attr_reader :project_dir

      def initialize(project_dir:)
        @project_dir = project_dir
        @style_guide_content = nil
        @style_guide_lines = nil
      end

      # Check if a provider needs style guide injection
      #
      # @param provider_name [String] Name of the provider
      # @return [Boolean] true if style guide should be injected
      def provider_needs_style_guide?(provider_name)
        return true if provider_name.nil?

        normalized = provider_name.to_s.downcase.strip
        !PROVIDERS_WITH_INSTRUCTION_FILES.include?(normalized)
      end

      # Select relevant sections from STYLE_GUIDE.md based on keywords
      #
      # @param keywords [Array<String>] Keywords to match against
      # @param include_core [Boolean] Whether to include core sections
      # @param max_lines [Integer, nil] Maximum lines to return (nil for unlimited)
      # @return [String] Combined content of selected sections
      def select_sections(keywords: [], include_core: true, max_lines: nil)
        Aidp.log_debug("style_guide_selector", "selecting_sections",
          keywords: keywords, include_core: include_core, max_lines: max_lines)

        return "" unless style_guide_exists?

        # Gather all matching sections
        sections = gather_sections(keywords, include_core)

        # Merge overlapping ranges and sort
        merged_ranges = merge_and_sort_ranges(sections)

        # Extract content from ranges
        content = extract_content(merged_ranges, max_lines)

        Aidp.log_debug("style_guide_selector", "sections_selected",
          section_count: merged_ranges.size, content_lines: content.lines.count)

        content
      end

      # Extract keywords from task context
      #
      # @param context [Hash, String] Task context (description, affected files, etc.)
      # @return [Array<String>] Extracted keywords
      def extract_keywords(context)
        text = context.is_a?(Hash) ? context.values.join(" ") : context.to_s
        text_lower = text.downcase

        keywords = []

        SECTION_MAPPING.keys.each do |keyword|
          # Convert keyword format (snake_case to spaces/variations)
          patterns = build_patterns(keyword)
          keywords << keyword if patterns.any? { |p| text_lower.include?(p) }
        end

        Aidp.log_debug("style_guide_selector", "keywords_extracted",
          input_length: text.length, keywords_found: keywords.size)

        keywords.uniq
      end

      # Get all available section names
      #
      # @return [Array<String>] List of all section mapping keys
      def available_keywords
        SECTION_MAPPING.keys.sort
      end

      # Check if style guide file exists
      #
      # @return [Boolean]
      def style_guide_exists?
        File.exist?(style_guide_path)
      end

      # Get information about what sections would be selected for given keywords
      #
      # @param keywords [Array<String>] Keywords to check
      # @return [Array<Hash>] Section info with line ranges and descriptions
      def preview_selection(keywords)
        sections = gather_sections(keywords, false)
        merged = merge_and_sort_ranges(sections)

        merged.map do |start_line, end_line, description|
          {
            start_line: start_line,
            end_line: end_line,
            description: description,
            estimated_lines: end_line - start_line + 1
          }
        end
      end

      private

      def style_guide_path
        File.join(@project_dir, "docs", "STYLE_GUIDE.md")
      end

      def style_guide_lines
        @style_guide_lines ||= begin
          return [] unless style_guide_exists?

          content = File.read(style_guide_path, encoding: "UTF-8")
          content = content.encode("UTF-8", invalid: :replace, undef: :replace)
          content.lines
        end
      end

      def gather_sections(keywords, include_core)
        sections = []

        # Add core sections if requested
        sections.concat(CORE_SECTIONS.dup) if include_core

        # Add sections matching keywords
        keywords.each do |keyword|
          normalized = keyword.to_s.downcase.gsub(/[^a-z0-9]/, "_")
          if SECTION_MAPPING.key?(normalized)
            sections.concat(SECTION_MAPPING[normalized])
          end
        end

        sections
      end

      def merge_and_sort_ranges(sections)
        return [] if sections.empty?

        # Convert to sortable format and sort by start line
        ranges = sections.map { |start_l, end_l, desc| [start_l.to_i, end_l.to_i, desc] }
        ranges.sort_by!(&:first)

        # Merge overlapping/adjacent ranges
        merged = []
        current_start, current_end, current_desc = ranges.first

        ranges[1..].each do |start_l, end_l, desc|
          if start_l <= current_end + 5 # Allow small gaps (5 lines)
            # Extend current range
            current_end = [current_end, end_l].max
            current_desc = "#{current_desc}, #{desc}" unless current_desc.include?(desc)
          else
            # Save current range and start new one
            merged << [current_start, current_end, current_desc]
            current_start = start_l
            current_end = end_l
            current_desc = desc
          end
        end

        # Don't forget the last range
        merged << [current_start, current_end, current_desc]

        merged
      end

      def extract_content(ranges, max_lines)
        return "" if ranges.empty?

        lines = style_guide_lines
        return "" if lines.empty?

        parts = []
        total_lines = 0

        ranges.each do |start_line, end_line, description|
          break if max_lines && total_lines >= max_lines

          # Adjust for 0-based indexing
          start_idx = [start_line - 1, 0].max
          end_idx = [end_line - 1, lines.length - 1].min

          section_lines = lines[start_idx..end_idx]
          next if section_lines.nil? || section_lines.empty?

          # Add section header comment
          parts << "<!-- Section: #{description} (lines #{start_line}-#{end_line}) -->"
          parts << section_lines.join

          total_lines += section_lines.length
        end

        content = parts.join("\n")

        # Trim to max_lines if specified
        if max_lines && content.lines.count > max_lines
          content = content.lines.first(max_lines).join
        end

        content
      end

      def build_patterns(keyword)
        patterns = [keyword]

        # Add variations
        patterns << keyword.tr("_", " ")
        patterns << keyword.tr("_", "-")

        # Add singular/plural variations for common terms
        patterns << "#{keyword}s" unless keyword.end_with?("s")
        patterns << keyword.chomp("s") if keyword.end_with?("s")

        patterns.uniq
      end
    end
  end
end
