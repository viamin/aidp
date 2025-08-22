# frozen_string_literal: true

module Aidp
  module Execute
    class Runner
      def initialize(project_dir)
        @project_dir = project_dir
      end

      def run_step(step_name, options = {})
        return mock_execution_result if should_use_mock_mode?(options)

        job = Aidp::Jobs::ProviderExecutionJob.enqueue(
          provider_type: "cursor",
          prompt: composed_prompt(step_name, options),
          metadata: {
            step_name: step_name,
            project_dir: @project_dir
          }
        )

        wait_for_job_completion(job)
      end

      private

      def should_use_mock_mode?(options)
        options[:mock_mode] || ENV["AIDP_MOCK_MODE"] == "1" || ENV["RAILS_ENV"] == "test"
      end

      def mock_execution_result
        {
          status: "completed",
          output: "Mock execution result"
        }
      end

      def wait_for_job_completion(job_id)
        loop do
          job = Que.execute("SELECT * FROM que_jobs WHERE job_id = $1", [job_id]).first
          return { status: "completed" } if job.finished_at && job.error_count == 0
          return { status: "failed", error: job.last_error_message } if job.error_count > 0

          if job.finished_at.nil?
            duration = Time.now - job.run_at
            minutes = (duration / 60).to_i
            seconds = (duration % 60).to_i
            duration_str = minutes > 0 ? "#{minutes}m #{seconds}s" : "#{seconds}s"
            print "\r🔄 Job #{job_id} is running (#{duration_str})...".ljust(80)
          else
            print "\r⏳ Job #{job_id} is pending...".ljust(80)
          end
          $stdout.flush
          sleep 1
        end
      ensure
        print "\r" + " " * 80 + "\r"
      end

      def find_template(template_name)
        template_search_paths.each do |path|
          template_path = File.join(path, template_name)
          return template_path if File.exist?(template_path)
        end
        nil
      end

      def template_search_paths
        [
          File.join(@project_dir, "templates", "EXECUTE"),
          File.join(@project_dir, "templates", "COMMON")
        ]
      end

      def composed_prompt(step_name, options = {})
        template_path = find_template("#{step_name}.md")
        raise "Template not found for step #{step_name}" unless template_path

        template = File.read(template_path)
        template % options
      end
    end
  end
end
