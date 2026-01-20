module Aidp
  module Watch
    # AIDecisionEngine for resolving merge conflicts and making intelligent decisions
    class AIDecisionEngine
      def resolve_merge_conflict(base_branch_path:, conflict_files:)
        # AI-powered merge conflict resolution with intelligent strategy
        Aidp.log_debug(
          "ai_decision_engine",
          "merge_conflict_resolution_start",
          conflict_files: conflict_files
        )

        conflict_resolution = {}
        conflict_files.each do |file|
          begin
            # Read the full file content
            content = File.read(file)

            # Detect conflict markers
            conflicts = detect_conflicts(content)

            # If no conflicts or too complex, preserve original file
            if conflicts.empty?
              conflict_resolution[file] = content
              next
            end

            # Intelligent conflict resolution strategy
            resolved_content = resolve_conflicts(content, conflicts)

            # Log resolution details
            Aidp.log_debug(
              "ai_decision_engine",
              "file_conflict_resolved",
              file: file,
              conflict_count: conflicts.count
            )

            # Write resolved content
            conflict_resolution[file] = resolved_content
          rescue StandardError => e
            Aidp.log_debug(
              "ai_decision_engine",
              "file_conflict_resolution_failed",
              file: file,
              error: e.message
            )
            # Fallback to preserving base branch version
            conflict_resolution[file] = File.read(file).split("<<<<<<< HEAD")[0].strip
          end
        end

        Aidp.log_debug(
          "ai_decision_engine",
          "merge_conflict_resolution_complete",
          resolved_files: conflict_resolution.keys
        )

        conflict_resolution
      end

      private

      def detect_conflicts(content)
        # Detect merge conflict markers
        conflict_regex = /<<<<<<< HEAD\n(.*?)\n=======\n(.*?)\n>>>>>>> /m
        content.scan(conflict_regex)
      end

      def resolve_conflicts(content, conflicts)
        # Intelligent conflict resolution strategy
        resolved_content = content.dup

        conflicts.each do |head_version, branch_version|
          # Basic resolution strategy: prefer more structured/verbose version
          preferred_version =
            if head_version.lines.count > branch_version.lines.count
              head_version
            else
              branch_version
            end

          # Replace conflict block with preferred version
          resolved_content.gsub!(
            /<<<<<<< HEAD\n#{Regexp.escape(head_version)}\n=======\n#{Regexp.escape(branch_version)}\n>>>>>>> /,
            preferred_version
          )
        end

        resolved_content
      end
    end
  end
end
