# frozen_string_literal: true

require "fileutils"
require "time"

module Aidp
  module Init
    # Creates project documentation artefacts based on the analyzer output. All
    # documents are deterministic and tailored with repository insights.
    class DocGenerator
      OUTPUT_DIR = "docs"
      STYLE_GUIDE_PATH = File.join(OUTPUT_DIR, "LLM_STYLE_GUIDE.md")
      ANALYSIS_PATH = File.join(OUTPUT_DIR, "PROJECT_ANALYSIS.md")
      QUALITY_PLAN_PATH = File.join(OUTPUT_DIR, "CODE_QUALITY_PLAN.md")

      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
      end

      def generate(analysis:, preferences: {})
        ensure_output_directory
        write_style_guide(analysis, preferences)
        write_project_analysis(analysis)
        write_quality_plan(analysis, preferences)
      end

      private

      def ensure_output_directory
        FileUtils.mkdir_p(File.join(@project_dir, OUTPUT_DIR))
      end

      def write_style_guide(analysis, preferences)
        languages = format_list(analysis[:languages].keys)
        # Extract high-confidence frameworks (>= 0.7)
        frameworks = extract_confident_names(analysis[:frameworks], threshold: 0.7)
        test_frameworks = extract_confident_names(analysis[:test_frameworks], threshold: 0.7)
        key_dirs = format_list(analysis[:key_directories])
        tooling = extract_confident_names(analysis[:tooling], threshold: 0.7, key: :tool).map { |tool| format_tool(tool) }.sort

        adoption_note = if truthy?(preferences[:adopt_new_conventions])
          "This project has opted to adopt new conventions recommended by aidp init. When in doubt, prefer the rules below over legacy patterns."
        else
          "Retain existing conventions when they do not conflict with the guidance below."
        end

        frameworks_text = frameworks.empty? ? "None detected" : frameworks.join(", ")
        test_frameworks_text = test_frameworks.empty? ? "Unknown" : test_frameworks.join(", ")

        content = <<~GUIDE
          # Project LLM Style Guide

          > Generated automatically by `aidp init` on #{Time.now.utc.iso8601}.
          >
          > Detected languages: #{languages}
          > Framework hints: #{frameworks_text}
          > Primary test frameworks: #{test_frameworks_text}
          > Key directories: #{key_dirs.empty? ? "Standard structure" : key_dirs}

          #{adoption_note}

          ## 1. Core Engineering Rules
          - Prioritise readability and maintainability; extract objects or modules once business logic exceeds a few branches.
          - Co-locate domain objects with their tests under the matching directory (e.g., `lib/` ↔ `spec/`).
          - Remove dead code and feature flags that are no longer exercised; keep git history as the source of truth.
          - Use small, composable services rather than bloated classes.

          ## 2. Naming & Structure
          - Follow idiomatic naming for the detected languages (#{languages}); align files under #{key_dirs.empty? ? "the project root" : key_dirs}.
          - Ensure top-level namespaces mirror the directory structure (e.g., `Aidp::Init` lives in `lib/aidp/init/`).
          - Keep public APIs explicit with keyword arguments and descriptive method names.

          ## 3. Parameters & Data
          - Limit positional arguments to three; prefer keyword arguments or value objects beyond that.
          - Reuse shared data structures to capture configuration (YAML/JSON) instead of scattered constants.
          - Validate incoming data at boundaries; rely on plain objects internally.

          ## 4. Error Handling
          - Raise domain-specific errors; avoid using plain `StandardError` without context.
          - Wrap external calls with rescuable adapters and surface actionable error messages.
          - Log failures with relevant identifiers only—never entire payloads.

          ## 5. Testing Contracts
          - Mirror production directory structure inside `#{preferred_test_dirs(analysis)}`.
          - Keep tests independent; mock external services only at the boundary layers.
          - Use the project's native assertions (#{test_frameworks.empty? ? "choose an appropriate framework" : test_frameworks}) and ensure every bug fix comes with a regression test.

          ## 6. Framework-Specific Guidelines
          - Adopt the idioms of detected frameworks#{frameworks.empty? ? " once adopted." : " (#{frameworks})."}
          - Keep controllers/handlers thin; delegate logic to service objects or interactors.
          - Store shared UI or component primitives in a central folder to make reuse easier.

          ## 7. Dependencies & External Services
          - Document every external integration inside `docs/` and keep credentials outside the repo.
          - Use dependency injection for clients; avoid global state or singletons.
          - When adding new gems or packages, document the rationale in `PROJECT_ANALYSIS.md`.

          ## 8. Build & Development
          - Run linters before committing: #{tooling.empty? ? "add rubocop/eslint/flake8 as appropriate." : tooling.join(", ")}.
          - Keep build scripts in `bin/` or `scripts/` and ensure they are idempotent.
          - Prefer `mise` or language-specific version managers to keep toolchains aligned.

          ## 9. Performance
          - Measure before optimising; add benchmarks for hotspots.
          - Cache expensive computations when they are pure and repeatable.
          - Review dependency load time; lazy-load optional components where possible.

          ## 10. Project-Specific Anti-Patterns
          - Avoid sprawling God objects that mix persistence, business logic, and presentation.
          - Resist ad-hoc shelling out; prefer library APIs with proper error handling.
          - Do not bypass the agreed testing workflow—even for small fixes.

          ---
          Generated from template `planning/generate_llm_style_guide.md` with repository-aware adjustments.

          **Note**: For comprehensive AIDP projects, consider creating both:
          1. `STYLE_GUIDE.md` - Detailed explanations with examples and rationale
          2. `LLM_STYLE_GUIDE.md` - Quick reference with `STYLE_GUIDE:line-range` cross-references

          See `planning/generate_llm_style_guide.md` for the two-guide approach.
        GUIDE

        File.write(File.join(@project_dir, STYLE_GUIDE_PATH), content)
      end

      def write_project_analysis(analysis)
        languages = format_language_breakdown(analysis[:languages])
        frameworks = format_framework_detection(analysis[:frameworks])
        test_frameworks = format_framework_detection(analysis[:test_frameworks])
        config_files = bullet_list(analysis[:config_files], default: "_No dedicated configuration files discovered_")
        tooling = format_tooling_detection(analysis[:tooling])

        stats = analysis[:repo_stats]
        stats_lines = [
          "- Total files scanned: #{stats[:total_files]}",
          "- Unique directories: #{stats[:total_directories]}",
          "- Documentation folder present: #{stats[:docs_present] ? "Yes" : "No"}",
          "- CI configuration present: #{stats[:has_ci_config] ? "Yes" : "No"}",
          "- Containerisation assets: #{stats[:has_containerization] ? "Yes" : "No"}"
        ]

        content = <<~ANALYSIS
          # Project Analysis

          Generated automatically by `aidp init` on #{Time.now.utc.iso8601}. This document summarises the repository structure to guide future autonomous work loops.

          ## Language & Framework Footprint
          #{languages}

          ### Framework Signals
          #{frameworks}

          ## Key Directories
          #{bullet_list(analysis[:key_directories], default: "_No conventional application directories detected_")}

          ## Configuration & Tooling Files
          #{config_files}

          ## Test & Quality Signals
          #{test_frameworks}

          ## Local Quality Toolchain
          #{tooling}

          ## Repository Stats
          #{stats_lines.join("\n")}

          ---
          Template inspiration: `analysis/analyze_repository.md`, `analysis/analyze_tests.md`.
        ANALYSIS

        File.write(File.join(@project_dir, ANALYSIS_PATH), content)
      end

      def write_quality_plan(analysis, preferences)
        tooling = analysis[:tooling]
        proactive = if truthy?(preferences[:stricter_linters])
          "- Enable stricter linting rules and fail CI on offences.\n- Enforce formatting checks (`mise exec --` for consistent environments).\n"
        else
          "- Maintain current linting thresholds while documenting exceptions.\n"
        end

        migration = if truthy?(preferences[:migrate_styles])
          "- Plan refactors to align legacy files with the new style guide.\n- Schedule incremental clean-up tasks to avoid large-batch rewrites.\n"
        else
          "- Keep legacy style deviations documented until dedicated refactors are scheduled.\n"
        end

        tooling_section = if tooling.empty?
          "_No linting/formatting tools detected. Consider adding RuboCop, ESLint, or Prettier based on the primary language._"
        else
          format_tooling_detection_table(tooling)
        end

        content = <<~PLAN
          # Code Quality Plan

          This plan captures the current tooling landscape and proposes next steps for keeping the codebase healthy. Generated by `aidp init` on #{Time.now.utc.iso8601}.

          ## Local Quality Toolchain
          #{tooling_section}

          ## Immediate Actions
          #{proactive}#{migration}- Document onboarding steps in `docs/` to ensure future contributors follow the agreed workflow.

          ## Long-Term Improvements
          - Keep the style guide in sync with real-world code changes; regenerate with `aidp init` after major rewrites.
          - Automate test and lint runs via CI (detected: #{analysis.dig(:repo_stats, :has_ci_config) ? "yes" : "no"}).
          - Track flaky tests or unstable tooling in `PROJECT_ANALYSIS.md` under a "Health Log" section.

          ---
          Based on templates: `analysis/analyze_static_code.md`, `analysis/analyze_tests.md`.
        PLAN

        File.write(File.join(@project_dir, QUALITY_PLAN_PATH), content)
      end

      def preferred_test_dirs(analysis)
        detected = Array(analysis[:key_directories]).select { |dir| dir =~ /\b(spec|test|tests)\b/ }
        detected.empty? ? "the chosen test directory" : detected.join(", ")
      end

      def format_list(values)
        Array(values).join(", ")
      end

      def bullet_list(values, prefix: "- ", default: "_None_")
        items = Array(values)
        return default if items.empty?

        items.map { |value| "#{prefix}#{value}" }.join("\n")
      end

      def format_language_breakdown(languages)
        return "_No source files detected._" if languages.nil? || languages.empty?

        total = languages.values.sum
        languages.map do |language, weight|
          percentage = total.zero? ? 0 : ((weight.to_f / total) * 100).round(2)
          "- #{language}: #{percentage}% of codebase"
        end.join("\n")
      end

      def format_tooling_table(tooling)
        rows = tooling.map do |tool, evidence|
          "| #{format_tool(tool)} | #{evidence.uniq.join(", ")} |"
        end
        header = "| Tool | Evidence |\n|------|----------|"
        ([header] + rows).join("\n")
      end

      def format_tooling_section(tooling)
        return "_No tooling detected._" if tooling.nil? || tooling.empty?

        header = "| Tool | Evidence |\n|------|----------|"
        rows = tooling.map do |tool, evidence|
          "| #{format_tool(tool)} | #{Array(evidence).uniq.join(", ")} |"
        end
        ([header] + rows).join("\n")
      end

      def format_tool(tool)
        tool.to_s.split("_").map(&:capitalize).join(" ")
      end

      def truthy?(value)
        value == true || value.to_s.strip.casecmp("yes").zero?
      rescue
        false
      end

      # Extract confident names from detection results
      def extract_confident_names(detections, threshold: 0.7, key: :name)
        return [] if detections.nil? || detections.empty?

        detections.select { |d| d[:confidence] >= threshold }.map { |d| d[key] }
      end

      # Format framework detection with confidence levels
      def format_framework_detection(detections)
        return "_None detected_" if detections.nil? || detections.empty?

        lines = detections.map do |detection|
          name = detection[:name]
          confidence = (detection[:confidence] * 100).round
          evidence = detection[:evidence].join("; ")
          "- **#{name}** (#{confidence}% confidence)\n  - Evidence: #{evidence}"
        end

        lines.join("\n")
      end

      # Format tooling detection with confidence levels
      def format_tooling_detection(tooling)
        return "_No tooling detected._" if tooling.nil? || tooling.empty?

        header = "| Tool | Confidence | Evidence |\n|------|------------|----------|"
        rows = tooling.map do |tool_data|
          tool_name = format_tool(tool_data[:tool])
          confidence = "#{(tool_data[:confidence] * 100).round}%"
          evidence = tool_data[:evidence].join(", ")
          "| #{tool_name} | #{confidence} | #{evidence} |"
        end

        ([header] + rows).join("\n")
      end

      # Format tooling detection table for quality plan
      def format_tooling_detection_table(tooling)
        return "_No tooling detected._" if tooling.nil? || tooling.empty?

        header = "| Tool | Evidence |\n|------|----------|"
        rows = tooling.select { |t| t[:confidence] >= 0.7 }.map do |tool_data|
          tool_name = format_tool(tool_data[:tool])
          evidence = tool_data[:evidence].join(", ")
          "| #{tool_name} | #{evidence} |"
        end

        if rows.empty?
          "_No high-confidence tooling detected. Consider adding linting and formatting tools._"
        else
          ([header] + rows).join("\n")
        end
      end
    end
  end
end
