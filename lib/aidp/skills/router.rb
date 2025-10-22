# frozen_string_literal: true

require "yaml"

module Aidp
  module Skills
    # Routes file paths and tasks to appropriate skills based on routing rules
    #
    # The Router reads routing configuration from aidp.yml and matches:
    # - File paths against glob patterns (path_rules)
    # - Task descriptions against keywords (task_rules)
    # - Combined path + task rules (combined_rules)
    #
    # @example Basic usage
    #   router = Router.new(project_dir: Dir.pwd)
    #   skill_id = router.route_by_path("app/controllers/users_controller.rb")
    #   # => "rails_expert"
    #
    # @example Task-based routing
    #   router = Router.new(project_dir: Dir.pwd)
    #   skill_id = router.route_by_task("Add API endpoint")
    #   # => "backend_developer"
    #
    # @example Combined routing
    #   router = Router.new(project_dir: Dir.pwd)
    #   skill_id = router.route(path: "lib/cli.rb", task: "Add command")
    #   # => "cli_expert"
    class Router
      attr_reader :config, :project_dir

      # Initialize router with project directory
      #
      # @param project_dir [String] Path to project directory
      def initialize(project_dir:)
        @project_dir = project_dir
        @config = load_config
      end

      # Route based on both path and task (highest priority)
      #
      # @param path [String, nil] File path to route
      # @param task [String, nil] Task description to route
      # @return [String, nil] Matched skill ID or nil
      def route(path: nil, task: nil)
        # Priority 1: Combined rules (path AND task)
        if path && task
          combined_match = match_combined_rules(path, task)
          return combined_match if combined_match
        end

        # Priority 2: Path rules
        path_match = route_by_path(path) if path
        return path_match if path_match

        # Priority 3: Task rules
        task_match = route_by_task(task) if task
        return task_match if task_match

        # Priority 4: Default skill
        config.dig("skills", "routing", "default")
      end

      # Route based on file path
      #
      # @param path [String] File path to match against patterns
      # @return [String, nil] Matched skill ID or nil
      def route_by_path(path)
        return nil unless path

        path_rules = config.dig("skills", "routing", "path_rules") || {}

        path_rules.each do |skill_id, patterns|
          patterns = [patterns] unless patterns.is_a?(Array)
          patterns.each do |pattern|
            return skill_id if File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
          end
        end

        nil
      end

      # Route based on task description
      #
      # @param task [String] Task description to match against keywords
      # @return [String, nil] Matched skill ID or nil
      def route_by_task(task)
        return nil unless task

        task_rules = config.dig("skills", "routing", "task_rules") || {}
        task_lower = task.downcase

        task_rules.each do |skill_id, keywords|
          keywords = [keywords] unless keywords.is_a?(Array)
          keywords.each do |keyword|
            return skill_id if task_lower.include?(keyword.downcase)
          end
        end

        nil
      end

      # Check if routing is enabled
      #
      # @return [Boolean] true if routing is configured
      def routing_enabled?
        config.dig("skills", "routing", "enabled") == true
      end

      # Get default skill
      #
      # @return [String, nil] Default skill ID or nil
      def default_skill
        config.dig("skills", "routing", "default")
      end

      # Get all routing rules
      #
      # @return [Hash] Hash containing path_rules, task_rules, and combined_rules
      def rules
        {
          path_rules: config.dig("skills", "routing", "path_rules") || {},
          task_rules: config.dig("skills", "routing", "task_rules") || {},
          combined_rules: config.dig("skills", "routing", "combined_rules") || {}
        }
      end

      private

      # Match combined rules (path AND task must both match)
      #
      # @param path [String] File path
      # @param task [String] Task description
      # @return [String, nil] Matched skill ID or nil
      def match_combined_rules(path, task)
        combined_rules = config.dig("skills", "routing", "combined_rules") || {}
        task_lower = task.downcase

        combined_rules.each do |skill_id, rule|
          path_patterns = rule["paths"] || []
          task_keywords = rule["tasks"] || []

          path_patterns = [path_patterns] unless path_patterns.is_a?(Array)
          task_keywords = [task_keywords] unless task_keywords.is_a?(Array)

          # Check if path matches any pattern
          path_match = path_patterns.any? do |pattern|
            File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
          end

          # Check if task matches any keyword
          task_match = task_keywords.any? do |keyword|
            task_lower.include?(keyword.downcase)
          end

          return skill_id if path_match && task_match
        end

        nil
      end

      # Load routing configuration from aidp.yml
      #
      # @return [Hash] Configuration hash
      def load_config
        config_path = File.join(project_dir, ".aidp", "aidp.yml")

        if File.exist?(config_path)
          YAML.safe_load_file(config_path, permitted_classes: [Date, Time, Symbol], aliases: true) || {}
        else
          {}
        end
      rescue => e
        Aidp.log_error("skills", "Failed to load routing config", error: e.message)
        {}
      end
    end
  end
end
