# frozen_string_literal: true

require "csv"
require "json"
require_relative "../../logger"

module Aidp
  module Planning
    module Parsers
      # Parse feedback data from multiple formats (CSV, JSON, markdown)
      # Normalizes data into consistent structure for analysis
      class FeedbackDataParser
        class FeedbackParseError < StandardError; end

        def initialize(file_path:)
          @file_path = file_path
          @format = detect_format
        end

        # Parse feedback file and return normalized structure
        # @return [Hash] Normalized feedback data
        def parse
          Aidp.log_debug("feedback_data_parser", "parsing", file: @file_path, format: @format)

          case @format
          when :csv
            parse_csv
          when :json
            parse_json
          when :markdown
            parse_markdown
          else
            raise FeedbackParseError, "Unsupported format: #{@format}"
          end
        rescue => e
          Aidp.log_error("feedback_data_parser", "parse_failed", error: e.message, file: @file_path)
          raise FeedbackParseError, "Failed to parse feedback file: #{e.message}"
        end

        private

        def detect_format
          ext = File.extname(@file_path).downcase

          case ext
          when ".csv"
            :csv
          when ".json"
            :json
          when ".md", ".markdown"
            :markdown
          else
            raise FeedbackParseError, "Unknown file extension: #{ext}"
          end
        end

        def parse_csv
          Aidp.log_debug("feedback_data_parser", "parsing_csv")

          unless File.exist?(@file_path)
            raise FeedbackParseError, "File not found: #{@file_path}"
          end

          rows = CSV.read(@file_path, headers: true)
          responses = rows.map { |row| normalize_csv_row(row) }

          {
            format: :csv,
            source_file: @file_path,
            parsed_at: Time.now.iso8601,
            response_count: responses.size,
            responses: responses,
            metadata: extract_csv_metadata(rows)
          }
        end

        def parse_json
          Aidp.log_debug("feedback_data_parser", "parsing_json")

          unless File.exist?(@file_path)
            raise FeedbackParseError, "File not found: #{@file_path}"
          end

          data = JSON.parse(File.read(@file_path))

          # Support both array of responses and object with responses key
          responses = if data.is_a?(Array)
            data
          elsif data.is_a?(Hash) && data["responses"]
            data["responses"]
          else
            raise FeedbackParseError, "Invalid JSON structure: expected array or {responses: [...]}"
          end

          normalized_responses = responses.map { |r| normalize_json_response(r) }

          {
            format: :json,
            source_file: @file_path,
            parsed_at: Time.now.iso8601,
            response_count: normalized_responses.size,
            responses: normalized_responses,
            metadata: extract_json_metadata(data)
          }
        end

        def parse_markdown
          Aidp.log_debug("feedback_data_parser", "parsing_markdown")

          unless File.exist?(@file_path)
            raise FeedbackParseError, "File not found: #{@file_path}"
          end

          content = File.read(@file_path)
          responses = extract_markdown_responses(content)

          {
            format: :markdown,
            source_file: @file_path,
            parsed_at: Time.now.iso8601,
            response_count: responses.size,
            responses: responses,
            metadata: extract_markdown_metadata(content)
          }
        end

        def normalize_csv_row(row)
          {
            respondent_id: row["id"] || row["respondent_id"] || row["user_id"],
            timestamp: row["timestamp"] || row["date"] || row["submitted_at"],
            rating: parse_rating(row["rating"] || row["score"]),
            feedback_text: row["feedback"] || row["comments"] || row["response"],
            feature: row["feature"] || row["area"],
            sentiment: row["sentiment"],
            tags: parse_tags(row["tags"]),
            raw_data: row.to_h
          }
        end

        def normalize_json_response(response)
          {
            respondent_id: response["id"] || response["respondent_id"] || response["user_id"],
            timestamp: response["timestamp"] || response["date"] || response["submitted_at"],
            rating: parse_rating(response["rating"] || response["score"]),
            feedback_text: response["feedback"] || response["comments"] || response["response"] || response["text"],
            feature: response["feature"] || response["area"] || response["category"],
            sentiment: response["sentiment"],
            tags: parse_tags(response["tags"]),
            raw_data: response
          }
        end

        def extract_markdown_responses(content)
          # Simple markdown parser that looks for response sections
          # Format: ## Response N or ### Respondent: ID
          responses = []
          current_response = nil

          content.each_line do |line|
            if line =~ /^##+ Response (\d+)/i || line =~ /^##+ Respondent:?\s*(.+)/i
              responses << current_response if current_response
              current_response = {text: "", metadata: {}}
            elsif current_response
              # Extract key-value pairs like **Rating:** 5
              if line =~ /\*\*(.+?):\*\*\s*(.+)/
                key = $1.downcase.strip
                value = $2.strip
                current_response[:metadata][key] = value
              else
                current_response[:text] += line
              end
            end
          end

          responses << current_response if current_response

          responses.map do |resp|
            {
              respondent_id: resp[:metadata]["id"] || resp[:metadata]["respondent"],
              timestamp: resp[:metadata]["timestamp"] || resp[:metadata]["date"],
              rating: parse_rating(resp[:metadata]["rating"] || resp[:metadata]["score"]),
              feedback_text: resp[:text].strip,
              feature: resp[:metadata]["feature"] || resp[:metadata]["area"],
              sentiment: resp[:metadata]["sentiment"],
              tags: parse_tags(resp[:metadata]["tags"]),
              raw_data: resp[:metadata]
            }
          end
        end

        def parse_rating(value)
          return nil if value.nil? || value.to_s.strip.empty?

          # Handle numeric ratings, star ratings, etc.
          if value.to_s =~ /^(\d+)(?:\/\d+)?$/
            $1.to_i
          elsif value.to_s =~ /^(\d+)\s*stars?$/i
            $1.to_i
          else
            value.to_s
          end
        end

        def parse_tags(value)
          return [] if value.nil? || value.to_s.strip.empty?

          if value.is_a?(Array)
            value
          elsif value.is_a?(String)
            value.split(/[,;]/).map(&:strip).reject(&:empty?)
          else
            []
          end
        end

        def extract_csv_metadata(rows)
          {
            total_rows: rows.size,
            columns: rows.headers,
            has_timestamps: rows.headers.any? { |h| h&.match?(/timestamp|date/i) },
            has_ratings: rows.headers.any? { |h| h&.match?(/rating|score/i) }
          }
        end

        def extract_json_metadata(data)
          metadata = data.is_a?(Hash) ? data.except("responses") : {}

          {
            survey_name: metadata["survey_name"] || metadata["name"],
            survey_id: metadata["survey_id"] || metadata["id"],
            created_at: metadata["created_at"] || metadata["timestamp"],
            additional_fields: metadata.keys - ["responses", "survey_name", "name", "id", "survey_id", "created_at", "timestamp"]
          }
        end

        def extract_markdown_metadata(content)
          # Extract YAML front matter if present
          if content =~ /^---\s*\n(.*?)\n---\s*\n/m
            begin
              YAML.safe_load($1, permitted_classes: [Date, Time, Symbol]) || {}
            rescue => e
              Aidp.log_debug("feedback_data_parser", "yaml_parse_failed", error: e.message)
              {}
            end
          else
            {}
          end
        end
      end
    end
  end
end
