# frozen_string_literal: true

require "yaml"
require "fileutils"
require_relative "usage_period"
require_relative "../rescue_logging"

module Aidp
  module Harness
    # Domain service for tracking usage metrics per provider and period
    # Handles recording usage, querying current usage, and period resets
    class UsageLimitTracker
      include Aidp::RescueLogging

      # Maximum number of historical periods to retain for trend analysis
      MAX_HISTORY_PERIODS = 12

      attr_reader :provider_name, :project_dir

      def initialize(provider_name:, project_dir:, metrics_repo: nil)
        @provider_name = provider_name.to_s
        @project_dir = project_dir
        @metrics_repo = metrics_repo
        @usage_file = File.join(project_dir, ".aidp", "usage_tracking", "#{@provider_name}.yml")
        @usage_data = nil
        @lock = Mutex.new if defined?(Mutex)

        Aidp.log_debug("usage_limit_tracker", "initialized",
          provider: @provider_name,
          project_dir: @project_dir)
      end

      # Record usage for a request
      #
      # @param tokens [Integer] Number of tokens used
      # @param cost [Float] Cost incurred
      # @param tier [String] Tier used (mini, standard, advanced, etc.)
      # @param period_type [String] Period type (daily, weekly, monthly)
      # @param reset_day [Integer] Reset day for monthly periods
      def record_usage(tokens:, cost:, tier: "standard", period_type: "monthly", reset_day: 1)
        Aidp.log_debug("usage_limit_tracker", "recording_usage",
          provider: @provider_name,
          tokens: tokens,
          cost: cost,
          tier: tier)

        return unless tokens.positive? || cost.positive?

        with_lock do
          data = load_usage_data
          period = UsagePeriod.current(period_type: period_type, reset_day: reset_day)
          period_key = period.period_key

          # Initialize period data if needed
          data[:periods] ||= {}
          data[:periods][period_key] ||= new_period_data(period)

          # Update usage metrics
          period_data = data[:periods][period_key]
          period_data[:total_tokens] = (period_data[:total_tokens] || 0) + tokens
          period_data[:total_cost] = (period_data[:total_cost] || 0.0) + cost
          period_data[:request_count] = (period_data[:request_count] || 0) + 1
          period_data[:last_updated] = Time.now.iso8601

          # Update tier-specific usage
          tier_key = tier.to_s.downcase
          period_data[:tier_usage] ||= {}
          period_data[:tier_usage][tier_key] ||= {tokens: 0, cost: 0.0, requests: 0}
          period_data[:tier_usage][tier_key][:tokens] += tokens
          period_data[:tier_usage][tier_key][:cost] += cost
          period_data[:tier_usage][tier_key][:requests] += 1

          # Prune old periods
          prune_old_periods(data)

          # Save updated data
          save_usage_data(data)
          @usage_data = data
        end
      end

      # Get current usage for a period
      #
      # @param period_type [String] Period type (daily, weekly, monthly)
      # @param reset_day [Integer] Reset day for monthly periods
      # @return [Hash] Current usage data with :total_tokens, :total_cost, :tier_usage
      def current_usage(period_type: "monthly", reset_day: 1)
        period = UsagePeriod.current(period_type: period_type, reset_day: reset_day)
        period_key = period.period_key

        data = load_usage_data
        period_data = data[:periods]&.[](period_key)

        if period_data
          {
            period_key: period_key,
            period_description: period.description,
            total_tokens: period_data[:total_tokens] || 0,
            total_cost: period_data[:total_cost] || 0.0,
            request_count: period_data[:request_count] || 0,
            tier_usage: period_data[:tier_usage] || {},
            start_time: period.start_time,
            end_time: period.end_time,
            remaining_seconds: period.remaining_seconds
          }
        else
          {
            period_key: period_key,
            period_description: period.description,
            total_tokens: 0,
            total_cost: 0.0,
            request_count: 0,
            tier_usage: {},
            start_time: period.start_time,
            end_time: period.end_time,
            remaining_seconds: period.remaining_seconds
          }
        end
      end

      # Get usage for a specific tier in the current period
      #
      # @param tier [String] Tier name
      # @param period_type [String] Period type
      # @param reset_day [Integer] Reset day
      # @return [Hash] Tier-specific usage data
      def tier_usage(tier:, period_type: "monthly", reset_day: 1)
        usage = current_usage(period_type: period_type, reset_day: reset_day)
        tier_key = tier.to_s.downcase

        tier_data = usage[:tier_usage][tier_key] || usage[:tier_usage][tier_key.to_sym]

        if tier_data
          {
            tokens: tier_data[:tokens] || tier_data["tokens"] || 0,
            cost: tier_data[:cost] || tier_data["cost"] || 0.0,
            requests: tier_data[:requests] || tier_data["requests"] || 0
          }
        else
          {tokens: 0, cost: 0.0, requests: 0}
        end
      end

      # Get usage history across multiple periods
      #
      # @param limit [Integer] Maximum number of periods to return
      # @return [Array<Hash>] Array of period usage data, newest first
      def usage_history(limit: MAX_HISTORY_PERIODS)
        data = load_usage_data
        return [] unless data[:periods].is_a?(Hash)

        data[:periods]
          .sort_by { |key, _| key }
          .reverse
          .take(limit)
          .map do |key, period_data|
            {
              period_key: key,
              total_tokens: period_data[:total_tokens] || 0,
              total_cost: period_data[:total_cost] || 0.0,
              request_count: period_data[:request_count] || 0,
              tier_usage: period_data[:tier_usage] || {}
            }
          end
      end

      # Reset usage for the current period (for testing or manual reset)
      #
      # @param period_type [String] Period type
      # @param reset_day [Integer] Reset day
      def reset_current_period(period_type: "monthly", reset_day: 1)
        Aidp.log_info("usage_limit_tracker", "resetting_current_period",
          provider: @provider_name,
          period_type: period_type)

        with_lock do
          period = UsagePeriod.current(period_type: period_type, reset_day: reset_day)
          period_key = period.period_key

          data = load_usage_data
          data[:periods]&.delete(period_key)

          save_usage_data(data)
          @usage_data = data
        end
      end

      # Clear all usage data (for testing or user request)
      def clear_all_usage
        Aidp.log_warn("usage_limit_tracker", "clearing_all_usage",
          provider: @provider_name)

        with_lock do
          File.delete(@usage_file) if File.exist?(@usage_file)
          @usage_data = nil
        end
      end

      private

      def load_usage_data
        return @usage_data if @usage_data

        ensure_directory

        if File.exist?(@usage_file)
          raw_data = YAML.safe_load_file(@usage_file,
            permitted_classes: [Time, Date, Symbol],
            aliases: true)
          @usage_data = symbolize_keys(raw_data) if raw_data.is_a?(Hash)
        end

        @usage_data ||= {provider: @provider_name, periods: {}}
      rescue => e
        log_rescue(e, component: "usage_limit_tracker", action: "load_usage_data", fallback: {})
        @usage_data = {provider: @provider_name, periods: {}}
      end

      def save_usage_data(data)
        ensure_directory

        # Write atomically using temp file + rename
        temp_file = "#{@usage_file}.tmp"
        File.write(temp_file, YAML.dump(stringify_keys(data)))
        File.rename(temp_file, @usage_file)
      rescue => e
        log_rescue(e, component: "usage_limit_tracker", action: "save_usage_data", fallback: nil)
        File.delete(temp_file) if File.exist?(temp_file)
      end

      def ensure_directory
        dir = File.dirname(@usage_file)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
      end

      def new_period_data(period)
        {
          period_type: period.period_type,
          start_time: period.start_time.iso8601,
          end_time: period.end_time.iso8601,
          total_tokens: 0,
          total_cost: 0.0,
          request_count: 0,
          tier_usage: {},
          created_at: Time.now.iso8601,
          last_updated: Time.now.iso8601
        }
      end

      def prune_old_periods(data)
        return unless data[:periods].is_a?(Hash)
        return if data[:periods].size <= MAX_HISTORY_PERIODS

        # Keep only the most recent periods
        sorted_keys = data[:periods].keys.sort.reverse
        keys_to_remove = sorted_keys[MAX_HISTORY_PERIODS..]

        keys_to_remove&.each do |key|
          data[:periods].delete(key)
        end
      end

      def with_lock(&block)
        if @lock
          @lock.synchronize(&block)
        else
          yield
        end
      end

      def symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.transform_keys(&:to_sym).transform_values do |v|
          case v
          when Hash then symbolize_keys(v)
          when Array then v.map { |i| i.is_a?(Hash) ? symbolize_keys(i) : i }
          else v
          end
        end
      end

      def stringify_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.transform_keys(&:to_s).transform_values do |v|
          case v
          when Hash then stringify_keys(v)
          when Array then v.map { |i| i.is_a?(Hash) ? stringify_keys(i) : i }
          else v
          end
        end
      end
    end
  end
end
