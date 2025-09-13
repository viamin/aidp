# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ConditionDetector do
  let(:detector) { described_class.new }

  describe "timeout detection and handling" do
    describe "#is_timeout?" do
      it "detects explicit timeout indicators" do
        start_time = Time.now - 10
        result = {output: "Request timeout occurred"}

        expect(detector.is_timeout?(result, start_time)).to be true
      end

      it "detects duration-based timeout" do
        start_time = Time.now - 130 # 130 seconds ago
        timeout_duration = 120 # 2 minutes
        result = {output: "Some output"}

        expect(detector.is_timeout?(result, start_time, timeout_duration)).to be true
      end

      it "returns false for no timeout" do
        start_time = Time.now - 10
        timeout_duration = 120
        result = {output: "Some output"}

        expect(detector.is_timeout?(result, start_time, timeout_duration)).to be false
      end

      it "returns false for invalid input" do
        expect(detector.is_timeout?(nil, Time.now)).to be false
        expect(detector.is_timeout?({output: "test"}, nil)).to be false
      end
    end

    describe "#has_timeout_indicators?" do
      it "detects timeout patterns" do
        result = {output: "Request timeout occurred"}
        expect(detector.has_timeout_indicators?(result)).to be true
      end

      it "detects timed out patterns" do
        result = {output: "Operation timed out"}
        expect(detector.has_timeout_indicators?(result)).to be true
      end

      it "detects connection timeout patterns" do
        result = {output: "Connection timeout"}
        expect(detector.has_timeout_indicators?(result)).to be true
      end

      it "detects deadline exceeded patterns" do
        result = {output: "Deadline exceeded"}
        expect(detector.has_timeout_indicators?(result)).to be true
      end

      it "detects time limit exceeded patterns" do
        result = {output: "Time limit exceeded"}
        expect(detector.has_timeout_indicators?(result)).to be true
      end

      it "detects time expired patterns" do
        result = {output: "Time expired"}
        expect(detector.has_timeout_indicators?(result)).to be true
      end

      it "returns false for no timeout indicators" do
        result = {output: "Operation completed successfully"}
        expect(detector.has_timeout_indicators?(result)).to be false
      end

      it "returns false for empty result" do
        result = {}
        expect(detector.has_timeout_indicators?(result)).to be false
      end

      it "returns false for invalid input" do
        expect(detector.has_timeout_indicators?(nil)).to be false
      end
    end

    describe "#extract_timeout_info" do
      it "extracts explicit timeout information" do
        start_time = Time.now - 10
        result = {output: "Request timeout occurred"}

        info = detector.extract_timeout_info(result, start_time)

        expect(info[:is_timeout]).to be true
        expect(info[:timeout_type]).to eq("explicit")
        expect(info[:indicators]).to include("timeout")
        expect(info[:duration]).to be_nil
        expect(info[:exceeded_by]).to be_nil
      end

      it "extracts duration-based timeout information" do
        start_time = Time.now - 130
        timeout_duration = 120
        result = {output: "Some output"}

        info = detector.extract_timeout_info(result, start_time, timeout_duration)

        expect(info[:is_timeout]).to be true
        expect(info[:timeout_type]).to eq("duration")
        expect(info[:duration]).to be > 120
        expect(info[:exceeded_by]).to be > 0
        expect(info[:timeout_duration]).to eq(120)
      end

      it "extracts no timeout information" do
        start_time = Time.now - 10
        timeout_duration = 120
        result = {output: "Some output"}

        info = detector.extract_timeout_info(result, start_time, timeout_duration)

        expect(info[:is_timeout]).to be false
        expect(info[:timeout_type]).to be_nil
        expect(info[:duration]).to be < 120
        expect(info[:exceeded_by]).to be_nil
      end

      it "handles invalid input" do
        info = detector.extract_timeout_info(nil, Time.now)

        expect(info[:is_timeout]).to be false
        expect(info[:timeout_type]).to be_nil
      end
    end

    describe "#extract_timeout_indicators" do
      it "extracts timeout indicators" do
        result = {output: "Request timeout occurred"}
        indicators = detector.extract_timeout_indicators(result)

        expect(indicators).to be_an(Array)
        expect(indicators).to include("timeout")
      end

      it "extracts multiple timeout indicators" do
        result = {output: "Request timeout and connection timeout occurred"}
        indicators = detector.extract_timeout_indicators(result)

        expect(indicators).to be_an(Array)
        expect(indicators.length).to be >= 1
      end

      it "returns empty array for no timeout indicators" do
        result = {output: "Operation completed successfully"}
        indicators = detector.extract_timeout_indicators(result)

        expect(indicators).to be_an(Array)
        expect(indicators).to be_empty
      end
    end

    describe "#get_timeout_duration" do
      it "returns default timeout for analyze operation" do
        duration = detector.get_timeout_duration(:analyze)
        expect(duration).to eq(300) # 5 minutes
      end

      it "returns default timeout for execute operation" do
        duration = detector.get_timeout_duration(:execute)
        expect(duration).to eq(600) # 10 minutes
      end

      it "returns default timeout for provider_call operation" do
        duration = detector.get_timeout_duration(:provider_call)
        expect(duration).to eq(120) # 2 minutes
      end

      it "returns default timeout for file_operation" do
        duration = detector.get_timeout_duration(:file_operation)
        expect(duration).to eq(30) # 30 seconds
      end

      it "returns default timeout for network_request" do
        duration = detector.get_timeout_duration(:network_request)
        expect(duration).to eq(60) # 1 minute
      end

      it "returns default timeout for user_input" do
        duration = detector.get_timeout_duration(:user_input)
        expect(duration).to eq(300) # 5 minutes
      end

      it "returns default timeout for unknown operation" do
        duration = detector.get_timeout_duration(:unknown_operation)
        expect(duration).to eq(120) # 2 minutes
      end

      it "returns configured timeout when available" do
        configuration = {
          timeouts: {
            analyze: 600
          }
        }

        duration = detector.get_timeout_duration(:analyze, configuration)
        expect(duration).to eq(600)
      end
    end

    describe "#approaching_timeout?" do
      it "returns true when approaching timeout" do
        start_time = Time.now - 100 # 100 seconds ago
        timeout_duration = 120 # 2 minutes
        warning_threshold = 0.8 # 80%

        expect(detector.approaching_timeout?(start_time, timeout_duration, warning_threshold)).to be true
      end

      it "returns false when not approaching timeout" do
        start_time = Time.now - 10 # 10 seconds ago
        timeout_duration = 120 # 2 minutes
        warning_threshold = 0.8 # 80%

        expect(detector.approaching_timeout?(start_time, timeout_duration, warning_threshold)).to be false
      end

      it "returns false for invalid input" do
        expect(detector.approaching_timeout?(nil, 120)).to be false
        expect(detector.approaching_timeout?(Time.now, nil)).to be false
      end
    end

    describe "#time_until_timeout" do
      it "returns remaining time until timeout" do
        start_time = Time.now - 10 # 10 seconds ago
        timeout_duration = 120 # 2 minutes

        remaining = detector.time_until_timeout(start_time, timeout_duration)
        expect(remaining).to be > 100
        expect(remaining).to be < 120
      end

      it "returns 0 when timeout has passed" do
        start_time = Time.now - 130 # 130 seconds ago
        timeout_duration = 120 # 2 minutes

        remaining = detector.time_until_timeout(start_time, timeout_duration)
        expect(remaining).to eq(0)
      end

      it "returns 0 for invalid input" do
        expect(detector.time_until_timeout(nil, 120)).to eq(0)
        expect(detector.time_until_timeout(Time.now, nil)).to eq(0)
      end
    end

    describe "#get_timeout_status_description" do
      it "returns description for explicit timeout" do
        timeout_info = {
          is_timeout: true,
          timeout_type: "explicit"
        }

        description = detector.get_timeout_status_description(timeout_info)
        expect(description).to eq("Operation timed out (explicit timeout detected)")
      end

      it "returns description for duration timeout with exceeded time" do
        timeout_info = {
          is_timeout: true,
          timeout_type: "duration",
          exceeded_by: 10.5
        }

        description = detector.get_timeout_status_description(timeout_info)
        expect(description).to eq("Operation timed out (exceeded by 10.5s)")
      end

      it "returns description for duration timeout without exceeded time" do
        timeout_info = {
          is_timeout: true,
          timeout_type: "duration"
        }

        description = detector.get_timeout_status_description(timeout_info)
        expect(description).to eq("Operation timed out (duration exceeded)")
      end

      it "returns no timeout for non-timeout" do
        timeout_info = {
          is_timeout: false
        }

        description = detector.get_timeout_status_description(timeout_info)
        expect(description).to eq("No timeout")
      end

      it "returns no timeout for nil info" do
        description = detector.get_timeout_status_description(nil)
        expect(description).to eq("No timeout")
      end
    end

    describe "#get_timeout_recovery_suggestions" do
      it "returns suggestions for explicit timeout" do
        timeout_info = {
          timeout_type: "explicit"
        }

        suggestions = detector.get_timeout_recovery_suggestions(timeout_info)

        expect(suggestions).to be_an(Array)
        expect(suggestions).to include("Check network connection")
        expect(suggestions).to include("Verify service availability")
        expect(suggestions).to include("Retry with longer timeout")
      end

      it "returns suggestions for duration timeout" do
        timeout_info = {
          timeout_type: "duration"
        }

        suggestions = detector.get_timeout_recovery_suggestions(timeout_info)

        expect(suggestions).to be_an(Array)
        expect(suggestions).to include("Increase timeout duration")
        expect(suggestions).to include("Optimize operation performance")
        expect(suggestions).to include("Break operation into smaller chunks")
      end

      it "returns operation-specific suggestions for analyze" do
        timeout_info = {
          timeout_type: "duration"
        }

        suggestions = detector.get_timeout_recovery_suggestions(timeout_info, :analyze)

        expect(suggestions).to include("Reduce analysis scope")
        expect(suggestions).to include("Use incremental analysis")
      end

      it "returns operation-specific suggestions for execute" do
        timeout_info = {
          timeout_type: "duration"
        }

        suggestions = detector.get_timeout_recovery_suggestions(timeout_info, :execute)

        expect(suggestions).to include("Break execution into smaller steps")
        expect(suggestions).to include("Optimize execution performance")
      end

      it "returns operation-specific suggestions for provider_call" do
        timeout_info = {
          timeout_type: "duration"
        }

        suggestions = detector.get_timeout_recovery_suggestions(timeout_info, :provider_call)

        expect(suggestions).to include("Check provider status")
        expect(suggestions).to include("Try different provider")
      end

      it "returns operation-specific suggestions for file_operation" do
        timeout_info = {
          timeout_type: "duration"
        }

        suggestions = detector.get_timeout_recovery_suggestions(timeout_info, :file_operation)

        expect(suggestions).to include("Check file system performance")
        expect(suggestions).to include("Verify file permissions")
      end

      it "returns operation-specific suggestions for network_request" do
        timeout_info = {
          timeout_type: "duration"
        }

        suggestions = detector.get_timeout_recovery_suggestions(timeout_info, :network_request)

        expect(suggestions).to include("Check network connectivity")
        expect(suggestions).to include("Verify endpoint availability")
      end
    end

    describe "#create_timeout_error" do
      it "creates error for explicit timeout" do
        timeout_info = {
          timeout_type: "explicit"
        }

        error = detector.create_timeout_error(timeout_info)

        expect(error).to be_a(StandardError)
        expect(error.message).to include("explicit timeout detected")
      end

      it "creates error for duration timeout with exceeded time" do
        timeout_info = {
          timeout_type: "duration",
          exceeded_by: 10.5,
          duration: 130.5
        }

        error = detector.create_timeout_error(timeout_info)

        expect(error).to be_a(StandardError)
        expect(error.message).to include("exceeded duration by 10.5 seconds")
        expect(error.message).to include("(duration: 130.5s)")
      end

      it "creates error for duration timeout without exceeded time" do
        timeout_info = {
          timeout_type: "duration",
          duration: 130.5
        }

        error = detector.create_timeout_error(timeout_info)

        expect(error).to be_a(StandardError)
        expect(error.message).to include("duration exceeded")
        expect(error.message).to include("(duration: 130.5s)")
      end

      it "creates error with operation context" do
        timeout_info = {
          timeout_type: "explicit"
        }

        error = detector.create_timeout_error(timeout_info, :analyze)

        expect(error).to be_a(StandardError)
        expect(error.message).to include("(operation: analyze)")
      end

      it "creates error for unknown timeout type" do
        timeout_info = {
          timeout_type: "unknown"
        }

        error = detector.create_timeout_error(timeout_info)

        expect(error).to be_a(StandardError)
        expect(error.message).to eq("Operation timed out")
      end
    end
  end
end
