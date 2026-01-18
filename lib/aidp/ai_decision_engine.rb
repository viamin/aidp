require "shellwords"

module Aidp
  # AI-powered decision engine for resolving complex merge conflicts
  class AIDecisionEngine
    def initialize(repository_client: nil, ai_provider: nil)
      @repository_client = repository_client
      @ai_provider = ai_provider || default_ai_provider
    end

    # Resolve merge conflicts using advanced AI techniques
    # @param base_branch [String] The base branch to merge into
    # @param head_branch [String] The feature branch being merged
    # @return [Hash] Conflict resolution results
    def resolve_merge_conflicts(base_branch:, head_branch:)
      Aidp.log_debug(
        "ai_decision_engine",
        "resolving_merge_conflicts",
        base_branch: base_branch,
        head_branch: head_branch
      )

      # Collect conflict information
      conflict_info = gather_conflict_details(base_branch, head_branch)

      # If no conflicts, return early
      return {resolved: true, files: {}} if conflict_info[:files].empty?

      # Attempt AI-powered resolution
      resolution_result = perform_ai_conflict_resolution(conflict_info)

      # Log and return resolution result
      log_resolution_result(resolution_result)

      resolution_result
    end

    private

    def gather_conflict_details(base_branch, head_branch)
      # Execute git merge command with detailed conflict information
      Dir.chdir(Dir.pwd) do
        # Use git-merge-tree to get detailed conflict information
        merge_tree_output = `git merge-tree $(git merge-base #{Shellwords.escape(base_branch)} #{Shellwords.escape(head_branch)}) #{Shellwords.escape(base_branch)} #{Shellwords.escape(head_branch)}`

        files_with_conflicts = parse_merge_tree_output(merge_tree_output)

        {
          base_branch: base_branch,
          head_branch: head_branch,
          files: files_with_conflicts
        }
      end
    end

    def parse_merge_tree_output(output)
      # Advanced parsing of git merge-tree output
      conflict_files = {}

      # Capture files with conflicts and their specific conflict details
      output.scan(/changed in both.*?file:\s*(.+)/m).flatten.each do |filename|
        # Read file contents from both branches
        base_content = `git show #{base_branch}:#{Shellwords.escape(filename)} 2>/dev/null` || ""
        head_content = `git show #{head_branch}:#{Shellwords.escape(filename)} 2>/dev/null` || ""

        # Add to conflict files with raw content
        conflict_files[filename] = {
          base_content: base_content,
          head_content: head_content
        }
      end

      conflict_files
    end

    def perform_ai_conflict_resolution(conflict_info)
      # Safeguard against empty conflicts
      return {resolved: true, files: {}} if conflict_info[:files].empty?

      begin
        # Use AI to analyze and resolve conflicts
        resolution_results = @ai_provider.resolve_merge_conflicts(
          base_branch: conflict_info[:base_branch],
          head_branch: conflict_info[:head_branch],
          conflicts: conflict_info[:files]
        )

        # Validate AI resolution
        validate_resolution(resolution_results)
      rescue => e
        Aidp.log_error(
          "ai_decision_engine",
          "conflict_resolution_failed",
          error: e.message,
          base_branch: conflict_info[:base_branch],
          head_branch: conflict_info[:head_branch]
        )

        {
          resolved: false,
          reason: "AI conflict resolution encountered an error: #{e.message}"
        }
      end
    end

    def validate_resolution(resolution_results)
      # Validate the AI's conflict resolution strategy
      if resolution_results.nil? || !resolution_results[:resolved]
        return {
          resolved: false,
          reason: resolution_results&.fetch(:reason, "Unknown resolution failure")
        }
      end

      # Basic validation of resolved files
      resolved_files = resolution_results[:files]
      if resolved_files.nil? || resolved_files.empty?
        return {
          resolved: false,
          reason: "No files resolved"
        }
      end

      # Successful resolution
      {
        resolved: true,
        files: resolved_files
      }
    end

    def log_resolution_result(result)
      log_method = result[:resolved] ? :log_debug : :log_warn
      Aidp.send(
        log_method,
        "ai_decision_engine",
        "merge_conflict_resolution_result",
        resolved: result[:resolved],
        reason: result[:reason] || "N/A",
        resolved_files_count: result[:files]&.size || 0
      )
    end

    # Fallback AI provider with basic/no resolution
    def default_ai_provider
      Class.new do
        def resolve_merge_conflicts(*)
          {
            resolved: false,
            reason: "No AI provider configured for conflict resolution"
          }
        end
      end.new
    end
  end
end
