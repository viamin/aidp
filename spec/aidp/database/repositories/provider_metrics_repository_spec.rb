# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Repositories::ProviderMetricsRepository do
  let(:temp_dir) { Dir.mktmpdir("aidp_metrics_repo_test")}
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

  describe "#save_metrics and #load_metrics" do
    it "saves and loads metrics" do
      repository.save_metrics("openai", {success_count: 10, error_count: 1, avg_latency: 500.5})

      metrics = repository.load_metrics

      expect(metrics["openai"][:success_count]).to eq(10.0)
      expect(metrics["openai"][:error_count]).to eq(1.0)
    end
  end

  describe "#load_provider_metrics" do
    it "loads metrics for specific provider" do
      repository.save_metrics("anthropic", {success_count: 5})
      repository.save_metrics("openai", {success_count: 10})

      metrics = repository.load_provider_metrics("anthropic")

      expect(metrics[:success_count]).to eq(5.0)
    end
  end

  describe "#save_rate_limits and #load_rate_limits" do
    it "saves and loads rate limits" do
      reset_time = Time.now + 3600

      repository.save_rate_limits("openai", {
        requests: {limit: 1000, remaining: 500, reset_at: reset_time}
     })

      limits = repository.load_rate_limits

      expect(limits["openai"][:requests][:limit]).to eq(1000)
      expect(limits["openai"][:requests][:remaining]).to eq(500)
    end
  end

  describe "#clear" do
    it "clears all data" do
      repository.save_metrics("test", {count: 1})
      repository.save_rate_limits("test", {x: {limit: 10, remaining: 5 }})

      repository.clear

      expect(repository.load_metrics).to be_empty
      expect(repository.load_rate_limits).to be_empty
    end
  end

  describe "#metrics_history" do
    it "returns historical values" do
      3.times do |i|
        repository.save_metrics("provider", {latency: i * 100})
      end

      history = repository.metrics_history("provider", "latency")

      expect(history.size).to eq(3)
    end
  end
end
