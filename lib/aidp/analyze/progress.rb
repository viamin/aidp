# frozen_string_literal: true

require "yaml"
require "time"

module Aidp
  module Analyze
    # Manages progress tracking for analyze mode, isolated from execute mode
    class Progress
      attr_reader :project_dir, :progress_file

      def initialize(project_dir, skip_persistence: false)
        @project_dir = project_dir
        @progress_file = File.join(project_dir, ".aidp", "progress", "analyze.yml")
        @skip_persistence = skip_persistence
        load_progress
      end

      def completed_steps
        @progress["completed_steps"] || []
      end

      def current_step
        @progress["current_step"]
      end

      def started_at
        @progress["started_at"] ? Time.parse(@progress["started_at"]) : nil
      end

      def step_completed?(step_name)
        completed_steps.include?(step_name)
      end

      def mark_step_completed(step_name)
        @progress["completed_steps"] ||= []
        @progress["completed_steps"] << step_name unless step_completed?(step_name)
        @progress["current_step"] = nil
        save_progress
      end

      def mark_step_in_progress(step_name)
        @progress["current_step"] = step_name
        @progress["started_at"] ||= Time.now.iso8601
        save_progress
      end

      def reset
        @progress = {
          "completed_steps" => [],
          "current_step" => nil,
          "started_at" => nil
        }
        save_progress
      end

      def next_step
        Aidp::Analyze::Steps::SPEC.keys.find { |step| !step_completed?(step) }
      end

      private

      def load_progress
        if @skip_persistence && !File.exist?(@progress_file)
          @progress = {}
          return
        end
        @progress = if !@skip_persistence && File.exist?(@progress_file)
          YAML.safe_load_file(@progress_file, permitted_classes: [Date, Time, Symbol], aliases: true) || {}
        else
          {}
        end
        @progress = {} if @progress.nil?
      end

      def save_progress
        return if @skip_persistence
        FileUtils.mkdir_p(File.dirname(@progress_file))
        File.write(@progress_file, @progress.to_yaml)
      end
    end
  end
end
