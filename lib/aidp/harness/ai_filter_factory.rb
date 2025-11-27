# frozen_string_literal: true

require "json"
require_relative "filter_definition"
require_relative "provider_factory"
require_relative "thinking_depth_manager"

module Aidp
  module Harness
    # AI-powered factory for generating deterministic filter definitions
    #
    # Uses AI ONCE during configuration to analyze a tool and generate
    # regex patterns and extraction rules. The generated FilterDefinition
    # is then applied deterministically at runtime without any AI calls.
    #
    # @example Generate a filter for pytest
    #   factory = AIFilterFactory.new(config)
    #   definition = factory.generate_filter(
    #     tool_name: "pytest",
    #     tool_command: "pytest -v",
    #     sample_output: "... actual pytest output ..."
    #   )
    #   # Save definition to config, use deterministically at runtime
    #
    # @see FilterDefinition for the generated output format
    # @see GeneratedFilterStrategy for runtime application
    class AIFilterFactory
      GENERATION_PROMPT = <<~PROMPT
        Analyze the following tool output and generate regex patterns for filtering.
        The goal is to extract ONLY the important information (failures, errors, locations)
        and filter out noise, so that AI assistants receive concise, actionable output.

        Tool: {{tool_name}}
        Command: {{tool_command}}

        Sample output:
        ```
        {{sample_output}}
        ```

        Generate a filter definition with these components:

        1. summary_patterns: Regex patterns that match summary/result lines (e.g., "5 passed, 2 failed")
        2. failure_section_start: Regex pattern marking where failures section begins (if applicable)
        3. failure_section_end: Regex pattern marking where failures section ends (if applicable)
        4. error_section_start: Regex pattern for errors section start (if different from failures)
        5. error_section_end: Regex pattern for errors section end
        6. error_patterns: Regex patterns that identify error/failure indicator lines
        7. location_patterns: Regex patterns to extract file:line locations from output
        8. noise_patterns: Regex patterns for lines that should be filtered out (timestamps, progress bars, etc.)
        9. important_patterns: Regex patterns for lines that should ALWAYS be kept

        Important guidelines for patterns:
        - Use simple, portable regex syntax
        - Escape special characters properly (dots, brackets, etc.)
        - Make patterns case-insensitive where appropriate
        - For location patterns, use capture groups to extract the file:line portion
        - Leave fields as null/empty if not applicable to this tool

        Respond with ONLY valid JSON matching this structure:
        {
          "tool_name": "string",
          "summary_patterns": ["pattern1", "pattern2"],
          "failure_section_start": "pattern or null",
          "failure_section_end": "pattern or null",
          "error_section_start": "pattern or null",
          "error_section_end": "pattern or null",
          "error_patterns": ["pattern1"],
          "location_patterns": ["pattern with (capture) group"],
          "noise_patterns": ["pattern1"],
          "important_patterns": ["pattern1"]
        }
      PROMPT

      # JSON schema for validating AI response
      RESPONSE_SCHEMA = {
        type: "object",
        properties: {
          tool_name: {type: "string"},
          summary_patterns: {type: "array", items: {type: "string"}},
          failure_section_start: {type: ["string", "null"]},
          failure_section_end: {type: ["string", "null"]},
          error_section_start: {type: ["string", "null"]},
          error_section_end: {type: ["string", "null"]},
          error_patterns: {type: "array", items: {type: "string"}},
          location_patterns: {type: "array", items: {type: "string"}},
          noise_patterns: {type: "array", items: {type: "string"}},
          important_patterns: {type: "array", items: {type: "string"}}
        },
        required: ["tool_name", "summary_patterns"]
      }.freeze

      attr_reader :config, :provider_factory

      # Initialize the AI filter factory
      #
      # @param config [Configuration] AIDP configuration
      # @param provider_factory [ProviderFactory, nil] Optional factory for AI providers
      def initialize(config, provider_factory: nil)
        @config = config
        @provider_factory = provider_factory || ProviderFactory.new(config)
      end

      # Generate a filter definition for a tool
      #
      # @param tool_name [String] Human-readable tool name
      # @param tool_command [String] The command used to run the tool
      # @param sample_output [String, nil] Sample output from the tool (for better patterns)
      # @param tier [String] AI tier to use ("mini", "standard", "advanced")
      # @return [FilterDefinition] Generated filter definition
      # @raise [GenerationError] If AI fails to generate valid patterns
      def generate_filter(tool_name:, tool_command:, sample_output: nil, tier: "mini")
        Aidp.log_info("ai_filter_factory", "Generating filter definition",
          tool_name: tool_name, tool_command: tool_command, tier: tier)

        # Build prompt with context
        prompt = build_prompt(tool_name, tool_command, sample_output)

        # Get AI model for the tier
        thinking_manager = ThinkingDepthManager.new(config)
        provider_name, model_name, _model_data = thinking_manager.select_model_for_tier(
          tier,
          provider: config.respond_to?(:default_provider) ? config.default_provider : nil
        )

        Aidp.log_debug("ai_filter_factory", "Using AI model",
          provider: provider_name, model: model_name)

        # Call AI
        response = call_ai(provider_name, model_name, prompt)

        # Parse and validate response
        definition_data = parse_response(response)
        validate_patterns(definition_data)

        # Create FilterDefinition
        definition = FilterDefinition.new(
          tool_name: definition_data[:tool_name] || tool_name,
          tool_command: tool_command,
          summary_patterns: definition_data[:summary_patterns] || [],
          failure_section_start: definition_data[:failure_section_start],
          failure_section_end: definition_data[:failure_section_end],
          error_section_start: definition_data[:error_section_start],
          error_section_end: definition_data[:error_section_end],
          error_patterns: definition_data[:error_patterns] || [],
          location_patterns: definition_data[:location_patterns] || [],
          noise_patterns: definition_data[:noise_patterns] || [],
          important_patterns: definition_data[:important_patterns] || [],
          context_lines: 3
        )

        Aidp.log_info("ai_filter_factory", "Filter definition generated",
          tool_name: definition.tool_name,
          summary_pattern_count: definition.summary_patterns.size,
          location_pattern_count: definition.location_patterns.size)

        definition
      rescue => e
        Aidp.log_error("ai_filter_factory", "Failed to generate filter",
          tool_name: tool_name, error: e.message, error_class: e.class.name)
        raise GenerationError, "Failed to generate filter for #{tool_name}: #{e.message}"
      end

      # Generate filter from tool command by running it and capturing output
      #
      # @param tool_command [String] Command to run
      # @param project_dir [String] Directory to run command in
      # @param tier [String] AI tier to use
      # @return [FilterDefinition] Generated filter definition
      def generate_from_command(tool_command:, project_dir: Dir.pwd, tier: "mini")
        tool_name = extract_tool_name(tool_command)

        # Try to get sample output by running the command
        sample_output = capture_sample_output(tool_command, project_dir)

        generate_filter(
          tool_name: tool_name,
          tool_command: tool_command,
          sample_output: sample_output,
          tier: tier
        )
      end

      private

      def build_prompt(tool_name, tool_command, sample_output)
        prompt = GENERATION_PROMPT.dup
        prompt.gsub!("{{tool_name}}", tool_name)
        prompt.gsub!("{{tool_command}}", tool_command)

        if sample_output && !sample_output.empty?
          # Truncate very long output
          truncated = (sample_output.length > 5000) ? sample_output[0..5000] + "\n...[truncated]" : sample_output
          prompt.gsub!("{{sample_output}}", truncated)
        else
          prompt.gsub!("{{sample_output}}", "[No sample output provided - generate common patterns for #{tool_name}]")
        end

        prompt
      end

      def call_ai(provider_name, model_name, prompt)
        provider_options = {
          model: model_name,
          output: nil,
          prompt: nil
        }

        provider = @provider_factory.create_provider(provider_name, provider_options)
        provider.send_message(prompt: prompt, session: nil)
      end

      def parse_response(response)
        response_text = response.is_a?(String) ? response : response.to_s

        # Extract JSON from response
        json_match = response_text.match(/\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/m) ||
          response_text.match(/\{.*\}/m)

        raise GenerationError, "No JSON found in AI response" unless json_match

        JSON.parse(json_match[0], symbolize_names: true)
      rescue JSON::ParserError => e
        raise GenerationError, "Invalid JSON in AI response: #{e.message}"
      end

      def validate_patterns(data)
        # Validate that required patterns are present
        unless data[:summary_patterns]&.any?
          raise GenerationError, "No summary patterns generated"
        end

        # Test that patterns compile
        test_patterns(data[:summary_patterns], "summary")
        test_patterns(data[:error_patterns], "error") if data[:error_patterns]
        test_patterns(data[:location_patterns], "location") if data[:location_patterns]
        test_patterns(data[:noise_patterns], "noise") if data[:noise_patterns]

        test_pattern(data[:failure_section_start], "failure_section_start") if data[:failure_section_start]
        test_pattern(data[:failure_section_end], "failure_section_end") if data[:failure_section_end]
      end

      def test_patterns(patterns, name)
        Array(patterns).each_with_index do |pattern, i|
          test_pattern(pattern, "#{name}[#{i}]")
        end
      end

      def test_pattern(pattern, name)
        return if pattern.nil? || pattern.empty?
        Regexp.new(pattern)
      rescue RegexpError => e
        raise GenerationError, "Invalid regex for #{name}: #{pattern} - #{e.message}"
      end

      def extract_tool_name(command)
        # Extract tool name from command (first word after common prefixes)
        cleaned = command
          .sub(/^(bundle exec|npm run|yarn|npx|python -m)\s+/, "")
          .split(/\s+/)
          .first

        cleaned || "unknown"
      end

      def capture_sample_output(command, project_dir)
        # Run command and capture output (with timeout)
        require "open3"

        stdout, stderr, _ = Open3.capture3(command, chdir: project_dir)

        # Combine stdout and stderr for analysis
        output = stdout + stderr
        output.empty? ? nil : output
      rescue => e
        Aidp.log_debug("ai_filter_factory", "Failed to capture sample output",
          command: command, error: e.message)
        nil
      end
    end

    # Error raised when filter generation fails
    class GenerationError < StandardError; end
  end
end
