# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::UserInterface do
  let(:ui) { described_class.new }

  describe "file selection interface with @ character" do
    describe "#parse_file_search_options" do
      it "parses basic search term" do
        options = ui.parse_file_search_options("config")

        expect(options[:term]).to eq("config")
        expect(options[:extensions]).to be_empty
        expect(options[:directories]).to be_empty
        expect(options[:patterns]).to eq(["config"])
        expect(options[:preview]).to be false
        expect(options[:case_sensitive]).to be false
      end

      it "parses extension filters" do
        options = ui.parse_file_search_options(".rb")

        expect(options[:term]).to eq("")
        expect(options[:extensions]).to eq([".rb"])
        expect(options[:directories]).to be_empty
        expect(options[:patterns]).to be_empty
      end

      it "parses directory filters" do
        options = ui.parse_file_search_options("lib/")

        expect(options[:term]).to eq("")
        expect(options[:extensions]).to be_empty
        expect(options[:directories]).to eq(["lib"])
        expect(options[:patterns]).to be_empty
      end

      it "parses preview option" do
        options = ui.parse_file_search_options("config preview")

        expect(options[:term]).to eq("config")
        expect(options[:preview]).to be true
      end

      it "parses case sensitive option" do
        options = ui.parse_file_search_options("Config case")

        expect(options[:term]).to eq("Config")
        expect(options[:case_sensitive]).to be true
      end

      it "parses complex search options" do
        options = ui.parse_file_search_options("spec preview case")

        expect(options[:term]).to eq("spec")
        expect(options[:preview]).to be true
        expect(options[:case_sensitive]).to be true
      end
    end

    describe "#determine_search_paths" do
      it "returns default paths when no directories specified" do
        search_options = { directories: [] }
        paths = ui.determine_search_paths(search_options)

        expect(paths).to include(".", "lib", "spec", "app", "src", "docs", "templates")
      end

      it "returns specified directories when provided" do
        search_options = { directories: ["lib", "spec"] }
        paths = ui.determine_search_paths(search_options)

        expect(paths).to eq(["lib", "spec"])
      end
    end

    describe "#build_glob_pattern" do
      it "builds pattern for specific extensions" do
        search_options = { extensions: [".rb", ".js"] }
        pattern = ui.build_glob_pattern("lib", search_options)

        expect(pattern).to eq("lib/**/*{.rb,.js}")
      end

      it "builds pattern for all files" do
        search_options = { extensions: [] }
        pattern = ui.build_glob_pattern("lib", search_options)

        expect(pattern).to eq("lib/**/*")
      end
    end

    describe "#matches_filters?" do
      it "matches files by term" do
        search_options = { term: "config", case_sensitive: false }

        expect(ui.matches_filters?("config.yml", search_options)).to be true
        expect(ui.matches_filters?("app_config.rb", search_options)).to be true
        expect(ui.matches_filters?("README.md", search_options)).to be false
      end

      it "matches files by patterns" do
        search_options = { patterns: ["config", "spec"], case_sensitive: false }

        expect(ui.matches_filters?("config.yml", search_options)).to be true
        expect(ui.matches_filters?("spec_helper.rb", search_options)).to be true
        expect(ui.matches_filters?("README.md", search_options)).to be false
      end

      it "handles case sensitivity" do
        search_options = { term: "Config", case_sensitive: true }

        expect(ui.matches_filters?("Config.yml", search_options)).to be true
        expect(ui.matches_filters?("config.yml", search_options)).to be false
      end

      it "matches all files when term is empty" do
        search_options = { term: "", case_sensitive: false }

        expect(ui.matches_filters?("any_file.rb", search_options)).to be true
        expect(ui.matches_filters?("another_file.js", search_options)).to be true
      end
    end

    describe "#sort_files" do
      it "sorts files by relevance" do
        files = ["config.yml", "app_config.rb", "README.md"]
        search_options = { term: "config" }

        sorted = ui.sort_files(files, search_options)

        expect(sorted.first).to eq("config.yml") # Exact match
        expect(sorted[1]).to eq("app_config.rb") # Contains term
        expect(sorted.last).to eq("README.md") # No match
      end

      it "prioritizes file types" do
        files = ["script.sh", "app.rb", "data.json"]
        search_options = { term: "" }

        sorted = ui.sort_files(files, search_options)

        expect(sorted.first).to eq("app.rb") # Ruby files get higher priority
        expect(sorted[1]).to eq("data.json") # JSON files get medium priority
        expect(sorted.last).to eq("script.sh") # Shell files get lower priority
      end

      it "prioritizes directories" do
        files = ["README.md", "lib/app.rb", "spec/app_spec.rb"]
        search_options = { term: "" }

        sorted = ui.sort_files(files, search_options)

        expect(sorted.first).to eq("lib/app.rb") # lib/ gets highest priority
        expect(sorted[1]).to eq("spec/app_spec.rb") # spec/ gets high priority
        expect(sorted.last).to eq("README.md") # root files get lower priority
      end
    end

    describe "#get_file_info" do
      it "returns file information" do
        # Create a temporary file for testing
        temp_file = Tempfile.new("test")
        temp_file.write("test content")
        temp_file.close

        file_info = ui.get_file_info(temp_file.path)

        expect(file_info[:display_name]).to eq(temp_file.path)
        expect(file_info[:size]).to eq("12 B")
        expect(file_info[:modified]).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}/)
        expect(file_info[:type]).to eq("File")

        temp_file.unlink
      end
    end

    describe "#format_file_size" do
      it "formats bytes" do
        expect(ui.format_file_size(512)).to eq("512 B")
      end

      it "formats kilobytes" do
        expect(ui.format_file_size(1536)).to eq("1.5 KB")
      end

      it "formats megabytes" do
        expect(ui.format_file_size(2097152)).to eq("2.0 MB")
      end
    end

    describe "#get_file_type" do
      it "identifies Ruby files" do
        expect(ui.get_file_type("app.rb")).to eq("Ruby")
      end

      it "identifies JavaScript files" do
        expect(ui.get_file_type("app.js")).to eq("JavaScript")
      end

      it "identifies TypeScript files" do
        expect(ui.get_file_type("app.ts")).to eq("TypeScript")
      end

      it "identifies Python files" do
        expect(ui.get_file_type("app.py")).to eq("Python")
      end

      it "identifies Markdown files" do
        expect(ui.get_file_type("README.md")).to eq("Markdown")
      end

      it "identifies YAML files" do
        expect(ui.get_file_type("config.yml")).to eq("YAML")
        expect(ui.get_file_type("config.yaml")).to eq("YAML")
      end

      it "identifies JSON files" do
        expect(ui.get_file_type("package.json")).to eq("JSON")
      end

      it "identifies HTML files" do
        expect(ui.get_file_type("index.html")).to eq("HTML")
        expect(ui.get_file_type("index.htm")).to eq("HTML")
      end

      it "identifies CSS files" do
        expect(ui.get_file_type("style.css")).to eq("CSS")
      end

      it "identifies Sass files" do
        expect(ui.get_file_type("style.scss")).to eq("Sass")
        expect(ui.get_file_type("style.sass")).to eq("Sass")
      end

      it "identifies SQL files" do
        expect(ui.get_file_type("schema.sql")).to eq("SQL")
      end

      it "identifies Shell files" do
        expect(ui.get_file_type("script.sh")).to eq("Shell")
      end

      it "identifies Text files" do
        expect(ui.get_file_type("notes.txt")).to eq("Text")
      end

      it "handles files without extensions" do
        expect(ui.get_file_type("README")).to eq("File")
      end

      it "handles unknown extensions" do
        expect(ui.get_file_type("file.xyz")).to eq("XYZ")
      end
    end

    describe "#show_file_preview" do
      it "shows file preview" do
        # Create a temporary file for testing
        temp_file = Tempfile.new("test")
        temp_file.write("Line 1\nLine 2\nLine 3\n" * 10) # 30 lines
        temp_file.close

        # Mock Readline to return empty input
        allow(Readline).to receive(:readline).and_return("")

        expect { ui.show_file_preview(temp_file.path) }.to output(/File Preview/).to_stdout
        expect { ui.show_file_preview(temp_file.path) }.to output(/File Info/).to_stdout
        expect { ui.show_file_preview(temp_file.path) }.to output(/Content Preview/).to_stdout
        expect { ui.show_file_preview(temp_file.path) }.to output(/30 more lines/).to_stdout

        temp_file.unlink
      end

      it "handles file read errors" do
        # Mock Readline to return empty input
        allow(Readline).to receive(:readline).and_return("")

        expect { ui.show_file_preview("nonexistent.txt") }.to output(/Error reading file/).to_stdout
      end
    end

    describe "#show_file_selection_help" do
      it "displays help information" do
        expect { ui.show_file_selection_help }.to output(/File Selection Help/).to_stdout
        expect { ui.show_file_selection_help }.to output(/Search Examples/).to_stdout
        expect { ui.show_file_selection_help }.to output(/Selection Commands/).to_stdout
        expect { ui.show_file_selection_help }.to output(/Tips/).to_stdout
      end
    end

    describe "#handle_file_selection" do
      it "handles basic file selection" do
        # Mock file finding
        allow(ui).to receive(:find_files_advanced).and_return(["file1.rb", "file2.js"])

        # Mock file menu display
        allow(ui).to receive(:display_advanced_file_menu)

        # Mock file selection
        allow(ui).to receive(:get_advanced_file_selection).and_return(0)

        result = ui.handle_file_selection("@.rb")

        expect(result).to eq("file1.rb")
      end

      it "handles search refinement" do
        # Mock file finding
        allow(ui).to receive(:find_files_advanced).and_return(["file1.rb", "file2.js"])

        # Mock file menu display
        allow(ui).to receive(:display_advanced_file_menu)

        # Mock file selection returning -1 for refinement
        allow(ui).to receive(:get_advanced_file_selection).and_return(-1)

        # Mock recursive call
        allow(ui).to receive(:handle_file_selection).and_return("refined_result.rb")

        result = ui.handle_file_selection("@.rb")

        expect(result).to eq("refined_result.rb")
      end

      it "handles no files found" do
        # Mock file finding returning empty array
        allow(ui).to receive(:find_files_advanced).and_return([])

        result = ui.handle_file_selection("@nonexistent")

        expect(result).to be_nil
      end
    end

    describe "integration with file response" do
      it "integrates with file response method" do
        # Mock file finding
        allow(ui).to receive(:find_files_advanced).and_return(["config.yml"])

        # Mock file menu display
        allow(ui).to receive(:display_advanced_file_menu)

        # Mock file selection
        allow(ui).to receive(:get_advanced_file_selection).and_return(0)

        # Mock Readline for file response
        allow(Readline).to receive(:readline).and_return("@config")

        result = ui.get_file_response("text", nil, true)

        expect(result).to eq("config.yml")
      end
    end
  end
end
