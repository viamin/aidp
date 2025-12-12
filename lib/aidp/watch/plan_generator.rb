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

      HIERARCHICAL_PROVIDER_PROMPT = <<~PROMPT
        You are AIDP's planning specialist for large projects. Read the GitHub issue and existing comments.
        This is a LARGE project that should be broken down into independent sub-issues.

        Analyze the requirements and break them into logical sub-tasks that can be worked on independently.
        For each sub-task, identify:
        1. What should be built (clear, focused scope)
        2. What skills are required (e.g., "GraphQL API", "React Components", "Database Schema")
        3. What personas should work on it (e.g., "Backend Engineer", "Frontend Developer")
        4. What dependencies exist (which other sub-tasks must complete first)

        Respond in JSON with the following shape (no extra text, no code fences):
        {
          "plan_summary": "one paragraph summary of the overall project",
          "should_create_sub_issues": true,
          "sub_issues": [
            {
              "title": "Brief title for the sub-issue",
              "description": "Detailed description of what needs to be built",
              "tasks": ["Specific task 1", "Specific task 2"],
              "skills": ["Skill 1", "Skill 2"],
              "personas": ["Persona 1"],
              "dependencies": ["Reference to other sub-issue by title if needed"]
            }
          ],
          "clarifying_questions": ["question 1", "question 2"]
        }

        Guidelines:
        - Each sub-issue should be independently testable and deliverable
        - Sub-issues should be sized for 1-3 days of work
        - Include 3-8 sub-issues for a large project
        - Be specific about skills needed (avoid generic terms)
        - Only create sub-issues if the project truly warrants it (complexity, multiple components, etc.)
      PROMPT

      def initialize(provider_name: nil, verbose: false, hierarchical: false)
        @provider_name = provider_name
        @verbose = verbose
        @hierarchical = hierarchical
        @providers_attempted = []
      end

      def generate(issue, hierarchical: @hierarchical)
        Aidp.log_debug("plan_generator", "generate.start", provider: @provider_name, issue: issue[:number])

        # Try providers in fallback chain order
        providers_to_try = build_provider_fallback_chain
        Aidp.log_debug("plan_generator", "fallback_chain", providers: providers_to_try, count: providers_to_try.size)

        providers_to_try.each do |provider_name|
          next if @providers_attempted.include?(provider_name)

          Aidp.log_debug("plan_generator", "trying_provider", provider: provider_name, attempted: @providers_attempted)

          provider = resolve_provider(provider_name)
          unless provider
            Aidp.log_debug("plan_generator", "provider_unavailable", provider: provider_name, reason: "not resolved")
            @providers_attempted << provider_name
            next
          end

          begin
            Aidp.log_info("plan_generator", "generate_with_provider", provider: provider_name, issue: issue[:number], hierarchical: hierarchical)
            result = generate_with_provider(provider, issue, provider_name, hierarchical: hierarchical)
            if result
              Aidp.log_info("plan_generator", "generation_success", provider: provider_name, issue: issue[:number])
              return result
            end

            # Provider returned nil - try next provider
            Aidp.log_warn("plan_generator", "provider_returned_nil", provider: provider_name)
            @providers_attempted << provider_name
          rescue => e
            # Log error and try next provider in chain
            Aidp.log_warn("plan_generator", "provider_failed", provider: provider_name, error: e.message, error_class: e.class.name)
            @providers_attempted << provider_name
          end
        end

        # All providers exhausted - silently fail without heuristic fallback
        Aidp.log_warn("plan_generator", "all_providers_exhausted", attempted: @providers_attempted, result: "failed")
        display_message("⚠️  All providers unavailable or failed. Unable to generate plan.", type: :warn)
        nil
      rescue => e
        Aidp.log_error("plan_generator", "generation_failed_unexpectedly", error: e.message, backtrace: e.backtrace&.first(3))
        display_message("⚠️  Plan generation failed unexpectedly (#{e.message}).", type: :warn)
        nil
      end

      private

      def build_provider_fallback_chain
        # Start with specified provider or default
        primary_provider = @provider_name || detect_default_provider
        providers = []

        # Add primary provider first
        providers << primary_provider if primary_provider

        # Try to get fallback chain from config
        begin
          config_manager = Aidp::Harness::ConfigManager.new(Dir.pwd)
          fallback_providers = config_manager.fallback_providers || []

          # Add fallback providers that aren't already in the list
          fallback_providers.each do |fallback|
            providers << fallback unless providers.include?(fallback)
          end
        rescue => e
          Aidp.log_debug("plan_generator", "config_fallback_unavailable", error: e.message)
        end

        # If we still have no providers, add cursor as last resort
        providers << "cursor" if providers.empty?

        # Remove duplicates while preserving order
        providers.uniq
      end

      def resolve_provider(provider_name = nil)
        provider_name ||= @provider_name || detect_default_provider
        return nil unless provider_name

        Aidp.log_debug("plan_generator", "resolve_provider", provider: provider_name)

        provider = Aidp::ProviderManager.get_provider(provider_name)

        if provider&.available?
          Aidp.log_debug("plan_generator", "provider_resolved", provider: provider_name, available: true)
          return provider
        end

        Aidp.log_debug("plan_generator", "provider_not_available", provider: provider_name, available: provider&.available?)
        nil
      rescue => e
        Aidp.log_warn("plan_generator", "resolve_provider_failed", provider: provider_name, error: e.message)
        display_message("⚠️  Failed to resolve provider #{provider_name}: #{e.message}", type: :warn)
        nil
      end

      def detect_default_provider
        config_manager = Aidp::Harness::ConfigManager.new(Dir.pwd)
        config_manager.default_provider || "cursor"
      rescue
        "cursor"
      end

      def generate_with_provider(provider, issue, provider_name = "unknown", hierarchical: false)
        payload = build_prompt(issue, hierarchical: hierarchical)

        Aidp.log_debug("plan_generator", "sending_to_provider", provider: provider_name, prompt_length: payload.length, hierarchical: hierarchical)

        if @verbose
          display_message("\n--- Plan Generation Prompt ---", type: :muted)
          display_message(payload.strip, type: :muted)
          display_message("--- End Prompt ---\n", type: :muted)
        end

        response = provider.send_message(prompt: payload)

        Aidp.log_debug("plan_generator", "provider_response_received", provider: provider_name, response_length: response&.length || 0)

        if @verbose
          display_message("\n--- Provider Response ---", type: :muted)
          display_message(response.strip, type: :muted)
          display_message("--- End Response ---\n", type: :muted)
        end

        parsed = parse_structured_response(response, hierarchical: hierarchical)

        if parsed
          Aidp.log_debug("plan_generator", "response_parsed", provider: provider_name, has_summary: !parsed[:summary].to_s.empty?, tasks_count: parsed[:tasks]&.size || 0, sub_issues_count: parsed[:sub_issues]&.size || 0)
          return parsed
        end

        Aidp.log_warn("plan_generator", "parse_failed", provider: provider_name)
        display_message("⚠️  Unable to parse #{provider_name} response. Trying next provider.", type: :warn)
        nil
      end

      def build_prompt(issue, hierarchical: false)
        comments_text = issue[:comments]
          .sort_by { |comment| comment["createdAt"].to_s }
          .map do |comment|
            author = comment["author"] || "unknown"
            body = comment["body"] || ""
            "#{author}:\n#{body}"
          end
          .join("\n\n")

        prompt_template = hierarchical ? HIERARCHICAL_PROVIDER_PROMPT : PROVIDER_PROMPT

        <<~PROMPT
          #{prompt_template}

          Issue Title: #{issue[:title]}
          Issue URL: #{issue[:url]}

          Issue Body:
          #{issue[:body]}

          Existing Comments:
          #{comments_text}
        PROMPT
      end

      def parse_structured_response(response, hierarchical: false)
        text = response.to_s.strip
        candidate = extract_json_payload(text)
        return nil unless candidate

        data = JSON.parse(candidate)

        result = {
          summary: data["plan_summary"].to_s.strip,
          tasks: Array(data["plan_tasks"]).map(&:to_s),
          questions: Array(data["clarifying_questions"]).map(&:to_s)
        }

        # Add hierarchical planning data if present
        if hierarchical || data["should_create_sub_issues"]
          result[:should_create_sub_issues] = data["should_create_sub_issues"] || false
          result[:sub_issues] = Array(data["sub_issues"]).map do |sub|
            {
              title: sub["title"].to_s,
              description: sub["description"].to_s,
              tasks: Array(sub["tasks"]).map(&:to_s),
              skills: Array(sub["skills"]).map(&:to_s),
              personas: Array(sub["personas"]).map(&:to_s),
              dependencies: Array(sub["dependencies"]).map(&:to_s)
            }
          end
        end

        result
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
    end
  end
end
