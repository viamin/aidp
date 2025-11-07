# frozen_string_literal: true

require "json"

require_relative "../message_display"
require_relative "../harness/config_manager"
require_relative "../provider_manager"

module Aidp
  module Watch
    # Generates implementation plans for issues during watch mode. Attempts to
    # use a configured provider for high quality output and falls back to a
    # deterministic heuristic plan when no provider can be invoked.
    class PlanGenerator
      include Aidp::MessageDisplay

      PROVIDER_PROMPT = <<~PROMPT
        You are AIDP's planning specialist. Read the GitHub issue and existing comments.
        Produce a concise implementation contract describing the plan for the aidp agent.
        Respond in JSON with the following shape (no extra text, no code fences):
        {
          "plan_summary": "one paragraph summary of what will be implemented",
          "plan_tasks": ["task 1", "task 2", "..."],
          "clarifying_questions": ["question 1", "question 2"]
        }
        Focus on concrete engineering tasks. Ensure questions are actionable.
      PROMPT

      def initialize(provider_name: nil, verbose: false)
        @provider_name = provider_name
        @verbose = verbose
      end

      def generate(issue)
        provider = resolve_provider
        if provider
          generate_with_provider(provider, issue)
        else
          display_message("⚠️  No active provider available. Falling back to heuristic plan.", type: :warn)
          heuristic_plan(issue)
        end
      rescue => e
        display_message("⚠️  Plan generation failed (#{e.message}). Using heuristic.", type: :warn)
        heuristic_plan(issue)
      end

      private

      def resolve_provider
        provider_name = @provider_name || detect_default_provider
        return nil unless provider_name

        provider = Aidp::ProviderManager.get_provider(provider_name, use_harness: false)
        return provider if provider&.available?

        nil
      rescue => e
        display_message("⚠️  Failed to resolve provider #{provider_name}: #{e.message}", type: :warn)
        nil
      end

      def detect_default_provider
        config_manager = Aidp::Harness::ConfigManager.new(Dir.pwd)
        config_manager.default_provider || "cursor"
      rescue
        "cursor"
      end

      def generate_with_provider(provider, issue)
        payload = build_prompt(issue)

        if @verbose
          display_message("\n--- Plan Generation Prompt ---", type: :muted)
          display_message(payload.strip, type: :muted)
          display_message("--- End Prompt ---\n", type: :muted)
        end

        response = provider.send_message(prompt: payload)

        if @verbose
          display_message("\n--- Provider Response ---", type: :muted)
          display_message(response.strip, type: :muted)
          display_message("--- End Response ---\n", type: :muted)
        end

        parsed = parse_structured_response(response)

        return parsed if parsed

        display_message("⚠️  Unable to parse provider response. Using heuristic plan.", type: :warn)
        heuristic_plan(issue)
      end

      def build_prompt(issue)
        comments_text = issue[:comments]
          .sort_by { |comment| comment["createdAt"].to_s }
          .map do |comment|
            author = comment["author"] || "unknown"
            body = comment["body"] || ""
            "#{author}:\n#{body}"
          end
          .join("\n\n")

        <<~PROMPT
          #{PROVIDER_PROMPT}

          Issue Title: #{issue[:title]}
          Issue URL: #{issue[:url]}

          Issue Body:
          #{issue[:body]}

          Existing Comments:
          #{comments_text}
        PROMPT
      end

      def parse_structured_response(response)
        text = response.to_s.strip
        candidate = extract_json_payload(text)
        return nil unless candidate

        data = JSON.parse(candidate)
        {
          summary: data["plan_summary"].to_s.strip,
          tasks: Array(data["plan_tasks"]).map(&:to_s),
          questions: Array(data["clarifying_questions"]).map(&:to_s)
        }
      rescue JSON::ParserError
        nil
      end

      def extract_json_payload(text)
        return text if text.start_with?("{") && text.end_with?("}")

        if text =~ /```json\s*(\{.*\})\s*```/m
          return $1
        end

        json_match = text.match(/\{.*\}/m)
        json_match ? json_match[0] : nil
      end

      def heuristic_plan(issue)
        body = issue[:body].to_s
        bullet_tasks = body.lines
          .map(&:strip)
          .select { |line| line.start_with?("-", "*") }
          .map { |line| line.sub(/\A[-*]\s*/, "") }
          .uniq
          .first(5)

        paragraphs = body.split(/\n{2,}/).map(&:strip).reject(&:empty?)
        summary = paragraphs.first(2).join(" ")
        summary = summary.empty? ? "Implement the requested changes described in the issue." : summary

        tasks = if bullet_tasks.empty?
          [
            "Review the repository context and identify impacted components.",
            "Implement the necessary code changes and add tests.",
            "Document the changes and ensure lint/test pipelines succeed."
          ]
        else
          bullet_tasks
        end

        questions = [
          "Are there constraints (framework versions, performance budgets) we must respect?",
          "Are there existing tests or acceptance criteria we should extend?",
          "Is there additional context (design docs, related issues) we should review?"
        ]

        {
          summary: summary,
          tasks: tasks,
          questions: questions
        }
      end
    end
  end
end
