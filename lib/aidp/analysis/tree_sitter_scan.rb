# frozen_string_literal: true

require "json"
require "fileutils"
require "digest"
require "etc"

require_relative "tree_sitter_grammar_loader"
require_relative "seams"

module Aidp
  module Analysis
    class TreeSitterScan
      def initialize(root: Dir.pwd, kb_dir: ".aidp/kb", langs: %w[ruby], threads: Etc.nprocessors)
        @root = File.expand_path(root)
        @kb_dir = File.expand_path(kb_dir, @root)
        @langs = Array(langs)
        @threads = threads
        @grammar_loader = TreeSitterGrammarLoader.new(@root)

        # Data structures to accumulate analysis results
        @symbols = []
        @imports = []
        @calls = []
        @metrics = []
        @seams = []
        @hotspots = []
        @tests = []
        @cycles = []

        # Cache for parsed files
        @cache = {}
        @cache_file = File.join(@kb_dir, ".cache")
      end

      def run
        puts "🔍 Starting Tree-sitter static analysis..."
        puts "📁 Root: #{@root}"
        puts "🗂️  KB Directory: #{@kb_dir}"
        puts "🌐 Languages: #{@langs.join(", ")}"
        puts "🧵 Threads: #{@threads}"

        files = discover_files
        puts "📄 Found #{files.length} files to analyze"

        prepare_kb_dir
        load_cache

        parallel_parse(files)
        write_kb_files

        puts "✅ Tree-sitter analysis complete!"
        puts "📊 Generated KB files in #{@kb_dir}"
      end

      private

      def discover_files
        files = []

        @langs.each do |lang|
          patterns = @grammar_loader.file_patterns_for_language(lang)
          patterns.each do |pattern|
            files.concat(Dir.glob(File.join(@root, pattern)))
          end
        end

        # Filter out files that should be ignored
        files = filter_ignored_files(files)

        # Sort for consistent processing
        files.sort
      end

      def filter_ignored_files(files)
        # Respect .gitignore
        gitignore_path = File.join(@root, ".gitignore")
        ignored_patterns = []

        if File.exist?(gitignore_path)
          File.readlines(gitignore_path).each do |line|
            line = line.strip
            next if line.empty? || line.start_with?("#")

            # Convert gitignore patterns to glob patterns
            pattern = convert_gitignore_to_glob(line)
            ignored_patterns << pattern
          end
        end

        # Add common ignore patterns
        ignored_patterns.concat([
          "**/.git/**", "**/node_modules/**", "**/vendor/**",
          "**/tmp/**", "tmp/**", "**/log/**", "log/**", "**/.aidp/**"
        ])

        files.reject do |file|
          relative_path = file.sub(/^#{Regexp.escape(@root)}\/?/, "")
          ignored_patterns.any? { |pattern| File.fnmatch?(pattern, relative_path) }
        end
      end

      # Convert gitignore patterns to Ruby glob patterns
      def convert_gitignore_to_glob(gitignore_pattern)
        # Handle different gitignore pattern types
        case gitignore_pattern
        when /^\//
          # Absolute path from root: /foo -> foo
          gitignore_pattern[1..]
        when /\/$/
          # Directory only: foo/ -> **/foo/**
          "**/" + gitignore_pattern.chomp("/") + "/**"
        when /\*\*/
          # Already contains **: leave as-is for glob
          gitignore_pattern
        else
          # Regular pattern: foo -> **/foo
          if gitignore_pattern.include?("/")
            # Contains path separator: keep relative structure
            gitignore_pattern
          else
            # Simple filename: match anywhere
            "**/" + gitignore_pattern
          end
        end
      end

      def prepare_kb_dir
        FileUtils.mkdir_p(@kb_dir)
      end

      def load_cache
        return unless File.exist?(@cache_file)

        begin
          @cache = JSON.parse(File.read(@cache_file), symbolize_names: true)
        rescue JSON::ParserError
          @cache = {}
        end
      end

      def save_cache
        File.write(@cache_file, JSON.pretty_generate(@cache))
      end

      def parallel_parse(files)
        puts "🔄 Parsing files in parallel..."

        # Group files by language for efficient processing
        files_by_lang = files.group_by { |file| detect_language(file) }

        # Process each language group
        files_by_lang.each do |lang, lang_files|
          puts "📝 Processing #{lang_files.length} #{lang} files..."

          # Load grammar for this language
          grammar = @grammar_loader.load_grammar(lang)

          # Process files synchronously (simplified)
          lang_files.each do |file|
            parse_file(file, grammar)
          end
        end

        save_cache
      end

      def detect_language(file_path)
        case File.extname(file_path)
        when ".rb"
          "ruby"
        when ".js", ".jsx"
          "javascript"
        when ".ts", ".tsx"
          "typescript"
        when ".py"
          "python"
        else
          "unknown"
        end
      end

      def parse_file(file_path, grammar)
        relative_path = file_path.sub(@root + File::SEPARATOR, "")

        # Check cache first
        cache_key = relative_path
        file_mtime = File.mtime(file_path).to_i

        if @cache[cache_key] && @cache[cache_key][:mtime] == file_mtime
          # Use cached results
          cached_data = @cache[cache_key][:data]
          merge_cached_data(cached_data)
          return
        end

        # Parse the file
        # Set current file for context in helper methods
        @current_file_path = file_path

        source_code = File.read(file_path)
        ast = grammar[:parser][:parse].call(source_code)

        # Extract data from AST
        file_data = extract_file_data(file_path, ast, source_code)

        # Cache the results
        @cache[cache_key] = {
          mtime: file_mtime,
          data: file_data
        }

        # Merge into global data structures
        merge_file_data(file_data)
      end

      def extract_file_data(file_path, ast, source_code)
        relative_path = file_path.sub(@root + File::SEPARATOR, "")

        {
          symbols: extract_symbols(ast, relative_path),
          imports: extract_imports(ast, relative_path),
          calls: extract_calls(ast, relative_path),
          metrics: calculate_metrics(ast, source_code, relative_path),
          seams: extract_seams(ast, relative_path)
        }
      end

      def extract_symbols(ast, file_path)
        symbols = []

        children = ast[:children] || []
        children = children.is_a?(Array) ? children : []

        children.each do |node|
          case node[:type].to_s
          when "class"
            symbols << {
              id: "#{file_path}:#{node[:line]}:#{node[:name]}",
              file: file_path,
              line: node[:line],
              kind: "class",
              name: node[:name],
              visibility: "public",
              arity: 0,
              loc: {
                start_line: node[:line],
                end_line: node[:line],
                start_column: node[:start_column],
                end_column: node[:end_column]
              },
              nesting_depth: calculate_nesting_depth(node)
            }
          when "module"
            symbols << {
              id: "#{file_path}:#{node[:line]}:#{node[:name]}",
              file: file_path,
              line: node[:line],
              kind: "module",
              name: node[:name],
              visibility: "public",
              arity: 0,
              loc: {
                start_line: node[:line],
                end_line: node[:line],
                start_column: node[:start_column],
                end_column: node[:end_column]
              },
              nesting_depth: calculate_nesting_depth(node)
            }
          when "method"
            symbols << {
              id: "#{file_path}:#{node[:line]}:#{node[:name]}",
              file: file_path,
              line: node[:line],
              kind: "method",
              name: node[:name],
              visibility: determine_method_visibility(node),
              arity: calculate_method_arity(node),
              loc: {
                start_line: node[:line],
                end_line: node[:line],
                start_column: node[:start_column],
                end_column: node[:end_column]
              },
              nesting_depth: calculate_nesting_depth(node)
            }
          end
        end

        symbols
      end

      def extract_imports(ast, file_path)
        imports = []

        children = ast[:children] || []
        children = children.is_a?(Array) ? children : []

        children.each do |node|
          case node[:type].to_s
          when "require"
            imports << {
              file: file_path,
              kind: "require",
              target: node[:target],
              line: node[:line]
            }
          when "require_relative"
            imports << {
              file: file_path,
              kind: "require_relative",
              target: node[:target],
              line: node[:line]
            }
          when "call"
            # Handle require statements that are parsed as call nodes
            # Check if this is a require call by looking at the first child (identifier)
            # The children are nested in the structure
            actual_children = (node[:children] && node[:children][:children]) ? node[:children][:children] : node[:children]
            if actual_children&.is_a?(Array) && actual_children.first
              first_child = actual_children.first
              # Extract the actual identifier name from the source code
              identifier_name = extract_identifier_name(first_child, file_path)
              if identifier_name == "require"
                # Extract the target from the argument list
                target = extract_require_target(node)
                if target
                  imports << {
                    file: file_path,
                    kind: "require",
                    target: target,
                    line: node[:line]
                  }
                end
              elsif identifier_name == "require_relative"
                # Extract the target from the argument list
                target = extract_require_target(node)
                if target
                  imports << {
                    file: file_path,
                    kind: "require_relative",
                    target: target,
                    line: node[:line]
                  }
                end
              end
            end
          end
        end

        imports
      end

      def extract_require_target(node)
        # Recursively search for string literals in the require call
        find_string_in_node(node)
      end

      # Recursively find string content in a Tree-sitter node
      def find_string_in_node(node)
        return nil unless node.is_a?(Hash)

        case node[:type].to_s
        when "string"
          # Found a string node - extract its content
          return extract_string_literal_content(node)
        when "string_content"
          # Direct string content - extract text
          return extract_node_text_from_source(node)
        end

        # Recursively search in children
        children = get_node_children(node)
        if children&.is_a?(Array)
          children.each do |child|
            result = find_string_in_node(child)
            return result if result
          end
        end

        nil
      end

      # Extract content from a string literal, handling quotes properly
      def extract_string_literal_content(string_node)
        # Get the full text of the string node including quotes
        full_text = extract_node_text_from_source(string_node)
        return nil unless full_text

        # Remove quotes and handle escape sequences
        case full_text[0]
        when '"'
          # Double-quoted string - handle escape sequences
          content = full_text[1..-2] # Remove surrounding quotes
          unescape_string(content)
        when "'"
          # Single-quoted string - minimal escaping
          content = full_text[1..-2] # Remove surrounding quotes
          content.gsub("\\'", "'").gsub("\\\\", "\\")
        when "%"
          # Percent notation strings (%q, %Q, %w, etc.)
          handle_percent_string(full_text)
        else
          # Fallback: try to extract content between quotes
          if (match = full_text.match(/^["'](.*)["']$/))
            match[1]
          else
            full_text
          end
        end
      end

      # Handle Ruby's percent notation strings
      def handle_percent_string(text)
        return text unless text.start_with?("%")

        case text[1]
        when "q", "Q"
          # %q{...} or %Q{...}
          delimiter = text[2]
          closing_delimiter = get_closing_delimiter(delimiter)
          content = text[3..-(closing_delimiter.length + 1)]
          (text[1] == "Q") ? unescape_string(content) : content
        else
          text
        end
      end

      # Get closing delimiter for percent strings
      def get_closing_delimiter(opening)
        case opening
        when "(" then ")"
        when "[" then "]"
        when "{" then "}"
        when "<" then ">"
        else; opening
        end
      end

      # Unescape common Ruby escape sequences
      def unescape_string(str)
        str.gsub("\\n", "\n")
          .gsub("\\t", "\t")
          .gsub("\\r", "\r")
          .gsub('\"', '"')
          .gsub("\\\\", "\\")
      end

      # Safely extract children from a node, handling nested structures
      def get_node_children(node)
        if node[:children].is_a?(Hash) && node[:children][:children]
          node[:children][:children]
        else
          node[:children]
        end
      end

      def extract_string_content(string_content_node, _line_number)
        # Extract the actual string content from the source code using node position
        extract_node_text_from_source(string_content_node)
      end

      def extract_identifier_name(identifier_node, file_path)
        # Extract the actual identifier name from the source code using node position
        extract_node_text_from_source(identifier_node, file_path)
      end

      # Generalized method to extract text from any Tree-sitter node using source position
      def extract_node_text_from_source(node, file_path = nil)
        return nil unless node&.dig(:start_line) && node.dig(:end_line)
        return nil unless node&.dig(:start_column) && node.dig(:end_column)

        # Get source file path - either from parameter or from current parsing context
        source_file = file_path ? File.join(@root, file_path) : @current_file_path
        return nil unless source_file && File.exist?(source_file)

        # Read source lines
        source_lines = File.readlines(source_file)

        start_line = node[:start_line]
        end_line = node[:end_line]
        start_col = node[:start_column]
        end_col = node[:end_column]

        # Handle single line nodes
        if start_line == end_line
          line_content = source_lines[start_line - 1] || ""
          return line_content[start_col...end_col]
        end

        # Handle multi-line nodes
        result = ""
        (start_line..end_line).each do |line_num|
          line_content = source_lines[line_num - 1] || ""

          result += if line_num == start_line
            # First line: from start_col to end
            line_content[start_col..] || ""
          elsif line_num == end_line
            # Last line: from start to end_col
            line_content[0...end_col] || ""
          else
            # Middle lines: entire line
            line_content
          end
        end

        result
      end

      def extract_calls(_ast, _file_path)
        []

        # This would extract method calls from the AST
        # For now, return empty array
      end

      def calculate_metrics(ast, source_code, file_path)
        metrics = []

        ast[:children]&.each do |node|
          if node[:type] == "method"
            method_metrics = {
              symbol_id: "#{file_path}:#{node[:line]}:#{node[:name]}",
              file: file_path,
              method: node[:name],
              cyclomatic_proxy: calculate_cyclomatic_complexity(node),
              branch_count: count_branches(node),
              max_nesting: calculate_max_nesting(node),
              fan_out: calculate_fan_out(node),
              lines: calculate_method_lines(node)
            }
            metrics << method_metrics
          end
        end

        # Add file-level metrics
        children = ast[:children] || []
        children = children.is_a?(Array) ? children : []

        file_metrics = {
          file: file_path,
          total_lines: source_code.lines.count,
          total_methods: children.count { |n| n[:type].to_s == "method" },
          total_classes: children.count { |n| n[:type].to_s == "class" },
          total_modules: children.count { |n| n[:type].to_s == "module" }
        }
        metrics << file_metrics

        metrics
      end

      def extract_seams(ast, file_path)
        children = ast[:children] || []
        children = children.is_a?(Array) ? children : []
        Seams.detect_seams_in_ast(children, file_path)
      end

      def calculate_nesting_depth(_node)
        # Simple nesting depth calculation
        # In practice, this would analyze the actual AST structure
        0
      end

      def determine_method_visibility(_node)
        # Determine method visibility based on context
        # In practice, this would analyze the AST structure
        "public"
      end

      def calculate_method_arity(_node)
        # Calculate method arity from parameters
        # In practice, this would analyze the method's parameter list
        0
      end

      def calculate_cyclomatic_complexity(node)
        # Calculate cyclomatic complexity proxy
        # Count control flow statements
        count_branches(node) + 1
      end

      def count_branches(_node)
        # Count branching statements in the method
        # This would analyze the method's AST for if/elsif/else/case/when/while/until/rescue
        0
      end

      def calculate_max_nesting(_node)
        # Calculate maximum nesting depth in the method
        0
      end

      def calculate_fan_out(_node)
        # Calculate fan-out (number of distinct method calls)
        0
      end

      def calculate_method_lines(_node)
        # Calculate lines of code in the method
        1
      end

      def merge_cached_data(cached_data)
        @symbols.concat(cached_data[:symbols] || [])
        @imports.concat(cached_data[:imports] || [])
        @calls.concat(cached_data[:calls] || [])
        @metrics.concat(cached_data[:metrics] || [])
        @seams.concat(cached_data[:seams] || [])
      end

      def merge_file_data(file_data)
        @symbols.concat(file_data[:symbols])
        @imports.concat(file_data[:imports])
        @calls.concat(file_data[:calls])
        @metrics.concat(file_data[:metrics])
        @seams.concat(file_data[:seams])
      end

      def write_kb_files
        puts "💾 Writing knowledge base files..."

        prepare_kb_dir

        write_json_file("symbols.json", @symbols)
        write_json_file("imports.json", @imports)
        write_json_file("calls.json", @calls)
        write_json_file("metrics.json", @metrics)
        write_json_file("seams.json", @seams)

        # Generate derived data
        generate_hotspots
        generate_tests
        generate_cycles

        write_json_file("hotspots.json", @hotspots)
        write_json_file("tests.json", @tests)
        write_json_file("cycles.json", @cycles)
      end

      def write_json_file(filename, data)
        file_path = File.join(@kb_dir, filename)
        File.write(file_path, JSON.pretty_generate(data))
        puts "📄 Written #{filename} (#{data.length} entries)"
      end

      def generate_hotspots
        # Merge structural metrics with git churn data
        # For now, create mock hotspots based on complexity
        @hotspots = @metrics.select { |m| m[:symbol_id] }
          .map do |metric|
            {
              symbol_id: metric[:symbol_id],
              score: (metric[:cyclomatic_proxy] || 1) * (metric[:fan_out] || 1),
              complexity: metric[:cyclomatic_proxy] || 1,
              touches: 1, # This would come from git log analysis
              file: metric[:file],
              method: metric[:method]
            }
          end
          .sort_by { |h| -h[:score] }
          .first(20)
      end

      def generate_tests
        # Map public APIs to tests based on naming conventions
        public_methods = @symbols.select { |s| s[:kind] == "method" && s[:visibility] == "public" }

        @tests = public_methods.map do |method|
          {
            symbol_id: method[:id],
            tests: find_tests_for_method(method)
          }
        end
      end

      def generate_cycles
        # Detect import cycles
        # For now, return empty array
        @cycles = []
      end

      def find_tests_for_method(_method)
        # Find test files that might test this method
        # This would analyze test file naming and content
        []
      end
    end
  end
end
