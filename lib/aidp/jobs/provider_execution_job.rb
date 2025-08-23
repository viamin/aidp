# frozen_string_literal: true

module Aidp
  module Jobs
    class ProviderExecutionJob < BaseJob
      def self.enqueue(provider_type:, prompt:, session: nil, metadata: {})
        job = super
        # Extract job ID explicitly for better readability and debugging
        job_id = job.que_attrs[:job_id]
        raise "Failed to enqueue job: no job ID returned" unless job_id
        job_id
      end

      def run(provider_type:, prompt:, session: nil, metadata: {})
        start_time = Time.now

        # Get provider instance
        provider = Aidp::ProviderManager.get_provider(provider_type)
        raise "Provider #{provider_type} not available" unless provider

        begin
          # Execute provider
          result = provider.send(prompt: prompt, session: session)

          # Store result
          store_result(result, metadata)

          # Record metrics
          record_metrics(
            provider_type: provider_type,
            duration: Time.now - start_time,
            success: true,
            error: nil
          )
        rescue => error
          # Record metrics
          record_metrics(
            provider_type: provider_type,
            duration: Time.now - start_time,
            success: false,
            error: error.message
          )

          # Re-raise error to trigger Que's retry mechanism
          raise
        end
      end

      private

      def store_result(result, metadata)
        return unless metadata[:step_name]

        Aidp::DatabaseConnection.connection.exec_params(
          <<~SQL,
            INSERT INTO analysis_results (step_name, data, metadata, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (step_name)
            DO UPDATE SET
              data = EXCLUDED.data,
              metadata = EXCLUDED.metadata,
              updated_at = EXCLUDED.updated_at
          SQL
          [
            metadata[:step_name],
            result.to_json,
            metadata.to_json,
            Time.now,
            Time.now
          ]
        )
      end

      def record_metrics(provider_type:, duration:, success:, error: nil)
        Aidp::DatabaseConnection.connection.exec_params(
          <<~SQL,
            INSERT INTO provider_metrics (
              provider_type, duration, success, error,
              job_id, attempt, created_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7)
          SQL
          [
            provider_type,
            duration,
            success,
            error,
            que_attrs[:job_id],
            que_attrs[:error_count] + 1,
            Time.now
          ]
        )
      end
    end
  end
end
