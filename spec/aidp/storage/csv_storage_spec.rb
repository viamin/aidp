# frozen_string_literal: true

require "spec_helper"
require "aidp/storage/csv_storage"

RSpec.describe Aidp::Storage::CsvStorage do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:storage) { described_class.new(tmp_dir) }

  after { FileUtils.rm_rf(tmp_dir) }

  it "appends and reads rows" do
    result = storage.append("data", {"name" => "Alice"})
    expect(result[:success]).to be true
    expect(storage.read_all("data").first["name"]).to eq("Alice")
    expect(storage.count_rows("data")).to eq(1)
  end

  it "filters rows by columns" do
    storage.append("data", {"name" => "Alice"})
    storage.append("data", {"name" => "Bob"})

    filtered = storage.read_filtered("data", name: "Bob")
    expect(filtered.map { |r| r["name"] }).to eq(["Bob"])
  end

  it "computes summary with numeric stats" do
    storage.append("data", {"score" => "10"})
    storage.append("data", {"score" => "20"})

    summary = storage.summary("data")
    expect(summary[:total_rows]).to eq(2)
    expect(summary[:numeric_columns]).to include("score")
    expect(summary["score_stats"][:min]).to eq(10.0)
    expect(summary["score_stats"][:max]).to eq(20.0)
    expect(summary["score_stats"][:avg]).to eq(15.0)
  end

  it "returns unique values for a column" do
    storage.append("data", {"lang" => "ruby"})
    storage.append("data", {"lang" => "python"})
    storage.append("data", {"lang" => "ruby"})

    expect(storage.unique_values("data", :lang).sort).to eq(%w[python ruby])
  end

  it "handles delete and exists? checks" do
    storage.append("data", {"name" => "Alice"})
    expect(storage.exists?("data")).to be true
    storage.delete("data")
    expect(storage.exists?("data")).to be false
  end

  it "lists stored csv files" do
    storage.append("data", {"name" => "Alice"})
    expect(storage.list).to include("data")
  end

  it "falls back when base_dir is root" do
    storage = described_class.new(File::SEPARATOR)
    expect(storage.list).to be_a(Array)
  end
end
