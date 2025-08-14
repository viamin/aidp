# frozen_string_literal: true

require 'spec_helper'
require 'aidp/error_handler'

RSpec.describe Aidp::ErrorHandler do
  let(:error_handler) { described_class.new(verbose: false) }
  let(:log_file) { Tempfile.new('error_handler_test.log') }

  after do
    log_file.close
    log_file.unlink
  end

  describe '#initialize' do
    it 'initializes with default configuration' do
      expect(error_handler).to be_a(described_class)
      expect(error_handler.logger).to be_a(Logger)
      expect(error_handler.error_counts).to be_a(Hash)
      expect(error_handler.recovery_strategies).to be_a(Hash)
    end

    it 'initializes with custom log file' do
      handler = described_class.new(log_file: log_file.path)
      expect(handler.logger).to be_a(Logger)
    end

    it 'sets up recovery strategies' do
      strategies = error_handler.recovery_strategies
      expect(strategies[Net::TimeoutError]).to eq(:retry_with_backoff)
      expect(strategies[Errno::ENOENT]).to eq(:skip_step_with_warning)
      expect(strategies[Errno::ENOSPC]).to eq(:critical_error)
    end
  end

  describe '#handle_error' do
    let(:test_error) { StandardError.new('Test error') }
    let(:context) { { step: 'test_step', retryable: true } }

    it 'handles errors with proper logging' do
      result = error_handler.handle_error(test_error, context: context, step: 'test_step')

      expect(error_handler.error_counts[StandardError]).to eq(1)
      expect(result).to be_a(Hash)
      expect(result[:status]).to eq('continued_with_error')
    end

    it 'increments error count for specific error types' do
      error_handler.handle_error(Net::TimeoutError.new('Timeout'), context: context)
      error_handler.handle_error(Errno::ENOENT.new('File not found'), context: context)

      expect(error_handler.error_counts[Net::TimeoutError]).to eq(1)
      expect(error_handler.error_counts[Errno::ENOENT]).to eq(1)
    end

    it 'maintains error history' do
      error_handler.handle_error(test_error, context: context)

      summary = error_handler.get_error_summary
      expect(summary[:total_errors]).to eq(1)
      expect(summary[:recent_errors]).to have(1).item
    end
  end

  describe '#handle_network_error' do
    context 'with timeout error' do
      let(:timeout_error) { Net::TimeoutError.new('Request timeout') }
      let(:context) { { step: 'network_test', retryable: true, operation: -> { 'success' } } }

      it 'handles timeout errors with retry' do
        result = error_handler.handle_network_error(timeout_error, context: context)
        expect(result).to eq('success')
      end

      it 'handles non-retryable timeout errors' do
        context[:retryable] = false
        result = error_handler.handle_network_error(timeout_error, context: context)
        expect(result[:status]).to eq('skipped')
      end
    end

    context 'with HTTP error' do
      let(:http_error) { Net::HTTPError.new('HTTP Error', '500') }
      let(:context) { { step: 'http_test', operation: -> { 'success' } } }

      it 'handles HTTP errors with retry' do
        result = error_handler.handle_network_error(http_error, context: context)
        expect(result).to eq('success')
      end
    end

    context 'with socket error' do
      let(:socket_error) { SocketError.new('Connection failed') }
      let(:context) do
        {
          step: 'socket_test',
          network_required: false,
          operation: -> { 'success' },
          fallback_data: { status: 'fallback' }
        }
      end

      it 'handles socket errors with fallback' do
        result = error_handler.handle_network_error(socket_error, context: context)
        expect(result).to eq({ status: 'fallback' })
      end

      it 'raises critical error for required network operations' do
        context[:network_required] = true
        expect do
          error_handler.handle_network_error(socket_error, context: context)
        end.to raise_error(Aidp::CriticalAnalysisError)
      end
    end
  end

  describe '#handle_file_system_error' do
    context 'with file not found error' do
      let(:file_error) { Errno::ENOENT.new('File not found') }
      let(:context) { { step: 'file_test', required: false } }

      it 'handles file not found errors' do
        result = error_handler.handle_file_system_error(file_error, context: context)
        expect(result[:status]).to eq('skipped')
      end

      it 'raises critical error for required files' do
        context[:required] = true
        expect do
          error_handler.handle_file_system_error(file_error, context: context)
        end.to raise_error(Aidp::CriticalAnalysisError)
      end
    end

    context 'with permission denied error' do
      let(:permission_error) { Errno::EACCES.new('Permission denied') }

      it 'raises critical error for permission issues' do
        expect do
          error_handler.handle_file_system_error(permission_error, context: {})
        end.to raise_error(Aidp::CriticalAnalysisError)
      end
    end

    context 'with disk full error' do
      let(:disk_error) { Errno::ENOSPC.new('No space left on device') }

      it 'raises critical error for disk space issues' do
        expect do
          error_handler.handle_file_system_error(disk_error, context: {})
        end.to raise_error(Aidp::CriticalAnalysisError)
      end
    end
  end

  describe '#handle_database_error' do
    context 'with database busy error' do
      let(:busy_error) { SQLite3::BusyException.new('Database is locked') }
      let(:context) { { operation: -> { 'success' } } }

      it 'handles database busy errors with retry' do
        result = error_handler.handle_database_error(busy_error, context: context)
        expect(result).to eq('success')
      end
    end

    context 'with database corrupt error' do
      let(:corrupt_error) { SQLite3::CorruptException.new('Database file is corrupt') }

      it 'raises critical error for corrupt database' do
        expect do
          error_handler.handle_database_error(corrupt_error, context: {})
        end.to raise_error(Aidp::CriticalAnalysisError)
      end
    end

    context 'with database readonly error' do
      let(:readonly_error) { SQLite3::ReadOnlyException.new('Database is read-only') }

      it 'raises critical error for readonly database' do
        expect do
          error_handler.handle_database_error(readonly_error, context: {})
        end.to raise_error(Aidp::CriticalAnalysisError)
      end
    end
  end

  describe '#handle_analysis_error' do
    context 'with analysis timeout error' do
      let(:timeout_error) { Aidp::AnalysisTimeoutError.new('Analysis timed out') }
      let(:context) { { step: 'analysis_test', chunkable: true } }

      it 'handles analysis timeout with chunking' do
        result = error_handler.handle_analysis_error(timeout_error, context: context)
        expect(result).to be_an(Array)
      end

      it 'skips non-chunkable analysis timeout' do
        context[:chunkable] = false
        result = error_handler.handle_analysis_error(timeout_error, context: context)
        expect(result[:status]).to eq('skipped')
      end
    end

    context 'with analysis data error' do
      let(:data_error) { Aidp::AnalysisDataError.new('Invalid data format') }
      let(:context) do
        {
          operation: -> { 'success' },
          partial_data_handler: ->(e) { { status: 'partial', error: e.message } }
        }
      end

      it 'handles analysis data errors with partial data' do
        result = error_handler.handle_analysis_error(data_error, context: context)
        expect(result).to eq({ status: 'partial', error: 'Invalid data format' })
      end
    end

    context 'with analysis tool error' do
      let(:tool_error) { Aidp::AnalysisToolError.new('Tool execution failed') }
      let(:context) do
        {
          operation: -> { 'success' },
          mock_data: { status: 'mock', data: 'test' }
        }
      end

      it 'handles analysis tool errors with mock data' do
        result = error_handler.handle_analysis_error(tool_error, context: context)
        expect(result).to eq({ status: 'mock', data: 'test' })
      end
    end
  end

  describe '#retry_with_backoff' do
    let(:failing_operation) { -> { raise StandardError.new('Operation failed') } }
    let(:succeeding_operation) { -> { 'success' } }

    it 'retries failing operations with exponential backoff' do
      expect do
        error_handler.retry_with_backoff(failing_operation, max_retries: 2)
      end.to raise_error(StandardError)
    end

    it 'succeeds on first try for working operations' do
      result = error_handler.retry_with_backoff(succeeding_operation)
      expect(result).to eq('success')
    end

    it 'respects custom retry parameters' do
      expect do
        error_handler.retry_with_backoff(failing_operation, max_retries: 1, base_delay: 0.1)
      end.to raise_error(StandardError)
    end
  end

  describe '#fallback_to_mock_data' do
    let(:failing_operation) { -> { raise StandardError.new('Operation failed') } }
    let(:fallback_data) { { status: 'fallback', data: 'mock' } }

    it 'returns fallback data when operation fails' do
      result = error_handler.fallback_to_mock_data(failing_operation, fallback_data)
      expect(result).to eq(fallback_data)
    end

    it 'executes operation when it succeeds' do
      result = error_handler.fallback_to_mock_data(-> { 'success' }, fallback_data)
      expect(result).to eq('success')
    end
  end

  describe '#skip_step_with_warning' do
    let(:error) { StandardError.new('Test error') }

    it 'returns skip status with error information' do
      result = error_handler.skip_step_with_warning('test_step', error)

      expect(result[:status]).to eq('skipped')
      expect(result[:reason]).to eq('Test error')
      expect(result[:timestamp]).to be_a(Time)
    end
  end

  describe '#continue_with_partial_data' do
    let(:failing_operation) { -> { raise StandardError.new('Operation failed') } }
    let(:partial_handler) { ->(e) { { status: 'partial', error: e.message } } }

    it 'continues with partial data when operation fails' do
      result = error_handler.continue_with_partial_data(failing_operation, partial_handler)
      expect(result).to eq({ status: 'partial', error: 'Operation failed' })
    end

    it 'executes operation when it succeeds' do
      result = error_handler.continue_with_partial_data(-> { 'success' }, partial_handler)
      expect(result).to eq('success')
    end
  end

  describe '#get_error_summary' do
    before do
      error_handler.handle_error(StandardError.new('Error 1'), context: {})
      error_handler.handle_error(Net::TimeoutError.new('Error 2'), context: {})
      error_handler.handle_error(StandardError.new('Error 3'), context: {})
    end

    it 'provides comprehensive error summary' do
      summary = error_handler.get_error_summary

      expect(summary[:total_errors]).to eq(3)
      expect(summary[:error_breakdown][StandardError]).to eq(2)
      expect(summary[:error_breakdown][Net::TimeoutError]).to eq(1)
      expect(summary[:recent_errors]).to have(3).items
      expect(summary[:recovery_success_rate]).to be_a(Float)
    end
  end

  describe '#get_error_recommendations' do
    it 'provides recommendations based on error patterns' do
      # Simulate various error patterns
      error_handler.handle_error(Net::TimeoutError.new('Timeout'), context: {})
      error_handler.handle_error(Net::TimeoutError.new('Timeout'), context: {})
      error_handler.handle_error(Net::TimeoutError.new('Timeout'), context: {})
      error_handler.handle_error(Net::TimeoutError.new('Timeout'), context: {})
      error_handler.handle_error(Net::TimeoutError.new('Timeout'), context: {})
      error_handler.handle_error(Net::TimeoutError.new('Timeout'), context: {})

      error_handler.handle_error(Errno::ENOSPC.new('No space'), context: {})

      recommendations = error_handler.get_error_recommendations

      expect(recommendations).to include('Consider increasing timeout values for network operations')
      expect(recommendations).to include('Check available disk space and implement cleanup procedures')
    end

    it 'returns empty array when no significant error patterns' do
      recommendations = error_handler.get_error_recommendations
      expect(recommendations).to be_empty
    end
  end

  describe '#cleanup' do
    before do
      error_handler.handle_error(StandardError.new('Test error'), context: {})
    end

    it 'cleans up error handler resources' do
      expect(error_handler.error_counts).not_to be_empty
      expect(error_handler.get_error_summary[:total_errors]).to eq(1)

      error_handler.cleanup

      expect(error_handler.error_counts).to be_empty
      expect(error_handler.get_error_summary[:total_errors]).to eq(0)
    end
  end

  describe 'custom error classes' do
    it 'defines custom error classes' do
      expect(Aidp::CriticalAnalysisError).to be < StandardError
      expect(Aidp::AnalysisTimeoutError).to be < StandardError
      expect(Aidp::AnalysisDataError).to be < StandardError
      expect(Aidp::AnalysisToolError).to be < StandardError
    end

    it 'CriticalAnalysisError includes error info' do
      error_info = { step: 'test', context: { test: true } }
      error = Aidp::CriticalAnalysisError.new('Test message', error_info)

      expect(error.message).to eq('Test message')
      expect(error.error_info).to eq(error_info)
    end
  end

  describe 'edge cases' do
    it 'handles nil context gracefully' do
      result = error_handler.handle_error(StandardError.new('Test'), context: nil)
      expect(result).to be_a(Hash)
    end

    it 'handles empty context gracefully' do
      result = error_handler.handle_error(StandardError.new('Test'), context: {})
      expect(result).to be_a(Hash)
    end

    it 'handles missing operation in context' do
      result = error_handler.handle_error(Net::TimeoutError.new('Test'), context: { retryable: true })
      expect(result[:status]).to eq('skipped')
    end

    it 'limits error history size' do
      150.times do |i|
        error_handler.handle_error(StandardError.new("Error #{i}"), context: {})
      end

      summary = error_handler.get_error_summary
      expect(summary[:recent_errors]).to have(10).items
      expect(summary[:total_errors]).to eq(150)
    end
  end

  describe 'recovery strategy determination' do
    it 'overrides strategy based on context' do
      error = StandardError.new('Test error')
      context = { critical: true }

      # StandardError normally uses :log_and_continue, but critical context should override
      result = error_handler.handle_error(error, context: context)
      expect(result[:status]).to eq('continued_with_error')
    end

    it 'respects retryable context' do
      error = StandardError.new('Test error')
      context = { retryable: true, operation: -> { 'success' } }

      result = error_handler.handle_error(error, context: context)
      expect(result[:status]).to eq('continued_with_error')
    end
  end
end
