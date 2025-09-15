# frozen_string_literal: true

require_relative "base"
require_relative "frame_manager"
require_relative "status_widget"

module Aidp
  module Harness
    module UI
      # File selection using CLI UI components
      class FileSelector < Base
        class FileSelectionError < StandardError; end
        class InvalidSearchError < FileSelectionError; end
        class FileNotFoundError < FileSelectionError; end

        def initialize(ui_components = {})
          super()
          @frame_manager = ui_components[:frame_manager] || FrameManager.new
          @status_widget = ui_components[:status_widget] || StatusWidget.new
          @formatter = ui_components[:formatter] || FileSelectorFormatter.new
          @prompt = ui_components[:prompt] || CLI::UI::Prompt
        end

        def select_files(search_term = nil, max_files = 1, options = {})
          validate_selection_params(search_term, max_files)

          @frame_manager.section("File Selection") do
            files = find_files_with_progress(search_term, options)
            display_file_selection_menu(files, max_files, options)
          end
        rescue => e
          raise FileSelectionError, "Failed to select files: #{e.message}"
        end

        def select_single_file(search_term = nil, options = {})
          files = select_files(search_term, 1, options)
          files.first
        end

        def select_multiple_files(search_term = nil, max_files = 10, options = {})
          select_files(search_term, max_files, options)
        end

        def browse_directory(directory = ".", options = {})
          validate_directory(directory)

          @frame_manager.section("Directory Browser") do
            files = list_directory_contents(directory, options)
            display_directory_browser(files, directory, options)
          end
        rescue => e
          raise FileSelectionError, "Failed to browse directory: #{e.message}"
        end

        def find_files_by_pattern(pattern, options = {})
          validate_pattern(pattern)

          @status_widget.show_loading_status("Searching for files") do
            files = perform_file_search(pattern, options)
            display_search_results(files, pattern)
            files
          end
        rescue => e
          raise FileSelectionError, "Failed to find files: #{e.message}"
        end

        private

        def validate_selection_params(search_term, max_files)
          raise InvalidSearchError, "Max files must be positive" unless max_files > 0
        end

        def validate_directory(directory)
          raise InvalidSearchError, "Directory does not exist" unless Dir.exist?(directory)
        end

        def validate_pattern(pattern)
          raise InvalidSearchError, "Pattern cannot be empty" if pattern.to_s.strip.empty?
        end

        def find_files_with_progress(search_term, options)
          @status_widget.show_loading_status("Finding files") do
            perform_file_search(search_term, options)
          end
        end

        def perform_file_search(search_term, options)
          return [] unless search_term

          search_options = parse_search_options(search_term, options)
          files = find_files_advanced(search_options)
          sort_and_filter_files(files, search_options)
        end

        def parse_search_options(search_term, options)
          {
            pattern: search_term,
            directory: options[:directory] || ".",
            recursive: options.fetch(:recursive, true),
            file_types: options[:file_types] || [],
            max_results: options[:max_results] || 50
          }
        end

        def find_files_advanced(search_options)
          pattern = build_glob_pattern(search_options)
          files = Dir.glob(pattern)
          files.first(search_options[:max_results])
        end

        def build_glob_pattern(search_options)
          base_path = search_options[:directory]
          pattern = search_options[:pattern]

          if search_options[:recursive]
            File.join(base_path, "**", "*#{pattern}*")
          else
            File.join(base_path, "*#{pattern}*")
          end
        end

        def sort_and_filter_files(files, search_options)
          files = filter_by_file_types(files, search_options[:file_types]) if search_options[:file_types].any?
          files.sort_by { |file| [File.directory?(file) ? 0 : 1, File.basename(file)] }
        end

        def filter_by_file_types(files, file_types)
          extensions = file_types.map { |type| ".#{type}" }
          files.select { |file| extensions.any? { |ext| file.end_with?(ext) } }
        end

        def display_file_selection_menu(files, max_files, options)
          if files.empty?
            display_no_files_found
            return []
          end

          display_files_list(files)
          selected_files = prompt_for_file_selection(files, max_files)
          display_selection_summary(selected_files)
          selected_files
        end

        def display_no_files_found
          CLI::UI.puts("❌ No files found matching the search criteria.")
        end

        def display_files_list(files)
          CLI::UI.puts("📁 Found #{files.length} files:")
          CLI::UI.puts(@formatter.format_separator)

          files.each_with_index do |file, index|
            display_file_info(file, index + 1)
          end
        end

        def display_file_info(file, index)
          file_info = get_file_info(file)
          formatted_info = @formatter.format_file_info(file, file_info, index)
          CLI::UI.puts(formatted_info)
        end

        def get_file_info(file)
          {
            name: File.basename(file),
            path: file,
            size: File.size(file),
            type: get_file_type(file),
            modified: File.mtime(file)
          }
        rescue
          {
            name: File.basename(file),
            path: file,
            size: 0,
            type: "unknown",
            modified: Time.now
          }
        end

        def get_file_type(file)
          if File.directory?(file)
            "directory"
          elsif file.end_with?(".rb")
            "ruby"
          elsif file.end_with?(".md")
            "markdown"
          elsif file.end_with?(".json")
            "json"
          elsif file.end_with?(".yml", ".yaml")
            "yaml"
          else
            "file"
          end
        end

        def prompt_for_file_selection(files, max_files)
          if max_files == 1
            prompt_for_single_file(files)
          else
            prompt_for_multiple_files(files, max_files)
          end
        end

        def prompt_for_single_file(files)
          options = files.map.with_index { |file, index| "#{index + 1}. #{File.basename(file)}" }
          options << "Cancel"

          selection = @prompt.ask("Select a file:") do |handler|
            options.each { |option| handler.option(option) }
          end

          return [] if selection == "Cancel"

          file_index = selection.match(/^(\d+)\./)[1].to_i - 1
          [files[file_index]]
        end

        def prompt_for_multiple_files(files, max_files)
          CLI::UI.puts("Select up to #{max_files} files (comma-separated numbers):")
          input = gets.chomp

          return [] if input.strip.empty?

          indices = input.split(",").map(&:strip).map(&:to_i)
          indices.map { |i| files[i - 1] }.compact.first(max_files)
        end

        def display_selection_summary(selected_files)
          CLI::UI.puts("\n✅ Selected #{selected_files.length} files:")
          selected_files.each { |file| CLI::UI.puts("  📄 #{file}") }
        end

        def list_directory_contents(directory, options)
          entries = Dir.entries(directory).reject { |entry| entry.start_with?(".") }
          entries.map { |entry| File.join(directory, entry) }
        end

        def display_directory_browser(files, directory, options)
          CLI::UI.puts("📁 Contents of #{directory}:")
          display_files_list(files)
        end

        def display_search_results(files, pattern)
          CLI::UI.puts("🔍 Search results for '#{pattern}':")
          display_files_list(files)
        end
      end

      # Formats file selection display
      class FileSelectorFormatter
        def format_separator
          "─" * 60
        end

        def format_file_info(file, file_info, index)
          name = file_info[:name]
          size = format_file_size(file_info[:size])
          type = file_info[:type]
          modified = format_modification_time(file_info[:modified])

          CLI::UI.fmt("{{bold:#{index}.}} {{bold:#{name}}} {{dim:(#{size}, #{type}, #{modified})}}")
        end

        def format_file_size(size)
          if size < 1024
            "#{size}B"
          elsif size < 1024 * 1024
            "#{(size / 1024.0).round(1)}KB"
          else
            "#{(size / (1024.0 * 1024)).round(1)}MB"
          end
        end

        def format_modification_time(time)
          time.strftime("%Y-%m-%d %H:%M")
        end

        def format_selection_prompt(max_files)
          if max_files == 1
            "Select a file:"
          else
            "Select up to #{max_files} files:"
          end
        end

        def format_no_files_message
          CLI::UI.fmt("{{yellow:⚠️ No files found}}")
        end

        def format_selection_summary(count)
          CLI::UI.fmt("{{green:✅ Selected #{count} files}}")
        end
      end
    end
  end
end
