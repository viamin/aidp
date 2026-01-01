# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "evaluation_record"
require_relative "../config_paths"
require_relative "../rescue_logging"

module Aidp
  module Evaluations
    # Storage manager for evaluation records
    #
    # Stores evaluations in `.aidp/evaluations/` with append-only semantics:
    # - Individual evaluations stored as JSON files: `eval_YYYYMMDD_HHMMSS_xxxx.json`
    # - Indexed summary file for efficient lookups: `index.json`
    #
    # @example Storing an evaluation
    #   storage = EvaluationStorage.new(project_dir: Dir.pwd)
    #   storage.store(record)
    #
    # @example Listing evaluations
    #   storage.list(limit: 10)
    #   storage.list(rating: "bad")
    class EvaluationStorage
      include Aidp::RescueLogging

      def initialize(project_dir: Dir.pwd)
        @project_dir = project_dir
        @evaluations_dir = ConfigPaths.evaluations_dir(project_dir)
        @index_file = ConfigPaths.evaluations_index_file(project_dir)

        Aidp.log_debug("evaluation_storage", "initialize",
          project_dir: project_dir, evaluations_dir: @evaluations_dir)
      end

      # Store a new evaluation record
      #
      # @param record [EvaluationRecord] The evaluation to store
      # @return [Hash] Result with :success and :id keys
      def store(record)
        ensure_directory
        file_path = File.join(@evaluations_dir, "#{record.id}.json")

        Aidp.log_debug("evaluation_storage", "store",
          id: record.id, rating: record.rating, file_path: file_path)

        File.write(file_path, JSON.pretty_generate(record.to_h))
        update_index(record)

        {success: true, id: record.id, file_path: file_path}
      rescue => error
        log_rescue(error,
          component: "evaluation_storage",
          action: "store",
          fallback: {success: false},
          id: record.id)
        {success: false, error: error.message, id: record.id}
      end

      # Load a specific evaluation by ID
      #
      # @param id [String] The evaluation ID
      # @return [EvaluationRecord, nil] The record or nil if not found
      def load(id)
        file_path = File.join(@evaluations_dir, "#{id}.json")
        return nil unless File.exist?(file_path)

        Aidp.log_debug("evaluation_storage", "load", id: id)

        data = JSON.parse(File.read(file_path))
        EvaluationRecord.from_h(data)
      rescue => error
        log_rescue(error,
          component: "evaluation_storage",
          action: "load",
          fallback: nil,
          id: id)
        nil
      end

      # List evaluations with optional filtering
      #
      # @param limit [Integer] Maximum number of records to return
      # @param rating [String, nil] Filter by rating (good/neutral/bad)
      # @param target_type [String, nil] Filter by target type
      # @return [Array<EvaluationRecord>] Matching records, newest first
      def list(limit: 50, rating: nil, target_type: nil)
        Aidp.log_debug("evaluation_storage", "list",
          limit: limit, rating: rating, target_type: target_type)

        index = load_index
        entries = index[:entries] || []

        # Apply filters
        entries = entries.select { |e| e[:rating] == rating } if rating
        entries = entries.select { |e| e[:target_type] == target_type } if target_type

        # Sort by created_at descending, take limit
        entries = entries.sort_by { |e| e[:created_at] || "" }.reverse.take(limit)

        # Load full records
        entries.filter_map { |entry| load(entry[:id]) }
      rescue => error
        log_rescue(error,
          component: "evaluation_storage",
          action: "list",
          fallback: [],
          limit: limit)
        []
      end

      # Get statistics about evaluations
      #
      # @return [Hash] Statistics including counts by rating
      def stats
        Aidp.log_debug("evaluation_storage", "stats")

        index = load_index
        entries = index[:entries] || []

        total = entries.size
        by_rating = entries.group_by { |e| e[:rating] }
        by_target = entries.group_by { |e| e[:target_type] }

        {
          total: total,
          by_rating: {
            good: (by_rating["good"] || []).size,
            neutral: (by_rating["neutral"] || []).size,
            bad: (by_rating["bad"] || []).size
          },
          by_target_type: by_target.transform_values(&:size),
          first_evaluation: entries.min_by { |e| e[:created_at] || "" }&.dig(:created_at),
          last_evaluation: entries.max_by { |e| e[:created_at] || "" }&.dig(:created_at)
        }
      rescue => error
        log_rescue(error,
          component: "evaluation_storage",
          action: "stats",
          fallback: {total: 0, by_rating: {good: 0, neutral: 0, bad: 0}})
        {total: 0, by_rating: {good: 0, neutral: 0, bad: 0}, by_target_type: {}}
      end

      # Delete an evaluation by ID
      #
      # @param id [String] The evaluation ID
      # @return [Hash] Result with :success key
      def delete(id)
        file_path = File.join(@evaluations_dir, "#{id}.json")
        return {success: true, message: "Evaluation not found"} unless File.exist?(file_path)

        Aidp.log_debug("evaluation_storage", "delete", id: id)

        File.delete(file_path)
        remove_from_index(id)

        {success: true, id: id}
      rescue => error
        log_rescue(error,
          component: "evaluation_storage",
          action: "delete",
          fallback: {success: false},
          id: id)
        {success: false, error: error.message}
      end

      # Clear all evaluations
      #
      # @return [Hash] Result with :success and :count keys
      def clear
        Aidp.log_debug("evaluation_storage", "clear")

        return {success: true, count: 0} unless Dir.exist?(@evaluations_dir)

        count = Dir.glob(File.join(@evaluations_dir, "eval_*.json")).size
        FileUtils.rm_rf(@evaluations_dir)

        {success: true, count: count}
      rescue => error
        log_rescue(error,
          component: "evaluation_storage",
          action: "clear",
          fallback: {success: false})
        {success: false, error: error.message}
      end

      # Check if evaluations directory exists and has evaluations
      def any?
        Dir.exist?(@evaluations_dir) && Dir.glob(File.join(@evaluations_dir, "eval_*.json")).any?
      end

      private

      def ensure_directory
        ConfigPaths.ensure_evaluations_dir(@project_dir)
      end

      def load_index
        return {entries: []} unless File.exist?(@index_file)

        data = JSON.parse(File.read(@index_file))
        symbolize_index(data)
      rescue
        {entries: []}
      end

      def update_index(record)
        index = load_index
        index[:entries] ||= []

        # Add new entry to index (stores minimal data for quick lookups)
        index[:entries] << {
          id: record.id,
          rating: record.rating,
          target_type: record.target_type,
          target_id: record.target_id,
          created_at: record.created_at
        }

        index[:updated_at] = Time.now.iso8601

        File.write(@index_file, JSON.pretty_generate(index))
      end

      def remove_from_index(id)
        index = load_index
        index[:entries]&.reject! { |e| e[:id] == id }
        index[:updated_at] = Time.now.iso8601

        File.write(@index_file, JSON.pretty_generate(index))
      end

      def symbolize_index(data)
        return data unless data.is_a?(Hash)
        result = {}
        data.each do |key, value|
          sym_key = key.is_a?(String) ? key.to_sym : key
          result[sym_key] = if value.is_a?(Array)
            value.map { |v| v.is_a?(Hash) ? symbolize_index(v) : v }
          elsif value.is_a?(Hash)
            symbolize_index(value)
          else
            value
          end
        end
        result
      end
    end
  end
end
