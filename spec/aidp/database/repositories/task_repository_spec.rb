# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Repositories::TaskRepository do
  let(:temp_dir) { Dir.mktmpdir("aidp_task_repo_test") }
  let(:db_path) { File.join(temp_dir, ".aidp", "aidp.db") }
  let(:repository) { described_class.new(project_dir: temp_dir) }

  before do
    allow(Aidp::ConfigPaths).to receive(:database_file).with(temp_dir).and_return(db_path)
    Aidp::Database::Migrations.run!(temp_dir)
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.remove_entry(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "#create" do
    it "creates a new task" do
      task = repository.create(description: "Test task")

      expect(task[:id]).to start_with("task_")
      expect(task[:description]).to eq("Test task")
      expect(task[:status]).to eq(:pending)
      expect(task[:priority]).to eq(:medium)
    end

    it "accepts priority parameter" do
      task = repository.create(description: "High priority", priority: :high)

      expect(task[:priority]).to eq(:high)
    end

    it "accepts tags parameter" do
      task = repository.create(description: "Tagged task", tags: ["bug", "urgent"])

      expect(task[:tags]).to eq(["bug", "urgent"])
    end

    it "stores session and discovered_during" do
      task = repository.create(
        description: "Discovered task",
        session: "session_123",
        discovered_during: "code review"
      )

      expect(task[:session]).to eq("session_123")
      expect(task[:discovered_during]).to eq("code review")
    end
  end

  describe "#find" do
    it "finds task by ID" do
      created = repository.create(description: "Find me")

      found = repository.find(created[:id])

      expect(found[:description]).to eq("Find me")
    end

    it "returns nil for non-existent ID" do
      expect(repository.find("nonexistent")).to be_nil
    end
  end

  describe "#update_status" do
    let!(:task) { repository.create(description: "Status test") }

    it "updates status to in_progress" do
      updated = repository.update_status(task[:id], :in_progress)

      expect(updated[:status]).to eq(:in_progress)
      expect(updated[:started_at]).not_to be_nil
    end

    it "updates status to done" do
      updated = repository.update_status(task[:id], :done)

      expect(updated[:status]).to eq(:done)
      expect(updated[:completed_at]).not_to be_nil
    end

    it "updates status to abandoned with reason" do
      updated = repository.update_status(task[:id], :abandoned, reason: "No longer needed")

      expect(updated[:status]).to eq(:abandoned)
      expect(updated[:source][:abandoned_reason]).to eq("No longer needed")
    end

    it "returns nil for non-existent task" do
      expect(repository.update_status("nonexistent", :done)).to be_nil
    end
  end

  describe "#all" do
    before do
      repository.create(description: "Pending 1", priority: :high)
      repository.create(description: "Pending 2", priority: :medium, tags: ["bug"])
      task = repository.create(description: "Done task", priority: :low)
      repository.update_status(task[:id], :done)
    end

    it "returns all tasks" do
      tasks = repository.all

      expect(tasks.size).to eq(3)
    end

    it "filters by status" do
      tasks = repository.all(status: :pending)

      expect(tasks.size).to eq(2)
    end

    it "filters by priority" do
      tasks = repository.all(priority: :high)

      expect(tasks.size).to eq(1)
      expect(tasks.first[:description]).to eq("Pending 1")
    end

    it "filters by tags" do
      tasks = repository.all(tags: ["bug"])

      expect(tasks.size).to eq(1)
      expect(tasks.first[:description]).to eq("Pending 2")
    end
  end

  describe "#pending" do
    before do
      repository.create(description: "Pending")
      task = repository.create(description: "Done")
      repository.update_status(task[:id], :done)
    end

    it "returns only pending tasks" do
      tasks = repository.pending

      expect(tasks.size).to eq(1)
      expect(tasks.first[:description]).to eq("Pending")
    end
  end

  describe "#in_progress" do
    before do
      repository.create(description: "Pending")
      task = repository.create(description: "In progress")
      repository.update_status(task[:id], :in_progress)
    end

    it "returns only in_progress tasks" do
      tasks = repository.in_progress

      expect(tasks.size).to eq(1)
      expect(tasks.first[:description]).to eq("In progress")
    end
  end

  describe "#counts" do
    before do
      2.times { repository.create(description: "Pending") }

      in_progress = repository.create(description: "In progress")
      repository.update_status(in_progress[:id], :in_progress)

      done = repository.create(description: "Done")
      repository.update_status(done[:id], :done)
    end

    it "returns counts by status" do
      counts = repository.counts

      expect(counts[:total]).to eq(4)
      expect(counts[:pending]).to eq(2)
      expect(counts[:in_progress]).to eq(1)
      expect(counts[:done]).to eq(1)
      expect(counts[:abandoned]).to eq(0)
    end
  end
end
