# frozen_string_literal: true

module JobHelper
  def create_mock_job(id:, status: "completed", error: nil)
    Que.execute(
      <<~SQL,
        INSERT INTO que_jobs (
          job_id, job_class, queue, run_at,
          error_count, last_error_message, finished_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7)
      SQL
      [
        id,
        "Aidp::Jobs::ProviderExecutionJob",
        "test_queue",
        Time.now - 10,
        error ? 1 : 0,
        error,
        Time.now
      ]
    )
  end
end

RSpec.configure do |config|
  config.include JobHelper
end
