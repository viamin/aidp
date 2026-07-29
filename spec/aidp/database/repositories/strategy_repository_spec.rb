# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Database::Repositories::StrategyRepository do
  let(:project_dir) { Dir.mktmpdir("aidp_strategy_repo") }
  let(:repository) { described_class.new(project_dir: project_dir) }

  before do
    Aidp::Database.migrate!(project_dir)
  end

  after do
    Aidp::Database.close(project_dir)
    FileUtils.remove_entry(project_dir) if Dir.exist?(project_dir)
  end

  it "keeps prior strategy specs addressable by id when a named strategy changes" do
    original = repository.upsert(name: "fanout", spec: %({"name":"fanout","fanout":2}))
    updated = repository.upsert(name: "fanout", spec: %({"name":"fanout","fanout":4}))

    expect(original[:id]).not_to eq(updated[:id])
    expect(repository.load(original[:id])[:spec]).to include(name: "fanout", fanout: 2)
    expect(repository.load(updated[:id])[:spec]).to include(name: "fanout", fanout: 4)
    expect(repository.find_by_name("fanout")[:id]).to eq(updated[:id])
  end

  it "does not duplicate a strategy row when the spec is unchanged" do
    strategy = repository.upsert(name: "fanout", spec: %({"name":"fanout","fanout":2}))

    repository.upsert(name: "fanout", spec: %({"name":"fanout","fanout":2}))

    rows = repository.send(:query, "SELECT id FROM strategies WHERE project_dir = ?", [project_dir])

    expect(rows.map { |row| row["id"] }).to eq([strategy[:id]])
  end
end
