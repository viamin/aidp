# frozen_string_literal: true

require "pastel"
require_relative "builder"

module Aidp
  module Skills
    module Wizard
      # Generates and displays diffs between skills
      #
      # Shows differences between an original skill and a modified version,
      # or between a project skill and its template.
      #
      # @example Showing a diff
      #   differ = Differ.new
      #   diff = differ.diff(original_skill, modified_skill)
      #   differ.display(diff)
      class Differ
        attr_reader :pastel

        def initialize
          @pastel = Pastel.new
        end

        # Generate a diff between two skills
        #
        # @param original [Skill, String] Original skill or content
        # @param modified [Skill, String] Modified skill or content
        # @return [Hash] Diff information
        def diff(original, modified)
          original_content = skill_to_content(original)
          modified_content = skill_to_content(modified)

          {
            original: original_content,
            modified: modified_content,
            lines: generate_line_diff(original_content, modified_content),
            has_changes: original_content != modified_content
          }
        end

        # Display a diff to the terminal
        #
        # @param diff [Hash] Diff information from #diff
        # @param output [IO] Output stream (default: $stdout)
        def display(diff, output: $stdout)
          unless diff[:has_changes]
            output.puts pastel.dim("No differences found")
            return
          end

          output.puts pastel.bold("\n" + "=" * 60)
          output.puts pastel.bold("Skill Diff")
          output.puts pastel.bold("=" * 60)

          diff[:lines].each do |line_info|
            case line_info[:type]
            when :context
              output.puts pastel.dim("  #{line_info[:line]}")
            when :add
              output.puts pastel.green("+ #{line_info[:line]}")
            when :remove
              output.puts pastel.red("- #{line_info[:line]}")
            end
          end

          output.puts pastel.bold("=" * 60 + "\n")
        end

        # Generate a unified diff string
        #
        # @param original [Skill, String] Original skill or content
        # @param modified [Skill, String] Modified skill or content
        # @return [String] Unified diff format
        def unified_diff(original, modified)
          original_content = skill_to_content(original)
          modified_content = skill_to_content(modified)

          original_lines = original_content.lines
          modified_lines = modified_content.lines

          diff_lines = []
          diff_lines << "--- original"
          diff_lines << "+++ modified"

          # Simple line-by-line diff (not optimal but functional)
          max_lines = [original_lines.size, modified_lines.size].max

          (0...max_lines).each do |i|
            orig_line = original_lines[i]
            mod_line = modified_lines[i]

            if orig_line && !mod_line
              diff_lines << "-#{orig_line}"
            elsif !orig_line && mod_line
              diff_lines << "+#{mod_line}"
            elsif orig_line != mod_line
              diff_lines << "-#{orig_line}"
              diff_lines << "+#{mod_line}"
            else
              diff_lines << " #{orig_line}"
            end
          end

          diff_lines.join
        end

        # Compare a project skill with its template
        #
        # @param project_skill [Skill] Project skill
        # @param template_skill [Skill] Template skill
        # @return [Hash] Comparison information
        def compare_with_template(project_skill, template_skill)
          {
            skill_id: project_skill.id,
            overrides: detect_overrides(project_skill, template_skill),
            additions: detect_additions(project_skill, template_skill),
            diff: diff(template_skill, project_skill)
          }
        end

        private

        # Convert skill or string to content
        #
        # @param skill_or_content [Skill, String] Skill object or content string
        # @return [String] Content string
        def skill_to_content(skill_or_content)
          if skill_or_content.is_a?(String)
            skill_or_content
          elsif skill_or_content.respond_to?(:content)
            # Build full SKILL.md content
            builder = Builder.new
            builder.to_skill_md(skill_or_content)
          else
            skill_or_content.to_s
          end
        end

        # Generate line-by-line diff
        #
        # @param original [String] Original content
        # @param modified [String] Modified content
        # @return [Array<Hash>] Array of line diff information
        def generate_line_diff(original, modified)
          original_lines = original.lines.map(&:chomp)
          modified_lines = modified.lines.map(&:chomp)

          lines = []
          i = 0
          j = 0

          while i < original_lines.size || j < modified_lines.size
            if i >= original_lines.size
              # Only modified lines remain
              lines << {type: :add, line: modified_lines[j]}
              j += 1
            elsif j >= modified_lines.size
              # Only original lines remain
              lines << {type: :remove, line: original_lines[i]}
              i += 1
            elsif original_lines[i] == modified_lines[j]
              # Lines match
              lines << {type: :context, line: original_lines[i]}
              i += 1
              j += 1
            else
              # Lines differ - show removal then addition
              lines << {type: :remove, line: original_lines[i]}
              lines << {type: :add, line: modified_lines[j]}
              i += 1
              j += 1
            end
          end

          lines
        end

        # Detect field overrides between project and template
        #
        # @param project_skill [Skill] Project skill
        # @param template_skill [Skill] Template skill
        # @return [Hash] Hash of overridden fields
        def detect_overrides(project_skill, template_skill)
          overrides = {}

          # Check metadata fields
          if project_skill.name != template_skill.name
            overrides[:name] = {template: template_skill.name, project: project_skill.name}
          end

          if project_skill.description != template_skill.description
            overrides[:description] = {template: template_skill.description, project: project_skill.description}
          end

          if project_skill.version != template_skill.version
            overrides[:version] = {template: template_skill.version, project: project_skill.version}
          end

          if project_skill.content != template_skill.content
            overrides[:content] = {template: "...", project: "..."}
          end

          overrides
        end

        # Detect additions in project skill compared to template
        #
        # @param project_skill [Skill] Project skill
        # @param template_skill [Skill] Template skill
        # @return [Hash] Hash of added items
        def detect_additions(project_skill, template_skill)
          additions = {}

          # Check for added expertise
          new_expertise = project_skill.expertise - template_skill.expertise
          additions[:expertise] = new_expertise if new_expertise.any?

          # Check for added keywords
          new_keywords = project_skill.keywords - template_skill.keywords
          additions[:keywords] = new_keywords if new_keywords.any?

          # Check for added when_to_use
          new_when_to_use = project_skill.when_to_use - template_skill.when_to_use
          additions[:when_to_use] = new_when_to_use if new_when_to_use.any?

          additions
        end
      end
    end
  end
end
