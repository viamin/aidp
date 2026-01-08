# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Repositories::JobRepository do
  let(:temp_dir) { Dir.mktmpdir("aidp_job_repo_test")}
  let(:db_path) { File.join(temp_dir, ".aidp", "aidp.db")}
  let(:repository) { described_class.new(project_dir: temp_dir)}

  before do
    allow(Aidp::ConfigPaths).to receive(:database_file).with(temp_dir).and_return(db_path)
    Aidp::Database::Migrations.run!(temp_dir)
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.remove_entry(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "#create" do
    it "creates a job" do
      job_id = repository.create(job_type: "execute", input: {mode: "analyze"})

      expect(job_id).to start_with("job_")
    end
  end

  describe "#find" do
    it "finds job by ID" do
      job_id = repository.create(job_type: "test")

      job = repository.find(job_id)

      expect(job[:id]).to eq(job_id)
      expect(job[:job_type]).to eq("test")
      expect(job[:status]).to eq("pending")
    end
  end

  describe "#start" do
    it "starts a job" do
      job_id = repository.create(job_type: "execute")

      repository.start(job_id, pid: 12345)

      job = repository.find(job_id)
      expect(job[:status]).to eq("running")
      expect(job[:input][:pid]).to eq(12345)
    end
  end

  describe "#complete" do
    it "completes a job" do
      job_id = repository.create(job_type: "execute")
      repository.start(job_id)

      repository.complete(job_id, output: {result: "success"})

      job = repository.find(job_id)
      expect(job[:status]).to eq("completed")
      expect(job[:output][:result]).to eq("success")
    end
  end

  describe "#fail" do
    it "fails a job" do
      job_id = repository.create(job_type: "execute")

      repository.fail(job_id, error: "Something went wrong")

      job = repository.find(job_id)
      expect(job[:status]).to eq("failed")
      expect(job[:error]).to eq("Something went wrong")
    end
  end

  describe "#stop" do
    it "stops a job" do
      job_id = repository.create(job_type: "execute")
      repository.start(job_id)

      repository.stop(job_id)

      job = repository.find(job_id)
      expect(job[:status]).to eq("stopped")
    end
  end

  describe "#list" do
    before do
      @pending = repository.create(job_type: "a")
      @running = repository.create(job_type: "b")
      repository.start(@running)
    end

    it "lists all jobs" do
      expect(repository.list.size).to eq(2)
    end

    it "filters by status" do
      expect(repository.list(status: "pending").size).to eq(1)
      expect(repository.list(status: "running").size).to eq(1)
    end
  end

  describe "#running" do
    it "returns running jobs" do
      job_id = repository.create(job_type: "x")
      repository.start(job_id)

      running = repository.running

      expect(running.size).to eq(1)
    end
  end

  describe "#status" do
    it "returns job status" do
      job_id = repository.create(job_type: "analyze")
      repository.start(job_id, pid: 99999)

      status = repository.status(job_id)

      expect(status[:job_id]).to eq(job_id)
      expect(status[:mode]).to eq("analyze")
      expect(status[:status]).to eq("running")
      expect(status[:pid]).to eq(99999)
    end
  end

  describe "#delete" do
    it "deletes a job" do
      job_id = repository.create(job_type: "x")

      repository.delete(job_id)

      expect(repository.find(job_id)).to be_nil
    end
  end
end
