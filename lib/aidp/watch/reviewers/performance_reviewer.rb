# frozen_string_literal: true

require_relative "base_reviewer"

module Aidp
  module Watch
    module Reviewers
      # Performance Reviewer - focuses on performance issues and optimizations
      class PerformanceReviewer < BaseReviewer
        PERSONA_NAME = "Performance Analyst"
        FOCUS_AREAS = [
          "Algorithm complexity (O(n) vs O(n²), etc.)",
          "Database query optimization (N+1 queries, missing indexes)",
          "Memory allocation and garbage collection pressure",
          "Blocking I/O operations",
          "Inefficient data structures",
          "Unnecessary computations or redundant work",
          "Caching opportunities",
          "Resource leaks (connections, file handles, etc.)",
          "Concurrent access patterns",
          "Network round-trips and latency"
        ].freeze

        def review(pr_data:, files:, diff:)
          user_prompt = build_performance_prompt(pr_data: pr_data, files: files, diff: diff)
          findings = analyze_with_provider(user_prompt)

          {
            persona: PERSONA_NAME,
            findings: findings
          }
        end

        private

        def build_performance_prompt(pr_data:, files:, diff:)
          base_prompt = build_review_prompt(pr_data: pr_data, files: files, diff: diff)

          <<~PROMPT
            #{base_prompt}

            **Additional Performance Focus:**
            Pay special attention to:
            1. Loop complexity and nested iterations
            2. Database queries (look for N+1 patterns, missing eager loading)
            3. Memory allocations in hot paths
            4. I/O operations (file, network, database) - are they batched?
            5. Synchronous operations that could be asynchronous
            6. Large data structures being copied or traversed repeatedly
            7. Missing caching opportunities
            8. Resource pooling and connection management
            9. Lazy loading vs eager loading trade-offs
            10. Potential bottlenecks under high load

            Mark performance issues as:
            - "high" if they could cause timeouts, out-of-memory errors, or severe degradation
            - "major" if they significantly impact response time or resource usage
            - "minor" for optimizations that would improve efficiency
            - "nit" for micro-optimizations with negligible impact
          PROMPT
        end
      end
    end
  end
end
