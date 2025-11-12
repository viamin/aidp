# frozen_string_literal: true

require_relative "base_reviewer"

module Aidp
  module Watch
    module Reviewers
      # Security Reviewer - focuses on security vulnerabilities and risks
      class SecurityReviewer < BaseReviewer
        PERSONA_NAME = "Security Specialist"
        FOCUS_AREAS = [
          "Injection vulnerabilities (SQL, command, XSS, etc.)",
          "Authentication and authorization flaws",
          "Sensitive data exposure",
          "Insecure deserialization",
          "Security misconfiguration",
          "Insufficient logging and monitoring",
          "Insecure dependencies",
          "Secrets and credentials in code",
          "Input validation and sanitization",
          "OWASP Top 10 vulnerabilities"
        ].freeze

        def review(pr_data:, files:, diff:)
          user_prompt = build_security_prompt(pr_data: pr_data, files: files, diff: diff)
          findings = analyze_with_provider(user_prompt)

          {
            persona: PERSONA_NAME,
            findings: findings
          }
        end

        private

        def build_security_prompt(pr_data:, files:, diff:)
          base_prompt = build_review_prompt(pr_data: pr_data, files: files, diff: diff)

          <<~PROMPT
            #{base_prompt}

            **Additional Security Focus:**
            Pay special attention to:
            1. User input handling and validation
            2. Database queries and potential SQL injection
            3. File operations and path traversal risks
            4. Authentication and session management
            5. Cryptographic operations and key management
            6. API endpoints and their access controls
            7. Third-party dependencies and their security posture
            8. Environment variables and configuration
            9. Logging of sensitive information
            10. Command execution and shell injection risks

            Mark any security issues as "high" severity if they could lead to:
            - Unauthorized access or privilege escalation
            - Data breach or exposure of sensitive information
            - Remote code execution
            - Denial of service
          PROMPT
        end
      end
    end
  end
end
