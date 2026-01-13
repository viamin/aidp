# frozen_string_literal: true

require "yaml"
require "fileutils"
require "digest"

module Aidp
  module Prompts
    # Manages dynamic prompt templates with support for:
    # - Template loading from YAML files
    # - Variable substitution with {{placeholder}} syntax
    # - Template versioning and caching
    # - User/project-level template customization
    # - Per issue #402: Database-backed versioned templates with feedback-based selection
    #
    # Template search order:
    # 0. Database versioned templates (for versionable categories like work_loop)
    # 1. Project-level: .aidp/prompts/<category>/<name>.yml
    # 2. User-level: ~/.aidp/prompts/<category>/<name>.yml
    # 3. Built-in: lib/aidp/prompts/defaults/<category>/<name>.yml
    #
    # @example Load and render a template
    #   manager = PromptTemplateManager.new(project_dir: Dir.pwd)
    #   prompt = manager.render("decision_engine/condition_detection",
    #     response: error_message)
    #
    # @example Check if a template exists
    #   manager.template_exists?("decision_engine/completion_detection")
    #
    class PromptTemplateManager
      # Template file extension
      TEMPLATE_EXT = ".yml"

      # Cache TTL for template metadata (5 minutes)
      CACHE_TTL = 300

      # Categories that support database versioning
      VERSIONED_CATEGORIES = %w[work_loop].freeze

      attr_reader :project_dir, :cache

      def initialize(project_dir: Dir.pwd, version_manager: nil)
        @project_dir = project_dir
        @cache = {}
        @cache_timestamps = {}
        @version_manager_instance = version_manager
      end

      # Lazily initialize version manager
      def version_manager
        @version_manager_instance ||= begin
          require_relative "template_version_manager"
          TemplateVersionManager.new(project_dir: @project_dir)
        end
      end

      # Check if a template category supports versioning
      #
      # @param template_id [String] Template identifier
      # @return [Boolean]
      def versionable?(template_id)
        category = template_id.split("/").first
        VERSIONED_CATEGORIES.include?(category)
      end

      # Render a template with variable substitution
      # Per issue #402: Checks database versions first for versionable templates
      #
      # @param template_id [String] Template identifier (e.g., "decision_engine/condition_detection")
      # @param variables [Hash] Variables to substitute in the template
      # @param use_versioned [Boolean] Whether to check versioned templates (default: true)
      # @return [String] Rendered prompt text
      # @raise [TemplateNotFoundError] If template is not found
      def render(template_id, use_versioned: true, **variables)
        Aidp.log_debug("prompt_template_manager", "rendering_template",
          template_id: template_id,
          variables: variables.keys,
          use_versioned: use_versioned)

        # Try versioned template first for versionable categories
        if use_versioned && versionable?(template_id)
          versioned_result = render_versioned(template_id, **variables)
          return versioned_result if versioned_result
        end

        template_data = load_template(template_id)
        raise TemplateNotFoundError, "Template not found: #{template_id}" if template_data.nil?

        prompt_text = template_data["prompt"] || template_data[:prompt]
        raise TemplateNotFoundError, "Template has no prompt: #{template_id}" if prompt_text.nil?

        substitute_variables(prompt_text, variables)
      end

      # Render using a versioned template from the database
      #
      # @param template_id [String] Template identifier
      # @param variables [Hash] Variables to substitute
      # @return [String, nil] Rendered prompt or nil if no version exists
      def render_versioned(template_id, **variables)
        return nil unless versionable?(template_id)

        active = version_manager.active_version(template_id: template_id)
        return nil unless active

        Aidp.log_debug("prompt_template_manager", "rendering_versioned_template",
          template_id: template_id,
          version_id: active[:id],
          version_number: active[:version_number])

        # Parse the stored YAML content
        template_data = YAML.safe_load(active[:content], permitted_classes: [Symbol], aliases: true)
        prompt_text = template_data["prompt"] || template_data[:prompt]
        return nil unless prompt_text

        substitute_variables(prompt_text, variables)
      rescue => e
        Aidp.log_warn("prompt_template_manager", "versioned_render_failed",
          template_id: template_id,
          error: e.message)
        nil
      end

      # Load template metadata without rendering
      # Per issue #402: Checks database versions first for versionable templates
      #
      # @param template_id [String] Template identifier
      # @param use_versioned [Boolean] Whether to check versioned templates (default: true)
      # @return [Hash, nil] Template data or nil if not found
      def load_template(template_id, use_versioned: true)
        cache_key = "template:#{template_id}"

        # Check cache
        if cached_valid?(cache_key)
          Aidp.log_debug("prompt_template_manager", "cache_hit",
            template_id: template_id)
          return @cache[cache_key]
        end

        # Try versioned template first for versionable categories
        if use_versioned && versionable?(template_id)
          versioned = load_versioned_template(template_id)
          if versioned
            set_cache(cache_key, versioned)
            return versioned
          end
        end

        # Search for template in order of precedence (file-based)
        template_path = find_template_path(template_id)
        return nil unless template_path

        Aidp.log_debug("prompt_template_manager", "loading_template",
          template_id: template_id,
          path: template_path)

        template_data = load_yaml_template(template_path)
        set_cache(cache_key, template_data)
        template_data
      end

      # Load template data from versioned storage
      #
      # @param template_id [String] Template identifier
      # @return [Hash, nil] Template data or nil if no version exists
      def load_versioned_template(template_id)
        return nil unless versionable?(template_id)

        active = version_manager.active_version(template_id: template_id)
        return nil unless active

        Aidp.log_debug("prompt_template_manager", "loading_versioned_template",
          template_id: template_id,
          version_id: active[:id])

        YAML.safe_load(active[:content], permitted_classes: [Symbol], aliases: true)
      rescue => e
        Aidp.log_warn("prompt_template_manager", "versioned_load_failed",
          template_id: template_id,
          error: e.message)
        nil
      end

      # Check if a template exists
      #
      # @param template_id [String] Template identifier
      # @return [Boolean]
      def template_exists?(template_id)
        !find_template_path(template_id).nil?
      end

      # List all available templates
      #
      # @return [Array<Hash>] List of template metadata
      def list_templates
        templates = []

        search_paths.each do |base_path|
          next unless Dir.exist?(base_path)

          Dir.glob(File.join(base_path, "**", "*#{TEMPLATE_EXT}")).each do |path|
            relative_path = path.sub("#{base_path}/", "")
            template_id = relative_path.sub(TEMPLATE_EXT, "")

            # Only add if not already found (respects precedence)
            next if templates.any? { |t| t[:id] == template_id }

            template_data = load_yaml_template(path)
            next if template_data.nil?

            templates << {
              id: template_id,
              path: path,
              name: template_data["name"] || template_id,
              description: template_data["description"],
              version: template_data["version"],
              category: File.dirname(template_id)
            }
          end
        end

        templates.sort_by { |t| t[:id] }
      end

      # Get template info
      #
      # @param template_id [String] Template identifier
      # @return [Hash, nil] Template info including path and source
      def template_info(template_id)
        path = find_template_path(template_id)
        return nil unless path

        template_data = load_yaml_template(path)
        return nil if template_data.nil?

        source = determine_source(path)

        {
          id: template_id,
          path: path,
          source: source,
          name: template_data["name"],
          description: template_data["description"],
          version: template_data["version"],
          variables: extract_variables(template_data["prompt"]),
          schema: template_data["schema"],
          prompt_preview: truncate(template_data["prompt"], 500)
        }
      end

      # Copy a template to project-level for customization
      #
      # @param template_id [String] Template identifier
      # @return [String] Path to the new template file
      def customize_template(template_id)
        source_path = find_template_path(template_id)
        raise TemplateNotFoundError, "Template not found: #{template_id}" unless source_path

        dest_path = project_template_path(template_id)
        return dest_path if File.exist?(dest_path)

        FileUtils.mkdir_p(File.dirname(dest_path))
        FileUtils.cp(source_path, dest_path)

        Aidp.log_info("prompt_template_manager", "template_customized",
          template_id: template_id,
          path: dest_path)

        # Clear cache for this template
        invalidate_cache("template:#{template_id}")

        dest_path
      end

      # Reset a customized template to default
      #
      # @param template_id [String] Template identifier
      # @return [Boolean] True if reset, false if no customization existed
      def reset_template(template_id)
        project_path = project_template_path(template_id)

        unless File.exist?(project_path)
          Aidp.log_debug("prompt_template_manager", "no_customization_to_reset",
            template_id: template_id)
          return false
        end

        FileUtils.rm(project_path)

        Aidp.log_info("prompt_template_manager", "template_reset",
          template_id: template_id)

        invalidate_cache("template:#{template_id}")
        true
      end

      # Clear all cached templates
      def clear_cache
        @cache.clear
        @cache_timestamps.clear
        Aidp.log_debug("prompt_template_manager", "cache_cleared")
      end

      # Get search paths in order of precedence
      def search_paths
        [
          project_prompts_dir,
          user_prompts_dir,
          builtin_prompts_dir
        ]
      end

      # Determine the source of a template based on its path
      #
      # @param path [String] Full path to the template file
      # @return [Symbol] :project, :user, or :builtin
      def determine_source(path)
        if path.start_with?(project_prompts_dir)
          :project
        elsif path.start_with?(user_prompts_dir)
          :user
        else
          :builtin
        end
      end

      private

      def project_prompts_dir
        File.join(@project_dir, ".aidp", "prompts")
      end

      def user_prompts_dir
        File.join(Dir.home, ".aidp", "prompts")
      end

      def builtin_prompts_dir
        File.join(File.dirname(__FILE__), "defaults")
      end

      def project_template_path(template_id)
        File.join(project_prompts_dir, "#{template_id}#{TEMPLATE_EXT}")
      end

      def find_template_path(template_id)
        search_paths.each do |base_path|
          path = File.join(base_path, "#{template_id}#{TEMPLATE_EXT}")
          return path if File.exist?(path)
        end
        nil
      end

      def load_yaml_template(path)
        YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true)
      rescue Errno::ENOENT
        Aidp.log_debug("prompt_template_manager", "template_file_not_found",
          path: path)
        nil
      rescue Psych::SyntaxError => e
        Aidp.log_error("prompt_template_manager", "invalid_yaml_syntax",
          path: path,
          error: e.message)
        nil
      rescue Psych::DisallowedClass => e
        Aidp.log_error("prompt_template_manager", "disallowed_yaml_class",
          path: path,
          error: e.message)
        nil
      end

      def substitute_variables(text, variables)
        return text if text.nil? || variables.empty?

        result = text.dup
        variables.each do |key, value|
          result.gsub!("{{#{key}}}", value.to_s)
        end
        result
      end

      def extract_variables(prompt_text)
        return [] if prompt_text.nil?

        prompt_text.scan(/\{\{(\w+)\}\}/).flatten.uniq
      end

      def truncate(text, max_length)
        return nil if text.nil?
        return text if text.length <= max_length

        "#{text[0, max_length]}..."
      end

      def cached_valid?(key)
        return false unless @cache.key?(key)
        return false unless @cache_timestamps.key?(key)

        Time.now - @cache_timestamps[key] < CACHE_TTL
      end

      def set_cache(key, value)
        @cache[key] = value
        @cache_timestamps[key] = Time.now
      end

      def invalidate_cache(key)
        @cache.delete(key)
        @cache_timestamps.delete(key)
      end
    end

    # Error raised when a template is not found
    class TemplateNotFoundError < StandardError; end
  end
end
