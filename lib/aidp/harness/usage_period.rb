# frozen_string_literal: true

require "time"
require "date"

module Aidp
  module Harness
    # Immutable value object representing a usage tracking period
    # Handles time period calculations, boundaries, and reset logic
    class UsagePeriod
      PERIOD_TYPES = %w[daily weekly monthly].freeze

      attr_reader :period_type, :reset_day, :start_time, :end_time

      # Create a UsagePeriod for the current time
      #
      # @param period_type [String] Type of period: daily, weekly, monthly
      # @param reset_day [Integer] Day of month for reset (1-28 for monthly)
      # @param reference_time [Time] Reference time (defaults to now)
      # @return [UsagePeriod] Period instance
      def self.current(period_type:, reset_day: 1, reference_time: Time.now)
        new(
          period_type: period_type,
          reset_day: reset_day,
          reference_time: reference_time
        )
      end

      # Create a UsagePeriod from a stored period key
      #
      # @param period_key [String] Period key (e.g., "2024-01", "2024-W01", "2024-01-15")
      # @param period_type [String] Type of period
      # @return [UsagePeriod] Period instance
      def self.from_key(period_key, period_type:)
        reference_time = parse_period_key(period_key, period_type)
        new(period_type: period_type, reference_time: reference_time)
      end

      def initialize(period_type:, reset_day: 1, reference_time: Time.now)
        @period_type = validate_period_type(period_type)
        @reset_day = validate_reset_day(reset_day)
        @reference_time = reference_time

        calculate_boundaries
        freeze
      end

      # Generate a unique key for this period (for storage)
      #
      # @return [String] Period key suitable for use as hash key
      def period_key
        case @period_type
        when "daily"
          @start_time.strftime("%Y-%m-%d")
        when "weekly"
          @start_time.strftime("%Y-W%V")
        when "monthly"
          @start_time.strftime("%Y-%m")
        end
      end

      # Check if a given time falls within this period
      #
      # @param time [Time] Time to check
      # @return [Boolean] True if time is within period
      def contains?(time)
        time >= @start_time && time < @end_time
      end

      # Check if this period has ended
      #
      # @param current_time [Time] Current time (defaults to now)
      # @return [Boolean] True if period has ended
      def ended?(current_time = Time.now)
        current_time >= @end_time
      end

      # Get the next period after this one
      #
      # @return [UsagePeriod] Next period instance
      def next_period
        self.class.new(
          period_type: @period_type,
          reset_day: @reset_day,
          reference_time: @end_time + 1
        )
      end

      # Get the previous period before this one
      #
      # @return [UsagePeriod] Previous period instance
      def previous_period
        self.class.new(
          period_type: @period_type,
          reset_day: @reset_day,
          reference_time: @start_time - 1
        )
      end

      # Calculate remaining time in this period
      #
      # @param current_time [Time] Current time (defaults to now)
      # @return [Integer] Seconds remaining in period
      def remaining_seconds(current_time = Time.now)
        return 0 if ended?(current_time)

        (@end_time - current_time).to_i
      end

      # Human-readable period description
      #
      # @return [String] Period description
      def description
        case @period_type
        when "daily"
          @start_time.strftime("%B %d, %Y")
        when "weekly"
          "Week of #{@start_time.strftime("%B %d, %Y")}"
        when "monthly"
          @start_time.strftime("%B %Y")
        end
      end

      # Value equality
      def ==(other)
        return false unless other.is_a?(UsagePeriod)

        period_type == other.period_type &&
          reset_day == other.reset_day &&
          start_time == other.start_time &&
          end_time == other.end_time
      end

      alias_method :eql?, :==

      def hash
        [period_type, reset_day, start_time, end_time].hash
      end

      # Convert to hash for serialization
      def to_h
        {
          period_type: @period_type,
          reset_day: @reset_day,
          start_time: @start_time.iso8601,
          end_time: @end_time.iso8601,
          period_key: period_key
        }
      end

      def self.parse_period_key(period_key, period_type)
        case period_type
        when "daily"
          Time.parse(period_key)
        when "weekly"
          # Parse ISO week format (e.g., "2024-W01")
          year, week = period_key.split("-W")
          Date.commercial(year.to_i, week.to_i, 1).to_time
        when "monthly"
          Time.parse("#{period_key}-01")
        else
          Time.now
        end
      rescue ArgumentError
        Time.now
      end

      private_class_method :parse_period_key

      private

      def validate_period_type(period_type)
        type_str = period_type.to_s.downcase
        PERIOD_TYPES.include?(type_str) ? type_str : "monthly"
      end

      def validate_reset_day(day)
        day_int = day.to_i
        day_int.between?(1, 28) ? day_int : 1
      end

      def calculate_boundaries
        case @period_type
        when "daily"
          calculate_daily_boundaries
        when "weekly"
          calculate_weekly_boundaries
        when "monthly"
          calculate_monthly_boundaries
        end
      end

      def calculate_daily_boundaries
        @start_time = Time.new(
          @reference_time.year,
          @reference_time.month,
          @reference_time.day,
          0, 0, 0
        )
        @end_time = @start_time + (24 * 60 * 60)
      end

      def calculate_weekly_boundaries
        # Start on Monday (wday 1), end on Sunday
        days_since_monday = (@reference_time.wday - 1) % 7
        monday = @reference_time - (days_since_monday * 24 * 60 * 60)
        @start_time = Time.new(monday.year, monday.month, monday.day, 0, 0, 0)
        @end_time = @start_time + (7 * 24 * 60 * 60)
      end

      def calculate_monthly_boundaries
        year = @reference_time.year
        month = @reference_time.month
        day = @reference_time.day

        # Determine if we're before or after the reset day in current month
        if day >= @reset_day
          # Current period started this month
          @start_time = Time.new(year, month, @reset_day, 0, 0, 0)
          # End at reset day next month
          next_month = (month == 12) ? 1 : month + 1
          next_year = (month == 12) ? year + 1 : year
          @end_time = Time.new(next_year, next_month, @reset_day, 0, 0, 0)
        else
          # Current period started last month
          prev_month = (month == 1) ? 12 : month - 1
          prev_year = (month == 1) ? year - 1 : year
          @start_time = Time.new(prev_year, prev_month, @reset_day, 0, 0, 0)
          @end_time = Time.new(year, month, @reset_day, 0, 0, 0)
        end
      end
    end
  end
end
