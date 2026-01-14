# frozen_string_literal: true

require_relative "../database/repositories/template_version_repository"
require_relative "prompt_template_manager"

module Aidp
  module Prompts
    # Manages versioned prompt templates with feedback-based selection
    #
    # Per issue #402:
    # - Positive feedback: Count votes, prioritize for future use
    # - Negative feedback: Trigger AGD to create new variant
    # - Retain last 5 versions, ensuring at least 2 positive-feedback versions
    # - Per-project feedback tracking
    # - Focus on work-loop templates initially
    #
    # @example Record positive feedback
    #   manager = TemplateVersionManager.new(project_dir: Dir.pwd)
    #   manager.record_positive_feedback(template_id: "work_loop/decide_whats_next")
    #
    # @example Record negative feedback (triggers evolution)
    #   manager.record_negative_feedback(
    #     template_id: "work_loop/decide_whats_next",
    #     suggestions: ["Be more specific about next unit selection"]
    #   )
    #
    class TemplateVersionManager
      # Categories eligible for versioning (focus on work-loop initially)
      VERSIONED_CATEGORIES = %w[work_loop].freeze

      attr_reader :project_dir, :repository, :template_manager

      def initialize(
        project_dir: Dir.pwd,
        repository: nil,
        template_manager: nil
      )
        @project_dir = project_dir
        @repository = repository ||
          Database::Repositories::TemplateVersionRepository.new(project_dir: project_dir)
        @template_manager = template_manager ||
          PromptTemplateManager.new(project_dir: project_dir)
      end

      # Check if a template is eligible for versioning
      #
      # @param template_id [String] Template identifier
      # @return [Boolean]
      def versionable?(template_id)
        return false unless valid_template_id?(template_id)

        category = template_id.split("/").first
        VERSIONED_CATEGORIES.include?(category)
      end

      # Validate template_id format (must be "category/name")
      #
      # @param template_id [String] Template identifier
      # @return [Boolean]
      def valid_template_id?(template_id)
        return false if template_id.nil? || template_id.empty?

        parts = template_id.split("/")
        parts.length == 2 && parts.all? { |p| !p.empty? }
      end

      # Initialize versioning for a template by importing current content
      #
      # @param template_id [String] Template identifier
      # @return [Hash] Result with :success, :version_id
      def initialize_versioning(template_id:)
        return {success: false, error: "Template not versionable"} unless versionable?(template_id)
        return {success: true, already_versioned: true} if @repository.any?(template_id: template_id)

        Aidp.log_debug("template_version_manager", "initializing_versioning",
          template_id: template_id)

        # Load current template content
        template_data = @template_manager.load_template(template_id)
        return {success: false, error: "Template not found"} unless template_data

        # Store as version 1
        content = YAML.dump(template_data)
        result = @repository.create(
          template_id: template_id,
          content: content,
          metadata: {source: "initial_import"}
        )

        if result[:success]
          Aidp.log_info("template_version_manager", "versioning_initialized",
            template_id: template_id,
            version_number: result[:version_number])
        end

        result
      end

      # Record positive feedback for active template version
      #
      # @param template_id [String] Template identifier
      # @return [Hash] Result with :success
      def record_positive_feedback(template_id:)
        return {success: false, error: "Template not versionable"} unless versionable?(template_id)

        # Ensure versioning is initialized
        init_result = initialize_versioning(template_id: template_id)
        return init_result unless init_result[:success] || init_result[:already_versioned]

        active = @repository.active_version(template_id: template_id)
        return {success: false, error: "No active version"} unless active

        Aidp.log_debug("template_version_manager", "recording_positive_feedback",
          template_id: template_id,
          version_id: active[:id])

        result = @repository.record_positive_vote(id: active[:id])

        if result[:success]
          Aidp.log_info("template_version_manager", "positive_feedback_recorded",
            template_id: template_id,
            version_id: active[:id])
        end

        result
      end

      # Record negative feedback for active template version
      # Triggers AGD-based evolution when evolve_on_negative is true
      #
      # @param template_id [String] Template identifier
      # @param suggestions [Array<String>] User-provided improvement suggestions
      # @param context [Hash] Additional context for evolution
      # @param evolve_on_negative [Boolean] Whether to trigger evolution (default: true)
      # @return [Hash] Result with :success, :evolution_triggered, :new_version_id
      def record_negative_feedback(template_id:, suggestions: [], context: {}, evolve_on_negative: true)
        return {success: false, error: "Template not versionable"} unless versionable?(template_id)

        # Ensure versioning is initialized
        init_result = initialize_versioning(template_id: template_id)
        return init_result unless init_result[:success] || init_result[:already_versioned]

        active = @repository.active_version(template_id: template_id)
        return {success: false, error: "No active version"} unless active

        Aidp.log_debug("template_version_manager", "recording_negative_feedback",
          template_id: template_id,
          version_id: active[:id],
          suggestion_count: suggestions.size)

        # Record the negative vote
        result = @repository.record_negative_vote(id: active[:id])
        return result unless result[:success]

        Aidp.log_info("template_version_manager", "negative_feedback_recorded",
          template_id: template_id,
          version_id: active[:id],
          total_negative: active[:negative_votes] + 1)

        # Store suggestions and context for later evolution
        evolution_result = {
          success: true,
          evolution_triggered: false,
          version_id: active[:id]
        }

        # Per issue #402: "Negative feedback (even a single vote) should trigger AGD"
        if evolve_on_negative
          evolution_result[:evolution_pending] = true
          evolution_result[:suggestions] = suggestions
          evolution_result[:context] = context

          Aidp.log_info("template_version_manager", "evolution_pending",
            template_id: template_id,
            version_id: active[:id])
        end

        evolution_result
      end

      # Evolve a template by creating a new AGD-generated variant
      # Called by TemplateEvolver after AI generates improved content
      #
      # @param template_id [String] Template identifier
      # @param new_content [String] New template YAML content
      # @param parent_version_id [Integer] ID of the version being evolved
      # @param metadata [Hash] Evolution metadata
      # @return [Hash] Result with :success, :new_version_id
      def create_evolved_version(template_id:, new_content:, parent_version_id:, metadata: {})
        return {success: false, error: "Template not versionable"} unless versionable?(template_id)

        Aidp.log_debug("template_version_manager", "creating_evolved_version",
          template_id: template_id,
          parent_version_id: parent_version_id)

        result = @repository.create(
          template_id: template_id,
          content: new_content,
          parent_version_id: parent_version_id,
          metadata: metadata.merge(source: "agd_evolution")
        )

        if result[:success]
          # Prune old versions
          @repository.prune_old_versions(template_id: template_id)

          Aidp.log_info("template_version_manager", "evolved_version_created",
            template_id: template_id,
            new_version_number: result[:version_number],
            parent_version_id: parent_version_id)
        end

        result
      end

      # Get the best template version to use
      # Prioritizes versions with higher positive votes
      #
      # @param template_id [String] Template identifier
      # @return [Hash, nil] Best version or nil
      def best_version(template_id:)
        return nil unless versionable?(template_id)

        @repository.best_version(template_id: template_id)
      end

      # Get the currently active version
      #
      # @param template_id [String] Template identifier
      # @return [Hash, nil] Active version or nil
      def active_version(template_id:)
        return nil unless versionable?(template_id)

        @repository.active_version(template_id: template_id)
      end

      # Activate a specific version
      #
      # @param version_id [Integer] Version ID to activate
      # @return [Hash] Result with :success
      def activate_version(version_id:)
        @repository.activate(id: version_id)
      end

      # List all versions for a template
      #
      # @param template_id [String] Template identifier
      # @param limit [Integer] Maximum versions to return
      # @return [Array<Hash>] Versions
      def list_versions(template_id:, limit: 20)
        return [] unless versionable?(template_id)

        @repository.list(template_id: template_id, limit: limit)
      end

      # Get versions that need evolution (have negative feedback)
      #
      # @param template_id [String, nil] Filter by template
      # @return [Array<Hash>] Versions needing evolution
      def versions_needing_evolution(template_id: nil)
        @repository.versions_needing_evolution(template_id: template_id)
      end

      # Get version statistics for a template
      #
      # @param template_id [String] Template identifier
      # @return [Hash] Statistics
      def version_stats(template_id:)
        return {error: "Template not versionable"} unless versionable?(template_id)

        versions = @repository.list(template_id: template_id, limit: 100)

        {
          template_id: template_id,
          total_versions: versions.size,
          active_version: versions.find { |v| v[:is_active] }&.dig(:version_number),
          total_positive_votes: versions.sum { |v| v[:positive_votes] },
          total_negative_votes: versions.sum { |v| v[:negative_votes] },
          best_version: @repository.best_version(template_id: template_id)&.dig(:version_number),
          oldest_version: versions.last&.dig(:created_at),
          newest_version: versions.first&.dig(:created_at)
        }
      end

      # Get all template IDs that have versioning enabled
      #
      # @return [Array<String>] Template IDs
      def versioned_template_ids
        @repository.template_ids
      end

      # Render a versioned template, using the active version if available
      #
      # @param template_id [String] Template identifier
      # @param variables [Hash] Variables to substitute
      # @return [String, nil] Rendered prompt or nil
      def render_versioned(template_id, **variables)
        return nil unless versionable?(template_id)

        active = @repository.active_version(template_id: template_id)
        return nil unless active

        Aidp.log_debug("template_version_manager", "rendering_versioned_template",
          template_id: template_id,
          version_id: active[:id],
          version_number: active[:version_number])

        # Parse the stored YAML content
        template_data = YAML.safe_load(active[:content], permitted_classes: [Symbol], aliases: true)
        prompt_text = template_data["prompt"] || template_data[:prompt]
        return nil unless prompt_text

        # Substitute variables
        result = prompt_text.dup
        variables.each do |key, value|
          result.gsub!("{{#{key}}}", value.to_s)
        end

        result
      end
    end
  end
end
