# frozen_string_literal: true

require "spec_helper"
require "net/http" # For Net::TimeoutError

RSpec.describe Aidp::Analyze::ErrorHandler do
  let(:error_handler) { described_class.new(verbose: false) }

  describe "initialization" do
    it "creates error handler with default settings" do
      handler = described_class.new
      expect(handler).to be_a(described_class)
      expect(handler.error_counts).to eq({})
      expect(handler.recovery_strategies).to be_a(Hash)
    end

    it "sets up logger" do
      expect(error_handler.logger).to be_a(Logger)
    end

    it "initializes recovery strategies" do
      expect(error_handler.recovery_strategies).to include(
        Errno::ENOENT => :skip_step_with_warning
      )
    end
  end

  describe "#handle_error" do
    let(:test_error) { StandardError.new("test error") }

    it "handles errors with context and step information" do
      context = {operation: -> { "test" }}

      error_handler.handle_error(test_error, context: context, step: "test_step")

      expect(error_handler.error_counts[StandardError]).to eq(1)
    end

    it "tracks error counts by class" do
      error_handler.handle_error(StandardError.new("error1"))
      error_handler.handle_error(StandardError.new("error2"))
      error_handler.handle_error(ArgumentError.new("error3"))

      expect(error_handler.error_counts[StandardError]).to eq(2)
      expect(error_handler.error_counts[ArgumentError]).to eq(1)
    end
  end

  describe "#retry_with_backoff" do
    it "retries operations with exponential backoff" do
      call_count = 0
      operation = lambda {
        call_count += 1
        (call_count < 3) ? raise(StandardError, "retry me") : "success"
      }

      result = error_handler.retry_with_backoff(operation, max_retries: 3, base_delay: 0.01)
      expect(result).to eq("success")
      expect(call_count).to eq(3)
    end

    it "raises MaxAttemptsError when retries exhausted" do
      operation = -> { raise StandardError, "always fails" }

      expect do
        error_handler.retry_with_backoff(operation, max_retries: 2, base_delay: 0.01)
      end.to raise_error(Aidp::Concurrency::MaxAttemptsError)
    end
  end

  describe "#skip_step_with_warning" do
    it "logs warning and returns skip status" do
      error = StandardError.new("skip this")
      result = error_handler.skip_step_with_warning("test_step", error)

      expect(result[:status]).to eq("skipped")
      expect(result[:reason]).to eq("skip this")
      expect(result[:timestamp]).to be_a(Time)
    end
  end

  describe "#get_error_summary" do
    it "returns comprehensive error statistics" do
      error_handler.handle_error(StandardError.new("error1"))
      error_handler.handle_error(ArgumentError.new("error2"))

      summary = error_handler.get_error_summary

      expect(summary[:total_errors]).to eq(2)
      expect(summary[:error_breakdown]).to include(StandardError => 1, ArgumentError => 1)
      expect(summary[:recent_errors]).to be_an(Array)
      expect(summary[:recovery_success_rate]).to be_a(Numeric)
    end
  end

  describe "#cleanup" do
    it "clears error history and counts" do
      error_handler.handle_error(StandardError.new("error"))

      error_handler.cleanup

      expect(error_handler.error_counts).to eq({})
      summary = error_handler.get_error_summary
      expect(summary[:recent_errors]).to be_empty
    end
  end

  describe "custom error classes" do
    it "creates CriticalAnalysisError with error info" do
      error_info = {step: "test", context: "important"}
      error = Aidp::Analyze::CriticalAnalysisError.new("Critical failure", error_info)

      expect(error.message).to eq("Critical failure")
      expect(error.error_info).to eq(error_info)
    end

    it "creates other custom error classes" do
      expect(Aidp::Analyze::AnalysisTimeoutError.new("timeout")).to be_a(StandardError)
      expect(Aidp::Analyze::AnalysisDataError.new("data error")).to be_a(StandardError)
      expect(Aidp::Analyze::AnalysisToolError.new("tool error")).to be_a(StandardError)
    end
  end

  describe "recovery strategies" do
    it "handles file not found errors appropriately" do
      file_error = Errno::ENOENT.new("file not found")
      context = {step: "file_operation"}

      error_handler.handle_error(file_error, context: context, step: "test")

      expect(error_handler.error_counts[Errno::ENOENT]).to eq(1)
    end
  end

  describe "specific error handlers" do
    describe "#handle_analysis_tool_error" do
      it "raises AnalysisToolError with installation guide" do
        tool_error = StandardError.new("tool failed")
        context = {
          tool_name: "rubocop",
          installation_guide: "gem install rubocop"
        }

        expect do
          error_handler.send(:handle_analysis_tool_error, tool_error, context)
        end.to raise_error(Aidp::Analyze::AnalysisToolError) do |error|
          expect(error.message).to include("rubocop failed")
          expect(error.message).to include("gem install rubocop")
        end
      end

      it "raises AnalysisToolError without installation guide" do
        tool_error = StandardError.new("tool failed")
        context = {tool_name: "custom_tool"}

        expect do
          error_handler.send(:handle_analysis_tool_error, tool_error, context)
        end.to raise_error(Aidp::Analyze::AnalysisToolError) do |error|
          expect(error.message).to include("custom_tool failed")
          expect(error.message).not_to include("To install")
        end
      end
    end

    describe "#handle_timeout_error" do
      it "retries when context is retryable" do
        timeout_error = Net::TimeoutError.new("timeout")
        call_count = 0
        operation = -> {
          call_count += 1
          "success"
        }
        context = {retryable: true, operation: operation}

        result = error_handler.send(:handle_timeout_error, timeout_error, context)

        expect(result).to eq("success")
      end

      it "skips step when not retryable" do
        timeout_error = Net::TimeoutError.new("timeout")
        context = {retryable: false, step: "network_call"}

        result = error_handler.send(:handle_timeout_error, timeout_error, context)

        expect(result[:status]).to eq("skipped")
      end
    end

    describe "#handle_file_not_found" do
      it "skips step when file is not required" do
        file_error = Errno::ENOENT.new("file not found")
        context = {required: false, step: "optional_file"}

        result = error_handler.send(:handle_file_not_found, file_error, context)

        expect(result[:status]).to eq("skipped")
      end

      it "raises critical error when file is required" do
        file_error = Errno::ENOENT.new("critical file missing")
        context = {required: true, step: "critical_file"}

        expect do
          error_handler.send(:handle_file_not_found, file_error, context)
        end.to raise_error(Aidp::Analyze::CriticalAnalysisError)
      end
    end

    describe "#handle_permission_denied" do
      it "raises critical error" do
        permission_error = Errno::EACCES.new("permission denied")
        context = {step: "restricted_file"}

        expect do
          error_handler.send(:handle_permission_denied, permission_error, context)
        end.to raise_error(Aidp::Analyze::CriticalAnalysisError)
      end
    end

    describe "#handle_disk_full" do
      it "raises critical error" do
        disk_error = Errno::ENOSPC.new("disk full")
        context = {step: "write_file"}

        expect do
          error_handler.send(:handle_disk_full, disk_error, context)
        end.to raise_error(Aidp::Analyze::CriticalAnalysisError)
      end
    end

    describe "#handle_analysis_timeout" do
      it "chunks and retries when chunkable" do
        timeout_error = Aidp::Analyze::AnalysisTimeoutError.new("analysis timeout")
        chunker = double("chunker", chunk_repository: {chunks: ["chunk1"]})
        operation = ->(chunk) { {status: "success", chunk: chunk} }
        context = {chunkable: true, chunker: chunker, operation: operation}

        result = error_handler.send(:handle_analysis_timeout, timeout_error, context)

        expect(result).to be_an(Array)
        expect(result.first[:status]).to eq("success")
      end

      it "skips step when not chunkable" do
        timeout_error = Aidp::Analyze::AnalysisTimeoutError.new("analysis timeout")
        context = {chunkable: false, step: "analysis"}

        result = error_handler.send(:handle_analysis_timeout, timeout_error, context)

        expect(result[:status]).to eq("skipped")
      end
    end

    describe "#handle_analysis_data_error" do
      it "continues with partial data" do
        data_error = Aidp::Analyze::AnalysisDataError.new("data incomplete")
        operation = -> { {full: "data"} }
        partial_handler = ->(e) { {partial: "data"} }
        context = {operation: operation, partial_data_handler: partial_handler}

        result = error_handler.send(:handle_analysis_data_error, data_error, context)

        expect(result).to eq({full: "data"})
      end
    end
  end

  describe "error handling with various recovery strategies" do
    it "applies correct recovery strategy for different errors" do
      # Test skip_step_with_warning strategy
      file_error = Errno::ENOENT.new("file not found")
      context = {step: "file_operation"}
      error_handler.handle_error(file_error, context: context, step: "test")

      expect(error_handler.error_counts[Errno::ENOENT]).to eq(1)
    end

    it "handles context overrides for recovery strategies" do
      # Test context override of recovery strategy
      file_error = Errno::ENOENT.new("critical file missing")
      context = {critical: true, step: "critical_operation"}

      expect do
        error_handler.handle_error(file_error, context: context, step: "test")
      end.to raise_error(Aidp::Analyze::CriticalAnalysisError)
    end
  end
end
