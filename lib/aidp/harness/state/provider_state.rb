# frozen_string_literal: true

module Aidp
  module Harness
    module State
      # Manages provider-specific state and rate limiting
      class ProviderState
        def initialize(persistence)
          @persistence = persistence
        end

        def provider_state
          state[:provider_state] || {}
        end

        def update_provider_state(provider_name, provider_data)
          current_provider_state = provider_state
          current_provider_state[provider_name] = provider_data
          update_state(provider_state: current_provider_state)
        end

        def rate_limit_info
          state[:rate_limit_info] || {}
        end

        def update_rate_limit_info(provider_name, reset_time, error_count = 0)
          current_info = rate_limit_info
          current_info[provider_name] = create_rate_limit_entry(reset_time, error_count)
          update_state(rate_limit_info: current_info)
        end

        def provider_rate_limited?(provider_name)
          info = rate_limit_info[provider_name]
          return false unless info

          reset_time = parse_reset_time(info[:reset_time])
          reset_time && Time.now < reset_time
        end

        def next_provider_reset_time
          rate_limit_info.map do |_provider, info|
            parse_reset_time(info[:reset_time])
          end.compact.min
        end

        def token_usage
          state[:token_usage] || {}
        end

        def record_token_usage(provider_name, model_name, input_tokens, output_tokens, cost = nil)
          current_usage = token_usage
          key = "#{provider_name}:#{model_name}"

          current_usage[key] = update_token_usage_entry(
            current_usage[key], input_tokens, output_tokens, cost
          )

          update_state(token_usage: current_usage)
        end

        def token_usage_summary
          usage = token_usage
          {
            total_tokens: calculate_total_tokens(usage),
            total_cost: calculate_total_cost(usage),
            total_requests: calculate_total_requests(usage),
            by_provider_model: usage
          }
        end

        private

        def state
          @persistence.load_state
        end

        def update_state(updates)
          current_state = state
          updated_state = current_state.merge(updates)
          updated_state[:last_updated] = Time.now
          @persistence.save_state(updated_state)
        end

        def create_rate_limit_entry(reset_time, error_count)
          {
            reset_time: reset_time&.iso8601,
            error_count: error_count,
            last_updated: Time.now.iso8601
          }
        end

        def parse_reset_time(reset_time_string)
          Time.parse(reset_time_string) if reset_time_string
        end

        def update_token_usage_entry(existing_entry, input_tokens, output_tokens, cost)
          existing_entry ||= create_empty_token_usage_entry

          existing_entry[:input_tokens] += input_tokens
          existing_entry[:output_tokens] += output_tokens
          existing_entry[:total_tokens] += (input_tokens + output_tokens)
          existing_entry[:cost] += cost if cost
          existing_entry[:requests] += 1

          existing_entry
        end

        def create_empty_token_usage_entry
          {
            input_tokens: 0,
            output_tokens: 0,
            total_tokens: 0,
            cost: 0.0,
            requests: 0
          }
        end

        def calculate_total_tokens(usage)
          usage.values.sum { |entry| entry[:total_tokens] }
        end

        def calculate_total_cost(usage)
          usage.values.sum { |entry| entry[:cost] }
        end

        def calculate_total_requests(usage)
          usage.values.sum { |entry| entry[:requests] }
        end
      end
    end
  end
end
