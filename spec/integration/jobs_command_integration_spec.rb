# frozen_string_literal: true

require "spec_helper"

RSpec.describe "JobsCommand Integration", type: :integration do
  before do
    # Create some test jobs
    create_mock_job(id: 1)
    create_mock_job(id: 2, error: "Test error")
    create_mock_job(id: 3, status: "running")
  end
end
