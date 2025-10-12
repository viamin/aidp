# frozen_string_literal: true

require "yaml"
require "fileutils"
require "time"

module Aidp
  module Watch
    # Persists watch mode progress for each repository/issue pair. Used to
    # avoid re-processing plan/build triggers and to retain generated plan
    # context between runs.
    class StateStore
      attr_reader :path

      def initialize(project_dir:, repository:)
        @project_dir = project_dir
        @repository = repository
        @path = File.join(project_dir, ".aidp", "watch", "#{sanitize_repository(repository)}.yml")
        ensure_directory
      end

      def plan_processed?(issue_number)
        plans.key?(issue_number.to_s)
      end

      def plan_data(issue_number)
        plans[issue_number.to_s]
      end

      def record_plan(issue_number, data)
        payload = {
          "summary" => data[:summary],
          "tasks" => data[:tasks],
          "questions" => data[:questions],
          "comment_body" => data[:comment_body],
          "comment_hint" => data[:comment_hint],
          "posted_at" => data[:posted_at] || Time.now.utc.iso8601
        }.compact

        plans[issue_number.to_s] = payload
        save!
      end

      def build_status(issue_number)
        builds[issue_number.to_s] || {}
      end

      def record_build_status(issue_number, status:, details: {})
        builds[issue_number.to_s] = {
          "status" => status,
          "updated_at" => Time.now.utc.iso8601
        }.merge(stringify_keys(details))
        save!
      end

      private

      def ensure_directory
        FileUtils.mkdir_p(File.dirname(@path))
      end

      def sanitize_repository(repository)
        repository.tr("/", "_")
      end

      def load_state
        @state ||= if File.exist?(@path)
          YAML.safe_load_file(@path, permitted_classes: [Time]) || {}
        else
          {}
        end
      end

      def save!
        File.write(@path, YAML.dump(state))
      end

      def state
        @state = nil if @state && !@state.is_a?(Hash)
        @state ||= begin
          base = load_state
          base["plans"] ||= {}
          base["builds"] ||= {}
          base
        end
      end

      def plans
        state["plans"]
      end

      def builds
        state["builds"]
      end

      def stringify_keys(hash)
        return {} unless hash

        hash.each_with_object({}) do |(key, value), memo|
          memo[key.to_s] = value
        end
      end
    end
  end
end
