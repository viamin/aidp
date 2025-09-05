# frozen_string_literal: true

require "tree_sitter"
require "fileutils"

module Aidp
  module Analysis
    class TreeSitterGrammarLoader
      # Default grammar configurations
      GRAMMAR_CONFIGS = {
        "ruby" => {
          name: "tree-sitter-ruby",
          version: "0.20.0",
          source: "https://github.com/tree-sitter/tree-sitter-ruby",
          file_patterns: ["**/*.rb"],
          node_types: {
            class: "class",
            module: "module",
            method: "method",
            call: "call",
            require: "call",
            require_relative: "call"
          }
        },
        "javascript" => {
          name: "tree-sitter-javascript",
          version: "0.20.0",
          source: "https://github.com/tree-sitter/tree-sitter-javascript",
          file_patterns: ["**/*.js", "**/*.jsx"],
          node_types: {
            class: "class_declaration",
            function: "function_declaration",
            call: "call_expression",
            import: "import_statement"
          }
        },
        "typescript" => {
          name: "tree-sitter-typescript",
          version: "0.20.0",
          source: "https://github.com/tree-sitter/tree-sitter-typescript",
          file_patterns: ["**/*.ts", "**/*.tsx"],
          node_types: {
            class: "class_declaration",
            function: "function_declaration",
            call: "call_expression",
            import: "import_statement"
          }
        },
        "python" => {
          name: "tree-sitter-python",
          version: "0.20.0",
          source: "https://github.com/tree-sitter/tree-sitter-python",
          file_patterns: ["**/*.py"],
          node_types: {
            class: "class_definition",
            function: "function_definition",
            call: "call",
            import: "import_statement"
          }
        }
      }.freeze

      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
        @grammars_dir = File.join(project_dir, ".aidp", "grammars")
        @loaded_grammars = {}
      end

      # Load grammar for a specific language
      def load_grammar(language)
        return @loaded_grammars[language] if @loaded_grammars[language]

        config = GRAMMAR_CONFIGS[language]
        raise "Unsupported language: #{language}" unless config

        ensure_grammar_available(language, config)
        @loaded_grammars[language] = create_parser(language, config)
      end

      # Get supported languages
      def supported_languages
        GRAMMAR_CONFIGS.keys
      end

      # Get file patterns for a language
      def file_patterns_for_language(language)
        config = GRAMMAR_CONFIGS[language]
        return [] unless config

        config[:file_patterns]
      end

      # Get node types for a language
      def node_types_for_language(language)
        config = GRAMMAR_CONFIGS[language]
        return {} unless config

        config[:node_types]
      end

      private

      def ensure_grammar_available(language, config)
        grammar_path = File.join(@grammars_dir, language)

        unless File.exist?(grammar_path)
          puts "Installing Tree-sitter grammar for #{language}..."
          install_grammar(language, config)
        end
      end

      def install_grammar(language, config)
        FileUtils.mkdir_p(@grammars_dir)

        # For now, we'll use the system-installed grammars
        # In a production setup, you might want to download and compile grammars
        grammar_path = File.join(@grammars_dir, language)

        # Create a placeholder file to indicate the grammar is "installed"
        # The actual grammar loading will be handled by tree_sitter
        FileUtils.mkdir_p(grammar_path)
        require "json"
        File.write(File.join(grammar_path, "grammar.json"), JSON.generate(config))

        puts "Grammar for #{language} marked as available"
      end

      def create_parser(language, config)
        # Create a Tree-sitter parser for the language
        # This is a simplified version - in practice you'd need to handle
        # the actual grammar loading from the ruby_tree_sitter gem

        {
          language: language,
          config: config,
          parser: create_tree_sitter_parser(language)
        }
      end

      def create_tree_sitter_parser(language)
        create_real_parser(language)
      end

      def create_real_parser(language)
        parser = TreeSitter::Parser.new
        language_obj = TreeSitter.lang(language)
        parser.language = language_obj

        {
          parse: ->(source_code) { parse_with_tree_sitter(parser, source_code) },
          language: language,
          real: true
        }
      rescue TreeSitter::ParserNotFoundError => e
        puts "Warning: Tree-sitter parser not found for #{language}: #{e.message}"
        create_mock_parser(language)
      rescue => e
        puts "Warning: Failed to create Tree-sitter parser for #{language}: #{e.message}"
        create_mock_parser(language)
      end

      def create_mock_parser(language)
        case language
        when "ruby"
          create_ruby_parser
        when "javascript"
          create_javascript_parser
        when "typescript"
          create_typescript_parser
        when "python"
          create_python_parser
        else
          raise "Unsupported language: #{language}"
        end
      end

      def parse_with_tree_sitter(parser, source_code)
        tree = parser.parse_string(nil, source_code)
        root = tree.root_node

        # Convert Tree-sitter AST to our internal format
        convert_tree_sitter_ast(root, source_code)
      end

      def convert_tree_sitter_ast(node, source_code)
        children = []

        begin
          node.each do |child|
            child_data = {
              type: child.type,
              name: extract_node_name(child, source_code),
              line: child.start_point.row + 1,
              start_column: child.start_point.column,
              end_column: child.end_point.column
            }

            # Recursively process child nodes
            if child.child_count > 0
              child_data[:children] = convert_tree_sitter_ast(child, source_code)
            end

            children << child_data
          end
        rescue => e
          puts "Warning: Error converting Tree-sitter AST: #{e.message}"
          # Return empty structure if conversion fails
          return {
            type: node.type,
            children: []
          }
        end

        {
          type: node.type,
          children: children
        }
      end

      def extract_node_name(node, source_code)
        # Extract meaningful names from nodes
        case node.type.to_s
        when "class", "module"
          # Look for the class/module name in the source, handling nested constants
          lines = source_code.lines
          line_content = lines[node.start_point.row] || ""
          # Handle patterns like: class Foo, class Foo::Bar, module A::B::C
          if (match = line_content.match(/(?:class|module)\s+((?:\w+::)*\w+)/))
            match[1]
          else
            node.type.to_s
          end
        when "method"
          # Look for method name, handling various definition styles
          lines = source_code.lines
          line_content = lines[node.start_point.row] || ""
          # Handle: def foo, def foo(args), def foo=(value), def []=(key, value)
          if (match = line_content.match(/def\s+([\w\[\]=!?]+)/))
            match[1]
          else
            node.type.to_s
          end
        when "singleton_method"
          # Look for singleton method name, handling class methods
          lines = source_code.lines
          line_content = lines[node.start_point.row] || ""
          # Handle: def self.foo, def ClassName.foo, def obj.method_name
          if (match = line_content.match(/def\s+(?:self|[\w:]+)\.([\w\[\]=!?]+)/))
            match[1]
          else
            node.type.to_s
          end
        when "constant"
          # Extract constant names
          lines = source_code.lines
          line_content = lines[node.start_point.row] || ""
          # Handle: CONSTANT = value, A::B::CONSTANT = value
          if (match = line_content.match(/((?:\w+::)*[A-Z_][A-Z0-9_]*)\s*=/))
            match[1]
          else
            node.type.to_s
          end
        else
          node.type.to_s
        end
      end

      def create_ruby_parser
        # Mock Ruby parser - fallback when Tree-sitter is not available
        {
          parse: ->(source_code) { parse_ruby_source(source_code) },
          language: "ruby",
          real: false
        }
      end

      def create_javascript_parser
        {
          parse: ->(source_code) { parse_javascript_source(source_code) },
          language: "javascript",
          real: false
        }
      end

      def create_typescript_parser
        {
          parse: ->(source_code) { parse_typescript_source(source_code) },
          language: "typescript",
          real: false
        }
      end

      def create_python_parser
        {
          parse: ->(source_code) { parse_python_source(source_code) },
          language: "python",
          real: false
        }
      end

      # Mock parsing methods - these would be replaced with actual Tree-sitter parsing
      def parse_ruby_source(source_code)
        # This would use the actual ruby_tree_sitter gem
        # For now, return a mock AST structure
        {
          type: "program",
          children: extract_ruby_nodes(source_code)
        }
      end

      def parse_javascript_source(source_code)
        {
          type: "program",
          children: extract_javascript_nodes(source_code)
        }
      end

      def parse_typescript_source(source_code)
        {
          type: "program",
          children: extract_typescript_nodes(source_code)
        }
      end

      def parse_python_source(source_code)
        {
          type: "module",
          children: extract_python_nodes(source_code)
        }
      end

      # Simple regex-based extraction for demonstration
      # In practice, these would be replaced with actual Tree-sitter node extraction
      def extract_ruby_nodes(source_code)
        nodes = []
        lines = source_code.lines

        lines.each_with_index do |line, index|
          line_number = index + 1

          # Extract class definitions (including nested constants)
          if (match = line.match(/^\s*class\s+((?:\w+::)*\w+)/))
            nodes << {
              type: "class",
              name: match[1],
              line: line_number,
              start_column: line.index(match[0]),
              end_column: line.index(match[0]) + match[0].length
            }
          end

          # Extract module definitions (including nested constants)
          if (match = line.match(/^\s*module\s+((?:\w+::)*\w+)/))
            nodes << {
              type: "module",
              name: match[1],
              line: line_number,
              start_column: line.index(match[0]),
              end_column: line.index(match[0]) + match[0].length
            }
          end

          # Extract method definitions (including special methods)
          if (match = line.match(/^\s*def\s+([\w\[\]=!?]+)/))
            nodes << {
              type: "method",
              name: match[1],
              line: line_number,
              start_column: line.index(match[0]),
              end_column: line.index(match[0]) + match[0].length
            }
          end

          # Extract singleton/class method definitions
          if (match = line.match(/^\s*def\s+(?:self|[\w:]+)\.([\w\[\]=!?]+)/))
            nodes << {
              type: "singleton_method",
              name: match[1],
              line: line_number,
              start_column: line.index(match[0]),
              end_column: line.index(match[0]) + match[0].length
            }
          end

          # Extract require statements
          if (match = line.match(/^\s*require\s+['"]([^'"]+)['"]/))
            nodes << {
              type: "require",
              target: match[1],
              line: line_number,
              start_column: line.index(match[0]),
              end_column: line.index(match[0]) + match[0].length
            }
          end

          # Extract require_relative statements
          if (match = line.match(/^\s*require_relative\s+['"]([^'"]+)['"]/))
            nodes << {
              type: "require_relative",
              target: match[1],
              line: line_number,
              start_column: line.index(match[0]),
              end_column: line.index(match[0]) + match[0].length
            }
          end
        end

        nodes
      end

      def extract_javascript_nodes(source_code)
        nodes = []
        lines = source_code.lines

        lines.each_with_index do |line, index|
          line_number = index + 1

          # Extract class declarations
          if (match = line.match(/class\s+(\w+)/))
            nodes << {
              type: "class",
              name: match[1],
              line: line_number,
              start_column: line.index(match[0]),
              end_column: line.index(match[0]) + match[0].length
            }
          end

          # Extract function declarations
          if (match = line.match(/function\s+(\w+)/))
            nodes << {
              type: "function",
              name: match[1],
              line: line_number,
              start_column: line.index(match[0]),
              end_column: line.index(match[0]) + match[0].length
            }
          end

          # Extract import statements
          if (match = line.match(/import\s+.*from\s+['"]([^'"]+)['"]/))
            nodes << {
              type: "import",
              target: match[1],
              line: line_number,
              start_column: line.index(match[0]),
              end_column: line.index(match[0]) + match[0].length
            }
          end
        end

        nodes
      end

      def extract_typescript_nodes(source_code)
        # Similar to JavaScript but with TypeScript-specific patterns
        extract_javascript_nodes(source_code)
      end

      def extract_python_nodes(source_code)
        nodes = []
        lines = source_code.lines

        lines.each_with_index do |line, index|
          line_number = index + 1

          # Extract class definitions
          if (match = line.match(/class\s+(\w+)/))
            nodes << {
              type: "class",
              name: match[1],
              line: line_number,
              start_column: line.index(match[0]),
              end_column: line.index(match[0]) + match[0].length
            }
          end

          # Extract function definitions
          if (match = line.match(/def\s+(\w+)/))
            nodes << {
              type: "function",
              name: match[1],
              line: line_number,
              start_column: line.index(match[0]),
              end_column: line.index(match[0]) + match[0].length
            }
          end

          # Extract import statements
          if (match = line.match(/import\s+([^#\n]+)/))
            nodes << {
              type: "import",
              target: match[1].strip,
              line: line_number,
              start_column: line.index(match[0]),
              end_column: line.index(match[0]) + match[0].length
            }
          end
        end

        nodes
      end
    end
  end
end
