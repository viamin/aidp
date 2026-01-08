# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Repositories::WorkstreamRepository do
  let(:temp_dir) { Dir.mktmpdir("aidp_workstream_repo_test")}
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

  describe "#init" do
    it "creates a new workstream" do
      state = repository.init(slug: "feature-123")

      expect(state[:slug]).to eq("feature-123")
      expect(state[:status]).to eq("active")
      expect(state[:iteration]).to eq(0)
    end

    it "stores task description" do
      state = repository.init(slug: "feature-123", task: "Implement feature X")

      expect(state[:task]).to eq("Implement feature X")
    end

    it "creates initial event" do
      repository.init(slug: "feature-123")

      events = repository.recent_events(slug: "feature-123")

      expect(events.size).to eq(1)
      expect(events.first[:type]).to eq("created")
    end
  end

  describe "#read" do
    it "returns nil for non-existent workstream" do
      expect(repository.read(slug: "nonexistent")).to be_nil
    end

    it "returns workstream state" do
      repository.init(slug: "feature-123", task: "Test task")

      state = repository.read(slug: "feature-123")

      expect(state[:slug]).to eq("feature-123")
      expect(state[:task]).to eq("Test task")
    end
  end

  describe "#update" do
    before { repository.init(slug: "feature-123")}

    it "updates attributes" do
      state = repository.update(slug: "feature-123", branch: "feature/123", status: "paused")

      expect(state[:branch]).to eq("feature/123")
      expect(state[:status]).to eq("paused")
    end

    it "creates workstream if not exists" do
      state = repository.update(slug: "new-workstream", branch: "new/branch")

      expect(state[:slug]).to eq("new-workstream")
      expect(state[:branch]).to eq("new/branch")
    end
  end

  describe "#increment_iteration" do
    before { repository.init(slug: "feature-123")}

    it "increments iteration counter" do
      state = repository.increment_iteration(slug: "feature-123")

      expect(state[:iteration]).to eq(1)
    end

    it "creates iteration event" do
      repository.increment_iteration(slug: "feature-123")

      events = repository.recent_events(slug: "feature-123")
      iteration_event = events.find { |e| e[:type] == "iteration"}

      expect(iteration_event[:data][:count]).to eq(1)
    end

    it "resumes paused workstream" do
      repository.pause(slug: "feature-123")
      state = repository.increment_iteration(slug: "feature-123")

      expect(state[:status]).to eq("active")
    end
  end

  describe "#pause" do
    before { repository.init(slug: "feature-123")}

    it "pauses workstream" do
      result = repository.pause(slug: "feature-123")

      expect(result[:status]).to eq("paused")
    end

    it "returns error if already paused" do
      repository.pause(slug: "feature-123")
      result = repository.pause(slug: "feature-123")

      expect(result[:error]).to eq("Already paused")
    end

    it "returns error for non-existent workstream" do
      result = repository.pause(slug: "nonexistent")

      expect(result[:error]).to eq("Workstream not found")
    end
  end

  describe "#resume" do
    before do
      repository.init(slug: "feature-123")
      repository.pause(slug: "feature-123")
    end

    it "resumes workstream" do
      result = repository.resume(slug: "feature-123")

      expect(result[:status]).to eq("active")
    end

    it "returns error if not paused" do
      repository.resume(slug: "feature-123")
      result = repository.resume(slug: "feature-123")

      expect(result[:error]).to eq("Not paused")
    end
  end

  describe "#complete" do
    before { repository.init(slug: "feature-123")}

    it "completes workstream" do
      result = repository.complete(slug: "feature-123")

      expect(result[:status]).to eq("completed")
    end

    it "returns error if already completed" do
      repository.complete(slug: "feature-123")
      result = repository.complete(slug: "feature-123")

      expect(result[:error]).to eq("Already completed")
    end
  end

  describe "#mark_removed" do
    before { repository.init(slug: "feature-123")}

    it "marks workstream as removed" do
      repository.mark_removed(slug: "feature-123")

      state = repository.read(slug: "feature-123")
      expect(state[:status]).to eq("removed")
    end

    it "auto-completes active workstream" do
      repository.mark_removed(slug: "feature-123")

      events = repository.recent_events(slug: "feature-123")
      completed_event = events.find { |e| e[:type] == "completed"}

      expect(completed_event).not_to be_nil
    end
  end

  describe "#recent_events" do
    before do
      repository.init(slug: "feature-123")
      3.times { repository.increment_iteration(slug: "feature-123")}
    end

    it "returns recent events" do
      events = repository.recent_events(slug: "feature-123")

      expect(events.size).to eq(4) # created + 3 iterations
    end

    it "respects limit" do
      events = repository.recent_events(slug: "feature-123", limit: 2)

      expect(events.size).to eq(2)
    end
  end

  describe "#list" do
    before do
      repository.init(slug: "active-1")
      repository.init(slug: "active-2")
      repository.init(slug: "completed-1")
      repository.complete(slug: "completed-1")
    end

    it "returns all workstreams" do
      workstreams = repository.list

      expect(workstreams.size).to eq(3)
    end

    it "filters by status" do
      active = repository.list(status: "active")
      completed = repository.list(status: "completed")

      expect(active.size).to eq(2)
      expect(completed.size).to eq(1)
    end
  end

  describe "#stalled?" do
    before { repository.init(slug: "feature-123")}

    it "returns false for recent activity" do
      expect(repository.stalled?(slug: "feature-123", threshold_seconds: 3600)).to be false
    end
  end
end
