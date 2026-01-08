# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Repositories::HarnessStateRepository do
  let(:temp_dir) { Dir.mktmpdir("aidp_harness_state_repo_test")}
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

  describe "#has_state?" do
    it "returns false when no state exists" do
      expect(repository.has_state?(:execute)).to be false
    end

    it "returns true when state exists" do
      repository.save_state(:execute, {foo: "bar"})

      expect(repository.has_state?(:execute)).to be true
    end
  end

  describe "#load_state" do
    it "returns empty hash when no state exists" do
      expect(repository.load_state(:execute)).to eq({})
    end

    it "returns saved state" do
      repository.save_state(:execute, {user_feedback: "positive", step: "01"})

      state = repository.load_state(:execute)

      expect(state[:user_feedback]).to eq("positive")
      expect(state[:step]).to eq("01")
    end

    it "includes metadata" do
      repository.save_state(:execute, {data: "test"})

      state = repository.load_state(:execute)

      expect(state[:mode]).to eq("execute")
      expect(state[:project_dir]).to eq(temp_dir)
      expect(state[:saved_at]).not_to be_nil
    end
  end

  describe "#save_state" do
    it "creates new state" do
      repository.save_state(:execute, {key: "value"})

      expect(repository.has_state?(:execute)).to be true
    end

    it "updates existing state" do
      repository.save_state(:execute, {key: "value1"})
      repository.save_state(:execute, {key: "value2"})

      state = repository.load_state(:execute)

      expect(state[:key]).to eq("value2")
    end

    it "increments version on update" do
      repository.save_state(:execute, {key: "v1"})
      expect(repository.version(:execute)).to eq(1)

      repository.save_state(:execute, {key: "v2"})
      expect(repository.version(:execute)).to eq(2)
    end
  end

  describe "#clear_state" do
    it "removes state" do
      repository.save_state(:execute, {key: "value"})
      repository.clear_state(:execute)

      expect(repository.has_state?(:execute)).to be false
    end
  end

  describe "#modes_with_state" do
    it "returns empty array when no state" do
      expect(repository.modes_with_state).to eq([])
    end

    it "returns modes with state" do
      repository.save_state(:execute, {x: 1})
      repository.save_state(:analyze, {x: 2})

      modes = repository.modes_with_state

      expect(modes).to contain_exactly("execute", "analyze")
    end
  end

  describe "#version" do
    it "returns 0 when no state" do
      expect(repository.version(:execute)).to eq(0)
    end

    it "returns current version" do
      repository.save_state(:execute, {x: 1})

      expect(repository.version(:execute)).to eq(1)
    end
  end

  describe "mode isolation" do
    it "keeps modes separate" do
      repository.save_state(:execute, {mode_data: "execute"})
      repository.save_state(:analyze, {mode_data: "analyze"})

      execute_state = repository.load_state(:execute)
      analyze_state = repository.load_state(:analyze)

      expect(execute_state[:mode_data]).to eq("execute")
      expect(analyze_state[:mode_data]).to eq("analyze")
    end
  end
end
