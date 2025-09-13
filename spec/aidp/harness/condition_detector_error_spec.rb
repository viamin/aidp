# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ConditionDetector do
  let(:detector) { described_class.new }

  describe "error classification system" do
    describe "#classify_error" do
      it "classifies timeout errors" do
        error = StandardError.new("Request timeout")
        expect(detector.classify_error(error)).to eq(:timeout)
      end

      it "classifies network errors" do
        error = StandardError.new("Network connection failed")
        expect(detector.classify_error(error)).to eq(:network)
      end

      it "classifies DNS resolution errors" do
        error = StandardError.new("DNS resolution failed")
        expect(detector.classify_error(error)).to eq(:dns_resolution)
      end

      it "classifies SSL/TLS errors" do
        error = StandardError.new("SSL certificate error")
        expect(detector.classify_error(error)).to eq(:ssl_tls)
      end

      it "classifies authentication errors" do
        error = StandardError.new("Authentication failed")
        expect(detector.classify_error(error)).to eq(:authentication)
      end

      it "classifies permission errors" do
        error = StandardError.new("Permission denied")
        expect(detector.classify_error(error)).to eq(:permission)
      end

      it "classifies access denied errors" do
        error = StandardError.new("Access denied")
        expect(detector.classify_error(error)).to eq(:access_denied)
      end

      it "classifies not found errors" do
        error = StandardError.new("Resource not found")
        expect(detector.classify_error(error)).to eq(:not_found)
      end

      it "classifies server errors" do
        error = StandardError.new("Internal server error")
        expect(detector.classify_error(error)).to eq(:server_error)
      end

      it "classifies bad request errors" do
        error = StandardError.new("Bad request")
        expect(detector.classify_error(error)).to eq(:bad_request)
      end

      it "classifies rate limit errors" do
        error = StandardError.new("Rate limit exceeded")
        expect(detector.classify_error(error)).to eq(:rate_limit)
      end

      it "classifies quota exceeded errors" do
        error = StandardError.new("Quota exceeded")
        expect(detector.classify_error(error)).to eq(:quota_exceeded)
      end

      it "classifies file not found errors" do
        error = StandardError.new("File not found")
        expect(detector.classify_error(error)).to eq(:file_not_found)
      end

      it "classifies file permission errors" do
        error = StandardError.new("Permission denied")
        expect(detector.classify_error(error)).to eq(:permission)
      end

      it "classifies disk full errors" do
        error = StandardError.new("Disk full")
        expect(detector.classify_error(error)).to eq(:disk_full)
      end

      it "classifies memory errors" do
        error = StandardError.new("Out of memory")
        expect(detector.classify_error(error)).to eq(:memory_error)
      end

      it "classifies configuration errors" do
        error = StandardError.new("Configuration error")
        expect(detector.classify_error(error)).to eq(:configuration)
      end

      it "classifies missing dependency errors" do
        error = StandardError.new("Missing dependency")
        expect(detector.classify_error(error)).to eq(:missing_dependency)
      end

      it "classifies provider-specific errors" do
        error = StandardError.new("Anthropic API error")
        expect(detector.classify_error(error)).to eq(:anthropic_error)
      end

      it "classifies parsing errors" do
        error = StandardError.new("JSON parsing error")
        expect(detector.classify_error(error)).to eq(:parsing_error)
      end

      it "classifies validation errors" do
        error = StandardError.new("Validation error")
        expect(detector.classify_error(error)).to eq(:validation_error)
      end

      it "classifies system errors" do
        error = StandardError.new("System error")
        expect(detector.classify_error(error)).to eq(:system_error)
      end

      it "classifies interrupted errors" do
        error = StandardError.new("Operation interrupted")
        expect(detector.classify_error(error)).to eq(:interrupted)
      end

      it "returns unknown for unrecognized errors" do
        error = StandardError.new("Some random error")
        expect(detector.classify_error(error)).to eq(:unknown)
      end

      it "returns unknown for non-StandardError objects" do
        expect(detector.classify_error("string")).to eq(:unknown)
        expect(detector.classify_error(nil)).to eq(:unknown)
      end
    end

    describe "#extract_error_info" do
      it "extracts comprehensive error information" do
        error = StandardError.new("Rate limit exceeded")
        info = detector.extract_error_info(error)

        expect(info).to be_a(Hash)
        expect(info[:type]).to eq(:rate_limit)
        expect(info[:severity]).to eq(:high)
        expect(info[:recoverable]).to be true
        expect(info[:retry_strategy]).to be_a(Hash)
        expect(info[:message]).to eq("Rate limit exceeded")
        expect(info[:class]).to eq("StandardError")
        expect(info[:backtrace]).to be_nil
      end

      it "extracts backtrace information" do
        raise StandardError.new("Test error")
      rescue => error
        info = detector.extract_error_info(error)
        expect(info[:backtrace]).to be_an(Array)
        expect(info[:backtrace].length).to be <= 5
      end

      it "handles non-StandardError objects" do
        info = detector.extract_error_info("string")
        expect(info[:type]).to eq(:unknown)
        expect(info[:severity]).to eq(:low)
        expect(info[:recoverable]).to be true
      end
    end

    describe "#recoverable_error?" do
      it "returns true for recoverable errors" do
        error = StandardError.new("Rate limit exceeded")
        expect(detector.recoverable_error?(error)).to be true
      end

      it "returns false for non-recoverable errors" do
        error = StandardError.new("Authentication failed")
        expect(detector.recoverable_error?(error)).to be false
      end
    end

    describe "#retry_delay_for_error" do
      it "calculates exponential backoff for timeout errors" do
        error = StandardError.new("Request timeout")
        delay1 = detector.retry_delay_for_error(error, 1)
        delay2 = detector.retry_delay_for_error(error, 2)
        delay3 = detector.retry_delay_for_error(error, 3)

        expect(delay1).to eq(5)
        expect(delay2).to eq(10)
        expect(delay3).to eq(20)
      end

      it "returns fixed delay for rate limit errors" do
        error = StandardError.new("Rate limit exceeded")
        delay1 = detector.retry_delay_for_error(error, 1)
        delay2 = detector.retry_delay_for_error(error, 2)

        expect(delay1).to eq(60)
        expect(delay2).to eq(60)
      end

      it "returns 0 for no-retry errors" do
        error = StandardError.new("Authentication failed")
        delay = detector.retry_delay_for_error(error, 1)

        expect(delay).to eq(0)
      end
    end

    describe "#max_retries_for_error" do
      it "returns max retries for timeout errors" do
        error = StandardError.new("Request timeout")
        expect(detector.max_retries_for_error(error)).to eq(3)
      end

      it "returns max retries for rate limit errors" do
        error = StandardError.new("Rate limit exceeded")
        expect(detector.max_retries_for_error(error)).to eq(2)
      end

      it "returns 0 for no-retry errors" do
        error = StandardError.new("Authentication failed")
        expect(detector.max_retries_for_error(error)).to eq(0)
      end
    end

    describe "#get_error_severity" do
      it "returns critical severity for authentication errors" do
        error = StandardError.new("Authentication failed")
        expect(detector.get_error_severity(error)).to eq(:critical)
      end

      it "returns high severity for rate limit errors" do
        error = StandardError.new("Rate limit exceeded")
        expect(detector.get_error_severity(error)).to eq(:high)
      end

      it "returns medium severity for timeout errors" do
        error = StandardError.new("Request timeout")
        expect(detector.get_error_severity(error)).to eq(:medium)
      end

      it "returns low severity for validation errors" do
        error = StandardError.new("Validation error")
        expect(detector.get_error_severity(error)).to eq(:low)
      end
    end

    describe "#critical_error?" do
      it "returns true for critical errors" do
        error = StandardError.new("Authentication failed")
        expect(detector.critical_error?(error)).to be true
      end

      it "returns false for non-critical errors" do
        error = StandardError.new("Rate limit exceeded")
        expect(detector.critical_error?(error)).to be false
      end
    end

    describe "#high_severity_error?" do
      it "returns true for high severity errors" do
        error = StandardError.new("Rate limit exceeded")
        expect(detector.high_severity_error?(error)).to be true
      end

      it "returns true for critical errors" do
        error = StandardError.new("Authentication failed")
        expect(detector.high_severity_error?(error)).to be true
      end

      it "returns false for low severity errors" do
        error = StandardError.new("Validation error")
        expect(detector.high_severity_error?(error)).to be false
      end
    end

    describe "#get_error_description" do
      it "returns description for timeout errors" do
        error = StandardError.new("Request timeout")
        expect(detector.get_error_description(error)).to eq("Request timed out")
      end

      it "returns description for network errors" do
        error = StandardError.new("Network connection failed")
        expect(detector.get_error_description(error)).to eq("Network connection error")
      end

      it "returns description for authentication errors" do
        error = StandardError.new("Authentication failed")
        expect(detector.get_error_description(error)).to eq("Authentication failed")
      end

      it "returns description for rate limit errors" do
        error = StandardError.new("Rate limit exceeded")
        expect(detector.get_error_description(error)).to eq("Rate limit exceeded")
      end

      it "returns description for unknown errors" do
        error = StandardError.new("Some random error")
        expect(detector.get_error_description(error)).to eq("Unknown error")
      end
    end

    describe "#get_error_recovery_suggestions" do
      it "returns suggestions for timeout errors" do
        error = StandardError.new("Request timeout")
        suggestions = detector.get_error_recovery_suggestions(error)

        expect(suggestions).to be_an(Array)
        expect(suggestions).to include("Check network connection")
        expect(suggestions).to include("Retry the operation")
      end

      it "returns suggestions for authentication errors" do
        error = StandardError.new("Authentication failed")
        suggestions = detector.get_error_recovery_suggestions(error)

        expect(suggestions).to be_an(Array)
        expect(suggestions).to include("Check credentials")
        expect(suggestions).to include("Verify permissions")
      end

      it "returns suggestions for rate limit errors" do
        error = StandardError.new("Rate limit exceeded")
        suggestions = detector.get_error_recovery_suggestions(error)

        expect(suggestions).to be_an(Array)
        expect(suggestions).to include("Wait before retrying")
        expect(suggestions).to include("Check usage limits")
      end

      it "returns suggestions for file errors" do
        error = StandardError.new("File not found")
        suggestions = detector.get_error_recovery_suggestions(error)

        expect(suggestions).to be_an(Array)
        expect(suggestions).to include("Check file path")
        expect(suggestions).to include("Verify file permissions")
      end

      it "returns suggestions for configuration errors" do
        error = StandardError.new("Configuration error")
        suggestions = detector.get_error_recovery_suggestions(error)

        expect(suggestions).to be_an(Array)
        expect(suggestions).to include("Check configuration")
        expect(suggestions).to include("Install missing dependencies")
      end

      it "returns suggestions for parsing errors" do
        error = StandardError.new("JSON parsing error")
        suggestions = detector.get_error_recovery_suggestions(error)

        expect(suggestions).to be_an(Array)
        expect(suggestions).to include("Check input format")
        expect(suggestions).to include("Validate parameters")
      end

      it "returns generic suggestions for unknown errors" do
        error = StandardError.new("Some random error")
        suggestions = detector.get_error_recovery_suggestions(error)

        expect(suggestions).to be_an(Array)
        expect(suggestions).to include("Review error details")
        expect(suggestions).to include("Check logs")
      end
    end
  end
end
