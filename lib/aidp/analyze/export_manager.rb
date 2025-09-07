# frozen_string_literal: true

require "json"
require "csv"
require "yaml"

module Aidp
  class ExportManager
    # Supported export formats
    SUPPORTED_FORMATS = %w[json csv yaml xml].freeze

    def initialize(project_dir = Dir.pwd, config = {})
      @project_dir = project_dir
      @config = config
      @output_dir = config[:output_dir] || File.join(project_dir, "exports")
    end

    # Export analysis data to JSON format
    def export_to_json(data, options = {})
      export_data(data, "json", options) do |formatted_data|
        JSON.pretty_generate(formatted_data)
      end
    end

    # Export analysis data to CSV format
    def export_to_csv(data, options = {})
      export_data(data, "csv", options) do |formatted_data|
        generate_csv_content(formatted_data, options)
      end
    end

    # Export analysis data to YAML format
    def export_to_yaml(data, options = {})
      export_data(data, "yaml", options) do |formatted_data|
        YAML.dump(formatted_data)
      end
    end

    # Export analysis data to XML format
    def export_to_xml(data, options = {})
      export_data(data, "xml", options) do |formatted_data|
        generate_xml_content(formatted_data, options)
      end
    end

    # Export analysis data to multiple formats
    def export_to_multiple_formats(data, formats, options = {})
      results = {}

      formats.each do |format|
        case format.downcase
        when "json"
          results[:json] = export_to_json(data, options)
        when "csv"
          results[:csv] = export_to_csv(data, options)
        when "yaml"
          results[:yaml] = export_to_yaml(data, options)
        when "xml"
          results[:xml] = export_to_xml(data, options)
        else
          results[format] = {error: "Unsupported format: #{format}"}
        end
      end

      results
    end

    # Export specific analysis components
    def export_analysis_component(component_name, data, format, options = {})
      component_data = extract_component_data(component_name, data)

      case format.downcase
      when "json"
        export_to_json(component_data, options.merge(component: component_name))
      when "csv"
        export_to_csv(component_data, options.merge(component: component_name))
      when "yaml"
        export_to_yaml(component_data, options.merge(component: component_name))
      when "xml"
        export_to_xml(component_data, options.merge(component: component_name))
      else
        {error: "Unsupported format: #{format}"}
      end
    end

    # Export metrics data
    def export_metrics(metrics_data, format, options = {})
      formatted_metrics = format_metrics_data(metrics_data)

      case format.downcase
      when "json"
        export_to_json(formatted_metrics, options.merge(type: "metrics"))
      when "csv"
        export_to_csv(formatted_metrics, options.merge(type: "metrics"))
      when "yaml"
        export_to_yaml(formatted_metrics, options.merge(type: "metrics"))
      when "xml"
        export_to_xml(formatted_metrics, options.merge(type: "metrics"))
      else
        {error: "Unsupported format: #{format}"}
      end
    end

    # Export comparison data
    def export_comparison(before_data, after_data, format, options = {})
      comparison_data = prepare_comparison_data(before_data, after_data)

      case format.downcase
      when "json"
        export_to_json(comparison_data, options.merge(type: "comparison"))
      when "csv"
        export_to_csv(comparison_data, options.merge(type: "comparison"))
      when "yaml"
        export_to_yaml(comparison_data, options.merge(type: "comparison"))
      when "xml"
        export_to_xml(comparison_data, options.merge(type: "comparison"))
      else
        {error: "Unsupported format: #{format}"}
      end
    end

    # Generate export summary
    def generate_export_summary(exports)
      {
        total_exports: exports.length,
        successful_exports: exports.count { |_, result| result[:success] },
        failed_exports: exports.count { |_, result| !result[:success] },
        formats_used: exports.keys.uniq,
        files_generated: exports.values.filter_map { |result| result[:path] },
        generated_at: Time.now
      }
    end

    private

    def export_data(data, format, options)
      timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
      component = options[:component] || "analysis"
      type = options[:type] || "data"

      filename = options[:filename] || "#{component}_#{type}_#{timestamp}.#{format}"
      output_path = File.join(@output_dir, filename)

      # Ensure output directory exists
      FileUtils.mkdir_p(@output_dir)

      # Format and write data
      formatted_data = format_export_data(data, options)
      content = yield(formatted_data)

      File.write(output_path, content)

      {
        success: true,
        path: output_path,
        format: format,
        filename: filename,
        size: File.size(output_path),
        generated_at: Time.now
      }
    end

    def format_export_data(data, options)
      formatted = {
        metadata: {
          exported_at: Time.now.iso8601,
          project_name: File.basename(@project_dir),
          project_path: @project_dir,
          export_type: options[:type] || "analysis",
          component: options[:component]
        },
        data: data
      }

      # Add configuration if requested
      formatted[:config] = @config if options[:include_config]

      formatted
    end

    def generate_csv_content(data, options)
      # Flatten nested data for CSV export
      flattened_data = flatten_data_for_csv(data)

      return "" if flattened_data.empty?

      # Generate CSV content
      CSV.generate do |csv|
        # Add headers
        headers = flattened_data.first.keys
        csv << headers

        # Add data rows
        flattened_data.each do |row|
          csv << headers.map { |header| row[header] }
        end
      end
    end

    def flatten_data_for_csv(data)
      flattened = []

      if data[:data].is_a?(Array)
        # Handle array data
        data[:data].each_with_index do |item, index|
          flattened_item = flatten_hash(item)
          flattened_item["index"] = index
          flattened << flattened_item
        end
      elsif data[:data].is_a?(Hash)
        # Handle hash data
        flattened << flatten_hash(data[:data])
      end

      flattened
    end

    def flatten_hash(hash, prefix = "")
      flattened = {}

      hash.each do |key, value|
        new_key = prefix.empty? ? key.to_s : "#{prefix}_#{key}"

        case value
        when Hash
          flattened.merge!(flatten_hash(value, new_key))
        when Array
          if value.all?(Hash)
            # Array of hashes - create separate rows
            value.each_with_index do |item, index|
              item_flattened = flatten_hash(item, "#{new_key}_#{index}")
              flattened.merge!(item_flattened)
            end
          else
            # Simple array - join with semicolon
            flattened[new_key] = value.join("; ")
          end
        else
          flattened[new_key] = value
        end
      end

      flattened
    end

    def generate_xml_content(data, options)
      require "rexml/document"

      doc = REXML::Document.new
      doc.add_element("analysis_export")

      # Add metadata
      metadata_elem = doc.root.add_element("metadata")
      data[:metadata].each do |key, value|
        elem = metadata_elem.add_element(key.to_s)
        elem.text = value.to_s
      end

      # Add data
      data_elem = doc.root.add_element("data")
      add_xml_element(data_elem, data[:data])

      # Format XML
      formatter = REXML::Formatters::Pretty.new(2)
      formatter.compact = true
      output = ""
      formatter.write(doc, output)

      output
    end

    def add_xml_element(parent, data)
      case data
      when Hash
        data.each do |key, value|
          elem = parent.add_element(key.to_s)
          add_xml_element(elem, value)
        end
      when Array
        data.each_with_index do |item, index|
          elem = parent.add_element("item_#{index}")
          add_xml_element(elem, item)
        end
      else
        parent.text = data.to_s
      end
    end

    def extract_component_data(component_name, data)
      case component_name
      when "repository_analysis"
        data[:repository_analysis] || {}
      when "architecture_analysis"
        data[:architecture_analysis] || {}
      when "static_analysis"
        data[:static_analysis] || {}
      when "security_analysis"
        data[:security_analysis] || {}
      when "performance_analysis"
        data[:performance_analysis] || {}
      when "test_coverage"
        data[:test_coverage] || {}
      when "refactoring_recommendations"
        data[:refactoring_recommendations] || {}
      when "modernization_recommendations"
        data[:modernization_recommendations] || {}
      else
        data[component_name.to_sym] || {}
      end
    end

    def format_metrics_data(metrics_data)
      formatted = {
        metrics: {},
        summary: {},
        trends: {}
      }

      if metrics_data.is_a?(Hash)
        metrics_data.each do |category, metrics|
          if metrics.is_a?(Hash)
            formatted[:metrics][category] = metrics
          else
            formatted[:summary][category] = metrics
          end
        end
      end

      formatted
    end

    def prepare_comparison_data(before_data, after_data)
      {
        before: before_data,
        after: after_data,
        changes: calculate_changes(before_data, after_data),
        improvements: identify_improvements(before_data, after_data),
        regressions: identify_regressions(before_data, after_data)
      }
    end

    def calculate_changes(before_data, after_data)
      changes = {}

      # Compare metrics
      before_metrics = extract_metrics(before_data)
      after_metrics = extract_metrics(after_data)

      all_metrics = (before_metrics.keys + after_metrics.keys).uniq

      all_metrics.each do |metric|
        before_value = before_metrics[metric]
        after_value = after_metrics[metric]

        next unless before_value && after_value

        changes[metric] = {
          before: before_value,
          after: after_value,
          change: after_value - before_value,
          percentage_change: ((after_value - before_value) / before_value * 100).round(2)
        }
      end

      changes
    end

    def identify_improvements(before_data, after_data)
      improvements = []

      changes = calculate_changes(before_data, after_data)
      changes.each do |metric, change|
        next unless change[:change] > 0

        improvements << {
          metric: metric,
          improvement: change[:change],
          percentage: change[:percentage_change]
        }
      end

      improvements
    end

    def identify_regressions(before_data, after_data)
      regressions = []

      changes = calculate_changes(before_data, after_data)
      changes.each do |metric, change|
        next unless change[:change] < 0

        regressions << {
          metric: metric,
          regression: change[:change].abs,
          percentage: change[:percentage_change].abs
        }
      end

      regressions
    end

    def extract_metrics(data)
      metrics = {}

      if data.is_a?(Hash)
        data.each do |key, value|
          if value.is_a?(Numeric)
            metrics[key] = value
          elsif value.is_a?(Hash)
            metrics.merge!(extract_metrics(value))
          end
        end
      end

      metrics
    end
  end
end
