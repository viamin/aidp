# frozen_string_literal: true

require "json"
require "cli/ui"

module Aidp
  module Analysis
    class KBInspector
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
          puts "Unknown KB type: #{type}"
          puts "Available types: seams, hotspots, cycles, apis, symbols, imports, summary"
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
          puts "Unknown graph type: #{type}"
          puts "Available types: imports, calls, cycles"
        end
      end

      private

      def truncate_text(text, max_length = 50)
        return nil unless text
        return text if text.length <= max_length

        text[0..max_length - 4] + "..."
      end

      def create_table(header, rows)
        # Use CLI UI for table display instead of TTY::Table
        CLI::UI::Frame.open("Knowledge Base Data") do
          rows.each_with_index do |row, index|
            CLI::UI::Frame.open("Row #{index + 1}") do
              header.each_with_index do |col_header, col_index|
                puts "#{col_header}: #{row[col_index]}"
              end
            end
          end
        end
      end

      def load_kb_data
        data = {}

        %w[symbols imports calls metrics seams hotspots tests cycles].each do |type|
          file_path = File.join(@kb_dir, "#{type}.json")
          if File.exist?(file_path)
            begin
              data[type.to_sym] = JSON.parse(File.read(file_path), symbolize_names: true)
            rescue JSON::ParserError => e
              # Suppress warnings in test mode to avoid CI failures
              unless ENV["RACK_ENV"] == "test" || defined?(RSpec)
                puts "Warning: Could not parse #{file_path}: #{e.message}"
              end
              data[type.to_sym] = []
            end
          else
            data[type.to_sym] = []
          end
        end

        data
      end

      def show_summary(_format)
        puts "\n📊 Knowledge Base Summary"
        puts "=" * 50

        puts "📁 KB Directory: #{@kb_dir}"
        puts "📄 Files analyzed: #{count_files}"
        puts "🏗️  Symbols: #{@data[:symbols]&.length || 0}"
        puts "📦 Imports: #{@data[:imports]&.length || 0}"
        puts "🔗 Calls: #{@data[:calls]&.length || 0}"
        puts "📏 Metrics: #{@data[:metrics]&.length || 0}"
        puts "🔧 Seams: #{@data[:seams]&.length || 0}"
        puts "🔥 Hotspots: #{@data[:hotspots]&.length || 0}"
        puts "🧪 Tests: #{@data[:tests]&.length || 0}"
        puts "🔄 Cycles: #{@data[:cycles]&.length || 0}"

        if @data[:seams]&.any?
          puts "\n🔧 Seam Types:"
          seam_types = @data[:seams].group_by { |s| s[:kind] }
          seam_types.each do |type, seams|
            puts "  #{type}: #{seams.length}"
          end
        end

        if @data[:hotspots]&.any?
          puts "\n🔥 Top 5 Hotspots:"
          @data[:hotspots].first(5).each_with_index do |hotspot, i|
            puts "  #{i + 1}. #{hotspot[:file]}:#{hotspot[:method]} (score: #{hotspot[:score]})"
          end
        end
      end

      def show_seams(format)
        return puts "No seams data available" unless @data[:seams]&.any?

        case format
        when "json"
          puts JSON.pretty_generate(@data[:seams])
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

        puts "\n🔧 Seams Analysis"
        puts "=" * 80
        puts table.render
      end

      def show_seams_summary
        puts "\n🔧 Seams Analysis"
        puts "=" * 50

        seam_types = @data[:seams].group_by { |s| s[:kind] }

        seam_types.each do |type, seams|
          puts "\n📌 #{type.upcase} (#{seams.length} found)"
          puts "-" * 30

          seams.first(10).each do |seam|
            puts "  #{seam[:file]}:#{seam[:line]}"
            puts "    Symbol: #{seam[:symbol_id]&.split(":")&.last}"
            puts "    Suggestion: #{seam[:suggestion]}"
            puts
          end

          if seams.length > 10
            puts "  ... and #{seams.length - 10} more"
          end
        end
      end

      def show_hotspots(format)
        return puts "No hotspots data available" unless @data[:hotspots]&.any?

        case format
        when "json"
          puts JSON.pretty_generate(@data[:hotspots])
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

        puts "\n🔥 Code Hotspots"
        puts "=" * 80
        puts table.render
      end

      def show_hotspots_summary
        puts "\n🔥 Code Hotspots (Top 20)"
        puts "=" * 50

        @data[:hotspots].each_with_index do |hotspot, i|
          puts "#{i + 1}. #{hotspot[:file]}:#{hotspot[:method]}"
          puts "   Score: #{hotspot[:score]} (Complexity: #{hotspot[:complexity]}, Touches: #{hotspot[:touches]})"
          puts
        end
      end

      def show_cycles(format)
        return puts "No cycles data available" unless @data[:cycles]&.any?

        case format
        when "json"
          puts JSON.pretty_generate(@data[:cycles])
        else
          show_cycles_summary
        end
      end

      def show_cycles_summary
        puts "\n🔄 Import Cycles"
        puts "=" * 50

        @data[:cycles].each_with_index do |cycle, i|
          puts "Cycle #{i + 1}:"
          cycle[:members].each do |member|
            puts "  - #{member}"
          end
          puts "  Weight: #{cycle[:weight]}" if cycle[:weight]
          puts
        end
      end

      def show_apis(format)
        return puts "No APIs data available" unless @data[:tests]&.any?

        untested_apis = @data[:tests].select { |t| t[:tests].empty? }

        case format
        when "json"
          puts JSON.pretty_generate(untested_apis)
        else
          show_apis_summary(untested_apis)
        end
      end

      def show_apis_summary(untested_apis)
        puts "\n🧪 Untested Public APIs"
        puts "=" * 50

        if untested_apis.empty?
          puts "✅ All public APIs have associated tests!"
        else
          puts "Found #{untested_apis.length} untested public APIs:"
          puts

          untested_apis.each do |api|
            symbol = @data[:symbols]&.find { |s| s[:id] == api[:symbol_id] }
            if symbol
              puts "  #{symbol[:file]}:#{symbol[:line]} - #{symbol[:name]}"
              puts "    Suggestion: Create characterization tests"
              puts
            end
          end
        end
      end

      def show_symbols(format)
        return puts "No symbols data available" unless @data[:symbols]&.any?

        case format
        when "json"
          puts JSON.pretty_generate(@data[:symbols])
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

        puts "\n🏗️  Symbols"
        puts "=" * 80
        puts table.render
      end

      def show_symbols_summary
        puts "\n🏗️  Symbols Summary"
        puts "=" * 50

        symbol_types = @data[:symbols].group_by { |s| s[:kind] }

        symbol_types.each do |type, symbols|
          puts "#{type.capitalize}: #{symbols.length}"
        end
      end

      def show_imports(format)
        return puts "No imports data available" unless @data[:imports]&.any?

        case format
        when "json"
          puts JSON.pretty_generate(@data[:imports])
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

        puts "\n📦 Imports"
        puts "=" * 80
        puts table.render
      end

      def show_imports_summary
        puts "\n📦 Imports Summary"
        puts "=" * 50

        import_types = @data[:imports].group_by { |i| i[:kind] }

        import_types.each do |type, imports|
          puts "#{type.capitalize}: #{imports.length}"
        end
      end

      def generate_import_graph(format, output)
        puts "Generating import graph in #{format} format..."

        case format
        when "dot"
          generate_dot_graph(output)
        when "mermaid"
          generate_mermaid_graph(output)
        when "json"
          generate_json_graph(output)
        else
          puts "Unsupported graph format: #{format}"
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
          puts "Graph written to #{output}"
        else
          puts content.join("\n")
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
          puts "Graph written to #{output}"
        else
          puts content.join("\n")
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
          puts "Graph written to #{output}"
        else
          puts JSON.pretty_generate(graph_data)
        end
      end

      def generate_call_graph(_format, _output)
        # Similar to import graph but for method calls
        puts "Call graph generation not yet implemented"
      end

      def generate_cycle_graph(_format, _output)
        # Generate graph showing only the cycles
        puts "Cycle graph generation not yet implemented"
      end

      def count_files
        @data[:symbols]&.map { |s| s[:file] }&.uniq&.length || 0
      end
    end
  end
end
