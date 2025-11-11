# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/provider_metrics"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Harness::ProviderMetrics do
  let(:project_dir) { Dir.mktmpdir }
  let(:metrics) { described_class.new(project_dir) }

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#initialize" do
    it "sets project_dir" do
      expect(metrics.project_dir).to eq(project_dir)
    end

    it "sets metrics_file path" do
      expected_path = File.join(project_dir, ".aidp", "provider_metrics.yml")
      expect(metrics.metrics_file).to eq(expected_path)
    end

    it "sets rate_limit_file path" do
      expected_path = File.join(project_dir, ".aidp", "provider_rate_limits.yml")
      expect(metrics.rate_limit_file).to eq(expected_path)
    end

    it "creates .aidp directory" do
      # After initialization, the directory should exist
      aidp_dir = File.join(project_dir, ".aidp")
      described_class.new(project_dir)
      expect(File.directory?(aidp_dir)).to be true
    end

    it "does not fail if .aidp directory already exists" do
      aidp_dir = File.join(project_dir, ".aidp")
      FileUtils.mkdir_p(aidp_dir)

      expect { described_class.new(project_dir) }.not_to raise_error
    end
  end

  describe "#save_metrics" do
    it "saves metrics hash to YAML file" do
      metrics_hash = {
        "anthropic" => {
          total_calls: 10,
          successful_calls: 8,
          failed_calls: 2
        }
      }

      metrics.save_metrics(metrics_hash)

      expect(File.exist?(metrics.metrics_file)).to be true
      loaded = YAML.load_file(metrics.metrics_file)
      expect(loaded["anthropic"][:total_calls]).to eq(10)
      expect(loaded["anthropic"][:successful_calls]).to eq(8)
    end

    it "converts Time objects to ISO8601 strings" do
      now = Time.now
      metrics_hash = {
        "anthropic" => {
          last_used: now,
          total_calls: 5
        }
      }

      metrics.save_metrics(metrics_hash)

      loaded = YAML.load_file(metrics.metrics_file)
      expect(loaded["anthropic"][:last_used]).to be_a(String)
      expect(loaded["anthropic"][:last_used]).to eq(now.iso8601)
    end

    it "handles nested Time objects in provider metrics" do
      now = Time.now
      metrics_hash = {
        "gemini" => {
          last_error_at: now,
          counters: {
            total: 10
          }
        }
      }

      metrics.save_metrics(metrics_hash)

      loaded = YAML.load_file(metrics.metrics_file)
      expect(loaded["gemini"][:last_error_at]).to eq(now.iso8601)
      expect(loaded["gemini"][:counters]).to eq({total: 10})
    end

    it "returns early if metrics_hash is nil" do
      expect { metrics.save_metrics(nil) }.not_to raise_error
      expect(File.exist?(metrics.metrics_file)).to be false
    end

    it "returns early if metrics_hash is empty" do
      expect { metrics.save_metrics({}) }.not_to raise_error
      expect(File.exist?(metrics.metrics_file)).to be false
    end

    it "handles write errors gracefully" do
      # Make directory read-only to force write error
      allow(File).to receive(:write).with(metrics.metrics_file, anything).and_raise(Errno::EACCES)

      expect { metrics.save_metrics({"provider" => {calls: 1}}) }.not_to raise_error
    end

    it "saves non-Time values unchanged" do
      metrics_hash = {
        "cursor" => {
          total_calls: 42,
          average_latency: 1.5,
          provider_name: "Cursor",
          active: true
        }
      }

      metrics.save_metrics(metrics_hash)

      loaded = YAML.load_file(metrics.metrics_file)
      expect(loaded["cursor"][:total_calls]).to eq(42)
      expect(loaded["cursor"][:average_latency]).to eq(1.5)
      expect(loaded["cursor"][:provider_name]).to eq("Cursor")
      expect(loaded["cursor"][:active]).to be true
    end

    it "handles non-hash provider values" do
      metrics_hash = {
        "provider1" => "string_value",
        "provider2" => {calls: 5}
      }

      metrics.save_metrics(metrics_hash)

      loaded = YAML.load_file(metrics.metrics_file)
      expect(loaded["provider1"]).to eq("string_value")
      expect(loaded["provider2"][:calls]).to eq(5)
    end
  end

  describe "#load_metrics" do
    it "returns empty hash if file doesn't exist" do
      expect(metrics.load_metrics).to eq({})
    end

    it "loads metrics from YAML file" do
      metrics_hash = {
        "anthropic" => {
          "total_calls" => 15,
          "failed_calls" => 3
        }
      }
      File.write(metrics.metrics_file, YAML.dump(metrics_hash))

      loaded = metrics.load_metrics

      expect(loaded["anthropic"][:total_calls]).to eq(15)
      expect(loaded["anthropic"][:failed_calls]).to eq(3)
    end

    it "converts ISO8601 strings back to Time objects" do
      now = Time.now
      metrics_hash = {
        "anthropic" => {
          "last_used" => now.iso8601,
          "total_calls" => 5
        }
      }
      File.write(metrics.metrics_file, YAML.dump(metrics_hash))

      loaded = metrics.load_metrics

      expect(loaded["anthropic"][:last_used]).to be_a(Time)
      expect(loaded["anthropic"][:last_used].to_i).to eq(now.to_i)
    end

    it "converts string keys to symbols" do
      metrics_hash = {
        "gemini" => {
          "total_calls" => 10,
          "error_count" => 2
        }
      }
      File.write(metrics.metrics_file, YAML.dump(metrics_hash))

      loaded = metrics.load_metrics

      expect(loaded["gemini"]).to have_key(:total_calls)
      expect(loaded["gemini"]).to have_key(:error_count)
    end

    it "handles non-hash values in loaded data" do
      metrics_hash = {
        "provider1" => "string_value",
        "provider2" => {
          "calls" => 5
        }
      }
      File.write(metrics.metrics_file, YAML.dump(metrics_hash))

      loaded = metrics.load_metrics

      expect(loaded["provider1"]).to eq("string_value")
      expect(loaded["provider2"][:calls]).to eq(5)
    end

    it "returns empty hash if YAML data is not a hash" do
      File.write(metrics.metrics_file, YAML.dump(["not", "a", "hash"]))

      expect(metrics.load_metrics).to eq({})
    end

    it "handles YAML parse errors gracefully" do
      File.write(metrics.metrics_file, "invalid: yaml: content:")

      expect { metrics.load_metrics }.not_to raise_error
      expect(metrics.load_metrics).to eq({})
    end

    it "handles read errors gracefully" do
      File.write(metrics.metrics_file, YAML.dump({"test" => {}}))
      allow(YAML).to receive(:safe_load_file).and_raise(Errno::EACCES)

      expect { metrics.load_metrics }.not_to raise_error
      expect(metrics.load_metrics).to eq({})
    end

    it "preserves non-timestamp string values" do
      metrics_hash = {
        "cursor" => {
          "provider_name" => "Cursor AI",
          "status" => "active"  # Use non-date string
        }
      }
      File.write(metrics.metrics_file, YAML.dump(metrics_hash))

      loaded = metrics.load_metrics

      expect(loaded["cursor"][:provider_name]).to eq("Cursor AI")
      expect(loaded["cursor"][:status]).to eq("active")
    end

    it "handles invalid timestamp strings" do
      metrics_hash = {
        "provider" => {
          "invalid_time" => "not-a-timestamp",
          "calls" => 5
        }
      }
      File.write(metrics.metrics_file, YAML.dump(metrics_hash))

      loaded = metrics.load_metrics

      expect(loaded["provider"][:invalid_time]).to eq("not-a-timestamp")
      expect(loaded["provider"][:calls]).to eq(5)
    end
  end

  describe "#save_rate_limits" do
    it "saves rate limit hash to YAML file" do
      rate_limits = {
        "anthropic" => {
          requests_remaining: 100,
          reset_at: Time.now + 3600
        }
      }

      metrics.save_rate_limits(rate_limits)

      expect(File.exist?(metrics.rate_limit_file)).to be true
      loaded = YAML.load_file(metrics.rate_limit_file)
      expect(loaded["anthropic"][:requests_remaining]).to eq(100)
    end

    it "converts Time objects to ISO8601 strings" do
      reset_time = Time.now + 3600
      rate_limits = {
        "gemini" => {
          reset_at: reset_time,
          limit: 60
        }
      }

      metrics.save_rate_limits(rate_limits)

      loaded = YAML.load_file(metrics.rate_limit_file)
      expect(loaded["gemini"][:reset_at]).to eq(reset_time.iso8601)
      expect(loaded["gemini"][:limit]).to eq(60)
    end

    it "returns early if rate_limit_hash is nil" do
      expect { metrics.save_rate_limits(nil) }.not_to raise_error
      expect(File.exist?(metrics.rate_limit_file)).to be false
    end

    it "returns early if rate_limit_hash is empty" do
      expect { metrics.save_rate_limits({}) }.not_to raise_error
      expect(File.exist?(metrics.rate_limit_file)).to be false
    end

    it "handles write errors gracefully" do
      allow(File).to receive(:write).with(metrics.rate_limit_file, anything).and_raise(Errno::EACCES)

      expect { metrics.save_rate_limits({"provider" => {limit: 100}}) }.not_to raise_error
    end

    it "handles non-hash limit info values" do
      rate_limits = {
        "provider1" => 100,
        "provider2" => {
          reset_at: Time.now,
          limit: 60
        }
      }

      metrics.save_rate_limits(rate_limits)

      loaded = YAML.load_file(metrics.rate_limit_file)
      expect(loaded["provider1"]).to eq(100)
      expect(loaded["provider2"][:limit]).to eq(60)
    end
  end

  describe "#load_rate_limits" do
    it "returns empty hash if file doesn't exist" do
      expect(metrics.load_rate_limits).to eq({})
    end

    it "loads rate limits from YAML file" do
      rate_limits = {
        "anthropic" => {
          "requests_remaining" => 50,
          "limit" => 100
        }
      }
      File.write(metrics.rate_limit_file, YAML.dump(rate_limits))

      loaded = metrics.load_rate_limits

      expect(loaded["anthropic"][:requests_remaining]).to eq(50)
      expect(loaded["anthropic"][:limit]).to eq(100)
    end

    it "converts ISO8601 strings back to Time objects" do
      reset_time = Time.now + 1800
      rate_limits = {
        "gemini" => {
          "reset_at" => reset_time.iso8601,
          "limit" => 60
        }
      }
      File.write(metrics.rate_limit_file, YAML.dump(rate_limits))

      loaded = metrics.load_rate_limits

      expect(loaded["gemini"][:reset_at]).to be_a(Time)
      expect(loaded["gemini"][:reset_at].to_i).to eq(reset_time.to_i)
    end

    it "converts string keys to symbols" do
      rate_limits = {
        "cursor" => {
          "requests_remaining" => 200,
          "tokens_remaining" => 50000
        }
      }
      File.write(metrics.rate_limit_file, YAML.dump(rate_limits))

      loaded = metrics.load_rate_limits

      expect(loaded["cursor"]).to have_key(:requests_remaining)
      expect(loaded["cursor"]).to have_key(:tokens_remaining)
    end

    it "handles non-hash values in loaded data" do
      rate_limits = {
        "provider1" => 100,
        "provider2" => {
          "limit" => 60
        }
      }
      File.write(metrics.rate_limit_file, YAML.dump(rate_limits))

      loaded = metrics.load_rate_limits

      expect(loaded["provider1"]).to eq(100)
      expect(loaded["provider2"][:limit]).to eq(60)
    end

    it "returns empty hash if YAML data is not a hash" do
      File.write(metrics.rate_limit_file, YAML.dump([1, 2, 3]))

      expect(metrics.load_rate_limits).to eq({})
    end

    it "handles YAML parse errors gracefully" do
      File.write(metrics.rate_limit_file, "bad yaml content {")

      expect { metrics.load_rate_limits }.not_to raise_error
      expect(metrics.load_rate_limits).to eq({})
    end

    it "handles read errors gracefully" do
      File.write(metrics.rate_limit_file, YAML.dump({"test" => {}}))
      allow(YAML).to receive(:safe_load_file).and_raise(StandardError.new("read error"))

      expect { metrics.load_rate_limits }.not_to raise_error
      expect(metrics.load_rate_limits).to eq({})
    end
  end

  describe "#clear" do
    it "deletes metrics file if it exists" do
      metrics.save_metrics({"provider" => {calls: 1}})
      expect(File.exist?(metrics.metrics_file)).to be true

      metrics.clear

      expect(File.exist?(metrics.metrics_file)).to be false
    end

    it "deletes rate limit file if it exists" do
      metrics.save_rate_limits({"provider" => {limit: 100}})
      expect(File.exist?(metrics.rate_limit_file)).to be true

      metrics.clear

      expect(File.exist?(metrics.rate_limit_file)).to be false
    end

    it "does not fail if metrics file doesn't exist" do
      expect { metrics.clear }.not_to raise_error
    end

    it "does not fail if rate limit file doesn't exist" do
      expect { metrics.clear }.not_to raise_error
    end

    it "deletes both files when both exist" do
      metrics.save_metrics({"provider" => {calls: 1}})
      metrics.save_rate_limits({"provider" => {limit: 100}})

      metrics.clear

      expect(File.exist?(metrics.metrics_file)).to be false
      expect(File.exist?(metrics.rate_limit_file)).to be false
    end
  end

  describe "round-trip serialization" do
    it "preserves metrics data through save and load cycle" do
      now = Time.now
      original = {
        "anthropic" => {
          total_calls: 25,
          successful_calls: 20,
          failed_calls: 5,
          last_used: now,
          average_latency: 1.234,
          active: true
        },
        "gemini" => {
          total_calls: 10,
          error_count: 0,
          last_error_at: nil
        }
      }

      metrics.save_metrics(original)
      loaded = metrics.load_metrics

      expect(loaded["anthropic"][:total_calls]).to eq(25)
      expect(loaded["anthropic"][:successful_calls]).to eq(20)
      expect(loaded["anthropic"][:failed_calls]).to eq(5)
      expect(loaded["anthropic"][:last_used].to_i).to eq(now.to_i)
      expect(loaded["anthropic"][:average_latency]).to eq(1.234)
      expect(loaded["anthropic"][:active]).to be true

      expect(loaded["gemini"][:total_calls]).to eq(10)
      expect(loaded["gemini"][:error_count]).to eq(0)
    end

    it "preserves rate limit data through save and load cycle" do
      reset_time = Time.now + 7200
      original = {
        "anthropic" => {
          requests_remaining: 95,
          reset_at: reset_time,
          limit: 100,
          window: 60
        },
        "cursor" => {
          requests_remaining: 500,
          limit: 1000
        }
      }

      metrics.save_rate_limits(original)
      loaded = metrics.load_rate_limits

      expect(loaded["anthropic"][:requests_remaining]).to eq(95)
      expect(loaded["anthropic"][:reset_at].to_i).to eq(reset_time.to_i)
      expect(loaded["anthropic"][:limit]).to eq(100)
      expect(loaded["anthropic"][:window]).to eq(60)

      expect(loaded["cursor"][:requests_remaining]).to eq(500)
      expect(loaded["cursor"][:limit]).to eq(1000)
    end
  end

  describe "concurrent access" do
    it "handles multiple save operations" do
      metrics.save_metrics({"provider1" => {calls: 1}})
      metrics.save_metrics({"provider2" => {calls: 2}})

      loaded = metrics.load_metrics
      expect(loaded["provider2"][:calls]).to eq(2)
    end

    it "handles save and load operations in sequence" do
      metrics.save_metrics({"provider" => {calls: 5}})
      first_load = metrics.load_metrics

      metrics.save_metrics({"provider" => {calls: 10}})
      second_load = metrics.load_metrics

      expect(first_load["provider"][:calls]).to eq(5)
      expect(second_load["provider"][:calls]).to eq(10)
    end
  end
end
