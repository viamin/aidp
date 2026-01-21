# frozen_string_literal: true

require_relative "base_activity"

module Aidp
  module Temporal
    module Activities
      # Activity that analyzes a GitHub issue
      # Extracts requirements, acceptance criteria, and context
      class AnalyzeIssueActivity < BaseActivity
        activity_type "analyze_issue"

        def execute(input)
          with_activity_context do
            project_dir = input[:project_dir]
            issue_number = input[:issue_number]
            issue_url = input[:issue_url]

            log_activity("analyzing_issue",
              project_dir: project_dir,
              issue_number: issue_number)

            # Fetch issue details
            issue_data = fetch_issue(project_dir, issue_number, issue_url)

            unless issue_data
              return error_result("Failed to fetch issue ##{issue_number}")
            end

            heartbeat(phase: "analysis", issue_number: issue_number)

            # Extract structured information
            analysis = analyze_issue_content(project_dir, issue_data)

            success_result(
              result: analysis,
              issue_number: issue_number,
              issue_title: issue_data[:title]
            )
          end
        end

        private

        def fetch_issue(project_dir, issue_number, issue_url)
          # Try to use GitHub CLI if available
          if system("which gh > /dev/null 2>&1")
            fetch_with_gh_cli(issue_number)
          elsif issue_url
            fetch_with_url(issue_url)
          else
            nil
          end
        rescue => e
          Aidp.log_error("analyze_issue_activity", "fetch_failed",
            issue_number: issue_number,
            error: e.message)
          nil
        end

        def fetch_with_gh_cli(issue_number)
          output = `gh issue view #{issue_number} --json title,body,labels,comments 2>/dev/null`
          return nil unless $?.success?

          data = JSON.parse(output, symbolize_names: true)
          {
            number: issue_number,
            title: data[:title],
            body: data[:body],
            labels: data[:labels]&.map { |l| l[:name] } || [],
            comments: data[:comments]&.map { |c| c[:body] } || []
          }
        end

        def fetch_with_url(issue_url)
          # Parse issue URL to extract owner/repo/number
          match = issue_url.match(%r{github\.com/([^/]+)/([^/]+)/issues/(\d+)})
          return nil unless match

          owner, repo, number = match.captures

          output = `gh issue view #{number} --repo #{owner}/#{repo} --json title,body,labels,comments 2>/dev/null`
          return nil unless $?.success?

          data = JSON.parse(output, symbolize_names: true)
          {
            number: number.to_i,
            title: data[:title],
            body: data[:body],
            labels: data[:labels]&.map { |l| l[:name] } || [],
            comments: data[:comments]&.map { |c| c[:body] } || []
          }
        end

        def analyze_issue_content(project_dir, issue_data)
          # Build analysis structure
          {
            issue_number: issue_data[:number],
            title: issue_data[:title],
            description: issue_data[:body],
            labels: issue_data[:labels],
            comments: issue_data[:comments],
            requirements: extract_requirements(issue_data),
            acceptance_criteria: extract_acceptance_criteria(issue_data),
            affected_areas: identify_affected_areas(project_dir, issue_data)
          }
        end

        def extract_requirements(issue_data)
          body = issue_data[:body] || ""
          comments = issue_data[:comments] || []

          # Simple extraction - look for requirement patterns
          requirements = []

          # From body
          body.scan(/(?:^|\n)[-*]\s*(.+)/).flatten.each do |item|
            requirements << item.strip if item.length > 10
          end

          # From comments with context
          comments.each do |comment|
            comment.scan(/(?:^|\n)[-*]\s*(.+)/).flatten.each do |item|
              requirements << item.strip if item.length > 10
            end
          end

          requirements.uniq.first(20)
        end

        def extract_acceptance_criteria(issue_data)
          body = issue_data[:body] || ""

          # Look for acceptance criteria section
          criteria = []

          if body.include?("Acceptance Criteria") || body.include?("acceptance criteria")
            section = body.split(/acceptance criteria/i).last
            section = section.split(/\n##/).first if section.include?("\n##")

            section.scan(/(?:^|\n)[-*\d.]\s*(.+)/).flatten.each do |item|
              criteria << item.strip if item.length > 5
            end
          end

          criteria.first(10)
        end

        def identify_affected_areas(project_dir, issue_data)
          title = issue_data[:title] || ""
          body = issue_data[:body] || ""
          combined = "#{title}\n#{body}".downcase

          areas = []

          # Common area patterns
          areas << "tests" if combined.include?("test") || combined.include?("spec")
          areas << "documentation" if combined.include?("doc") || combined.include?("readme")
          areas << "configuration" if combined.include?("config") || combined.include?("setting")
          areas << "api" if combined.include?("api") || combined.include?("endpoint")
          areas << "ui" if combined.include?("ui") || combined.include?("interface") || combined.include?("display")
          areas << "database" if combined.include?("database") || combined.include?("migration") || combined.include?("schema")

          areas.uniq
        end
      end
    end
  end
end
