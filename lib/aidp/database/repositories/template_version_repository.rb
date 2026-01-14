# frozen_string_literal: true

require_relative "../repository"

module Aidp
  module Database
    module Repositories
      # Repository for template_versions table
      # Manages versioned prompt templates with feedback-based selection
      #
      # Per issue #402:
      # - Store template versions in SQLite
      # - Track positive/negative votes per version
      # - Retain last 5 versions, ensuring at least 2 positive-feedback versions
      # - Select best version based on positive vote count
      #
      class TemplateVersionRepository < Repository
        # Minimum versions to retain per template
        MIN_VERSIONS = 5

        # Minimum positive-feedback versions to retain
        MIN_POSITIVE_VERSIONS = 2

        def initialize(project_dir: Dir.pwd)
          super(project_dir: project_dir, table_name: "template_versions")
        end

        # Create a new template version
        #
        # @param template_id [String] Template identifier (e.g., "work_loop/decide_whats_next")
        # @param content [String] Full YAML content of the template
        # @param parent_version_id [Integer, nil] ID of parent version (for AGD-generated variants)
        # @param metadata [Hash, nil] Additional metadata
        # @return [Hash] Result with :success, :id, :version_number
        def create(template_id:, content:, parent_version_id: nil, metadata: nil)
          # Validate content is present
          if content.nil? || content.to_s.strip.empty?
            Aidp.log_error("template_version_repository", "invalid_content",
              template_id: template_id,
              error: "Content cannot be nil or empty")
            return {success: false, error: "Content cannot be nil or empty"}
          end

          Aidp.log_debug("template_version_repository", "creating_version",
            template_id: template_id,
            parent_version_id: parent_version_id)

          transaction do
            # Get next version number for this template
            next_version = next_version_number(template_id)

            # Deactivate all existing versions for this template
            execute(
              "UPDATE template_versions SET is_active = 0 WHERE project_dir = ? AND template_id = ?",
              [project_dir, template_id]
            )

            # Insert new version as active
            execute(
              insert_sql([
                :project_dir, :template_id, :version_number, :content,
                :parent_version_id, :is_active, :positive_votes, :negative_votes, :metadata
              ]),
              [
                project_dir,
                template_id,
                next_version,
                content,
                parent_version_id,
                1, # is_active
                0, # positive_votes
                0, # negative_votes
                serialize_json(metadata)
              ]
            )

            id = last_insert_row_id

            Aidp.log_info("template_version_repository", "version_created",
              template_id: template_id,
              version_number: next_version,
              id: id)

            {success: true, id: id, version_number: next_version}
          end
        rescue => e
          Aidp.log_error("template_version_repository", "create_failed",
            template_id: template_id,
            error: e.message)
          {success: false, error: e.message}
        end

        # Get the active version for a template
        #
        # @param template_id [String] Template identifier
        # @return [Hash, nil] Active version or nil
        def active_version(template_id:)
          row = query_one(
            <<~SQL,
              SELECT * FROM template_versions
              WHERE project_dir = ? AND template_id = ? AND is_active = 1
              LIMIT 1
            SQL
            [project_dir, template_id]
          )

          deserialize_version(row)
        end

        # Get a specific version by ID
        #
        # @param id [Integer] Version ID
        # @return [Hash, nil] Version or nil
        def find(id:)
          row = query_one(
            "SELECT * FROM template_versions WHERE id = ? AND project_dir = ?",
            [id, project_dir]
          )

          deserialize_version(row)
        end

        # Get all versions for a template
        #
        # @param template_id [String] Template identifier
        # @param limit [Integer] Maximum versions to return
        # @return [Array<Hash>] Versions sorted by version_number descending
        def list(template_id:, limit: 20)
          rows = query(
            <<~SQL,
              SELECT * FROM template_versions
              WHERE project_dir = ? AND template_id = ?
              ORDER BY version_number DESC
              LIMIT ?
            SQL
            [project_dir, template_id, limit]
          )

          rows.map { |row| deserialize_version(row) }.compact
        end

        # Record a positive vote for a version
        #
        # @param id [Integer] Version ID
        # @return [Hash] Result with :success
        def record_positive_vote(id:)
          Aidp.log_debug("template_version_repository", "recording_positive_vote", id: id)

          execute(
            "UPDATE template_versions SET positive_votes = positive_votes + 1 WHERE id = ? AND project_dir = ?",
            [id, project_dir]
          )

          {success: true}
        rescue => e
          Aidp.log_error("template_version_repository", "positive_vote_failed",
            id: id, error: e.message)
          {success: false, error: e.message}
        end

        # Record a negative vote for a version
        #
        # @param id [Integer] Version ID
        # @return [Hash] Result with :success
        def record_negative_vote(id:)
          Aidp.log_debug("template_version_repository", "recording_negative_vote", id: id)

          execute(
            "UPDATE template_versions SET negative_votes = negative_votes + 1 WHERE id = ? AND project_dir = ?",
            [id, project_dir]
          )

          {success: true}
        rescue => e
          Aidp.log_error("template_version_repository", "negative_vote_failed",
            id: id, error: e.message)
          {success: false, error: e.message}
        end

        # Activate a specific version
        #
        # @param id [Integer] Version ID to activate
        # @return [Hash] Result with :success
        def activate(id:)
          version = find(id: id)
          return {success: false, error: "Version not found"} unless version

          Aidp.log_debug("template_version_repository", "activating_version",
            id: id,
            template_id: version[:template_id])

          transaction do
            # Deactivate all versions for this template
            execute(
              "UPDATE template_versions SET is_active = 0 WHERE project_dir = ? AND template_id = ?",
              [project_dir, version[:template_id]]
            )

            # Activate the specified version
            execute(
              "UPDATE template_versions SET is_active = 1 WHERE id = ? AND project_dir = ?",
              [id, project_dir]
            )
          end

          Aidp.log_info("template_version_repository", "version_activated",
            id: id,
            template_id: version[:template_id])

          {success: true}
        rescue => e
          Aidp.log_error("template_version_repository", "activation_failed",
            id: id, error: e.message)
          {success: false, error: e.message}
        end

        # Get the best version for a template based on positive votes
        # Prioritizes higher positive vote counts
        #
        # @param template_id [String] Template identifier
        # @return [Hash, nil] Best version or nil
        def best_version(template_id:)
          row = query_one(
            <<~SQL,
              SELECT * FROM template_versions
              WHERE project_dir = ? AND template_id = ?
              ORDER BY positive_votes DESC, version_number DESC
              LIMIT 1
            SQL
            [project_dir, template_id]
          )

          deserialize_version(row)
        end

        # Get versions needing evolution (have negative votes)
        #
        # @param template_id [String, nil] Filter by template (nil for all)
        # @return [Array<Hash>] Versions with negative votes
        def versions_needing_evolution(template_id: nil)
          rows = if template_id
            query(
              <<~SQL,
                SELECT * FROM template_versions
                WHERE project_dir = ? AND template_id = ? AND negative_votes > 0
                ORDER BY negative_votes DESC
              SQL
              [project_dir, template_id]
            )
          else
            query(
              <<~SQL,
                SELECT * FROM template_versions
                WHERE project_dir = ? AND negative_votes > 0
                ORDER BY negative_votes DESC
              SQL
              [project_dir]
            )
          end

          rows.map { |row| deserialize_version(row) }.compact
        end

        # Prune old versions, keeping:
        # - At least MIN_VERSIONS (5) versions
        # - At least MIN_POSITIVE_VERSIONS (2) positive-feedback versions
        #
        # @param template_id [String] Template identifier
        # @return [Hash] Result with :success, :pruned_count
        def prune_old_versions(template_id:)
          Aidp.log_debug("template_version_repository", "pruning_versions",
            template_id: template_id)

          # Capture active version reference before list/delete operations.
          # This ensures we never prune the currently active version, even if
          # activation changes during pruning (defensive programming).
          active = active_version(template_id: template_id)

          versions = list(template_id: template_id, limit: 100)
          return {success: true, pruned_count: 0} if versions.size <= MIN_VERSIONS

          # Identify versions to keep
          versions_to_keep = identify_versions_to_keep(versions)
          versions_to_prune = versions.reject { |v| versions_to_keep.include?(v[:id]) }

          # Never prune the active version
          versions_to_prune.reject! { |v| v[:id] == active&.dig(:id) }

          pruned_count = 0
          versions_to_prune.each do |version|
            execute("DELETE FROM template_versions WHERE id = ?", [version[:id]])
            pruned_count += 1
          end

          Aidp.log_info("template_version_repository", "versions_pruned",
            template_id: template_id,
            pruned_count: pruned_count,
            remaining_count: versions.size - pruned_count)

          {success: true, pruned_count: pruned_count}
        rescue => e
          Aidp.log_error("template_version_repository", "prune_failed",
            template_id: template_id, error: e.message)
          {success: false, error: e.message}
        end

        # Count versions for a template
        #
        # @param template_id [String] Template identifier
        # @return [Integer] Version count
        def count(template_id:)
          query_value(
            "SELECT COUNT(*) FROM template_versions WHERE project_dir = ? AND template_id = ?",
            [project_dir, template_id]
          ) || 0
        end

        # Check if any versions exist for a template
        #
        # @param template_id [String] Template identifier
        # @return [Boolean]
        def any?(template_id:)
          count(template_id: template_id).positive?
        end

        # Get all unique template IDs with versions
        #
        # @return [Array<String>] Template IDs
        def template_ids
          rows = query(
            "SELECT DISTINCT template_id FROM template_versions WHERE project_dir = ? ORDER BY template_id",
            [project_dir]
          )

          rows.map { |r| r["template_id"] }
        end

        private

        def next_version_number(template_id)
          current_max = query_value(
            "SELECT MAX(version_number) FROM template_versions WHERE project_dir = ? AND template_id = ?",
            [project_dir, template_id]
          )

          (current_max || 0) + 1
        end

        def identify_versions_to_keep(versions)
          keep_ids = Set.new

          # Always keep the most recent MIN_VERSIONS
          versions.take(MIN_VERSIONS).each { |v| keep_ids << v[:id] }

          # Ensure we keep at least MIN_POSITIVE_VERSIONS with positive votes
          positive_versions = versions.select { |v| v[:positive_votes].positive? }
            .sort_by { |v| -v[:positive_votes] }

          positive_versions.take(MIN_POSITIVE_VERSIONS).each { |v| keep_ids << v[:id] }

          keep_ids
        end

        def deserialize_version(row)
          return nil unless row

          {
            id: row["id"],
            template_id: row["template_id"],
            version_number: row["version_number"],
            content: row["content"],
            parent_version_id: row["parent_version_id"],
            is_active: row["is_active"] == 1,
            positive_votes: row["positive_votes"] || 0,
            negative_votes: row["negative_votes"] || 0,
            created_at: row["created_at"],
            metadata: deserialize_json(row["metadata"])
          }
        end
      end
    end
  end
end
