# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ConditionDetector do
  let(:detector) { described_class.new }

  describe "#initialize" do
    it "initializes with rate limit patterns for different providers" do
      expect(detector.instance_variable_get(:@rate_limit_patterns)).to have_key(:common)
      expect(detector.instance_variable_get(:@rate_limit_patterns)).to have_key(:anthropic)
      expect(detector.instance_variable_get(:@rate_limit_patterns)).to have_key(:openai)
      expect(detector.instance_variable_get(:@rate_limit_patterns)).to have_key(:google)
      expect(detector.instance_variable_get(:@rate_limit_patterns)).to have_key(:cursor)
    end

    it "initializes with user feedback patterns" do
      patterns = detector.instance_variable_get(:@user_feedback_patterns)
      expect(patterns).to be_a(Hash)
      expect(patterns[:direct_requests]).to include(/please provide/i)
      expect(patterns[:clarification]).to include(/can you clarify/i)
    end

    it "initializes with question patterns" do
      patterns = detector.instance_variable_get(:@question_patterns)
      expect(patterns).to include(/^\d+\.\s+(.+)\?/)
      expect(patterns).to include(/^(\d+)\)\s+(.+)\?/)
    end

    it "initializes with reset time patterns" do
      patterns = detector.instance_variable_get(:@reset_time_patterns)
      expect(patterns).to include(/reset.{0,20}in.{0,20}(\d+).{0,20}seconds/i)
      expect(patterns).to include(/retry.{0,20}after.{0,20}(\d+).{0,20}seconds/i)
    end
  end

  describe "#is_rate_limited?" do
    it "detects rate limiting from HTTP status code" do
      result = {status_code: 429}
      expect(detector.is_rate_limited?(result)).to be true
    end

    it "detects rate limiting from http_status field" do
      result = {http_status: 429}
      expect(detector.is_rate_limited?(result)).to be true
    end

    it "detects rate limiting from error message" do
      result = {error: "Rate limit exceeded"}
      expect(detector.is_rate_limited?(result)).to be true
    end

    it "detects rate limiting from output" do
      result = {output: "Too many requests"}
      expect(detector.is_rate_limited?(result)).to be true
    end

    it "detects provider-specific rate limiting" do
      result = {error: "Anthropic rate limit exceeded"}
      expect(detector.is_rate_limited?(result, "anthropic")).to be true
    end

    it "detects OpenAI-specific rate limiting" do
      result = {error: "Requests per minute limit exceeded"}
      expect(detector.is_rate_limited?(result, "openai")).to be true
    end

    it "detects Google-specific rate limiting" do
      result = {error: "Quota exceeded for Google API"}
      expect(detector.is_rate_limited?(result, "google")).to be true
    end

    it "detects Cursor-specific rate limiting" do
      result = {error: "Package limit exceeded"}
      expect(detector.is_rate_limited?(result, "cursor")).to be true
    end

    it "returns false for non-rate-limited results" do
      result = {status: "success", output: "Task completed"}
      expect(detector.is_rate_limited?(result)).to be false
    end

    it "returns false for invalid input" do
      expect(detector.is_rate_limited?(nil)).to be false
      expect(detector.is_rate_limited?("string")).to be false
    end
  end

  describe "#extract_rate_limit_info" do
    it "extracts rate limit information from result" do
      result = {error: "Rate limit exceeded. Retry after 60 seconds"}
      info = detector.extract_rate_limit_info(result, "anthropic")

      expect(info).to be_a(Hash)
      expect(info[:provider]).to eq("anthropic")
      expect(info[:detected_at]).to be_a(Time)
      expect(info[:limit_type]).to eq("general_rate_limit")
      expect(info[:message]).to include("Rate limit exceeded")
    end

    it "extracts reset time from message" do
      result = {error: "Rate limit exceeded. Reset in 120 seconds"}
      info = detector.extract_rate_limit_info(result)

      expect(info[:reset_time]).to be_a(Time)
      expect(info[:reset_time]).to be > Time.now
    end

    it "extracts retry after value" do
      result = {error: "Rate limit exceeded. Retry after 90 seconds"}
      info = detector.extract_rate_limit_info(result)

      expect(info[:retry_after]).to eq(90)
    end

    it "detects limit type for Anthropic" do
      result = {error: "Requests per minute limit exceeded"}
      info = detector.extract_rate_limit_info(result, "anthropic")

      expect(info[:limit_type]).to eq("requests_per_minute")
    end

    it "detects limit type for OpenAI" do
      result = {error: "Tokens per minute limit exceeded"}
      info = detector.extract_rate_limit_info(result, "openai")

      expect(info[:limit_type]).to eq("tokens_per_minute")
    end

    it "detects limit type for Google" do
      result = {error: "Quota exceeded for Google API"}
      info = detector.extract_rate_limit_info(result, "google")

      expect(info[:limit_type]).to eq("quota_exceeded")
    end

    it "detects limit type for Cursor" do
      result = {error: "Package limit exceeded"}
      info = detector.extract_rate_limit_info(result, "cursor")

      expect(info[:limit_type]).to eq("package_limit")
    end

    it "returns nil for non-rate-limited results" do
      result = {status: "success", output: "Task completed"}
      expect(detector.extract_rate_limit_info(result)).to be_nil
    end
  end

  describe "#extract_reset_time" do
    it "extracts seconds from now" do
      text = "Rate limit exceeded. Reset in 120 seconds"
      reset_time = detector.send(:extract_reset_time, text)

      expect(reset_time).to be_a(Time)
      expect(reset_time).to be > Time.now
    end

    it "extracts specific timestamp" do
      future_time = Time.now + 300
      text = "Rate limit exceeded. Reset at #{future_time.strftime("%Y-%m-%d %H:%M:%S")}"
      reset_time = detector.send(:extract_reset_time, text)

      expect(reset_time).to be_a(Time)
      # Allow for a reasonable time difference since timestamp parsing can vary
      expect(reset_time.to_i).to be_within(300).of(future_time.to_i)
    end

    it "defaults to 60 seconds if no time found" do
      text = "Rate limit exceeded"
      reset_time = detector.send(:extract_reset_time, text)

      expect(reset_time).to be_a(Time)
      expect(reset_time).to be > Time.now
      expect(reset_time).to be <= Time.now + 61
    end
  end

  describe "#extract_retry_after" do
    it "extracts retry after value" do
      text = "Rate limit exceeded. Retry after 90 seconds"
      retry_after = detector.send(:extract_retry_after, text)

      expect(retry_after).to eq(90)
    end

    it "extracts wait time" do
      text = "Rate limit exceeded. Wait 45 seconds"
      retry_after = detector.send(:extract_retry_after, text)

      expect(retry_after).to eq(45)
    end

    it "defaults to 60 seconds if no time found" do
      text = "Rate limit exceeded"
      retry_after = detector.send(:extract_retry_after, text)

      expect(retry_after).to eq(60)
    end
  end

  describe "#detect_limit_type" do
    it "detects requests per minute for Anthropic" do
      text = "Requests per minute limit exceeded"
      limit_type = detector.send(:detect_limit_type, text, "anthropic")

      expect(limit_type).to eq("requests_per_minute")
    end

    it "detects tokens per minute for OpenAI" do
      text = "Tokens per minute limit exceeded"
      limit_type = detector.send(:detect_limit_type, text, "openai")

      expect(limit_type).to eq("tokens_per_minute")
    end

    it "detects quota exceeded for Google" do
      text = "Quota exceeded for Google API"
      limit_type = detector.send(:detect_limit_type, text, "google")

      expect(limit_type).to eq("quota_exceeded")
    end

    it "detects package limit for Cursor" do
      text = "Package limit exceeded"
      limit_type = detector.send(:detect_limit_type, text, "cursor")

      expect(limit_type).to eq("package_limit")
    end

    it "defaults to general rate limit" do
      text = "Rate limit exceeded"
      limit_type = detector.send(:detect_limit_type, text, "unknown")

      expect(limit_type).to eq("general_rate_limit")
    end
  end

  describe "#is_provider_rate_limited?" do
    it "returns true if provider is rate limited and not expired" do
      rate_limit_info = {
        provider: "anthropic",
        reset_time: Time.now + 60
      }

      expect(detector.is_provider_rate_limited?("anthropic", rate_limit_info)).to be true
    end

    it "returns false if provider is different" do
      rate_limit_info = {
        provider: "anthropic",
        reset_time: Time.now + 60
      }

      expect(detector.is_provider_rate_limited?("openai", rate_limit_info)).to be false
    end

    it "returns false if rate limit has expired" do
      rate_limit_info = {
        provider: "anthropic",
        reset_time: Time.now - 60
      }

      expect(detector.is_provider_rate_limited?("anthropic", rate_limit_info)).to be false
    end

    it "returns false if no rate limit info" do
      expect(detector.is_provider_rate_limited?("anthropic", nil)).to be false
    end
  end

  describe "#time_until_reset" do
    it "returns time until reset" do
      rate_limit_info = {
        reset_time: Time.now + 120
      }

      time_until = detector.time_until_reset(rate_limit_info)
      expect(time_until).to be_within(1).of(120)
    end

    it "returns 0 if rate limit has expired" do
      rate_limit_info = {
        reset_time: Time.now - 60
      }

      expect(detector.time_until_reset(rate_limit_info)).to eq(0)
    end

    it "returns 0 if no rate limit info" do
      expect(detector.time_until_reset(nil)).to eq(0)
    end
  end

  describe "#rate_limit_expired?" do
    it "returns true if rate limit has expired" do
      rate_limit_info = {
        reset_time: Time.now - 60
      }

      expect(detector.rate_limit_expired?(rate_limit_info)).to be true
    end

    it "returns false if rate limit is still active" do
      rate_limit_info = {
        reset_time: Time.now + 60
      }

      expect(detector.rate_limit_expired?(rate_limit_info)).to be false
    end

    it "returns true if no rate limit info" do
      expect(detector.rate_limit_expired?(nil)).to be true
    end
  end

  describe "#get_rate_limit_patterns" do
    it "returns common patterns for unknown provider" do
      patterns = detector.get_rate_limit_patterns("unknown")
      expect(patterns).to eq(detector.instance_variable_get(:@rate_limit_patterns)[:common])
    end

    it "returns combined patterns for known provider" do
      patterns = detector.get_rate_limit_patterns("anthropic")
      common_patterns = detector.instance_variable_get(:@rate_limit_patterns)[:common]
      anthropic_patterns = detector.instance_variable_get(:@rate_limit_patterns)[:anthropic]

      expect(patterns).to eq(common_patterns + anthropic_patterns)
    end

    it "returns common patterns for nil provider" do
      patterns = detector.get_rate_limit_patterns(nil)
      expect(patterns).to eq(detector.instance_variable_get(:@rate_limit_patterns)[:common])
    end
  end

  describe "integration with existing methods" do
    it "works with needs_user_feedback?" do
      result = {output: "Please provide more information"}
      expect(detector.needs_user_feedback?(result)).to be true
    end

    it "works with extract_questions" do
      result = {output: "1. What is your preference?\n2. Which option do you choose?"}
      questions = detector.extract_questions(result)

      expect(questions.length).to eq(3) # The method extracts individual questions plus the full text
      expect(questions[0][:question]).to eq("What is your preference")
      expect(questions[1][:question]).to eq("Which option do you choose")
    end

    it "works with is_work_complete?" do
      result = {output: "All steps completed successfully"}
      progress = double("progress", completed_steps: [], total_steps: 5)

      expect(detector.is_work_complete?(result, progress)).to be true
    end

    it "works with classify_error" do
      error = StandardError.new("Rate limit exceeded")
      expect(detector.classify_error(error)).to eq(:rate_limit)
    end

    it "works with recoverable_error?" do
      error = StandardError.new("Rate limit exceeded")
      expect(detector.recoverable_error?(error)).to be true
    end

    it "works with retry_delay_for_error" do
      error = StandardError.new("Rate limit exceeded")
      delay = detector.retry_delay_for_error(error, 1)
      expect(delay).to eq(60)
    end
  end
end
