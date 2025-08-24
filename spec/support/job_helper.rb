# frozen_string_literal: true

module JobHelper
  def create_mock_job(id:, status: "completed", error: nil)
    # Use the correct Que column names
    finished_at = (status == "completed") ? Time.now : nil
    error_count = error ? 1 : 0

    Que.execute(
      <<~SQL,
        INSERT INTO que_jobs (
          job_class, queue, run_at, error_count, 
          last_error_message, finished_at, job_schema_version,
          args, kwargs
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      SQL
      [
        "Aidp::Jobs::ProviderExecutionJob",
        "test_queue",
        Time.now - 10,
        error_count,
        error,
        finished_at,
        1, # job_schema_version
        [], # args
        {} # kwargs
      ]
    )
  end
end

RSpec.configure do |config|
  config.include JobHelper
end
