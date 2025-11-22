# frozen_string_literal: true

require_relative "../errors"
require_relative "tool_metadata"
require_relative "cache"

module Aidp
  module Metadata
    # Query interface for tool-choosing agent
    #
    # Provides filtering, ranking, and dependency resolution for tools
    # based on metadata criteria.
    #
    # @example Querying for tools
    #   query = Query.new(cache: cache)
    #   tools = query.find_by_tags(["ruby", "testing"])
    #   ranked = query.rank_by_priority(tools)
    class Query
      # Initialize query interface
      #
      # @param cache [Cache] Metadata cache instance
      def initialize(cache:)
        @cache = cache
        @directory = nil
      end

      # Load directory (lazy)
      #
      # @return [Hash] Tool directory
      def directory
        @directory ||= @cache.load
      end

      # Reload directory
      def reload
        @directory = @cache.reload
      end

      # Find tool by ID
      #
      # @param id [String] Tool ID
      # @return [Hash, nil] Tool metadata or nil
      def find_by_id(id)
        tools = directory["tools"]
        tools.find { |tool| tool["id"] == id }
      end

      # Find tools by type
      #
      # @param type [String] Tool type ("skill", "persona", "template")
      # @return [Array<Hash>] Matching tools
      def find_by_type(type)
        indexes = directory["indexes"]["by_type"]
        tool_ids = indexes[type] || []
        tools_by_ids(tool_ids)
      end

      # Find tools by applies_to tags
      #
      # @param tags [Array<String>] Tags to filter by
      # @param match_all [Boolean] Whether to match all tags (AND) or any tag (OR)
      # @return [Array<Hash>] Matching tools
      def find_by_tags(tags, match_all: false)
        Aidp.log_debug("metadata", "Finding by tags", tags: tags, match_all: match_all)

        tags = Array(tags).map(&:downcase)
        indexes = directory["indexes"]["by_tag"]

        if match_all
          # Find tools that have ALL specified tags
          tool_ids_sets = tags.map { |tag| indexes[tag] || [] }
          tool_ids = tool_ids_sets.reduce(&:&) || []
        else
          # Find tools that have ANY specified tag
          tool_ids = tags.flat_map { |tag| indexes[tag] || [] }.uniq
        end

        tools = tools_by_ids(tool_ids)

        Aidp.log_debug("metadata", "Found tools by tags", count: tools.size)

        tools
      end

      # Find tools by work unit type
      #
      # @param work_unit_type [String] Work unit type (e.g., "implementation", "analysis")
      # @return [Array<Hash>] Matching tools
      def find_by_work_unit_type(work_unit_type)
        Aidp.log_debug("metadata", "Finding by work unit type", type: work_unit_type)

        indexes = directory["indexes"]["by_work_unit_type"]
        tool_ids = indexes[work_unit_type.downcase] || []
        tools = tools_by_ids(tool_ids)

        Aidp.log_debug("metadata", "Found tools by work unit type", count: tools.size)

        tools
      end

      # Filter tools by multiple criteria
      #
      # @param type [String, nil] Tool type filter
      # @param tags [Array<String>, nil] Tag filter
      # @param work_unit_type [String, nil] Work unit type filter
      # @param experimental [Boolean, nil] Experimental filter (true/false/nil for all)
      # @return [Array<Hash>] Filtered tools
      def filter(type: nil, tags: nil, work_unit_type: nil, experimental: nil)
        Aidp.log_debug(
          "metadata",
          "Filtering tools",
          type: type,
          tags: tags,
          work_unit_type: work_unit_type,
          experimental: experimental
        )

        tools = directory["tools"]

        # Filter by type
        tools = tools.select { |t| t["type"] == type } if type

        # Filter by tags
        if tags && !tags.empty?
          tags = Array(tags).map(&:downcase)
          tools = tools.select do |t|
            tool_tags = (t["applies_to"] || []).map(&:downcase)
            (tool_tags & tags).any?
          end
        end

        # Filter by work unit type
        if work_unit_type
          wut_lower = work_unit_type.downcase
          tools = tools.select do |t|
            (t["work_unit_types"] || []).map(&:downcase).include?(wut_lower)
          end
        end

        # Filter by experimental flag
        tools = tools.select { |t| t["experimental"] == experimental } unless experimental.nil?

        Aidp.log_debug("metadata", "Filtered tools", count: tools.size)

        tools
      end

      # Rank tools by priority (highest first)
      #
      # @param tools [Array<Hash>] Tools to rank
      # @return [Array<Hash>] Ranked tools
      def rank_by_priority(tools)
        tools.sort_by { |t| -(t["priority"] || ToolMetadata::DEFAULT_PRIORITY) }
      end

      # Resolve dependencies for a tool
      #
      # Returns all dependencies recursively in dependency order (topological sort)
      #
      # @param tool_id [String] Tool ID
      # @return [Array<String>] Ordered list of dependency IDs
      # @raise [Aidp::Errors::ValidationError] if circular dependency detected
      def resolve_dependencies(tool_id)
        Aidp.log_debug("metadata", "Resolving dependencies", tool_id: tool_id)

        graph = directory["dependency_graph"]
        resolved = []
        seen = Set.new

        resolve_recursive(tool_id, graph, resolved, seen)

        Aidp.log_debug("metadata", "Dependencies resolved", tool_id: tool_id, dependencies: resolved)

        resolved
      end

      # Find dependents of a tool
      #
      # Returns all tools that depend on this tool (directly or indirectly)
      #
      # @param tool_id [String] Tool ID
      # @return [Array<String>] List of dependent tool IDs
      def find_dependents(tool_id)
        graph = directory["dependency_graph"]
        return [] unless graph[tool_id]

        graph[tool_id]["dependents"] || []
      end

      # Get statistics about the tool directory
      #
      # @return [Hash] Statistics
      def statistics
        directory["statistics"]
      end

      private

      # Get tools by IDs
      #
      # @param tool_ids [Array<String>] Tool IDs
      # @return [Array<Hash>] Tools
      def tools_by_ids(tool_ids)
        all_tools = directory["tools"]
        tool_ids.map { |id| all_tools.find { |t| t["id"] == id } }.compact
      end

      # Resolve dependencies recursively (topological sort)
      #
      # @param tool_id [String] Tool ID
      # @param graph [Hash] Dependency graph
      # @param resolved [Array<String>] Resolved dependencies (output)
      # @param seen [Set<String>] Seen tools (for cycle detection)
      # @raise [Aidp::Errors::ValidationError] if circular dependency detected
      def resolve_recursive(tool_id, graph, resolved, seen)
        return if resolved.include?(tool_id)

        if seen.include?(tool_id)
          raise Aidp::Errors::ValidationError, "Circular dependency detected: #{tool_id}"
        end

        seen.add(tool_id)

        node = graph[tool_id]
        if node
          dependencies = node["dependencies"] || []
          dependencies.each do |dep_id|
            resolve_recursive(dep_id, graph, resolved, seen)
          end
        end

        resolved << tool_id unless resolved.include?(tool_id)
        seen.delete(tool_id)
      end
    end
  end
end
