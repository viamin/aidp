# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Execute::PersistentTasklist do
  let(:project_dir) { Dir.mktmpdir }
  let(:tasklist) { described_class.new(project_dir) }

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#initialize" do
    it "creates .aidp directory if it doesn't exist" do
      # Create a fresh project directory without .aidp
      fresh_dir = Dir.mktmpdir
      begin
        described_class.new(fresh_dir)
        expect(File.directory?(File.join(fresh_dir, ".aidp"))).to be true
      ensure
        FileUtils.rm_rf(fresh_dir)
      end
    end

    it "creates tasklist.jsonl file if it doesn't exist" do
      expect(File.exist?(tasklist.file_path)).to be true
    end

    it "sets correct file path" do
      expect(tasklist.file_path).to eq(File.join(project_dir, ".aidp", "tasklist.jsonl"))
    end
  end

  describe "#create" do
    it "creates a new task with pending status" do
      task = tasklist.create("Test task", priority: :high)

      expect(task.description).to eq("Test task")
      expect(task.status).to eq(:pending)
      expect(task.priority).to eq(:high)
      expect(task.id).to match(/^task_/)
      expect(task.created_at).to be_a(Time)
      expect(task.updated_at).to be_a(Time)
    end

    it "uses medium priority by default" do
      task = tasklist.create("Test task")
      expect(task.priority).to eq(:medium)
    end

    it "persists task to JSONL file" do
      task = tasklist.create("Test task")

      file_content = File.read(tasklist.file_path)
      expect(file_content).to include(task.id)
      expect(file_content).to include("Test task")
      expect(file_content).to include('"status":"pending"')
    end

    it "supports optional session parameter" do
      task = tasklist.create("Test task", session: "auth-implementation")
      expect(task.session).to eq("auth-implementation")
    end

    it "supports optional discovered_during parameter" do
      task = tasklist.create("Test task", discovered_during: "OAuth flow")
      expect(task.discovered_during).to eq("OAuth flow")
    end

    it "supports optional tags parameter" do
      task = tasklist.create("Test task", tags: ["backend", "api"])
      expect(task.tags).to eq(["backend", "api"])
    end

    it "strips whitespace from description" do
      task = tasklist.create("  Test task  ")
      expect(task.description).to eq("Test task")
    end

    it "raises error for empty description" do
      expect {
        tasklist.create("")
      }.to raise_error(described_class::InvalidTaskError, "Description cannot be empty")
    end

    it "raises error for nil description" do
      expect {
        tasklist.create(nil)
      }.to raise_error(described_class::InvalidTaskError, "Description cannot be empty")
    end

    it "raises error for description exceeding 200 characters" do
      long_description = "a" * 201
      expect {
        tasklist.create(long_description)
      }.to raise_error(described_class::InvalidTaskError, "Description too long (max 200 chars)")
    end

    it "raises error for invalid priority" do
      expect {
        tasklist.create("Test task", priority: :invalid)
      }.to raise_error(described_class::InvalidTaskError, "Invalid priority: invalid")
    end
  end

  describe "#update_status" do
    let(:task) { tasklist.create("Test task") }

    it "updates task status to in_progress" do
      updated = tasklist.update_status(task.id, :in_progress)

      expect(updated.status).to eq(:in_progress)
      expect(updated.started_at).to be_a(Time)
      expect(updated.updated_at).to be > task.updated_at
    end

    it "updates task status to done" do
      updated = tasklist.update_status(task.id, :done)

      expect(updated.status).to eq(:done)
      expect(updated.completed_at).to be_a(Time)
    end

    it "updates task status to abandoned with reason" do
      updated = tasklist.update_status(task.id, :abandoned, reason: "Feature cancelled")

      expect(updated.status).to eq(:abandoned)
      expect(updated.abandoned_at).to be_a(Time)
      expect(updated.abandoned_reason).to eq("Feature cancelled")
    end

    it "appends updated task to JSONL file" do
      tasklist.update_status(task.id, :done)

      lines = File.readlines(tasklist.file_path)
      expect(lines.size).to eq(2)
      expect(lines[1]).to include('"status":"done"')
    end

    it "does not overwrite started_at when updating to in_progress again" do
      first_update = tasklist.update_status(task.id, :in_progress)
      original_started_at = first_update.started_at

      sleep 0.01 # Ensure time difference

      second_update = tasklist.update_status(task.id, :in_progress)
      # Compare as integers (seconds) since ISO8601 serialization loses sub-second precision
      expect(second_update.started_at.to_i).to eq(original_started_at.to_i)
    end

    it "raises error for non-existent task" do
      expect {
        tasklist.update_status("non_existent_id", :done)
      }.to raise_error(described_class::TaskNotFoundError)
    end

    it "raises error for invalid status" do
      expect {
        tasklist.update_status(task.id, :invalid_status)
      }.to raise_error(described_class::InvalidTaskError, "Invalid status: invalid_status")
    end
  end

  describe "#all" do
    before do
      tasklist.create("Task 1", priority: :high)
      tasklist.create("Task 2", priority: :low)
      task3 = tasklist.create("Task 3", priority: :high)
      tasklist.update_status(task3.id, :done)
    end

    it "returns all tasks with latest state" do
      tasks = tasklist.all
      expect(tasks.size).to eq(3)
    end

    it "returns tasks sorted by created_at descending" do
      tasks = tasklist.all
      expect(tasks[0].description).to eq("Task 3")
      expect(tasks[1].description).to eq("Task 2")
      expect(tasks[2].description).to eq("Task 1")
    end

    it "filters by status" do
      pending = tasklist.all(status: :pending)
      expect(pending.size).to eq(2)
      expect(pending.map(&:description)).to contain_exactly("Task 1", "Task 2")

      done = tasklist.all(status: :done)
      expect(done.size).to eq(1)
      expect(done.first.description).to eq("Task 3")
    end

    it "filters by priority" do
      high_priority = tasklist.all(priority: :high)
      expect(high_priority.size).to eq(2)
      expect(high_priority.map(&:description)).to contain_exactly("Task 1", "Task 3")
    end

    it "filters by created_at since timestamp" do
      # Use a cutoff from 1 hour ago to test the filter works
      one_hour_ago = Time.now - 3600
      recent = tasklist.all(since: one_hour_ago)
      # Should return all 3 tasks since they were all just created
      expect(recent.size).to eq(3)

      # Also test with future cutoff (should return nothing)
      future = Time.now + 60
      future_results = tasklist.all(since: future)
      expect(future_results.size).to eq(0)
    end

    it "filters by tags" do
      tasklist.create("Backend task", tags: ["backend", "api"])
      tasklist.create("Frontend task", tags: ["frontend", "ui"])

      backend_tasks = tasklist.all(tags: ["backend"])
      expect(backend_tasks.size).to eq(1)
      expect(backend_tasks.first.description).to eq("Backend task")
    end

    it "combines multiple filters" do
      task4 = tasklist.create("Task 4", priority: :high, tags: ["urgent"])
      tasklist.update_status(task4.id, :in_progress)

      result = tasklist.all(status: :in_progress, priority: :high, tags: ["urgent"])
      expect(result.size).to eq(1)
      expect(result.first.description).to eq("Task 4")
    end

    it "returns empty array when file is empty" do
      FileUtils.rm_f(tasklist.file_path)
      FileUtils.touch(tasklist.file_path)

      expect(tasklist.all).to eq([])
    end
  end

  describe "#find" do
    let(:task) { tasklist.create("Find me") }

    it "returns task by ID" do
      found = tasklist.find(task.id)
      expect(found.id).to eq(task.id)
      expect(found.description).to eq("Find me")
    end

    it "returns latest version of task" do
      tasklist.update_status(task.id, :done)

      found = tasklist.find(task.id)
      expect(found.status).to eq(:done)
    end

    it "returns nil for non-existent task" do
      expect(tasklist.find("non_existent")).to be_nil
    end
  end

  describe "#pending" do
    before do
      tasklist.create("Pending 1")
      task2 = tasklist.create("Pending 2")
      tasklist.update_status(task2.id, :in_progress)
      task3 = tasklist.create("Pending 3")
      tasklist.update_status(task3.id, :done)
    end

    it "returns only pending tasks" do
      pending = tasklist.pending
      expect(pending.size).to eq(1)
      expect(pending.first.description).to eq("Pending 1")
    end
  end

  describe "#in_progress" do
    before do
      tasklist.create("Pending task")
      task2 = tasklist.create("In progress task")
      tasklist.update_status(task2.id, :in_progress)
    end

    it "returns only in-progress tasks" do
      in_progress = tasklist.in_progress
      expect(in_progress.size).to eq(1)
      expect(in_progress.first.description).to eq("In progress task")
    end
  end

  describe "#counts" do
    before do
      tasklist.create("Pending 1")
      tasklist.create("Pending 2")

      task3 = tasklist.create("In progress 1")
      tasklist.update_status(task3.id, :in_progress)

      task4 = tasklist.create("Done 1")
      tasklist.update_status(task4.id, :done)
      task5 = tasklist.create("Done 2")
      tasklist.update_status(task5.id, :done)

      task6 = tasklist.create("Abandoned 1")
      tasklist.update_status(task6.id, :abandoned)
    end

    it "returns correct counts by status" do
      counts = tasklist.counts

      expect(counts[:total]).to eq(6)
      expect(counts[:pending]).to eq(2)
      expect(counts[:in_progress]).to eq(1)
      expect(counts[:done]).to eq(2)
      expect(counts[:abandoned]).to eq(1)
    end

    it "returns zero counts for empty tasklist" do
      FileUtils.rm_f(tasklist.file_path)
      FileUtils.touch(tasklist.file_path)

      counts = tasklist.counts

      expect(counts[:total]).to eq(0)
      expect(counts[:pending]).to eq(0)
      expect(counts[:in_progress]).to eq(0)
      expect(counts[:done]).to eq(0)
      expect(counts[:abandoned]).to eq(0)
    end
  end

  describe "JSONL format" do
    it "writes one task per line" do
      tasklist.create("Task 1")
      tasklist.create("Task 2")

      lines = File.readlines(tasklist.file_path)
      expect(lines.size).to eq(2)
    end

    it "writes valid JSON on each line" do
      tasklist.create("Task 1")

      lines = File.readlines(tasklist.file_path)
      expect {
        JSON.parse(lines.first)
      }.not_to raise_error
    end

    it "serializes timestamps as ISO8601 strings" do
      tasklist.create("Task 1")

      line = File.readlines(tasklist.file_path).first
      data = JSON.parse(line)

      expect(data["created_at"]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      expect(data["updated_at"]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it "omits nil fields from JSON" do
      tasklist.create("Task 1")

      line = File.readlines(tasklist.file_path).first
      data = JSON.parse(line)

      expect(data).not_to have_key("started_at")
      expect(data).not_to have_key("completed_at")
      expect(data).not_to have_key("abandoned_at")
    end
  end

  describe "error handling" do
    it "skips malformed JSONL lines and logs warning" do
      File.open(tasklist.file_path, "a") do |f|
        f.puts '{"id":"task_1","description":"Valid task","status":"pending"}'
        f.puts "invalid json line"
        f.puts '{"id":"task_2","description":"Another valid task","status":"pending"}'
      end

      tasks = tasklist.all
      expect(tasks.size).to eq(2)
      expect(tasks.map(&:description)).to contain_exactly("Valid task", "Another valid task")
    end

    it "handles missing .aidp directory gracefully" do
      FileUtils.rm_rf(File.join(project_dir, ".aidp"))

      # Should recreate directory and file
      new_tasklist = described_class.new(project_dir)
      task = new_tasklist.create("Test task")

      expect(task).to be_a(Aidp::Execute::Task)
      expect(File.exist?(new_tasklist.file_path)).to be true
    end
  end

  describe "append-only behavior" do
    it "keeps historical entries in JSONL file" do
      task = tasklist.create("Task 1")
      tasklist.update_status(task.id, :in_progress)
      tasklist.update_status(task.id, :done)

      lines = File.readlines(tasklist.file_path)
      expect(lines.size).to eq(3) # Original + 2 updates
    end

    it "loads only latest version of each task" do
      task = tasklist.create("Task 1")
      tasklist.update_status(task.id, :in_progress)
      tasklist.update_status(task.id, :done)

      tasks = tasklist.all
      expect(tasks.size).to eq(1)
      expect(tasks.first.status).to eq(:done)
    end

    it "handles interleaved task updates correctly" do
      task1 = tasklist.create("Task 1")
      task2 = tasklist.create("Task 2")
      tasklist.update_status(task1.id, :done)
      tasklist.update_status(task2.id, :in_progress)

      tasks = tasklist.all
      expect(tasks.size).to eq(2)

      found_task1 = tasks.find { |t| t.id == task1.id }
      found_task2 = tasks.find { |t| t.id == task2.id }

      expect(found_task1.status).to eq(:done)
      expect(found_task2.status).to eq(:in_progress)
    end
  end
end
