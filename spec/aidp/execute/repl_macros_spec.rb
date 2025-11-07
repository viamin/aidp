# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/repl_macros"
require "aidp/worktree"
require "aidp/workstream_state"
require "aidp/skills"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Execute::ReplMacros do
  let(:repl) { described_class.new }
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#current_skill_object" do
    it "logs and returns nil when registry fails" do
      macros = described_class.new(project_dir: temp_dir)
      macros.instance_variable_set(:@current_skill, "repo-analyst")
      allow(Aidp::Skills::Registry).to receive(:new).and_raise(StandardError, "boom")
      allow(Aidp).to receive(:log_error)

      expect(macros.current_skill_object).to be_nil
      expect(Aidp).to have_received(:log_error).with("repl_macros", /Failed/, hash_including(:error))
    end
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
    it "removes pinned files discovered via glob patterns" do
      macros = described_class.new
      macros.instance_variable_get(:@pinned_files) << "lib/example.rb"
      allow(macros).to receive(:expand_pattern).and_return(["lib/example.rb"])

      result = macros.send(:cmd_unpin, ["lib/*.rb"])

      expect(result[:success]).to be true
      expect(result[:message]).to include("Unpinned 1 file")
      expect(macros.pinned?("lib/example.rb")).to be false
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

  describe "/skill command" do
    let(:skill_project_dir) { Dir.mktmpdir }
    let(:skill_repl) { described_class.new(project_dir: skill_project_dir) }
    let(:skill_dir) { File.join(skill_project_dir, ".aidp", "skills", "test_skill") }

    before do
      # Create a test skill
      FileUtils.mkdir_p(skill_dir)
      File.write(
        File.join(skill_dir, "SKILL.md"),
        <<~SKILL
          ---
          id: test_skill
          name: Test Skill
          version: 1.0.0
          description: A test skill for testing
          ---

          # Test Skill

          This is a test skill.
        SKILL
      )
    end

    after do
      FileUtils.rm_rf(skill_project_dir)
    end

    describe "use subcommand" do
      it "switches to a valid skill" do
        result = skill_repl.execute("/skill use test_skill")
        expect(result[:success]).to be true
        expect(result[:action]).to eq(:switch_skill)
        expect(result[:message]).to include("Now using skill: Test Skill")
        expect(result[:data][:skill_id]).to eq("test_skill")
        expect(skill_repl.summary[:current_skill]).to eq("test_skill")
      end

      it "fails when skill ID is missing" do
        result = skill_repl.execute("/skill use")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage: /skill use <skill-id>")
      end

      it "fails when skill does not exist" do
        result = skill_repl.execute("/skill use nonexistent_skill")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Skill not found: nonexistent_skill")
        expect(result[:message]).to include("Use '/skill list' to see available skills")
      end

      it "updates current_skill in summary" do
        skill_repl.execute("/skill use test_skill")
        summary = skill_repl.summary
        expect(summary[:current_skill]).to eq("test_skill")
      end
    end

    describe "#current_skill_object" do
      it "returns nil when no skill is selected" do
        expect(skill_repl.current_skill_object).to be_nil
      end

      it "returns skill object after /skill use" do
        skill_repl.execute("/skill use test_skill")
        skill = skill_repl.current_skill_object
        expect(skill).not_to be_nil
        expect(skill.id).to eq("test_skill")
        expect(skill.name).to eq("Test Skill")
      end

      it "returns nil for non-existent skill" do
        skill_repl.instance_variable_set(:@current_skill, "nonexistent")
        expect(skill_repl.current_skill_object).to be_nil
      end

      it "provides access to skill content" do
        skill_repl.execute("/skill use test_skill")
        skill = skill_repl.current_skill_object
        expect(skill.content).to include("# Test Skill")
      end
    end

    describe "list subcommand" do
      it "returns success with display action" do
        result = skill_repl.execute("/skill list")
        expect(result[:success]).to be true
        expect(result[:action]).to eq(:display)
        expect(result[:message]).to include("Available Skills")
      end
    end

    describe "show subcommand" do
      it "shows skill details for valid skill" do
        result = skill_repl.execute("/skill show test_skill")
        expect(result[:success]).to be true
        expect(result[:action]).to eq(:display)
        expect(result[:message]).to include("Test Skill")
      end

      it "fails when skill ID is missing" do
        result = skill_repl.execute("/skill show")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage: /skill show <skill-id>")
      end

      it "fails when skill does not exist" do
        result = skill_repl.execute("/skill show nonexistent")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Skill not found")
      end
    end

    describe "search subcommand" do
      it "searches for skills by query" do
        result = skill_repl.execute("/skill search test")
        expect(result[:success]).to be true
        expect(result[:action]).to eq(:display)
      end

      it "fails when query is missing" do
        result = skill_repl.execute("/skill search")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage: /skill search <query>")
      end
    end

    describe "invalid subcommand" do
      it "shows usage help" do
        result = skill_repl.execute("/skill invalid")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage: /skill <command>")
      end
    end

    describe "no subcommand" do
      it "defaults to list command" do
        result = skill_repl.execute("/skill")
        expect(result[:success]).to be true
        expect(result[:action]).to eq(:display)
        expect(result[:message]).to include("Available Skills")
      end
    end
  end

  describe "/tools command" do
    let(:tools_repl) { described_class.new(project_dir: temp_dir) }
    let(:config_dir) { File.join(temp_dir, ".aidp") }
    let(:config_file) { File.join(config_dir, "aidp.yml") }

    before do
      FileUtils.mkdir_p(config_dir)
    end

    context "show subcommand" do
      it "displays configured tools when config exists" do
        config = {
          "harness" => {
            "default_provider" => "cursor",
            "work_loop" => {
              "version_control" => {
                "tool" => "git",
                "behavior" => "commit",
                "conventional_commits" => true
              },
              "coverage" => {
                "enabled" => true,
                "tool" => "simplecov",
                "run_command" => "bundle exec rspec",
                "report_paths" => ["coverage/index.html"]
              }
            }
          },
          "providers" => {
            "cursor" => {
              "type" => "subscription",
              "model_family" => "auto"
            }
          }
        }

        File.write(config_file, YAML.dump(config))

        result = tools_repl.execute("/tools show")

        expect(result[:success]).to be true
        expect(result[:message]).to include("Coverage")
        expect(result[:message]).to include("simplecov")
        expect(result[:message]).to include("Version Control")
        expect(result[:message]).to include("git")
        expect(result[:message]).to include("Model Families")
      end

      it "shows disabled state when coverage is disabled" do
        config = {
          "harness" => {
            "default_provider" => "cursor",
            "work_loop" => {
              "coverage" => {
                "enabled" => false
              }
            }
          },
          "providers" => {
            "cursor" => {"type" => "subscription"}
          }
        }

        File.write(config_file, YAML.dump(config))

        result = tools_repl.execute("/tools show")

        expect(result[:success]).to be true
        expect(result[:message]).to include("Coverage: disabled")
      end
    end

    context "coverage subcommand" do
      it "runs coverage when enabled and configured" do
        config = {
          "harness" => {
            "default_provider" => "cursor",
            "work_loop" => {
              "coverage" => {
                "enabled" => true,
                "tool" => "simplecov",
                "run_command" => "bundle exec rspec",
                "report_paths" => ["coverage/index.html"]
              }
            }
          },
          "providers" => {
            "cursor" => {"type" => "subscription"}
          }
        }

        File.write(config_file, YAML.dump(config))

        result = tools_repl.execute("/tools coverage")

        expect(result[:success]).to be true
        expect(result[:action]).to eq(:run_coverage)
        expect(result[:data][:command]).to eq("bundle exec rspec")
        expect(result[:data][:tool]).to eq("simplecov")
      end

      it "fails when coverage is not enabled" do
        config = {
          "harness" => {
            "default_provider" => "cursor",
            "work_loop" => {
              "coverage" => {
                "enabled" => false
              }
            }
          },
          "providers" => {
            "cursor" => {"type" => "subscription"}
          }
        }

        File.write(config_file, YAML.dump(config))

        result = tools_repl.execute("/tools coverage")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Coverage is not enabled")
      end

      it "fails when run command is not configured" do
        config = {
          "harness" => {
            "default_provider" => "cursor",
            "work_loop" => {
              "coverage" => {
                "enabled" => true,
                "tool" => "simplecov"
              }
            }
          },
          "providers" => {
            "cursor" => {"type" => "subscription"}
          }
        }

        File.write(config_file, YAML.dump(config))

        result = tools_repl.execute("/tools coverage")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Coverage run command not configured")
      end
    end

    context "test subcommand" do
      it "runs web tests when configured" do
        config = {
          "harness" => {
            "default_provider" => "cursor",
            "work_loop" => {
              "interactive_testing" => {
                "enabled" => true,
                "app_type" => "web",
                "tools" => {
                  "web" => {
                    "playwright_mcp" => {
                      "enabled" => true,
                      "run" => "npx playwright test",
                      "specs_dir" => ".aidp/tests/web"
                    }
                  }
                }
              }
            }
          },
          "providers" => {
            "cursor" => {"type" => "subscription"}
          }
        }

        File.write(config_file, YAML.dump(config))

        result = tools_repl.execute("/tools test web")

        expect(result[:success]).to be true
        expect(result[:action]).to eq(:run_interactive_tests)
        expect(result[:data][:test_type]).to eq("web")
        expect(result[:data][:tools]).to have_key(:playwright_mcp)
      end

      it "fails when interactive testing is not enabled" do
        config = {
          "harness" => {
            "default_provider" => "cursor",
            "work_loop" => {
              "interactive_testing" => {
                "enabled" => false
              }
            }
          },
          "providers" => {
            "cursor" => {"type" => "subscription"}
          }
        }

        File.write(config_file, YAML.dump(config))

        result = tools_repl.execute("/tools test web")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Interactive testing is not enabled")
      end

      it "fails with invalid test type" do
        config = {
          "harness" => {
            "default_provider" => "cursor",
            "work_loop" => {
              "interactive_testing" => {
                "enabled" => true,
                "app_type" => "web"
              }
            }
          },
          "providers" => {
            "cursor" => {"type" => "subscription"}
          }
        }

        File.write(config_file, YAML.dump(config))

        result = tools_repl.execute("/tools test mobile")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Invalid test type")
      end

      it "requires test type argument" do
        config = {
          "harness" => {
            "default_provider" => "cursor",
            "work_loop" => {
              "interactive_testing" => {"enabled" => true}
            }
          },
          "providers" => {
            "cursor" => {"type" => "subscription"}
          }
        }

        File.write(config_file, YAML.dump(config))

        result = tools_repl.execute("/tools test")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage: /tools test")
      end
    end

    context "invalid subcommand" do
      it "shows usage help" do
        result = tools_repl.execute("/tools invalid")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage: /tools")
        expect(result[:message]).to include("show")
        expect(result[:message]).to include("coverage")
        expect(result[:message]).to include("test")
      end
    end

    context "no subcommand" do
      it "shows usage help" do
        result = tools_repl.execute("/tools")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage: /tools")
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

  describe "/thinking command" do
    let(:project_dir) { Dir.mktmpdir }
    let(:repl) { described_class.new(project_dir: project_dir) }

    before do
      # Create config directory and files
      FileUtils.mkdir_p(File.join(project_dir, ".aidp"))

      # Create models catalog
      catalog_path = File.join(project_dir, ".aidp", "models_catalog.yml")
      catalog = {
        "schema_version" => "1.0",
        "providers" => {
          "anthropic" => {
            "display_name" => "Anthropic",
            "models" => {
              "claude-3-haiku" => {"tier" => "mini", "context_window" => 200000},
              "claude-3-5-sonnet" => {"tier" => "standard", "context_window" => 200000},
              "claude-3-opus" => {"tier" => "pro", "context_window" => 200000}
            }
          }
        }
      }
      File.write(catalog_path, YAML.dump(catalog))

      # Create config file
      config_path = File.join(project_dir, ".aidp", "aidp.yml")
      config = {
        "harness" => {
          "default_provider" => "anthropic"
        },
        "thinking" => {
          "default_tier" => "standard",
          "max_tier" => "pro"
        },
        "providers" => {
          "anthropic" => {
            "type" => "usage_based",
            "api_key" => "test-key",
            "models" => ["claude-3-5-sonnet"],
            "priority" => 1
          },
          "cursor" => {
            "type" => "usage_based",
            "api_key" => "test-key",
            "models" => ["cursor-small"],
            "priority" => 2
          }
        }
      }
      File.write(config_path, YAML.dump(config))
    end

    after do
      FileUtils.rm_rf(project_dir)
    end

    describe "/thinking show" do
      it "displays current thinking configuration" do
        result = repl.execute("/thinking show")
        expect(result[:success]).to be true
        expect(result[:message]).to include("Thinking Depth Configuration")
        expect(result[:message]).to include("Current Tier: standard")
        expect(result[:message]).to include("Max Tier: pro")
        expect(result[:action]).to eq(:display)
      end

      it "shows available tiers" do
        result = repl.execute("/thinking show")
        expect(result[:message]).to include("Available Tiers:")
        expect(result[:message]).to include("mini")
        expect(result[:message]).to include("standard")
        expect(result[:message]).to include("pro")
      end

      it "shows current model selection" do
        result = repl.execute("/thinking show")
        expect(result[:message]).to include("Current Model:")
        expect(result[:message]).to include("anthropic")
      end

      it "shows escalation settings" do
        result = repl.execute("/thinking show")
        expect(result[:message]).to include("Escalation Settings:")
        expect(result[:message]).to include("Fail Attempts Threshold:")
      end
    end

    describe "/thinking set" do
      it "changes current tier" do
        result = repl.execute("/thinking set thinking")
        expect(result[:success]).to be true
        expect(result[:message]).to include("standard → thinking")
        expect(result[:action]).to eq(:tier_changed)
      end

      it "validates tier name" do
        result = repl.execute("/thinking set invalid")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Invalid tier")
      end

      it "requires tier argument" do
        result = repl.execute("/thinking set")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage:")
      end

      it "enforces max tier" do
        result = repl.execute("/thinking set max")
        expect(result[:success]).to be true
        # Should be capped at pro (the configured max_tier)
        expect(result[:message]).to include("pro")
      end
    end

    describe "/thinking max" do
      it "changes max tier" do
        result = repl.execute("/thinking max thinking")
        expect(result[:success]).to be true
        expect(result[:message]).to include("pro → thinking")
        expect(result[:action]).to eq(:max_tier_changed)
      end

      it "validates tier name" do
        result = repl.execute("/thinking max invalid")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Invalid tier")
      end

      it "requires tier argument" do
        result = repl.execute("/thinking max")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage:")
      end
    end

    describe "/thinking reset" do
      it "resets tier to default" do
        result = repl.execute("/thinking reset")
        expect(result[:success]).to be true
        # Since each command creates a fresh manager, reset will show standard → standard
        # In a real REPL with persistent manager state, this would reset from current tier
        expect(result[:message]).to include("→ standard")
        expect(result[:message]).to include("Escalation count cleared")
        expect(result[:action]).to eq(:tier_reset)
      end
    end

    describe "unknown subcommand" do
      it "returns error for unknown subcommand" do
        result = repl.execute("/thinking invalid")
        expect(result[:success]).to be false
        expect(result[:message]).to include("Unknown subcommand")
      end
    end
  end

  # Interactive commands (previously repl_macros_interactive_spec.rb)
  describe "interactive commands" do
    let(:macros) { described_class.new }

    describe "/pause command" do
      it "returns success with pause action" do
        result = macros.execute("/pause")
        expect(result[:success]).to be true
        expect(result[:action]).to eq(:pause_work_loop)
        expect(result[:message]).to include("Pause signal")
      end
    end

    describe "/resume command" do
      it "returns success with resume action" do
        result = macros.execute("/resume")
        expect(result[:success]).to be true
        expect(result[:action]).to eq(:resume_work_loop)
        expect(result[:message]).to include("Resume signal")
      end
    end

    describe "/cancel command" do
      context "without flags" do
        it "cancels with checkpoint save" do
          result = macros.execute("/cancel")
          expect(result[:success]).to be true
          expect(result[:action]).to eq(:cancel_work_loop)
          expect(result[:data][:save_checkpoint]).to be true
        end
      end

      context "with --no-checkpoint flag" do
        it "cancels without checkpoint save" do
          result = macros.execute("/cancel --no-checkpoint")
          expect(result[:success]).to be true
          expect(result[:data][:save_checkpoint]).to be false
        end
      end
    end

    describe "/inject command" do
      context "with instruction" do
        it "enqueues instruction with normal priority" do
          result = macros.execute("/inject Add error handling")
          expect(result[:success]).to be true
          expect(result[:action]).to eq(:enqueue_instruction)
          expect(result[:data][:instruction]).to eq("Add error handling")
          expect(result[:data][:type]).to eq(:user_input)
          expect(result[:data][:priority]).to eq(:normal)
        end
      end

      context "with priority flag" do
        it "enqueues with high priority" do
          result = macros.execute("/inject Fix security issue --priority high")
          expect(result[:data][:priority]).to eq(:high)
        end

        it "enqueues with low priority" do
          result = macros.execute("/inject Improve logging --priority low")
          expect(result[:data][:priority]).to eq(:low)
        end
      end

      context "without instruction" do
        it "returns error" do
          result = macros.execute("/inject")
          expect(result[:success]).to be false
          expect(result[:message]).to include("Usage:")
        end
      end
    end

    describe "/merge command" do
      context "with plan update" do
        it "enqueues with plan_update type and high priority" do
          result = macros.execute("/merge Add acceptance criteria: handle timeouts")
          expect(result[:success]).to be true
          expect(result[:action]).to eq(:enqueue_instruction)
          expect(result[:data][:instruction]).to eq("Add acceptance criteria: handle timeouts")
          expect(result[:data][:type]).to eq(:plan_update)
          expect(result[:data][:priority]).to eq(:high)
        end
      end

      context "without plan update" do
        it "returns error" do
          result = macros.execute("/merge")
          expect(result[:success]).to be false
        end
      end
    end

    describe "/update command" do
      context "with guard category" do
        it "updates guard configuration" do
          result = macros.execute("/update guard max_lines=500")
          expect(result[:success]).to be true
          expect(result[:action]).to eq(:update_guard)
          expect(result[:data][:key]).to eq("max_lines")
          expect(result[:data][:value]).to eq("500")
        end

        it "handles key with underscores" do
          result = macros.execute("/update guard max_lines_per_commit=300")
          expect(result[:data][:key]).to eq("max_lines_per_commit")
          expect(result[:data][:value]).to eq("300")
        end
      end

      context "with invalid category" do
        it "returns error" do
          result = macros.execute("/update invalid key=value")
          expect(result[:success]).to be false
          expect(result[:message]).to include("Only 'guard' updates supported")
        end
      end

      context "without key=value format" do
        it "returns error" do
          result = macros.execute("/update guard invalid")
          expect(result[:success]).to be false
          expect(result[:message]).to include("Invalid format")
        end
      end

      context "without arguments" do
        it "returns error" do
          result = macros.execute("/update")
          expect(result[:success]).to be false
          expect(result[:message]).to include("Usage:")
        end
      end
    end

    describe "/reload command" do
      context "with config category" do
        it "requests config reload" do
          result = macros.execute("/reload config")
          expect(result[:success]).to be true
          expect(result[:action]).to eq(:reload_config)
        end
      end

      context "with invalid category" do
        it "returns error" do
          result = macros.execute("/reload invalid")
          expect(result[:success]).to be false
        end
      end

      context "without category" do
        it "returns error" do
          result = macros.execute("/reload")
          expect(result[:success]).to be false
        end
      end
    end

    describe "/rollback command" do
      context "with valid count" do
        it "requests rollback of n commits" do
          result = macros.execute("/rollback 3")
          expect(result[:success]).to be true
          expect(result[:action]).to eq(:rollback_commits)
          expect(result[:data][:count]).to eq(3)
        end
      end

      context "with count of 1" do
        it "rolls back one commit" do
          result = macros.execute("/rollback 1")
          expect(result[:data][:count]).to eq(1)
        end
      end

      context "with invalid count" do
        it "returns error for zero" do
          result = macros.execute("/rollback 0")
          expect(result[:success]).to be false
        end

        it "returns error for negative" do
          result = macros.execute("/rollback -1")
          expect(result[:success]).to be false
        end

        it "returns error for non-numeric" do
          result = macros.execute("/rollback abc")
          expect(result[:success]).to be false
        end
      end

      context "without count" do
        it "returns error" do
          result = macros.execute("/rollback")
          expect(result[:success]).to be false
        end
      end
    end

    describe "/undo command" do
      context "with 'last' argument" do
        it "rolls back one commit" do
          result = macros.execute("/undo last")
          expect(result[:success]).to be true
          expect(result[:action]).to eq(:rollback_commits)
          expect(result[:data][:count]).to eq(1)
        end
      end

      context "without 'last' argument" do
        it "returns error" do
          result = macros.execute("/undo")
          expect(result[:success]).to be false
        end
      end

      context "with wrong argument" do
        it "returns error" do
          result = macros.execute("/undo first")
          expect(result[:success]).to be false
        end
      end
    end

    describe "help system" do
      it "includes new commands in help" do
        result = macros.execute("/help")
        expect(result[:message]).to include("/pause")
        expect(result[:message]).to include("/resume")
        expect(result[:message]).to include("/cancel")
        expect(result[:message]).to include("/inject")
        expect(result[:message]).to include("/merge")
        expect(result[:message]).to include("/update")
        expect(result[:message]).to include("/reload")
        expect(result[:message]).to include("/rollback")
        expect(result[:message]).to include("/undo")
      end

      it "provides detailed help for specific commands" do
        result = macros.execute("/help /inject")
        expect(result[:message]).to include("Usage:")
        expect(result[:message]).to include("--priority")
      end
    end

    describe "command list" do
      it "includes all interactive commands" do
        commands = macros.list_commands
        expect(commands).to include("/pause")
        expect(commands).to include("/resume")
        expect(commands).to include("/cancel")
        expect(commands).to include("/inject")
        expect(commands).to include("/merge")
        expect(commands).to include("/update")
        expect(commands).to include("/reload")
        expect(commands).to include("/rollback")
        expect(commands).to include("/undo")
      end
    end
  end

  # Workstream commands (previously repl_macros_workstream_spec.rb)
  describe "workstream commands" do
    let(:project_dir) { Dir.mktmpdir }
    let(:repl) { described_class.new(project_dir: project_dir) }

    before do
      # Initialize a git repository
      Dir.chdir(project_dir) do
        system("git", "init", "-q")
        system("git", "config", "user.name", "Test User")
        system("git", "config", "user.email", "test@example.com")
        File.write("README.md", "# Test Project")
        system("git", "add", ".")
        system("git", "commit", "-q", "-m", "Initial commit")
      end
    end

    after do
      # Clean up git worktrees before removing directory
      Dir.chdir(project_dir) do
        worktrees = Aidp::Worktree.list(project_dir: project_dir)
        worktrees.each do |ws|
          Aidp::Worktree.remove(slug: ws[:slug], project_dir: project_dir)
        rescue
          nil
        end
      end
      FileUtils.rm_rf(project_dir)
    end

    describe "/ws list" do
      it "shows message when no workstreams exist" do
        result = repl.execute("/ws list")

        expect(result[:success]).to be true
        expect(result[:message]).to include("No workstreams found")
        expect(result[:message]).to include("/ws new")
        expect(result[:action]).to eq(:display)
      end

      it "lists existing workstreams" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "test-123", project_dir: project_dir)
          Aidp::Worktree.create(slug: "test-456", project_dir: project_dir)
        end

        result = repl.execute("/ws list")

        expect(result[:success]).to be true
        expect(result[:message]).to include("test-123")
        expect(result[:message]).to include("test-456")
        expect(result[:message]).to include("aidp/test-123")
        expect(result[:message]).to include("aidp/test-456")
      end

      it "marks current workstream in list" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "current-ws", project_dir: project_dir)
        end

        repl.execute("/ws switch current-ws")
        result = repl.execute("/ws list")

        expect(result[:success]).to be true
        expect(result[:message]).to include("current-ws")
        expect(result[:message]).to include("[CURRENT]")
      end

      it "handles /ws without subcommand as list" do
        result = repl.execute("/ws")

        expect(result[:success]).to be true
        expect(result[:message]).to include("No workstreams found")
      end
    end

    describe "/ws new" do
      it "creates a new workstream" do
        result = repl.execute("/ws new issue-123")

        expect(result[:success]).to be true
        expect(result[:message]).to include("Created workstream: issue-123")
        expect(result[:message]).to include("Path:")
        expect(result[:message]).to include("Branch: aidp/issue-123")
        expect(result[:message]).to include("/ws switch issue-123")
        expect(result[:action]).to eq(:display)

        # Verify worktree was created
        ws = Aidp::Worktree.info(slug: "issue-123", project_dir: project_dir)
        expect(ws).not_to be_nil
        expect(ws[:slug]).to eq("issue-123")
      end

      it "requires slug argument" do
        result = repl.execute("/ws new")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage: /ws new <slug>")
        expect(result[:action]).to eq(:none)
      end

      it "validates slug format" do
        result = repl.execute("/ws new Invalid_Slug")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Invalid slug format")
        expect(result[:message]).to include("lowercase with hyphens")
        expect(result[:action]).to eq(:none)
      end

      it "supports --base-branch option" do
        # Create a feature branch
        Dir.chdir(project_dir) do
          system("git", "checkout", "-q", "-b", "feature")
          File.write("feature.txt", "feature content")
          system("git", "add", ".")
          system("git", "commit", "-q", "-m", "Add feature")
          system("git", "checkout", "-q", "master")
        end

        result = repl.execute("/ws new from-feature --base-branch feature")

        expect(result[:success]).to be true
        expect(result[:message]).to include("Created workstream: from-feature")

        # Verify it was created from the feature branch
        ws = Aidp::Worktree.info(slug: "from-feature", project_dir: project_dir)
        expect(ws).not_to be_nil
        expect(File.exist?(File.join(ws[:path], "feature.txt"))).to be true
      end

      it "handles duplicate workstream error" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "duplicate", project_dir: project_dir)
        end

        result = repl.execute("/ws new duplicate")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Failed to create workstream")
        expect(result[:message]).to include("already exists")
        expect(result[:action]).to eq(:none)
      end
    end

    describe "/ws switch" do
      it "switches to an existing workstream" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "target-ws", project_dir: project_dir)
        end

        result = repl.execute("/ws switch target-ws")

        expect(result[:success]).to be true
        expect(result[:message]).to include("Switched to workstream: target-ws")
        expect(result[:message]).to include("All operations will now use:")
        expect(result[:action]).to eq(:switch_workstream)
        expect(result[:data][:slug]).to eq("target-ws")
        expect(result[:data][:branch]).to eq("aidp/target-ws")
        expect(result[:data][:path]).to include(".worktrees/target-ws")

        # Verify current workstream is updated
        expect(repl.current_workstream).to eq("target-ws")
      end

      it "requires slug argument" do
        result = repl.execute("/ws switch")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage: /ws switch <slug>")
        expect(result[:action]).to eq(:none)
      end

      it "handles non-existent workstream" do
        result = repl.execute("/ws switch nonexistent")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Workstream not found: nonexistent")
        expect(result[:action]).to eq(:none)
      end

      it "updates current_workstream_path after switch" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "path-test", project_dir: project_dir)
        end

        expect(repl.current_workstream_path).to eq(project_dir)

        repl.execute("/ws switch path-test")

        expect(repl.current_workstream_path).to include(".worktrees/path-test")
        expect(repl.current_workstream_path).not_to eq(project_dir)
      end
    end

    describe "/ws rm" do
      it "removes an existing workstream" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "to-remove", project_dir: project_dir)
        end

        result = repl.execute("/ws rm to-remove")

        expect(result[:success]).to be true
        expect(result[:message]).to include("Removed workstream: to-remove")
        expect(result[:action]).to eq(:display)

        # Verify worktree was removed
        ws = Aidp::Worktree.info(slug: "to-remove", project_dir: project_dir)
        expect(ws).to be_nil
      end

      it "requires slug argument" do
        result = repl.execute("/ws rm")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage: /ws rm <slug>")
        expect(result[:action]).to eq(:none)
      end

      it "supports --delete-branch option" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "with-branch", project_dir: project_dir)
        end

        result = repl.execute("/ws rm with-branch --delete-branch")

        expect(result[:success]).to be true
        expect(result[:message]).to include("Removed workstream: with-branch")
        expect(result[:message]).to include("(branch deleted)")

        # Verify branch was deleted
        Dir.chdir(project_dir) do
          branches = `git branch --list aidp/with-branch`.strip
          expect(branches).to be_empty
        end
      end

      it "prevents removing current workstream" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "current", project_dir: project_dir)
        end

        repl.execute("/ws switch current")
        result = repl.execute("/ws rm current")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Cannot remove current workstream")
        expect(result[:message]).to include("Switch to another first")
        expect(result[:action]).to eq(:none)

        # Verify worktree still exists
        ws = Aidp::Worktree.info(slug: "current", project_dir: project_dir)
        expect(ws).not_to be_nil
      end

      it "handles non-existent workstream" do
        result = repl.execute("/ws rm nonexistent")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Failed to remove workstream")
        expect(result[:message]).to include("not found")
        expect(result[:action]).to eq(:none)
      end
    end

    describe "/ws status" do
      it "shows detailed workstream status" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "status-test", project_dir: project_dir)
        end

        result = repl.execute("/ws status status-test")

        expect(result[:success]).to be true
        expect(result[:message]).to include("Workstream: status-test")
        expect(result[:message]).to include("Path:")
        expect(result[:message]).to include("Branch: aidp/status-test")
        expect(result[:message]).to include("Created:")
        expect(result[:message]).to include("Status: Active")
        expect(result[:action]).to eq(:display)
      end

      it "uses current workstream when no slug provided" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "current-status", project_dir: project_dir)
        end

        repl.execute("/ws switch current-status")
        result = repl.execute("/ws status")

        expect(result[:success]).to be true
        expect(result[:message]).to include("Workstream: current-status")
        expect(result[:message]).to include("[CURRENT]")
      end

      it "requires slug when no current workstream" do
        result = repl.execute("/ws status")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage: /ws status [slug]")
        expect(result[:message]).to include("No current workstream set")
        expect(result[:action]).to eq(:none)
      end

      it "handles non-existent workstream" do
        result = repl.execute("/ws status nonexistent")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Workstream not found: nonexistent")
        expect(result[:action]).to eq(:none)
      end
    end

    describe "/status integration" do
      it "includes current workstream in /status output" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "status-ws", project_dir: project_dir)
        end

        repl.execute("/ws switch status-ws")
        result = repl.execute("/status")

        expect(result[:success]).to be true
        expect(result[:message]).to include("Current Workstream: status-ws")
        expect(result[:message]).to include("Path:")
        expect(result[:message]).to include("Branch: aidp/status-ws")
      end

      it "shows (none) when no workstream is set" do
        result = repl.execute("/status")

        expect(result[:success]).to be true
        expect(result[:message]).to include("Current Workstream: (none - using main project)")
      end
    end

    describe "summary" do
      it "includes current_workstream in summary" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "summary-ws", project_dir: project_dir)
        end

        repl.execute("/ws switch summary-ws")
        summary = repl.summary

        expect(summary[:current_workstream]).to eq("summary-ws")
      end

      it "has nil current_workstream when none set" do
        summary = repl.summary

        expect(summary[:current_workstream]).to be_nil
      end
    end

    describe "current_workstream_path" do
      it "returns project_dir when no workstream is set" do
        expect(repl.current_workstream_path).to eq(project_dir)
      end

      it "returns workstream path when workstream is set" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "path-ws", project_dir: project_dir)
        end

        repl.execute("/ws switch path-ws")

        expect(repl.current_workstream_path).to include(".worktrees/path-ws")
        expect(repl.current_workstream_path).not_to eq(project_dir)
      end

      it "falls back to project_dir if workstream is deleted" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "deleted-ws", project_dir: project_dir)
        end

        repl.execute("/ws switch deleted-ws")

        # Manually remove the workstream without using /ws rm
        Dir.chdir(project_dir) do
          Aidp::Worktree.remove(slug: "deleted-ws", project_dir: project_dir)
        end

        expect(repl.current_workstream_path).to eq(project_dir)
      end
    end

    describe "switch_workstream method" do
      it "switches to existing workstream" do
        Dir.chdir(project_dir) do
          Aidp::Worktree.create(slug: "method-ws", project_dir: project_dir)
        end

        result = repl.switch_workstream("method-ws")

        expect(result).to be true
        expect(repl.current_workstream).to eq("method-ws")
      end

      it "returns false for non-existent workstream" do
        result = repl.switch_workstream("nonexistent")

        expect(result).to be false
        expect(repl.current_workstream).to be_nil
      end
    end

    describe "/help integration" do
      it "includes /ws in help output" do
        result = repl.execute("/help")

        expect(result[:success]).to be true
        expect(result[:message]).to include("/ws")
        expect(result[:message]).to include("workstreams")
      end

      it "shows detailed /ws help" do
        result = repl.execute("/help /ws")

        expect(result[:success]).to be true
        expect(result[:message]).to include("/ws")
        expect(result[:message]).to include("Usage:")
        expect(result[:message]).to include("Example:")
      end
    end

    describe "unknown /ws subcommand" do
      it "shows usage help" do
        result = repl.execute("/ws unknown")

        expect(result[:success]).to be false
        expect(result[:message]).to include("Usage: /ws <command>")
        expect(result[:message]).to include("Commands:")
        expect(result[:message]).to include("list")
        expect(result[:message]).to include("new <slug>")
        expect(result[:message]).to include("switch <slug>")
        expect(result[:message]).to include("rm <slug>")
        expect(result[:message]).to include("status [slug]")
        expect(result[:message]).to include("Examples:")
      end
    end
  end

  describe "/ws status error handling" do
    it "returns failure when worktree raises" do
      allow(Aidp::Worktree).to receive(:info).and_raise(Aidp::Worktree::Error, "boom")
      result = repl.execute("/ws status ghost-stream")
      expect(result[:success]).to be false
      expect(result[:message]).to include("Failed to get workstream status")
    end
  end

  describe "/ws pause command" do
    it "requires a slug or current workstream" do
      result = repl.execute("/ws pause")
      expect(result[:success]).to be false
      expect(result[:message]).to include("Usage")
    end

    it "surfaces pause errors" do
      allow(Aidp::WorkstreamState).to receive(:pause).and_return({error: "cannot pause"})
      result = repl.execute("/ws pause api-stream")
      expect(result[:success]).to be false
      expect(result[:message]).to include("Failed to pause")
    end

    it "confirms pause success" do
      allow(Aidp::WorkstreamState).to receive(:pause).and_return({})
      result = repl.execute("/ws pause api-stream")
      expect(result[:success]).to be true
      expect(result[:message]).to include("Paused workstream")
    end
  end

  describe "#matches_pattern?" do
    let(:macros) { described_class.new }

    it "treats bare ** as match-all" do
      expect(macros.send(:matches_pattern?, "lib/foo.rb", "**")).to be true
    end

    it "matches suffix patterns beginning with **" do
      expect(macros.send(:matches_pattern?, "lib/foo/bar.rb", "**/bar.rb")).to be true
    end

    it "matches prefix when pattern ends with **" do
      expect(macros.send(:matches_pattern?, "lib/foo/bar.rb", "lib/**")).to be true
    end
  end
end
