# frozen_string_literal: true

require_relative "../../provider_manager"
require_relative "../../harness/config_manager"

module Aidp
  module Watch
    module Reviewers
      # Base class for all PR reviewers
      class BaseReviewer
        attr_reader :provider_name, :persona_name, :focus_areas

        def initialize(provider_name: nil)
          @provider_name = provider_name
          @persona_name = self.class::PERSONA_NAME
          @focus_areas = self.class::FOCUS_AREAS
        end

        # Review the PR and return findings
        # @param pr_data [Hash] PR metadata (number, title, body, etc.)
        # @param files [Array<Hash>] Changed files with patches
        # @param diff [String] Full diff content
        # @return [Hash] Review findings with structure:
        #   {
        #     persona: String,
        #     findings: [
        #       {
        #         severity: "high|major|minor|nit",
        #         category: String,
        #         message: String,
        #         file: String (optional),
        #         line: Integer (optional),
        #         suggestion: String (optional)
        #       }
        #     ]
        #   }
        def review(pr_data:, files:, diff:)
          raise NotImplementedError, "Subclasses must implement #review"
        end

        protected

        def provider
          @provider ||= begin
            provider_name = @provider_name || detect_default_provider
            Aidp::ProviderManager.get_provider(provider_name, use_harness: false)
          end
        end

        def detect_default_provider
          config_manager = Aidp::Harness::ConfigManager.new(Dir.pwd)
          config_manager.default_provider || "anthropic"
        rescue
          "anthropic"
        end

        def system_prompt
          <<~PROMPT
            You are #{@persona_name}, reviewing a pull request.

            Your focus areas are:
            #{@focus_areas.map { |area| "- #{area}" }.join("\n")}

            Review the code changes and provide structured feedback in the following JSON format:
            {
              "findings": [
                {
                  "severity": "high|major|minor|nit",
                  "category": "Brief category (e.g., 'Security', 'Performance', 'Logic Error')",
                  "message": "Detailed explanation of the issue",
                  "file": "path/to/file.rb",
                  "line": 42,
                  "suggestion": "Optional: Suggested fix or improvement"
                }
              ]
            }

            Severity levels:
            - high: Critical issues that must be fixed (security vulnerabilities, data loss, crashes)
            - major: Significant problems that should be addressed (incorrect logic, performance issues)
            - minor: Improvements that would be good to have (code quality, maintainability)
            - nit: Stylistic or trivial suggestions (formatting, naming)

            Focus on actionable, specific feedback. If no issues are found, return an empty findings array.
          PROMPT
        end

        def analyze_with_provider(user_prompt)
          full_prompt = "#{system_prompt}\n\n#{user_prompt}"
          response = provider.send_message(prompt: full_prompt)
          content = response.to_s.strip

          # Extract JSON from response (handle code fences)
          json_content = extract_json(content)

          # Parse JSON response
          parsed = JSON.parse(json_content)
          parsed["findings"] || []
        rescue JSON::ParserError => e
          Aidp.log_error("reviewer", "Failed to parse provider response", persona: @persona_name, error: e.message, content: content)
          []
        rescue => e
          Aidp.log_error("reviewer", "Review failed", persona: @persona_name, error: e.message)
          []
        end

        def extract_json(text)
          # Try to extract JSON from code fences or find JSON object
          # Use non-greedy matching to avoid ReDoS
          return text if text.start_with?("{") && text.end_with?("}")

          # Match code fence with non-greedy quantifier
          if text =~ /```json\s*(\{.*?\})\s*```/m
            return $1
          end

          # Find JSON object with non-greedy quantifier
          json_match = text.match(/\{.*?\}/m)
          json_match ? json_match[0] : text
        end

        def build_review_prompt(pr_data:, files:, diff:)
          <<~PROMPT
            Review this pull request from your expertise perspective:

            **PR ##{pr_data[:number]}: #{pr_data[:title]}**

            #{pr_data[:body]}

            **Changed Files (#{files.length}):**
            #{files.map { |f| "- #{f[:filename]} (+#{f[:additions]}/-#{f[:deletions]})" }.join("\n")}

            **Diff:**
            ```diff
            #{truncate_diff(diff, max_lines: 500)}
            ```

            Please review the changes and provide your findings in JSON format.
          PROMPT
        end

        def truncate_diff(diff, max_lines: 500)
          lines = diff.lines
          if lines.length > max_lines
            lines.first(max_lines).join + "\n... (diff truncated, #{lines.length - max_lines} more lines)"
          else
            diff
          end
        end
      end
    end
  end
end
