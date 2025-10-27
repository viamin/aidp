# frozen_string_literal: true

module Aidp
  module PromptOptimization
    # Fragments source code files into retrievable code units
    #
    # Parses Ruby source files and extracts methods, classes, modules
    # along with their dependencies and imports. Each fragment can be
    # independently included or excluded from prompts.
    #
    # @example Basic usage
    #   fragmenter = SourceCodeFragmenter.new(project_dir: "/path/to/project")
    #   fragments = fragmenter.fragment_file("lib/my_file.rb")
    class SourceCodeFragmenter
      attr_reader :project_dir

      def initialize(project_dir:)
        @project_dir = project_dir
      end

      # Fragment a source file into code units
      #
      # @param file_path [String] Path to source file (relative or absolute)
      # @param context_lines [Integer] Number of context lines around code units
      # @return [Array<CodeFragment>] List of code fragments
      def fragment_file(file_path, context_lines: 2)
        abs_path = File.absolute_path?(file_path) ? file_path : File.join(@project_dir, file_path)

        return [] unless File.exist?(abs_path)
        return [] unless abs_path.end_with?(".rb")

        content = File.read(abs_path)
        fragments = []

        # Extract requires/imports as first fragment
        requires = extract_requires(content)
        if requires && !requires.empty?
          fragments << create_requires_fragment(abs_path, requires)
        end

        # Extract classes and modules
        fragments.concat(extract_classes_and_modules(abs_path, content))

        # Extract top-level methods
        fragments.concat(extract_methods(abs_path, content, context_lines: context_lines))

        fragments
      end

      # Fragment multiple files
      #
      # @param file_paths [Array<String>] List of file paths
      # @return [Array<CodeFragment>] All fragments from all files
      def fragment_files(file_paths)
        file_paths.flat_map { |path| fragment_file(path) }
      end

      private

      # Extract require statements from content
      #
      # @param content [String] File content
      # @return [String, nil] Combined require statements
      def extract_requires(content)
        lines = content.lines
        require_lines = lines.select do |line|
          line.strip =~ /^require(_relative)?\s+/
        end

        return nil if require_lines.empty?

        require_lines.join
      end

      # Create a fragment for require statements
      #
      # @param file_path [String] Source file path
      # @param requires [String] Require statements
      # @return [CodeFragment] Requires fragment
      def create_requires_fragment(file_path, requires)
        CodeFragment.new(
          id: "#{file_path}:requires",
          file_path: file_path,
          type: :requires,
          name: "requires",
          content: requires,
          line_start: 1,
          line_end: requires.lines.count
        )
      end

      # Extract classes and modules with their methods
      #
      # @param file_path [String] Source file path
      # @param content [String] File content
      # @return [Array<CodeFragment>] Class/module fragments
      def extract_classes_and_modules(file_path, content)
        fragments = []
        lines = content.lines

        current_class = nil
        class_start = nil
        indent_level = 0

        lines.each_with_index do |line, idx|
          # Detect class/module definition
          if line =~ /^(\s*)(class|module)\s+(\S+)/
            current_indent = $1.length
            $2
            name = $3

            # Save previous class if exists
            if current_class && class_start
              class_content = lines[class_start..idx - 1].join
              fragments << create_class_fragment(file_path, current_class, class_content, class_start + 1, idx)
            end

            current_class = name
            class_start = idx
            indent_level = current_indent
          elsif line =~ /^(\s*)end/ && current_class
            end_indent = $1.length
            if end_indent <= indent_level
              # Class/module end
              class_content = lines[class_start..idx].join
              fragments << create_class_fragment(file_path, current_class, class_content, class_start + 1, idx + 1)
              current_class = nil
              class_start = nil
            end
          end
        end

        # Save last class if exists
        if current_class && class_start
          class_content = lines[class_start..].join
          fragments << create_class_fragment(file_path, current_class, class_content, class_start + 1, lines.count)
        end

        fragments
      end

      # Create a fragment for a class/module
      #
      # @param file_path [String] Source file path
      # @param name [String] Class/module name
      # @param content [String] Class/module content
      # @param line_start [Integer] Starting line number
      # @param line_end [Integer] Ending line number
      # @return [CodeFragment] Class fragment
      def create_class_fragment(file_path, name, content, line_start, line_end)
        CodeFragment.new(
          id: "#{file_path}:#{name}",
          file_path: file_path,
          type: :class,
          name: name,
          content: content,
          line_start: line_start,
          line_end: line_end
        )
      end

      # Extract top-level methods (not inside classes)
      #
      # @param file_path [String] Source file path
      # @param content [String] File content
      # @param context_lines [Integer] Lines of context around method
      # @return [Array<CodeFragment>] Method fragments
      def extract_methods(file_path, content, context_lines: 2)
        fragments = []
        lines = content.lines

        in_class = false
        method_start = nil
        method_name = nil
        indent_level = 0

        lines.each_with_index do |line, idx|
          # Track if we're inside a class
          if /^(\s*)(class|module)\s+/.match?(line)
            in_class = true
            next
          elsif line =~ /^end/ && in_class
            in_class = false
            next
          end

          # Skip methods inside classes
          next if in_class

          # Detect method definition
          if line =~ /^(\s*)def\s+(\S+)/
            method_start = [idx - context_lines, 0].max
            method_name = $2
            indent_level = $1.length
          elsif line =~ /^(\s*)end/ && method_name
            end_indent = $1.length
            if end_indent <= indent_level
              # Method end
              method_end = [idx + context_lines, lines.count - 1].min
              method_content = lines[method_start..method_end].join

              fragments << CodeFragment.new(
                id: "#{file_path}:#{method_name}",
                file_path: file_path,
                type: :method,
                name: method_name,
                content: method_content,
                line_start: method_start + 1,
                line_end: method_end + 1
              )

              method_start = nil
              method_name = nil
            end
          end
        end

        fragments
      end
    end

    # Represents a code fragment (class, method, requires, etc.)
    #
    # Each fragment is a logical unit of code that can be independently
    # included or excluded from prompts based on relevance
    class CodeFragment
      attr_reader :id, :file_path, :type, :name, :content, :line_start, :line_end

      # @param id [String] Unique identifier (e.g., "lib/user.rb:User")
      # @param file_path [String] Source file path
      # @param type [Symbol] Fragment type (:class, :module, :method, :requires)
      # @param name [String] Name of the code unit
      # @param content [String] Code content
      # @param line_start [Integer] Starting line number
      # @param line_end [Integer] Ending line number
      def initialize(id:, file_path:, type:, name:, content:, line_start:, line_end:)
        @id = id
        @file_path = file_path
        @type = type
        @name = name
        @content = content
        @line_start = line_start
        @line_end = line_end
      end

      # Get the size of the fragment in characters
      #
      # @return [Integer] Character count
      def size
        @content.length
      end

      # Estimate token count (rough approximation: 1 token ≈ 4 chars)
      #
      # @return [Integer] Estimated token count
      def estimated_tokens
        (size / 4.0).ceil
      end

      # Get line count
      #
      # @return [Integer] Number of lines
      def line_count
        @line_end - @line_start + 1
      end

      # Get relative file path from project root
      #
      # @param project_dir [String] Project directory
      # @return [String] Relative path
      def relative_path(project_dir)
        @file_path.sub(%r{^#{Regexp.escape(project_dir)}/?}, "")
      end

      # Check if this is a test file fragment
      #
      # @return [Boolean] True if from spec file
      def test_file?
        !!(@file_path =~ /_(spec|test)\.rb$/)
      end

      # Get a summary of the fragment
      #
      # @return [Hash] Fragment summary
      def summary
        {
          id: @id,
          file_path: @file_path,
          type: @type,
          name: @name,
          lines: "#{@line_start}-#{@line_end}",
          line_count: line_count,
          size: size,
          estimated_tokens: estimated_tokens,
          test_file: test_file?
        }
      end

      def to_s
        "CodeFragment<#{@type}:#{@name}>"
      end

      def inspect
        "#<CodeFragment id=#{@id} type=#{@type} lines=#{@line_start}-#{@line_end}>"
      end
    end
  end
end
