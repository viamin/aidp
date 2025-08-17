# frozen_string_literal: true

require "json"
require "yaml"
require_relative "storage"

module Aidp
  module Analyze
    class DataRetentionManager
      # Retention policies
      RETENTION_POLICIES = {
        "metrics" => "indefinite",
        "analysis_results" => "configurable",
        "execution_logs" => "configurable",
        "temporary_data" => "immediate",
        "embeddings" => "indefinite"
      }.freeze

      # Default retention periods (in days)
      DEFAULT_RETENTION_PERIODS = {
        "analysis_results" => 90, # 3 months
        "execution_logs" => 30, # 1 month
        "temporary_data" => 1 # 1 day
      }.freeze

      def initialize(project_dir = Dir.pwd, config = {})
        @project_dir = project_dir
        @config = config
        @storage = config[:storage] || Aidp::AnalysisStorage.new(project_dir)
        @retention_config = load_retention_config
      end

      # Apply retention policies
      def apply_retention_policies(options = {})
        dry_run = options[:dry_run] || false
        options[:force] || false

        results = {
          cleaned_data: {},
          retained_data: {},
          errors: []
        }

        # Process each data type
        RETENTION_POLICIES.each do |data_type, policy|
          case policy
          when "indefinite"
            results[:retained_data][data_type] = retain_indefinitely(data_type)
          when "configurable"
            results[:cleaned_data][data_type] = apply_configurable_retention(data_type, dry_run)
          when "immediate"
            results[:cleaned_data][data_type] = clean_immediately(data_type, dry_run)
          end
        rescue => e
          results[:errors] << {
            data_type: data_type,
            error: e.message
          }
        end

        results
      end

      # Handle force/rerun operations
      def handle_force_rerun(execution_id, step_name, options = {})
        operation = options[:operation] || "force"

        case operation
        when "force"
          handle_force_operation(execution_id, step_name, options)
        when "rerun"
          handle_rerun_operation(execution_id, step_name, options)
        else
          raise "Unknown operation: #{operation}"
        end
      end

      # Clean old data based on retention policies
      def clean_old_data(options = {})
        dry_run = options[:dry_run] || false
        data_types = options[:data_types] || RETENTION_POLICIES.keys

        results = {
          cleaned: {},
          errors: []
        }

        data_types.each do |data_type|
          next unless RETENTION_POLICIES[data_type] == "configurable"

          begin
            cleaned = clean_data_by_type(data_type, dry_run)
            results[:cleaned][data_type] = cleaned
          rescue => e
            results[:errors] << {
              data_type: data_type,
              error: e.message
            }
          end
        end

        results
      end

      # Get retention statistics
      def get_retention_statistics
        stats = {
          policies: RETENTION_POLICIES,
          config: @retention_config,
          data_sizes: {},
          retention_status: {}
        }

        # Calculate data sizes
        RETENTION_POLICIES.keys.each do |data_type|
          stats[:data_sizes][data_type] = calculate_data_size(data_type)
          stats[:retention_status][data_type] = get_retention_status(data_type)
        end

        stats
      end

      # Export data with retention metadata
      def export_data_with_retention(data_type, options = {})
        include_retention_info = options[:include_retention_info] || true

        data = export_data(data_type, options)

        if include_retention_info
          data[:retention_info] = {
            policy: RETENTION_POLICIES[data_type],
            retention_period: @retention_config[data_type],
            last_cleaned: get_last_cleaned_date(data_type),
            next_cleanup: calculate_next_cleanup(data_type)
          }
        end

        data
      end

      # Set retention policy for a data type
      def set_retention_policy(data_type, policy, options = {})
        raise "Unknown data type: #{data_type}" unless RETENTION_POLICIES.key?(data_type)

        case policy
        when "indefinite"
          @retention_config[data_type] = {policy: "indefinite"}
        when "configurable"
          retention_period = options[:retention_period] || DEFAULT_RETENTION_PERIODS[data_type]
          @retention_config[data_type] = {
            policy: "configurable",
            retention_period: retention_period
          }
        when "immediate"
          @retention_config[data_type] = {policy: "immediate"}
        else
          raise "Unknown retention policy: #{policy}"
        end

        save_retention_config

        {
          data_type: data_type,
          policy: policy,
          config: @retention_config[data_type]
        }
      end

      # Get data retention status
      def get_data_retention_status(data_type)
        {
          data_type: data_type,
          policy: RETENTION_POLICIES[data_type],
          config: @retention_config[data_type],
          data_size: calculate_data_size(data_type),
          last_cleaned: get_last_cleaned_date(data_type),
          next_cleanup: calculate_next_cleanup(data_type),
          retention_status: get_retention_status(data_type)
        }
      end

      private

      def load_retention_config
        config_file = File.join(@project_dir, ".aidp-retention-config.yml")

        if File.exist?(config_file)
          YAML.load_file(config_file) || DEFAULT_RETENTION_PERIODS
        else
          DEFAULT_RETENTION_PERIODS
        end
      end

      def save_retention_config
        config_file = File.join(@project_dir, ".aidp-retention-config.yml")
        File.write(config_file, YAML.dump(@retention_config))
      end

      def retain_indefinitely(data_type)
        {
          data_type: data_type,
          action: "retained",
          reason: "Indefinite retention policy",
          timestamp: Time.now
        }
      end

      def apply_configurable_retention(data_type, dry_run)
        retention_period = @retention_config[data_type] || DEFAULT_RETENTION_PERIODS[data_type]
        cutoff_date = Time.now - (retention_period * 24 * 60 * 60)

        # Get old data
        old_data = get_old_data(data_type, cutoff_date)

        if dry_run
          {
            data_type: data_type,
            action: "would_clean",
            records_to_clean: old_data.length,
            cutoff_date: cutoff_date,
            dry_run: true
          }
        else
          # Actually clean the data
          cleaned_count = clean_data(data_type, old_data)

          {
            data_type: data_type,
            action: "cleaned",
            records_cleaned: cleaned_count,
            cutoff_date: cutoff_date,
            timestamp: Time.now
          }
        end
      end

      def clean_immediately(data_type, dry_run)
        if dry_run
          {
            data_type: data_type,
            action: "would_clean_immediately",
            dry_run: true
          }
        else
          # Clean all data of this type
          cleaned_count = clean_all_data(data_type)

          {
            data_type: data_type,
            action: "cleaned_immediately",
            records_cleaned: cleaned_count,
            timestamp: Time.now
          }
        end
      end

      def handle_force_operation(execution_id, step_name, options)
        # Force operation: overwrite main data, retain metrics
        results = {
          operation: "force",
          execution_id: execution_id,
          step_name: step_name,
          actions: []
        }

        # Overwrite analysis results
        if options[:analysis_data]
          @storage.force_overwrite(execution_id, step_name, options[:analysis_data])
          results[:actions] << "overwrote_analysis_data"
        end

        # Retain metrics (indefinite retention)
        results[:actions] << "retained_metrics"

        results
      end

      def handle_rerun_operation(execution_id, step_name, options)
        # Rerun operation: overwrite main data, retain metrics
        results = {
          operation: "rerun",
          execution_id: execution_id,
          step_name: step_name,
          actions: []
        }

        # Overwrite analysis results
        if options[:analysis_data]
          @storage.force_overwrite(execution_id, step_name, options[:analysis_data])
          results[:actions] << "overwrote_analysis_data"
        end

        # Retain metrics (indefinite retention)
        results[:actions] << "retained_metrics"

        results
      end

      def get_old_data(data_type, cutoff_date)
        case data_type
        when "analysis_results"
          get_old_analysis_results(cutoff_date)
        when "execution_logs"
          get_old_execution_logs(cutoff_date)
        when "temporary_data"
          get_old_temporary_data(cutoff_date)
        else
          []
        end
      end

      def get_old_analysis_results(cutoff_date)
        # Get analysis results older than cutoff date
        # This would query the database for old records
        []
      end

      def get_old_execution_logs(cutoff_date)
        # Get execution logs older than cutoff date
        []
      end

      def get_old_temporary_data(cutoff_date)
        # Get temporary data older than cutoff date
        []
      end

      def clean_data(data_type, old_data)
        case data_type
        when "analysis_results"
          clean_analysis_results(old_data)
        when "execution_logs"
          clean_execution_logs(old_data)
        when "temporary_data"
          clean_temporary_data(old_data)
        else
          0
        end
      end

      def clean_all_data(data_type)
        case data_type
        when "temporary_data"
          clean_all_temporary_data
        else
          0
        end
      end

      def clean_analysis_results(old_data)
        # Clean old analysis results from database
        # This would delete records from the database
        old_data.length
      end

      def clean_execution_logs(old_data)
        # Clean old execution logs
        old_data.length
      end

      def clean_temporary_data(old_data)
        # Clean old temporary data
        old_data.length
      end

      def clean_all_temporary_data
        # Clean all temporary data
        0
      end

      def calculate_data_size(data_type)
        case data_type
        when "metrics"
          @storage.get_analysis_statistics[:total_metrics] || 0
        when "analysis_results"
          @storage.get_analysis_statistics[:total_steps] || 0
        when "execution_logs"
          @storage.get_execution_history.length
        else
          0
        end
      end

      def get_retention_status(data_type)
        policy = RETENTION_POLICIES[data_type]
        config = @retention_config[data_type]

        {
          policy: policy,
          config: config,
          status: "active"
        }
      end

      def get_last_cleaned_date(data_type)
        # This would be stored in a metadata table
        nil
      end

      def calculate_next_cleanup(data_type)
        policy = RETENTION_POLICIES[data_type]

        case policy
        when "indefinite"
          nil
        when "configurable"
          retention_period = @retention_config[data_type] || DEFAULT_RETENTION_PERIODS[data_type]
          Time.now + (retention_period * 24 * 60 * 60)
        when "immediate"
          Time.now
        end
      end

      def export_data(data_type, options)
        case data_type
        when "metrics"
          @storage.export_data("json", options)
        when "analysis_results"
          @storage.export_data("json", options)
        else
          {error: "Unknown data type: #{data_type}"}
        end
      end
    end
  end
end
