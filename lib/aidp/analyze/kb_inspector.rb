# frozen_string_literal: true

require "json"
require "tty-box"
require "tty-prompt"

module Aidp
  module Analyze
    class KBInspector
      include Aidp::MessageDisplay

      def initialize(kb_dir = ".aidp/kb", prompt: TTY::Prompt.new)
        @kb_dir = File.expand_path(kb_dir)
        @prompt = prompt
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
          display_message("Unknown KB type: #{type}", type: :error)
          display_message("Available types: seams, hotspots, cycles, apis, symbols, imports, summary", type: :info)
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
          display_message("Unknown graph type: #{type}", type: :error)
          display_message("Available types: imports, calls, cycles", type: :info)
        end
      end

      private

      def truncate_text(text, max_length = 50)
        return nil unless text
        return text if text.length <= max_length

        text[0..max_length - 4] + "..."
      end

      def create_table(header, rows)
        # Use TTY::Box for table display
        content = []
        rows.each_with_index do |row, index|
          row_content = []
          header.each_with_index do |col_header, col_index|
            row_content << "#{col_header}: #{row[col_index]}"
          end
          content << "Row #{index + 1}:\n#{row_content.join("\n")}"
        end

        box = TTY::Box.frame(
          content.join("\n\n"),
          title: {top_left: "Knowledge Base Data"},
          border: :thick,
          padding: [1, 2]
        )
        display_message(box)
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
                display_message("Warning: Could not parse #{file_path}: #{e.message}", type: :warn)
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
        display_message("\n📊 Knowledge Base Summary", type: :highlight)
        display_message("=" * 50, type: :info)

        display_message("📁 KB Directory: #{@kb_dir}", type: :info)
        display_message("📄 Files analyzed: #{count_files}", type: :info)
        display_message("🏗️  Symbols: #{@data[:symbols]&.length || 0}", type: :info)
        display_message("📦 Imports: #{@data[:imports]&.length || 0}", type: :info)
        display_message("🔗 Calls: #{@data[:calls]&.length || 0}", type: :info)
        display_message("📏 Metrics: #{@data[:metrics]&.length || 0}", type: :info)
        display_message("🔧 Seams: #{@data[:seams]&.length || 0}", type: :info)
        display_message("🔥 Hotspots: #{@data[:hotspots]&.length || 0}", type: :info)
        display_message("🧪 Tests: #{@data[:tests]&.length || 0}", type: :info)
        display_message("🔄 Cycles: #{@data[:cycles]&.length || 0}", type: :info)

        if @data[:seams]&.any?
          display_message("\n🔧 Seam Types:", type: :info)
          seam_types = @data[:seams].group_by { |s| s[:kind] }
          seam_types.each do |type, seams|
            display_message("  #{type}: #{seams.length}", type: :info)
          end
        end

        if @data[:hotspots]&.any?
          display_message("\n🔥 Top 5 Hotspots:", type: :info)
          @data[:hotspots].first(5).each_with_index do |hotspot, i|
            display_message("  #{i + 1}. #{hotspot[:file]}:#{hotspot[:method]} (score: #{hotspot[:score]})", type: :info)
          end
        end
      end

      def show_seams(format)
        return display_message("No seams data available") unless @data[:seams]&.any?

        case format
        when "json"
          display_message(JSON.pretty_generate(@data[:seams]))
        when "table"
          show_seams_table
        else
          show_seams_summary
        end
      end

      def show_seams_table
        display_message("\n🔧 Seams Analysis")
        display_message("=" * 80)

        create_table(
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
      end

      def show_seams_summary
        display_message("\n🔧 Seams Analysis")
        display_message("=" * 50)

        seam_types = @data[:seams].group_by { |s| s[:kind] }

        seam_types.each do |type, seams|
          display_message("\n📌 #{type.upcase} (#{seams.length} found)")
          display_message("-" * 30)

          seams.first(10).each do |seam|
            display_message("  #{seam[:file]}:#{seam[:line]}")
            display_message("    Symbol: #{seam[:symbol_id]&.split(":")&.last}")
            display_message("    Suggestion: #{seam[:suggestion]}")
            display_message("")
          end

          if seams.length > 10
            display_message("  ... and #{seams.length - 10} more")
          end
        end
      end

      def show_hotspots(format)
        return display_message("No hotspots data available") unless @data[:hotspots]&.any?

        case format
        when "json"
          display_message(JSON.pretty_generate(@data[:hotspots]))
        when "table"
          show_hotspots_table
        else
          show_hotspots_summary
        end
      end

      def show_hotspots_table
        display_message("\n🔥 Code Hotspots")
        display_message("=" * 80)

        create_table(
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
      end

      def show_hotspots_summary
        display_message("\n🔥 Code Hotspots (Top 20)")
        display_message("=" * 50)

        @data[:hotspots].each_with_index do |hotspot, i|
          display_message("#{i + 1}. #{hotspot[:file]}:#{hotspot[:method]}")
          display_message("   Score: #{hotspot[:score]} (Complexity: #{hotspot[:complexity]}, Touches: #{hotspot[:touches]})")
          display_message("")
        end
      end

      def show_cycles(format)
        return display_message("No cycles data available") unless @data[:cycles]&.any?

        case format
        when "json"
          display_message(JSON.pretty_generate(@data[:cycles]))
        else
          show_cycles_summary
        end
      end

      def show_cycles_summary
        display_message("\n🔄 Import Cycles")
        display_message("=" * 50)

        @data[:cycles].each_with_index do |cycle, i|
          display_message("Cycle #{i + 1}:")
          cycle[:members].each do |member|
            display_message("  - #{member}")
          end
          display_message("  Weight: #{cycle[:weight]}") if cycle[:weight]
          display_message("")
        end
      end

      def show_apis(format)
        return display_message("No APIs data available") unless @data[:tests]&.any?

        untested_apis = @data[:tests].select { |t| t[:tests].empty? }

        case format
        when "json"
          display_message(JSON.pretty_generate(untested_apis))
        else
          show_apis_summary(untested_apis)
        end
      end

      def show_apis_summary(untested_apis)
        display_message("\n🧪 Untested Public APIs")
        display_message("=" * 50)

        if untested_apis.empty?
          display_message("✅ All public APIs have associated tests!")
        else
          display_message("Found #{untested_apis.length} untested public APIs:")
          display_message("")

          untested_apis.each do |api|
            symbol = @data[:symbols]&.find { |s| s[:id] == api[:symbol_id] }
            if symbol
              display_message("  #{symbol[:file]}:#{symbol[:line]} - #{symbol[:name]}")
              display_message("    Suggestion: Create characterization tests")
              display_message("")
            end
          end
        end
      end

      def show_symbols(format)
        return display_message("No symbols data available") unless @data[:symbols]&.any?

        case format
        when "json"
          display_message(JSON.pretty_generate(@data[:symbols]))
        when "table"
          show_symbols_table
        else
          show_symbols_summary
        end
      end

      def show_symbols_table
        display_message("\n🏗️  Symbols")
        display_message("=" * 80)

        create_table(
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
      end

      def show_symbols_summary
        display_message("\n🏗️  Symbols Summary")
        display_message("=" * 50)

        symbol_types = @data[:symbols].group_by { |s| s[:kind] }

        symbol_types.each do |type, symbols|
          display_message("#{type.capitalize}: #{symbols.length}")
        end
      end

      def show_imports(format)
        return display_message("No imports data available") unless @data[:imports]&.any?

        case format
        when "json"
          display_message(JSON.pretty_generate(@data[:imports]))
        when "table"
          show_imports_table
        else
          show_imports_summary
        end
      end

      def show_imports_table
        display_message("\n📦 Imports")
        display_message("=" * 80)

        create_table(
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
      end

      def show_imports_summary
        display_message("\n📦 Imports Summary")
        display_message("=" * 50)

        import_types = @data[:imports].group_by { |i| i[:kind] }

        import_types.each do |type, imports|
          display_message("#{type.capitalize}: #{imports.length}")
        end
      end

      def generate_import_graph(format, output)
        display_message("Generating import graph in #{format} format...")

        case format
        when "dot"
          generate_dot_graph(output)
        when "mermaid"
          generate_mermaid_graph(output)
        when "json"
          generate_json_graph(output)
        else
          display_message("Unsupported graph format: #{format}")
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
          display_message("Graph written to #{output}")
        else
          display_message(content.join("\n"))
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
          display_message("Graph written to #{output}")
        else
          display_message(content.join("\n"))
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
          display_message("Graph written to #{output}")
        else
          display_message(JSON.pretty_generate(graph_data))
        end
      end

      def generate_call_graph(_format, _output)
        # Similar to import graph but for method calls
        display_message("Call graph generation not yet implemented")
      end

      def generate_cycle_graph(_format, _output)
        # Generate graph showing only the cycles
        display_message("Cycle graph generation not yet implemented")
      end

      def count_files
        @data[:symbols]&.map { |s| s[:file] }&.uniq&.length || 0
      end
    end
  end
end
