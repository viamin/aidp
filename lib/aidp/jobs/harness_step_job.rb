# frozen_string_literal: true

require_relative "harness_job"

module Aidp
  module Jobs
    # Job for executing individual harness steps
    class HarnessStepJob < HarnessJob
      def execute_harness_job(step_name:, provider_type:, prompt:, session: nil, **_options)
        log_harness_info("Executing harness step: #{step_name}")
        log_harness_info("Provider: #{provider_type}")

        # Update progress
        update_job_progress({
          step_name: step_name,
          provider_type: provider_type,
          status: :initializing,
          progress: 0
        })

        # Get provider instance
        provider = get_provider(provider_type)
        unless provider
          error_msg = "Provider #{provider_type} not available"
          log_harness_error(error_msg)
          raise error_msg
        end

        # Set up provider with harness context
        if provider.respond_to?(:set_harness_context)
          # Get harness runner if available
          harness_runner = get_harness_runner
          provider.set_harness_context(harness_runner) if harness_runner
        end

        # Update progress
        update_job_progress({
          step_name: step_name,
          provider_type: provider_type,
          status: :executing,
          progress: 25
        })

        # Execute the step
        result = execute_step_with_provider(provider, prompt, session, step_name)

        # Update progress
        update_job_progress({
          step_name: step_name,
          provider_type: provider_type,
          status: :processing_result,
          progress: 75
        })

        # Process and store result
        processed_result = process_step_result(result, step_name, provider_type)

        # Update progress
        update_job_progress({
          step_name: step_name,
          provider_type: provider_type,
          status: :completed,
          progress: 100
        })

        log_harness_info("Step #{step_name} completed successfully")

        processed_result
      rescue => error
        log_harness_error("Step #{step_name} failed: #{error.message}")

        # Update progress with error
        update_job_progress({
          step_name: step_name,
          provider_type: provider_type,
          status: :failed,
          progress: 0,
          error: error.message
        })

        raise
      end

      private

      def get_provider(provider_type)
        begin
          require_relative "../provider_manager"
          Aidp::ProviderManager.get_provider(provider_type)
        rescue => e
          log_harness_error("Failed to get provider #{provider_type}: #{e.message}")
          nil
        end
      end

      def get_harness_runner
        return nil unless @harness_runner_id

        # In a real implementation, this would look up the harness runner
        # For now, we'll return nil
        nil
      end

      def execute_step_with_provider(provider, prompt, session, _step_name)
        log_harness_info("Executing with provider: #{provider.name}")

        # Use harness-aware send method if available
        if provider.respond_to?(:send_with_harness)
          provider.send_with_harness(prompt: prompt, session: session)
        else
          provider.send(prompt: prompt, session: session)
        end
      end

      def process_step_result(result, step_name, provider_type)
        # Extract token usage if available
        token_usage = extract_token_usage(result)

        # Extract any rate limiting information
        rate_limited = extract_rate_limiting(result)

        # Create processed result
        processed_result = {
          step_name: step_name,
          provider_type: provider_type,
          result: result,
          token_usage: token_usage,
          rate_limited: rate_limited,
          executed_at: Time.now,
          job_id: que_attrs[:job_id]
        }

        # Store result in database if available
        store_step_result(processed_result)

        # Log token usage
        if token_usage && token_usage[:total] > 0
          log_harness_info("Token usage: #{token_usage[:total]} tokens")
          if token_usage[:cost] && token_usage[:cost] > 0
            log_harness_info("Cost: $#{token_usage[:cost].round(4)}")
          end
        end

        # Log rate limiting
        if rate_limited
          log_harness_warning("Rate limiting detected")
        end

        processed_result
      end

      def extract_token_usage(result)
        return nil unless result.is_a?(Hash)

        if result[:token_usage]
          result[:token_usage]
        elsif result[:usage]
          result[:usage]
        else
          nil
        end
      end

      def extract_rate_limiting(result)
        return false unless result.is_a?(Hash)

        if result[:rate_limited]
          result[:rate_limited]
        elsif result[:rate_limit]
          result[:rate_limit]
        else
          false
        end
      end

      def store_step_result(result)
        begin
          require_relative "../database_connection"

          Aidp::DatabaseConnection.connection.exec_params(
            <<~SQL,
              INSERT INTO harness_step_results (
                step_name, provider_type, result_data, token_usage,
                rate_limited, executed_at, job_id, created_at
              )
              VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            SQL
            [
              result[:step_name],
              result[:provider_type],
              result[:result].to_json,
              result[:token_usage]&.to_json,
              result[:rate_limited],
              result[:executed_at],
              result[:job_id],
              Time.now
            ]
          )
        rescue => e
          log_harness_warning("Could not store step result: #{e.message}")
        end
      end

      def cleanup_on_cancellation
        log_harness_info("Cleaning up harness step job on cancellation")

        # Update progress to show cancellation
        update_job_progress({
          status: :cancelled,
          progress: 0,
          cancelled_at: Time.now
        })
      end

      def get_job_progress
        super.merge({
          step_name: @step_name,
          provider_type: @provider_type,
          current_phase: @current_phase || :initializing
        })
      end
    end
  end
end
