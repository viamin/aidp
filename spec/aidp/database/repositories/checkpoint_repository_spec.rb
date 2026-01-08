# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Repositories::CheckpointRepository do
  let(:temp_dir) { Dir.mktmpdir("aidp_checkpoint_repo_test")}
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

  describe "#save_checkpoint" do
    let(:checkpoint_data) do
      {
        step_name: "01_SETUP",
        iteration: 1,
        status: "healthy",
        run_loop_started_at: "2024-01-01T00:00:00Z",
        metrics: {lines_of_code: 1000, test_coverage: 80}
     }
    end

    it "creates a new checkpoint" do
      id = repository.save_checkpoint(checkpoint_data)

      expect(id).to be_a(Integer)
    end

    it "returns current checkpoint after save" do
      repository.save_checkpoint(checkpoint_data)

      current = repository.current_checkpoint

      expect(current[:step_name]).to eq("01_SETUP")
      expect(current[:iteration]).to eq(1)
      expect(current[:status]).to eq("healthy")
      expect(current[:metrics][:lines_of_code]).to eq(1000)
    end

    it "updates existing checkpoint" do
      id1 = repository.save_checkpoint(checkpoint_data)
      id2 = repository.save_checkpoint(checkpoint_data.merge(iteration: 2))

      expect(id2).to eq(id1)

      current = repository.current_checkpoint
      expect(current[:iteration]).to eq(2)
    end
  end

  describe "#current_checkpoint" do
    it "returns nil when no checkpoint exists" do
      expect(repository.current_checkpoint).to be_nil
    end

    it "returns latest checkpoint" do
      repository.save_checkpoint(step_name: "01_SETUP", iteration: 1, status: "ok", metrics: {})

      current = repository.current_checkpoint

      expect(current).not_to be_nil
      expect(current[:step_name]).to eq("01_SETUP")
    end
  end

  describe "#append_history" do
    it "appends to history" do
      repository.append_history(step_name: "01_SETUP", iteration: 1, status: "ok", metrics: {})
      repository.append_history(step_name: "02_BUILD", iteration: 2, status: "ok", metrics: {})

      history = repository.history

      expect(history.size).to eq(2)
      expect(history.first[:step_name]).to eq("01_SETUP")
      expect(history.last[:step_name]).to eq("02_BUILD")
    end
  end

  describe "#history" do
    before do
      5.times do |i|
        repository.append_history(
          step_name: "step_#{i}",
          iteration: i + 1,
          status: "ok",
          metrics: {count: i}
        )
      end
    end

    it "returns history in chronological order" do
      history = repository.history

      expect(history.size).to eq(5)
      expect(history.first[:step_name]).to eq("step_0")
      expect(history.last[:step_name]).to eq("step_4")
    end

    it "respects limit parameter" do
      history = repository.history(limit: 2)

      expect(history.size).to eq(2)
    end
  end

  describe "#clear" do
    it "clears all checkpoint data" do
      repository.save_checkpoint(step_name: "test", iteration: 1, status: "ok", metrics: {})
      repository.append_history(step_name: "test", iteration: 1, status: "ok", metrics: {})

      repository.clear

      expect(repository.current_checkpoint).to be_nil
      expect(repository.history).to be_empty
    end
  end
end
