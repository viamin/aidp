# frozen_string_literal: true

require "json"
require "tty-table"
require_relative "../output_helper"

module Aidp
  module Analysis
    class KBInspector
      include Aidp::OutputHelper
      def initialize(kb_dir = ".aidp/kb")
        @kb_dir = File.expand_path(kb_dir)
        @data = load_kb_data
      end

      def show(type, format: "summary")
        case type
        when "seams"
          show_seams(format)
        when "hotspots"
          show_hotspots(format)
        when "cycles"
          show_cycles(format)
        when "apis"
          show_apis(format)
        when "symbols"
          show_symbols(format)
        when "imports"
          show_imports(format)
        when "summary"
          show_summary(format)
        else
          Aidp::OutputLogger.puts "Unknown KB type: #{type}"
          Aidp::OutputLogger.puts "Available types: seams, hotspots, cycles, apis, symbols, imports, summary"
        end
      end

      def generate_graph(type, format: "dot", output: nil)
        case type
        when "imports"
          generate_import_graph(format, output)
        when "calls"
          generate_call_graph(format, output)
        when "cycles"
          generate_cycle_graph(format, output)
        else
          Aidp::OutputLogger.puts "Unknown graph type: #{type}"
          Aidp::OutputLogger.puts "Available types: imports, calls, cycles"
        end
      end

      private

      def truncate_text(text, max_length = 50)
        return nil unless text
        return text if text.length <= max_length

        text[0..max_length - 4] + "..."
      end

      def create_table(header, rows)
        TTY::Table.new(header: header, rows: rows)
      end

      def load_kb_data
        data = {}

        %w[symbols imports calls metrics seams hotspots tests cycles].each do |type|
          file_path = File.join(@kb_dir, "#{type}.json")
          if File.exist?(file_path)
            begin
              data[type.to_sym] = JSON.parse(File.read(file_path), symbolize_names: true)
            rescue JSON::ParserError => e
              Aidp::OutputLogger.puts "Warning: Could not parse #{file_path}: #{e.message}"
              data[type.to_sym] = []
            end
          else
            data[type.to_sym] = []
          end
        end

        data
      end

      def show_summary(_format)
        Aidp::OutputLogger.puts "\n📊 Knowledge Base Summary"
        Aidp::OutputLogger.puts "=" * 50

        Aidp::OutputLogger.puts "📁 KB Directory: #{@kb_dir}"
        Aidp::OutputLogger.puts "📄 Files analyzed: #{count_files}"
        Aidp::OutputLogger.puts "🏗️  Symbols: #{@data[:symbols]&.length || 0}"
        Aidp::OutputLogger.puts "📦 Imports: #{@data[:imports]&.length || 0}"
        Aidp::OutputLogger.puts "🔗 Calls: #{@data[:calls]&.length || 0}"
        Aidp::OutputLogger.puts "📏 Metrics: #{@data[:metrics]&.length || 0}"
        Aidp::OutputLogger.puts "🔧 Seams: #{@data[:seams]&.length || 0}"
        Aidp::OutputLogger.puts "🔥 Hotspots: #{@data[:hotspots]&.length || 0}"
        Aidp::OutputLogger.puts "🧪 Tests: #{@data[:tests]&.length || 0}"
        Aidp::OutputLogger.puts "🔄 Cycles: #{@data[:cycles]&.length || 0}"

        if @data[:seams]&.any?
          Aidp::OutputLogger.puts "\n🔧 Seam Types:"
          seam_types = @data[:seams].group_by { |s| s[:kind] }
          seam_types.each do |type, seams|
            Aidp::OutputLogger.puts "  #{type}: #{seams.length}"
          end
        end

        if @data[:hotspots]&.any?
          Aidp::OutputLogger.puts "\n🔥 Top 5 Hotspots:"
          @data[:hotspots].first(5).each_with_index do |hotspot, i|
            Aidp::OutputLogger.puts "  #{i + 1}. #{hotspot[:file]}:#{hotspot[:method]} (score: #{hotspot[:score]})"
          end
        end
      end

      def show_seams(format)
        return puts "No seams data available" unless @data[:seams]&.any?

        case format
        when "json"
          Aidp::OutputLogger.puts JSON.pretty_generate(@data[:seams])
        when "table"
          show_seams_table
        else
          show_seams_summary
        end
      end

      def show_seams_table
        table = create_table(
          ["Type", "File", "Line", "Symbol", "Suggestion"],
          @data[:seams].map do |seam|
            [
              seam[:kind],
              seam[:file],
              seam[:line],
              seam[:symbol_id]&.split(":")&.last || "N/A",
              truncate_text(seam[:suggestion], 50) || "N/A"
            ]
          end
        )

        Aidp::OutputLogger.puts "\n🔧 Seams Analysis"
        Aidp::OutputLogger.puts "=" * 80
        Aidp::OutputLogger.puts table.render
      end

      def show_seams_summary
        Aidp::OutputLogger.puts "\n🔧 Seams Analysis"
        Aidp::OutputLogger.puts "=" * 50

        seam_types = @data[:seams].group_by { |s| s[:kind] }

        seam_types.each do |type, seams|
          Aidp::OutputLogger.puts "\n📌 #{type.upcase} (#{seams.length} found)"
          Aidp::OutputLogger.puts "-" * 30

          seams.first(10).each do |seam|
            Aidp::OutputLogger.puts "  #{seam[:file]}:#{seam[:line]}"
            Aidp::OutputLogger.puts "    Symbol: #{seam[:symbol_id]&.split(":")&.last}"
            Aidp::OutputLogger.puts "    Suggestion: #{seam[:suggestion]}"
            Aidp::OutputLogger.puts
          end

          if seams.length > 10
            Aidp::OutputLogger.puts "  ... and #{seams.length - 10} more"
          end
        end
      end

      def show_hotspots(format)
        return puts "No hotspots data available" unless @data[:hotspots]&.any?

        case format
        when "json"
          Aidp::OutputLogger.puts JSON.pretty_generate(@data[:hotspots])
        when "table"
          show_hotspots_table
        else
          show_hotspots_summary
        end
      end

      def show_hotspots_table
        table = create_table(
          ["Rank", "File", "Method", "Score", "Complexity", "Touches"],
          @data[:hotspots].map.with_index do |hotspot, i|
            [
              i + 1,
              hotspot[:file],
              hotspot[:method],
              hotspot[:score],
              hotspot[:complexity],
              hotspot[:touches]
            ]
          end
        )

        Aidp::OutputLogger.puts "\n🔥 Code Hotspots"
        Aidp::OutputLogger.puts "=" * 80
        Aidp::OutputLogger.puts table.render
      end

      def show_hotspots_summary
        Aidp::OutputLogger.puts "\n🔥 Code Hotspots (Top 20)"
        Aidp::OutputLogger.puts "=" * 50

        @data[:hotspots].each_with_index do |hotspot, i|
          Aidp::OutputLogger.puts "#{i + 1}. #{hotspot[:file]}:#{hotspot[:method]}"
          Aidp::OutputLogger.puts "   Score: #{hotspot[:score]} (Complexity: #{hotspot[:complexity]}, Touches: #{hotspot[:touches]})"
          Aidp::OutputLogger.puts
        end
      end

      def show_cycles(format)
        return puts "No cycles data available" unless @data[:cycles]&.any?

        case format
        when "json"
          Aidp::OutputLogger.puts JSON.pretty_generate(@data[:cycles])
        else
          show_cycles_summary
        end
      end

      def show_cycles_summary
        Aidp::OutputLogger.puts "\n🔄 Import Cycles"
        Aidp::OutputLogger.puts "=" * 50

        @data[:cycles].each_with_index do |cycle, i|
          Aidp::OutputLogger.puts "Cycle #{i + 1}:"
          cycle[:members].each do |member|
            Aidp::OutputLogger.puts "  - #{member}"
          end
          Aidp::OutputLogger.puts "  Weight: #{cycle[:weight]}" if cycle[:weight]
          Aidp::OutputLogger.puts
        end
      end

      def show_apis(format)
        return puts "No APIs data available" unless @data[:tests]&.any?

        untested_apis = @data[:tests].select { |t| t[:tests].empty? }

        case format
        when "json"
          Aidp::OutputLogger.puts JSON.pretty_generate(untested_apis)
        else
          show_apis_summary(untested_apis)
        end
      end

      def show_apis_summary(untested_apis)
        Aidp::OutputLogger.puts "\n🧪 Untested Public APIs"
        Aidp::OutputLogger.puts "=" * 50

        if untested_apis.empty?
          Aidp::OutputLogger.puts "✅ All public APIs have associated tests!"
        else
          Aidp::OutputLogger.puts "Found #{untested_apis.length} untested public APIs:"
          Aidp::OutputLogger.puts

          untested_apis.each do |api|
            symbol = @data[:symbols]&.find { |s| s[:id] == api[:symbol_id] }
            if symbol
              Aidp::OutputLogger.puts "  #{symbol[:file]}:#{symbol[:line]} - #{symbol[:name]}"
              Aidp::OutputLogger.puts "    Suggestion: Create characterization tests"
              Aidp::OutputLogger.puts
            end
          end
        end
      end

      def show_symbols(format)
        return puts "No symbols data available" unless @data[:symbols]&.any?

        case format
        when "json"
          Aidp::OutputLogger.puts JSON.pretty_generate(@data[:symbols])
        when "table"
          show_symbols_table
        else
          show_symbols_summary
        end
      end

      def show_symbols_table
        table = create_table(
          ["Type", "Name", "File", "Line", "Visibility"],
          @data[:symbols].map do |symbol|
            [
              symbol[:kind],
              symbol[:name],
              symbol[:file],
              symbol[:line],
              symbol[:visibility]
            ]
          end
        )

        Aidp::OutputLogger.puts "\n🏗️  Symbols"
        Aidp::OutputLogger.puts "=" * 80
        Aidp::OutputLogger.puts table.render
      end

      def show_symbols_summary
        Aidp::OutputLogger.puts "\n🏗️  Symbols Summary"
        Aidp::OutputLogger.puts "=" * 50

        symbol_types = @data[:symbols].group_by { |s| s[:kind] }

        symbol_types.each do |type, symbols|
          Aidp::OutputLogger.puts "#{type.capitalize}: #{symbols.length}"
        end
      end

      def show_imports(format)
        return puts "No imports data available" unless @data[:imports]&.any?

        case format
        when "json"
          Aidp::OutputLogger.puts JSON.pretty_generate(@data[:imports])
        when "table"
          show_imports_table
        else
          show_imports_summary
        end
      end

      def show_imports_table
        table = create_table(
          ["Type", "Target", "File", "Line"],
          @data[:imports].map do |import|
            [
              import[:kind],
              import[:target],
              import[:file],
              import[:line]
            ]
          end
        )

        Aidp::OutputLogger.puts "\n📦 Imports"
        Aidp::OutputLogger.puts "=" * 80
        Aidp::OutputLogger.puts table.render
      end

      def show_imports_summary
        Aidp::OutputLogger.puts "\n📦 Imports Summary"
        Aidp::OutputLogger.puts "=" * 50

        import_types = @data[:imports].group_by { |i| i[:kind] }

        import_types.each do |type, imports|
          Aidp::OutputLogger.puts "#{type.capitalize}: #{imports.length}"
        end
      end

      def generate_import_graph(format, output)
        Aidp::OutputLogger.puts "Generating import graph in #{format} format..."

        case format
        when "dot"
          generate_dot_graph(output)
        when "mermaid"
          generate_mermaid_graph(output)
        when "json"
          generate_json_graph(output)
        else
          Aidp::OutputLogger.puts "Unsupported graph format: #{format}"
        end
      end

      def generate_dot_graph(output)
        content = ["digraph ImportGraph {"]
        content << "  rankdir=LR;"
        content << "  node [shape=box];"

        @data[:imports]&.each do |import|
          from = import[:file].gsub(/[^a-zA-Z0-9]/, "_")
          to = import[:target].gsub(/[^a-zA-Z0-9]/, "_")
          content << "  \"#{from}\" -> \"#{to}\" [label=\"#{import[:kind]}\"];"
        end

        content << "}"

        if output
          File.write(output, content.join("\n"))
          Aidp::OutputLogger.puts "Graph written to #{output}"
        else
          Aidp::OutputLogger.puts content.join("\n")
        end
      end

      def generate_mermaid_graph(output)
        content = ["graph LR"]

        @data[:imports]&.each do |import|
          from = import[:file].gsub(/[^a-zA-Z0-9]/, "_")
          to = import[:target].gsub(/[^a-zA-Z0-9]/, "_")
          content << "  #{from} --> #{to}"
        end

        if output
          File.write(output, content.join("\n"))
          Aidp::OutputLogger.puts "Graph written to #{output}"
        else
          Aidp::OutputLogger.puts content.join("\n")
        end
      end

      def generate_json_graph(output)
        graph_data = {
          nodes: [],
          edges: []
        }

        # Add nodes
        files = (@data[:imports]&.map { |i| i[:file] } || []).uniq
        targets = (@data[:imports]&.map { |i| i[:target] } || []).uniq

        (files + targets).uniq.each do |node|
          graph_data[:nodes] << {id: node, label: node}
        end

        # Add edges
        @data[:imports]&.each do |import|
          graph_data[:edges] << {
            from: import[:file],
            to: import[:target],
            label: import[:kind]
          }
        end

        if output
          File.write(output, JSON.pretty_generate(graph_data))
          Aidp::OutputLogger.puts "Graph written to #{output}"
        else
          Aidp::OutputLogger.puts JSON.pretty_generate(graph_data)
        end
      end

      def generate_call_graph(_format, _output)
        # Similar to import graph but for method calls
        Aidp::OutputLogger.puts "Call graph generation not yet implemented"
      end

      def generate_cycle_graph(_format, _output)
        # Generate graph showing only the cycles
        Aidp::OutputLogger.puts "Cycle graph generation not yet implemented"
      end

      def count_files
        @data[:symbols]&.map { |s| s[:file] }&.uniq&.length || 0
      end
    end
  end
end
