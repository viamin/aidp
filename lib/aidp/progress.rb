# frozen_string_literal: true

require "yaml"
require "fileutils"

module Aidp
  class Progress
    def self.tracker_file(project_dir = Dir.pwd)
      File.join(project_dir, ".aidp-progress.yml")
    end

    def self.load(project_dir = Dir.pwd)
      file = tracker_file(project_dir)
      return {} unless File.exist?(file)

      YAML.load_file(file) || {}
    rescue => e
      warn "Warning: Could not load progress file: #{e.message}"
      {}
    end

    def self.save(progress, project_dir = Dir.pwd)
      file = tracker_file(project_dir)
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, progress.to_yaml)
    end

    def self.mark_completed(step_name, project_dir = Dir.pwd)
      progress = load(project_dir)
      progress[step_name] = {
        "completed_at" => Time.now.iso8601,
        "status" => "completed"
      }
      save(progress, project_dir)
    end

    def self.mark_in_progress(step_name, project_dir = Dir.pwd)
      progress = load(project_dir)
      progress[step_name] = {
        "started_at" => Time.now.iso8601,
        "status" => "in_progress"
      }
      save(progress, project_dir)
    end

    def self.completed_steps(project_dir = Dir.pwd)
      progress = load(project_dir)
      progress.select { |_, data| data["status"] == "completed" }.keys
    end

    def self.in_progress_steps(project_dir = Dir.pwd)
      progress = load(project_dir)
      progress.select { |_, data| data["status"] == "in_progress" }.keys
    end

    def self.display_status(project_dir = Dir.pwd)
      progress = load(project_dir)
      all_steps = Aidp::Steps.list

      puts "\n📊 AI Dev Pipeline Progress:"
      puts "=" * 50

      all_steps.each do |step|
        step_data = progress[step]
        if step_data
          case step_data["status"]
          when "completed"
            puts "✅ #{step.upcase} - Completed at #{step_data["completed_at"]}"
          when "in_progress"
            puts "🔄 #{step.upcase} - In Progress (started #{step_data["started_at"]})"
          end
        else
          gate = Aidp::Steps.for(step)[:gate] ? " (GATE)" : ""
          puts "⏳ #{step.upcase}#{gate} - Pending"
        end
      end
      puts "=" * 50
    end
  end
end
