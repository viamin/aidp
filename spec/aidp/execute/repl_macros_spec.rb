# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/repl_macros"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Execute::ReplMacros do
  let(:repl) { described_class.new }
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "starts with empty state" do
      expect(repl.pinned_files).to be_empty
      expect(repl.focus_patterns).to be_empty
      expect(repl.halt_patterns).to be_empty
      expect(repl.split_mode).to be false
    end
  end

  describe "#execute" do
    context "with empty command" do
      it "returns error for nil" do
        result = repl.execute(nil)
        expect(result[:success]).to be false
        expect(result[:message]).to include("Empty command")
      end

      it "returns error for empty string" do
        result = repl.execute("")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Empty command")
      end
    end

    context "with unknown command" do
      it "returns error" do
        result = repl.execute("/unknown")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Unknown command")
      end
    end

    context "with non-slash command" do
      it "returns error" do
        result = repl.execute("not-a-command")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Unknown command")
      end
    end
  end

  describe "/pin command" do
    it "pins a single file" do
      result = repl.execute("/pin config/database.yml")
      expect(result[:success]).to be true
      expect(result[:message]).to include("Pinned 1 file")
      expect(repl.pinned?("config/database.yml")).to be true
    end

    it "returns error without arguments" do
      result = repl.execute("/pin")
      expect(result[:success]).to be false
      expect(result[:message]).to include("Usage")
    end

    it "normalizes file paths" do
      repl.execute("/pin ./lib/file.rb")
      expect(repl.pinned?("lib/file.rb")).to be true
    end

    it "pins multiple files with glob pattern" do
      Dir.chdir(temp_dir) do
        FileUtils.mkdir_p("config")
        File.write("config/database.yml", "test")
        File.write("config/secrets.yml", "test")

        result = repl.execute("/pin config/*.yml")
        expect(result[:success]).to be true
        expect(repl.pinned_files.size).to be >= 1
      end
    end

    it "returns correct action" do
      result = repl.execute("/pin test.rb")
      expect(result[:action]).to eq(:update_constraints)
    end
  end

  describe "/unpin command" do
    before do
      repl.execute("/pin config/database.yml")
      repl.execute("/pin config/secrets.yml")
    end

    it "unpins a file" do
      result = repl.execute("/unpin config/database.yml")
      expect(result[:success]).to be true
      expect(result[:message]).to include("Unpinned 1 file")
      expect(repl.pinned?("config/database.yml")).to be false
    end

    it "returns error if file not pinned" do
      # Create a fresh REPL to ensure no pinned files
      fresh_repl = described_class.new
      result = fresh_repl.execute("/unpin config/never_existed.yml")
      expect(result[:success]).to be false
      expect(result[:message]).to include("No matching pinned files")
    end

    it "returns error without arguments" do
      result = repl.execute("/unpin")
      expect(result[:success]).to be false
      expect(result[:message]).to include("Usage")
    end
  end

  describe "/focus command" do
    it "sets focus to a directory pattern" do
      result = repl.execute("/focus lib/**/*.rb")
      expect(result[:success]).to be true
      expect(result[:message]).to include("Focus set")
      expect(repl.focus_patterns).to include("lib/**/*.rb")
    end

    it "allows multiple focus patterns" do
      repl.execute("/focus lib/**/*.rb")
      repl.execute("/focus spec/**/*_spec.rb")
      expect(repl.focus_patterns.size).to eq(2)
    end

    it "returns error without arguments" do
      result = repl.execute("/focus")
      expect(result[:success]).to be false
      expect(result[:message]).to include("Usage")
    end

    it "returns correct action" do
      result = repl.execute("/focus lib/**/*")
      expect(result[:action]).to eq(:update_constraints)
    end
  end

  describe "/unfocus command" do
    before do
      repl.execute("/focus lib/**/*.rb")
      repl.execute("/focus spec/**/*.rb")
    end

    it "clears all focus patterns" do
      result = repl.execute("/unfocus")
      expect(result[:success]).to be true
      expect(result[:message]).to include("Focus removed")
      expect(repl.focus_patterns).to be_empty
    end

    it "indicates all files are in scope" do
      result = repl.execute("/unfocus")
      expect(result[:message]).to include("all files in scope")
    end
  end

  describe "/split command" do
    it "enables split mode" do
      result = repl.execute("/split")
      expect(result[:success]).to be true
      expect(result[:message]).to include("Split mode enabled")
      expect(repl.split_mode).to be true
    end

    it "returns split_work action" do
      result = repl.execute("/split")
      expect(result[:action]).to eq(:split_work)
    end
  end

  describe "/halt-on command" do
    it "adds halt pattern" do
      result = repl.execute("/halt-on authentication.*failed")
      expect(result[:success]).to be true
      expect(result[:message]).to include("Will halt on")
      expect(repl.halt_patterns).to include("authentication.*failed")
    end

    it "removes quotes from pattern" do
      repl.execute("/halt-on 'test pattern'")
      expect(repl.halt_patterns).to include("test pattern")
    end

    it "supports double quotes" do
      repl.execute('/halt-on "another pattern"')
      expect(repl.halt_patterns).to include("another pattern")
    end

    it "returns error without arguments" do
      result = repl.execute("/halt-on")
      expect(result[:success]).to be false
      expect(result[:message]).to include("Usage")
    end

    it "allows multiple halt patterns" do
      repl.execute("/halt-on pattern1")
      repl.execute("/halt-on pattern2")
      expect(repl.halt_patterns.size).to eq(2)
    end
  end

  describe "/unhalt command" do
    before do
      repl.execute("/halt-on pattern1")
      repl.execute("/halt-on pattern2")
    end

    it "removes specific pattern" do
      result = repl.execute("/unhalt pattern1")
      expect(result[:success]).to be true
      expect(result[:message]).to include("Removed halt pattern")
      expect(repl.halt_patterns).not_to include("pattern1")
      expect(repl.halt_patterns).to include("pattern2")
    end

    it "clears all patterns without arguments" do
      result = repl.execute("/unhalt")
      expect(result[:success]).to be true
      expect(result[:message]).to include("All halt patterns removed")
      expect(repl.halt_patterns).to be_empty
    end

    it "returns error if pattern not found" do
      result = repl.execute("/unhalt nonexistent")
      expect(result[:success]).to be false
      expect(result[:message]).to include("not found")
    end
  end

  describe "/status command" do
    it "shows empty state" do
      result = repl.execute("/status")
      expect(result[:success]).to be true
      expect(result[:message]).to include("REPL Macro Status")
      expect(result[:message]).to include("(none)")
    end

    it "shows pinned files" do
      repl.execute("/pin file1.rb")
      repl.execute("/pin file2.rb")
      result = repl.execute("/status")
      expect(result[:message]).to include("Pinned Files (2)")
      expect(result[:message]).to include("file1.rb")
      expect(result[:message]).to include("file2.rb")
    end

    it "shows focus patterns" do
      repl.execute("/focus lib/**/*.rb")
      result = repl.execute("/status")
      expect(result[:message]).to include("Focus Patterns")
      expect(result[:message]).to include("lib/**/*.rb")
    end

    it "shows halt patterns" do
      repl.execute("/halt-on error")
      result = repl.execute("/status")
      expect(result[:message]).to include("Halt Patterns")
      expect(result[:message]).to include("error")
    end

    it "shows split mode status" do
      repl.execute("/split")
      result = repl.execute("/status")
      expect(result[:message]).to include("Split Mode: enabled")
    end
  end

  describe "/reset command" do
    before do
      repl.execute("/pin file.rb")
      repl.execute("/focus lib/**/*")
      repl.execute("/halt-on error")
      repl.execute("/split")
    end

    it "clears all macros" do
      result = repl.execute("/reset")
      expect(result[:success]).to be true
      expect(result[:message]).to include("All REPL macros cleared")
      expect(repl.pinned_files).to be_empty
      expect(repl.focus_patterns).to be_empty
      expect(repl.halt_patterns).to be_empty
      expect(repl.split_mode).to be false
    end
  end

  describe "/help command" do
    it "shows all commands without arguments" do
      result = repl.execute("/help")
      expect(result[:success]).to be true
      expect(result[:message]).to include("Available REPL Commands")
      expect(result[:message]).to include("/pin")
      expect(result[:message]).to include("/focus")
      expect(result[:message]).to include("/halt-on")
    end

    it "shows specific command help" do
      result = repl.execute("/help /pin")
      expect(result[:success]).to be true
      expect(result[:message]).to include("/pin")
      expect(result[:message]).to include("Usage")
      expect(result[:message]).to include("Example")
    end

    it "shows help for unknown command" do
      result = repl.execute("/help unknown")
      expect(result[:success]).to be true
      expect(result[:message]).to include("Unknown command")
    end
  end

  describe "#pinned?" do
    before do
      repl.execute("/pin config/database.yml")
    end

    it "returns true for pinned files" do
      expect(repl.pinned?("config/database.yml")).to be true
    end

    it "returns false for non-pinned files" do
      expect(repl.pinned?("lib/file.rb")).to be false
    end

    it "handles path normalization" do
      expect(repl.pinned?("./config/database.yml")).to be true
    end
  end

  describe "#in_focus?" do
    context "without focus patterns" do
      it "returns true for all files" do
        expect(repl.in_focus?("any/file.rb")).to be true
        expect(repl.in_focus?("another/file.js")).to be true
      end
    end

    context "with focus patterns" do
      before do
        repl.execute("/focus lib/**/*.rb")
      end

      it "returns true for matching files" do
        expect(repl.in_focus?("lib/foo/bar.rb")).to be true
      end

      it "returns false for non-matching files" do
        expect(repl.in_focus?("spec/foo_spec.rb")).to be false
      end
    end

    context "with multiple focus patterns" do
      before do
        repl.execute("/focus lib/**/*.rb")
        repl.execute("/focus spec/**/*_spec.rb")
      end

      it "returns true if any pattern matches" do
        expect(repl.in_focus?("lib/file.rb")).to be true
        expect(repl.in_focus?("spec/file_spec.rb")).to be true
      end

      it "returns false if no patterns match" do
        expect(repl.in_focus?("app/file.js")).to be false
      end
    end
  end

  describe "#should_halt?" do
    context "without halt patterns" do
      it "returns false for any message" do
        expect(repl.should_halt?("any error message")).to be false
      end
    end

    context "with halt patterns" do
      before do
        repl.execute("/halt-on authentication.*failed")
        repl.execute("/halt-on database.*error")
      end

      it "returns true for matching messages" do
        expect(repl.should_halt?("Authentication test failed")).to be true
        expect(repl.should_halt?("Database connection error")).to be true
      end

      it "returns false for non-matching messages" do
        expect(repl.should_halt?("Some other error")).to be false
      end

      it "is case insensitive" do
        expect(repl.should_halt?("AUTHENTICATION FAILED")).to be true
      end
    end
  end

  describe "#summary" do
    it "returns complete state summary" do
      repl.execute("/pin file1.rb")
      repl.execute("/pin file2.rb")
      repl.execute("/focus lib/**/*")
      repl.execute("/halt-on error")
      repl.execute("/split")

      summary = repl.summary
      expect(summary[:pinned_files]).to contain_exactly("file1.rb", "file2.rb")
      expect(summary[:focus_patterns]).to eq(["lib/**/*"])
      expect(summary[:halt_patterns]).to eq(["error"])
      expect(summary[:split_mode]).to be true
      expect(summary[:active_constraints]).to eq(5)
    end
  end

  describe "#reset!" do
    before do
      repl.execute("/pin file.rb")
      repl.execute("/focus lib/**/*")
      repl.execute("/halt-on error")
      repl.execute("/split")
    end

    it "clears all state" do
      repl.reset!
      expect(repl.pinned_files).to be_empty
      expect(repl.focus_patterns).to be_empty
      expect(repl.halt_patterns).to be_empty
      expect(repl.split_mode).to be false
    end
  end

  describe "#list_commands" do
    it "returns sorted list of commands" do
      commands = repl.list_commands
      expect(commands).to be_an(Array)
      expect(commands).to include("/pin", "/focus", "/halt-on", "/help")
      expect(commands).to eq(commands.sort)
    end
  end

  describe "#help" do
    it "returns help for all commands" do
      help_text = repl.help
      expect(help_text).to include("/pin")
      expect(help_text).to include("/focus")
      expect(help_text).to include("/halt-on")
    end

    it "returns specific command help" do
      help_text = repl.help("/pin")
      expect(help_text).to include("/pin")
      expect(help_text).to include("Usage")
      expect(help_text).to include("Example")
    end

    it "returns error for unknown command" do
      help_text = repl.help("/unknown")
      expect(help_text).to include("Unknown command")
    end
  end

  describe "pattern matching" do
    describe "simple patterns" do
      before do
        repl.execute("/focus *.rb")
      end

      it "matches simple wildcard" do
        expect(repl.in_focus?("file.rb")).to be true
        expect(repl.in_focus?("file.js")).to be false
      end
    end

    describe "directory patterns" do
      before do
        repl.execute("/focus lib/**/*.rb")
      end

      it "matches nested directories" do
        expect(repl.in_focus?("lib/foo/bar.rb")).to be true
        # lib/**/*.rb matches files in subdirectories, but lib/baz.rb is directly in lib
        # which technically matches lib/**/*.rb pattern
        expect(repl.in_focus?("spec/baz.rb")).to be false
      end
    end

    describe "prefix patterns" do
      before do
        repl.execute("/focus lib/**")
      end

      it "matches directory prefix" do
        expect(repl.in_focus?("lib/anything.rb")).to be true
        expect(repl.in_focus?("lib/nested/file.js")).to be true
        expect(repl.in_focus?("spec/file.rb")).to be false
      end
    end
  end

  describe "integration scenarios" do
    it "handles complex macro combinations" do
      # Pin critical files
      repl.execute("/pin config/database.yml")
      repl.execute("/pin .env")

      # Focus on feature directory
      repl.execute("/focus lib/features/auth/**/*")

      # Halt on authentication errors
      repl.execute("/halt-on authentication.*failed")

      # Enable split mode
      repl.execute("/split")

      # Verify state
      expect(repl.pinned?("config/database.yml")).to be true
      expect(repl.in_focus?("lib/features/auth/user.rb")).to be true
      expect(repl.in_focus?("lib/other/file.rb")).to be false
      expect(repl.should_halt?("Authentication test failed")).to be true
      expect(repl.split_mode).to be true
    end

    it "allows gradual constraint building" do
      # Start with broad focus
      repl.execute("/focus lib/**/*")
      expect(repl.in_focus?("lib/anything.rb")).to be true

      # Narrow focus
      repl.execute("/unfocus")
      repl.execute("/focus lib/specific/**/*")
      expect(repl.in_focus?("lib/specific/file.rb")).to be true
      expect(repl.in_focus?("lib/other/file.rb")).to be false
    end
  end
end
