# frozen_string_literal: true

RSpec.describe Aidp::Concurrency::Backoff do
  let(:config) { Aidp::Concurrency.configuration }

  before do
    # Reset configuration and disable logging for tests
    Aidp::Concurrency.configuration = Aidp::Concurrency::Configuration.new
    config.log_retries = false
  end

  describe ".retry" do
    it "returns result on first successful attempt" do
      result = described_class.retry(max_attempts: 3) { "success" }
      expect(result).to eq("success")
    end

    it "retries on failure and eventually succeeds" do
      attempt = 0
      result = described_class.retry(max_attempts: 5, base: 0.01) do
        attempt += 1
        raise StandardError, "fail" if attempt < 3
        "success"
      end

      expect(result).to eq("success")
      expect(attempt).to eq(3)
    end

    it "raises MaxAttemptsError after exhausting retries" do
      attempt = 0
      expect {
        described_class.retry(max_attempts: 3, base: 0.01) do
          attempt += 1
          raise StandardError, "persistent failure"
        end
      }.to raise_error(Aidp::Concurrency::MaxAttemptsError, /Max attempts \(3\) exceeded/)

      expect(attempt).to eq(3)
    end

    it "only retries specified exception classes" do
      attempt = 0
      expect {
        described_class.retry(max_attempts: 3, base: 0.01, on: [ArgumentError]) do
          attempt += 1
          raise StandardError, "wrong exception"
        end
      }.to raise_error(StandardError, /wrong exception/)

      expect(attempt).to eq(1) # Should not retry
    end

    it "retries multiple exception classes" do
      attempt = 0
      result = described_class.retry(max_attempts: 5, base: 0.01, on: [ArgumentError, RuntimeError]) do
        attempt += 1
        case attempt
        when 1
          raise ArgumentError, "arg error"
        when 2
          raise "runtime error"
        else
          "success"
        end
      end

      expect(result).to eq("success")
      expect(attempt).to eq(3)
    end

    it "requires a block" do
      expect {
        described_class.retry(max_attempts: 3)
      }.to raise_error(ArgumentError, /Block required/)
    end

    it "requires max_attempts >= 1" do
      expect {
        described_class.retry(max_attempts: 0) { "test" }
      }.to raise_error(ArgumentError, /max_attempts must be >= 1/)
    end

    it "uses default configuration values" do
      config.default_max_attempts = 3
      config.default_backoff_base = 0.01

      attempt = 0
      expect {
        described_class.retry {
          attempt += 1
          raise StandardError
        }
      }.to raise_error(Aidp::Concurrency::MaxAttemptsError)

      expect(attempt).to eq(3)
    end
  end

  describe ".calculate_delay" do
    it "calculates exponential backoff" do
      delays = (1..5).map { |i| described_class.calculate_delay(i, :exponential, 1.0, 100, 0) }
      expect(delays).to eq([1.0, 2.0, 4.0, 8.0, 16.0])
    end

    it "calculates linear backoff" do
      delays = (1..5).map { |i| described_class.calculate_delay(i, :linear, 1.0, 100, 0) }
      expect(delays).to eq([1.0, 2.0, 3.0, 4.0, 5.0])
    end

    it "calculates constant backoff" do
      delays = (1..5).map { |i| described_class.calculate_delay(i, :constant, 2.0, 100, 0) }
      expect(delays).to all(eq(2.0))
    end

    it "caps delay at max_delay" do
      delay = described_class.calculate_delay(10, :exponential, 1.0, 5.0, 0)
      expect(delay).to eq(5.0)
    end

    it "applies jitter to reduce delay" do
      # With jitter, delay should be reduced by 0-20%
      delays = (1..20).map { described_class.calculate_delay(3, :exponential, 1.0, 100, 0.2) }

      delays.each do |delay|
        expect(delay).to be >= 3.2 # 4.0 * (1 - 0.2)
        expect(delay).to be <= 4.0
      end
    end

    it "handles zero jitter" do
      delay = described_class.calculate_delay(3, :exponential, 1.0, 100, 0)
      expect(delay).to eq(4.0)
    end

    it "raises on unknown strategy" do
      expect {
        described_class.calculate_delay(1, :unknown, 1.0, 100, 0)
      }.to raise_error(ArgumentError, /Unknown strategy/)
    end
  end

  describe "backoff timing" do
    it "actually waits between retries" do
      attempt = 0
      start_time = Time.now

      begin
        described_class.retry(max_attempts: 3, base: 0.1, jitter: 0, strategy: :constant) do
          attempt += 1
          raise StandardError, "fail"
        end
      rescue Aidp::Concurrency::MaxAttemptsError
        # Expected
      end

      elapsed = Time.now - start_time

      # Should have waited ~0.2s (2 retries * 0.1s each)
      # Allow some tolerance for execution time
      expect(elapsed).to be >= 0.18
      expect(elapsed).to be < 0.5
    end
  end
end
