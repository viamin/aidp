# frozen_string_literal: true

require "tty-prompt"

module Aidp
  module Skills
    module Wizard
      # Interactive prompter for the skill wizard
      #
      # Uses TTY::Prompt to gather user input through guided questions.
      #
      # @example Basic usage
      #   prompter = Prompter.new
      #   responses = prompter.gather_responses(template_library)
      class Prompter
        attr_reader :prompt

        def initialize
          @prompt = TTY::Prompt.new
        end

        # Gather all responses for creating a skill
        #
        # @param template_library [TemplateLibrary] Library for template selection
        # @param options [Hash] Options for the wizard
        # @option options [String] :id Pre-filled skill ID
        # @option options [String] :name Pre-filled skill name
        # @option options [Boolean] :minimal Skip optional sections
        # @option options [String] :from_template Template ID to inherit from
        # @option options [String] :clone Skill ID to clone
        # @return [Hash] Complete set of responses
        def gather_responses(template_library, options: {})
          responses = {}

          # Step 1: Template selection
          if options[:from_template]
            responses[:base_skill] = template_library.find(options[:from_template])
            unless responses[:base_skill]
              raise Aidp::Errors::ValidationError, "Template not found: #{options[:from_template]}"
            end
          elsif options[:clone]
            responses[:base_skill] = template_library.find(options[:clone])
            unless responses[:base_skill]
              raise Aidp::Errors::ValidationError, "Skill not found: #{options[:clone]}"
            end
          elsif !options[:minimal]
            responses[:base_skill] = prompt_template_selection(template_library)
          end

          # Step 2: Identity & Metadata
          responses.merge!(prompt_identity(options))

          # Step 3: Expertise & Keywords
          responses.merge!(prompt_expertise) unless options[:minimal]

          # Step 4: When to use
          responses.merge!(prompt_when_to_use) unless options[:minimal]

          # Step 5: Compatible providers
          responses[:compatible_providers] = prompt_providers unless options[:minimal]

          # Step 6: Content
          responses[:content] = prompt_content(responses[:name], responses[:base_skill])

          responses
        end

        private

        # Prompt for template selection
        #
        # @param template_library [TemplateLibrary] Available templates
        # @return [Skill, nil] Selected base skill or nil
        def prompt_template_selection(template_library)
          prompt.say("\n" + "=" * 60)
          prompt.say("Create New Skill")
          prompt.say("=" * 60 + "\n")

          choice = prompt.select("How would you like to create your skill?") do |menu|
            menu.choice "Start from scratch", :from_scratch
            menu.choice "Inherit from a template", :inherit
            menu.choice "Clone an existing skill", :clone
          end

          case choice
          when :from_scratch
            nil
          when :inherit, :clone
            select_base_skill(template_library)
          end
        end

        # Select a base skill from templates
        #
        # @param template_library [TemplateLibrary] Available templates
        # @return [Skill, nil] Selected skill
        def select_base_skill(template_library)
          skills = template_library.skill_list

          if skills.empty?
            prompt.warn("No templates available")
            return nil
          end

          choices = skills.map do |skill_info|
            source_label = (skill_info[:source] == :template) ? "(template)" : "(project)"
            {
              name: "#{skill_info[:name]} #{source_label} - #{skill_info[:description]}",
              value: skill_info[:id]
            }
          end

          selected_id = prompt.select("Select a base skill:", choices, per_page: 10)
          template_library.find(selected_id)
        end

        # Prompt for identity and metadata
        #
        # @param options [Hash] Pre-filled values
        # @return [Hash] Identity responses
        def prompt_identity(options)
          responses = {}

          # Name
          default_name = options[:name]
          responses[:name] = prompt.ask("Skill Name:", default: default_name) do |q|
            q.required true
            q.modify :strip
          end

          # ID (auto-suggest from name)
          suggested_id = options[:id] || slugify(responses[:name])
          responses[:id] = prompt.ask("Skill ID:", default: suggested_id) do |q|
            q.required true
            q.modify :strip, :down
            q.validate(/\A[a-z0-9_]+\z/, "ID must be lowercase alphanumeric with underscores only")
          end

          # Description
          responses[:description] = prompt.ask("Description (one-line summary):") do |q|
            q.required true
            q.modify :strip
          end

          # Version
          responses[:version] = prompt.ask("Version:", default: "1.0.0") do |q|
            q.validate(/\A\d+\.\d+\.\d+\z/, "Must be semantic version (X.Y.Z)")
          end

          responses
        end

        # Prompt for expertise and keywords
        #
        # @return [Hash] Expertise responses
        def prompt_expertise
          responses = {}

          # Expertise areas
          prompt.say("\nExpertise Areas:")
          prompt.say("(Enter expertise areas, one per line. Leave blank and press Enter when done)")

          expertise = []
          loop do
            area = prompt.ask("  Area #{expertise.size + 1}:", required: false) do |q|
              q.modify :strip
            end
            break if area.nil? || area.empty?
            expertise << area
          end
          responses[:expertise] = expertise

          # Keywords
          keywords_input = prompt.ask("\nKeywords (comma-separated):", required: false) do |q|
            q.modify :strip
          end
          responses[:keywords] = keywords_input ? keywords_input.split(",").map(&:strip).reject(&:empty?) : []

          responses
        end

        # Prompt for when to use guidance
        #
        # @return [Hash] When to use responses
        def prompt_when_to_use
          responses = {}

          # When to use
          prompt.say("\nWhen to Use This Skill:")
          prompt.say("(Enter use cases, one per line. Leave blank and press Enter when done)")

          when_to_use = []
          loop do
            use_case = prompt.ask("  Use case #{when_to_use.size + 1}:", required: false) do |q|
              q.modify :strip
            end
            break if use_case.nil? || use_case.empty?
            when_to_use << use_case
          end
          responses[:when_to_use] = when_to_use

          # When NOT to use
          prompt.say("\nWhen NOT to Use This Skill:")
          prompt.say("(Leave blank and press Enter when done)")

          when_not_to_use = []
          loop do
            use_case = prompt.ask("  Avoid when #{when_not_to_use.size + 1}:", required: false) do |q|
              q.modify :strip
            end
            break if use_case.nil? || use_case.empty?
            when_not_to_use << use_case
          end
          responses[:when_not_to_use] = when_not_to_use

          responses
        end

        # Prompt for compatible providers
        #
        # @return [Array<String>] Selected providers
        def prompt_providers
          choices = [
            {name: "All providers (default)", value: []},
            {name: "Anthropic only", value: ["anthropic"]},
            {name: "OpenAI only", value: ["openai"]},
            {name: "Codex only", value: ["codex"]},
            {name: "Cursor only", value: ["cursor"]},
            {name: "Custom selection", value: :custom}
          ]

          selection = prompt.select("\nCompatible AI Providers:", choices)

          if selection == :custom
            prompt.multi_select("Select providers:") do |menu|
              menu.choice "Anthropic", "anthropic"
              menu.choice "OpenAI", "openai"
              menu.choice "Codex", "codex"
              menu.choice "Cursor", "cursor"
            end
          else
            selection
          end
        end

        # Prompt for skill content
        #
        # @param skill_name [String] Name of the skill
        # @param base_skill [Skill, nil] Base skill if inheriting
        # @return [String] Markdown content
        def prompt_content(skill_name, base_skill)
          if base_skill
            prompt.say("\nContent will be inherited from: #{base_skill.name}")
            if prompt.yes?("Would you like to customize the content?")
              prompt_custom_content(skill_name)
            else
              base_skill.content
            end
          else
            prompt_custom_content(skill_name)
          end
        end

        # Prompt for custom content
        #
        # @param skill_name [String] Name of the skill
        # @return [String] Markdown content
        def prompt_custom_content(skill_name)
          prompt.say("\nContent:")
          prompt.say("Enter the skill content (markdown). Type 'DONE' on a line by itself when finished.")
          prompt.say("(Or press Ctrl+D)")

          lines = []
          loop do
            line = prompt.ask("", required: false, echo: true)
            break if line.nil? || line.strip == "DONE"
            lines << line
          end

          if lines.empty?
            # Provide a minimal template
            generate_default_content(skill_name)
          else
            lines.join("\n")
          end
        end

        # Generate default content template
        #
        # @param skill_name [String] Name of the skill
        # @return [String] Default markdown content
        def generate_default_content(skill_name)
          <<~MARKDOWN
            # #{skill_name}

            You are a **#{skill_name}**, an expert in [describe expertise area].

            ## Your Core Capabilities

            - [Capability 1]
            - [Capability 2]
            - [Capability 3]

            ## Your Approach

            [Describe your philosophy and approach to tasks]
          MARKDOWN
        end

        # Convert a name to a slug (for ID suggestion)
        #
        # @param name [String] Human-readable name
        # @return [String] Slugified ID
        def slugify(name)
          name.to_s
            .downcase
            .gsub(/[^a-z0-9\s_-]/, "")
            .gsub(/\s+/, "_")
            .gsub(/-+/, "_").squeeze("_")
            .gsub(/\A_|_\z/, "")
        end
      end
    end
  end
end
