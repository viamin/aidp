# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/test_prompt"

RSpec.describe Aidp::Setup::Wizard do
  let(:tmp_dir) { Dir.mktmpdir }

  # Default prompt with comprehensive responses to avoid hanging
  let(:prompt) do
    TestPrompt.new(responses: {
      ask: "",
      yes?: false,  # Skip all optional configuration sections by default
      no?: false,
      multi_select: [],
      select_map: {
        # Required provider configuration
        "Select your primary provider:" => "anthropic",
        "Billing model for anthropic:" => "usage_based",
        "Preferred model family for anthropic:" => "Auto (let provider decide)",
        # Required logging configuration
        "Log level:" => "Info",
        # Required VCS configuration
        "Detected git. Use this version control system?" => "git",
        "Which version control system do you use?" => "git",
        "In copilot mode, should aidp:" => "Do nothing (manual git operations)"
      }
    })
  end

  # Clean up any background discovery threads after each test
  after do
    if defined?(wizard)
      threads = wizard.discovery_threads
      if threads&.any?
        threads.each do |entry|
          thread = entry[:thread]
          if thread&.alive?
            thread.kill
            begin
              thread.join(0.1)
            rescue
              nil
            end
          end
        end
      end
    end
  end

  before do
    FileUtils.mkdir_p(tmp_dir)
    File.write(File.join(tmp_dir, "Gemfile"), "source 'https://rubygems.org'")
    allow(Aidp::Util).to receive(:which).and_return("/usr/bin/fake")
  end

  after { FileUtils.rm_rf(tmp_dir) }

  describe "#run" do
    it "runs in dry run mode without writing" do
      wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
      expect(wizard.run).to be true
      expect(File).not_to exist(File.join(tmp_dir, ".aidp", "aidp.yml"))
    end

    it "saves config when user confirms" do
      prompt_with_yes = TestPrompt.new(responses: {
        ask: "",
        yes?: false,  # Default to no for optional sections
        yes_map: {
          "Save this configuration?" => true
        },
        multi_select: [],
        select_map: {
          "Select your primary provider:" => "anthropic",
          "Billing model for anthropic:" => "usage_based",
          "Preferred model family for anthropic:" => "Auto (let provider decide)",
          "Log level:" => "Info",
          "Detected git. Use this version control system?" => "git",
          "Which version control system do you use?" => "git",
          "In copilot mode, should aidp:" => "Do nothing (manual git operations)"
        }
      })
      wizard = described_class.new(tmp_dir, prompt: prompt_with_yes, dry_run: false)
      wizard.run
      expect(File).to exist(Aidp::ConfigPaths.config_file(tmp_dir))
    end

    it "captures auto-update configuration when enabled" do
      prompt_with_auto_update = TestPrompt.new(responses: {
        ask: "",
        yes?: false,
        yes_map: {
          "Enable auto-update for watch mode?" => true,
          "Allow prerelease versions?" => true,
          "Save this configuration?" => true
        },
        multi_select: [],
        select_map: {
          "Select your primary provider:" => "anthropic",
          "Billing model for anthropic:" => "usage_based",
          "Preferred model family for anthropic:" => "Auto (let provider decide)",
          "Log level:" => "Info",
          "Detected git. Use this version control system?" => "git",
          "Which version control system do you use?" => "git",
          "In copilot mode, should aidp:" => "Do nothing (manual git operations)",
          "Auto-update policy:" => "patch",
          "Update supervisor:" => "supervisord"
        }
      })

      wizard = described_class.new(tmp_dir, prompt: prompt_with_auto_update, dry_run: false)
      wizard.run

      config = YAML.safe_load_file(Aidp::ConfigPaths.config_file(tmp_dir), symbolize_names: true)
      auto_update = config[:auto_update]

      expect(auto_update[:enabled]).to be true
      expect(auto_update[:policy]).to eq("patch")
      expect(auto_update[:allow_prerelease]).to be true
      expect(auto_update[:supervisor]).to eq("supervisord")
      expect(auto_update[:check_interval_seconds]).to eq(3600)
      expect(auto_update[:max_consecutive_failures]).to eq(3)
    end

    it "does not save when user declines" do
      # Ensure config file doesn't exist before test
      config_file = Aidp::ConfigPaths.config_file(tmp_dir)
      FileUtils.rm_f(config_file) if File.exist?(config_file)

      prompt_with_no = TestPrompt.new(responses: {
        ask: "",
        yes?: false,  # Default to no for all optional sections
        yes_map: {
          "Save this configuration?" => false
        },
        multi_select: [],
        select_map: {
          "Select your primary provider:" => "anthropic",
          "Billing model for anthropic:" => "usage_based",
          "Preferred model family for anthropic:" => "Auto (let provider decide)",
          "Log level:" => "Info",
          "Detected git. Use this version control system?" => "git",
          "Which version control system do you use?" => "git",
          "In copilot mode, should aidp:" => "Do nothing (manual git operations)"
        }
      })
      wizard = described_class.new(tmp_dir, prompt: prompt_with_no, dry_run: false)
      wizard.run
      expect(File).not_to exist(config_file)
    end

    it "skips wizard when user declines to update existing config" do
      config_dir = Aidp::ConfigPaths.config_dir(tmp_dir)
      FileUtils.mkdir_p(config_dir)
      File.write(Aidp::ConfigPaths.config_file(tmp_dir), "schema_version: 1\n")

      prompt_skip = TestPrompt.new(responses: {yes?: false})
      wizard = described_class.new(tmp_dir, prompt: prompt_skip)
      result = wizard.run
      expect(result).to be true
      expect(wizard.saved?).to be true
    end

    it "continues wizard when user chooses to update existing config" do
      config_dir = Aidp::ConfigPaths.config_dir(tmp_dir)
      FileUtils.mkdir_p(config_dir)
      File.write(Aidp::ConfigPaths.config_file(tmp_dir), "schema_version: 1\n")

      prompt_continue = TestPrompt.new(responses: {
        ask: "",
        yes?: false,  # Default to no for optional sections
        yes_map: {
          "Would you like to update it?" => true,  # Yes to updating existing config
          "Save this configuration?" => true  # Yes to saving
        },
        multi_select: [],
        select_map: {
          "Select your primary provider:" => "anthropic",
          "Billing model for anthropic:" => "usage_based",
          "Preferred model family for anthropic:" => "Auto (let provider decide)",
          "Log level:" => "Info",
          "Detected git. Use this version control system?" => "git",
          "Which version control system do you use?" => "git",
          "In copilot mode, should aidp:" => "Do nothing (manual git operations)"
        }
      })
      wizard = described_class.new(tmp_dir, prompt: prompt_continue)
      wizard.run
      expect(wizard.saved?).to be true
    end
  end

  describe "#generate_yaml" do
    it "generates yaml with helpful comments" do
      wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
      wizard.run
      yaml = wizard.send(:generate_yaml)
      expect(yaml).to include("# Provider configuration")
      expect(yaml).to include("schema_version:")
    end

    it "includes schema version" do
      wizard = described_class.new(tmp_dir, prompt: prompt)
      yaml = wizard.send(:generate_yaml)
      expect(yaml).to include("schema_version: 1")
    end

    it "includes generation metadata" do
      wizard = described_class.new(tmp_dir, prompt: prompt)
      yaml = wizard.send(:generate_yaml)
      expect(yaml).to include("generated_by:")
      expect(yaml).to include("generated_at:")
    end
  end

  describe "diff display" do
    it "produces unified diff when existing config differs" do
      config_dir = Aidp::ConfigPaths.config_dir(tmp_dir)
      FileUtils.mkdir_p(config_dir)
      File.write(Aidp::ConfigPaths.config_file(tmp_dir), "schema_version: 1\nproviders:\n  llm:\n    name: cursor\n")

      wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
      yaml = wizard.send(:generate_yaml)
      diff = wizard.send(:line_diff, File.read(Aidp::ConfigPaths.config_file(tmp_dir)), yaml)
      expect(diff.any? { |line| line.start_with?("+") }).to be true
    end

    it "handles missing config file gracefully" do
      wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
      yaml = wizard.send(:generate_yaml)
      expect { wizard.send(:display_diff, yaml) }.not_to raise_error
    end
  end

  describe "stack detection" do
    it "detects Rails stack" do
      FileUtils.mkdir_p(File.join(tmp_dir, "config"))
      File.write(File.join(tmp_dir, "config", "application.rb"), "# Rails app")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_stack)).to eq(:rails)
    end

    it "detects Node stack" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      File.write(File.join(tmp_dir, "package.json"), "{}")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_stack)).to eq(:node)
    end

    it "detects Python stack from pyproject.toml" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      File.write(File.join(tmp_dir, "pyproject.toml"), "[tool.poetry]")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_stack)).to eq(:python)
    end

    it "detects Python stack from requirements.txt" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      File.write(File.join(tmp_dir, "requirements.txt"), "django")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_stack)).to eq(:python)
    end

    it "returns :other for unknown stacks" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_stack)).to eq(:other)
    end
  end

  describe "test command detection" do
    it "detects RSpec for Ruby projects" do
      FileUtils.mkdir_p(File.join(tmp_dir, "spec"))
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_unit_test_command)).to eq("bundle exec rspec")
    end

    it "detects npm test for Node projects" do
      File.write(File.join(tmp_dir, "package.json"), "{}")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_unit_test_command)).to eq("npm test")
    end

    it "detects pytest from pytest.ini" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      File.write(File.join(tmp_dir, "pytest.ini"), "[pytest]")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_unit_test_command)).to eq("pytest")
    end

    it "detects pytest from tests directory" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      FileUtils.mkdir_p(File.join(tmp_dir, "tests"))
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_unit_test_command)).to eq("pytest")
    end

    it "returns echo fallback when no test framework detected" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_unit_test_command)).to eq("echo 'No tests configured'")
    end
  end

  describe "lint command detection" do
    it "detects rubocop for Ruby projects" do
      File.write(File.join(tmp_dir, ".rubocop.yml"), "AllCops:")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_lint_command)).to eq("bundle exec rubocop")
    end

    it "detects npm lint for Node projects" do
      File.write(File.join(tmp_dir, "package.json"), "{}")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_lint_command)).to eq("npm run lint")
    end

    it "detects ruff for Python projects" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      File.write(File.join(tmp_dir, "pyproject.toml"), "[tool.ruff]")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_lint_command)).to eq("ruff check .")
    end

    it "returns echo fallback when no linter detected" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_lint_command)).to eq("echo 'No linter configured'")
    end
  end

  describe "format command detection" do
    it "detects rubocop -A for Ruby projects" do
      File.write(File.join(tmp_dir, ".rubocop.yml"), "AllCops:")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_format_command)).to eq("bundle exec rubocop -A")
    end

    it "detects npm format for Node projects" do
      File.write(File.join(tmp_dir, "package.json"), "{}")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_format_command)).to eq("npm run format")
    end

    it "detects ruff format for Python projects" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      File.write(File.join(tmp_dir, "pyproject.toml"), "[tool.ruff]")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_format_command)).to eq("ruff format .")
    end

    it "returns echo fallback when no formatter detected" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.send(:detect_format_command)).to eq("echo 'No formatter configured'")
    end
  end

  describe "watch patterns detection" do
    it "detects Ruby patterns for Gemfile projects" do
      wizard = described_class.new(tmp_dir, prompt: prompt)
      patterns = wizard.send(:detect_watch_patterns)
      expect(patterns).to include("spec/**/*_spec.rb", "lib/**/*.rb")
    end

    it "detects TypeScript patterns for Node projects" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      File.write(File.join(tmp_dir, "package.json"), "{}")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      patterns = wizard.send(:detect_watch_patterns)
      expect(patterns).to include("src/**/*.ts", "src/**/*.tsx", "tests/**/*.ts")
    end

    it "returns wildcard pattern for unknown projects" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      wizard = described_class.new(tmp_dir, prompt: prompt)
      patterns = wizard.send(:detect_watch_patterns)
      expect(patterns).to eq(["**/*"])
    end
  end

  describe "source patterns detection" do
    it "detects Ruby source patterns" do
      wizard = described_class.new(tmp_dir, prompt: prompt)
      patterns = wizard.send(:detect_source_patterns)
      expect(patterns).to include("app/**/*", "lib/**/*")
    end

    it "detects Node source patterns" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      File.write(File.join(tmp_dir, "package.json"), "{}")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      patterns = wizard.send(:detect_source_patterns)
      expect(patterns).to include("src/**/*", "app/**/*")
    end

    it "detects Python source patterns" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      File.write(File.join(tmp_dir, "pyproject.toml"), "[tool]")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      patterns = wizard.send(:detect_source_patterns)
      expect(patterns).to eq(%w[src/**/*])
    end

    it "returns wildcard pattern for unknown projects" do
      FileUtils.rm_f(File.join(tmp_dir, "Gemfile"))
      wizard = described_class.new(tmp_dir, prompt: prompt)
      patterns = wizard.send(:detect_source_patterns)
      expect(patterns).to eq(%w[**/*])
    end
  end

  describe "command validation" do
    it "adds warning when command not found" do
      allow(Aidp::Util).to receive(:which).and_return(nil)
      wizard = described_class.new(tmp_dir, prompt: prompt)
      wizard.send(:validate_command, "nonexistent-command")
      expect(wizard.warnings).to include(/Command 'nonexistent-command' not found/)
    end

    it "does not warn for nil commands" do
      wizard = described_class.new(tmp_dir, prompt: prompt)
      wizard.send(:validate_command, nil)
      expect(wizard.warnings).to be_empty
    end

    it "does not warn for empty commands" do
      wizard = described_class.new(tmp_dir, prompt: prompt)
      wizard.send(:validate_command, "  ")
      expect(wizard.warnings).to be_empty
    end

    it "does not warn for echo commands" do
      wizard = described_class.new(tmp_dir, prompt: prompt)
      wizard.send(:validate_command, "echo 'test'")
      expect(wizard.warnings).to be_empty
    end

    it "does not warn when command is found" do
      allow(Aidp::Util).to receive(:which).and_return("/usr/bin/found")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      wizard.send(:validate_command, "found-command")
      expect(wizard.warnings).to be_empty
    end
  end

  describe "helper methods" do
    let(:wizard) { described_class.new(tmp_dir, prompt: prompt) }

    describe "#ask_with_default" do
      it "returns default when answer is nil" do
        allow(prompt).to receive(:ask).and_return(nil)
        result = wizard.send(:ask_with_default, "question", "default")
        expect(result).to eq("default")
      end

      it "returns default when answer is empty" do
        allow(prompt).to receive(:ask).and_return("")
        result = wizard.send(:ask_with_default, "question", "default")
        expect(result).to eq("default")
      end

      it "returns nil when answer is 'clear'" do
        allow(prompt).to receive(:ask).and_return("clear")
        result = wizard.send(:ask_with_default, "question", "default")
        expect(result).to be_nil
      end

      it "returns answer when provided" do
        allow(prompt).to receive(:ask).and_return("answer")
        result = wizard.send(:ask_with_default, "question", "default")
        expect(result).to eq("answer")
      end

      it "applies block transform to default" do
        allow(prompt).to receive(:ask).and_return("")
        result = wizard.send(:ask_with_default, "question", "5") { |v| v.to_i }
        expect(result).to eq(5)
      end

      it "applies block transform to answer" do
        allow(prompt).to receive(:ask).and_return("10")
        result = wizard.send(:ask_with_default, "question", "5") { |v| v.to_i }
        expect(result).to eq(10)
      end
    end

    describe "#ask_multiline" do
      it "returns default when no input provided" do
        allow(prompt).to receive(:ask).and_return("")
        result = wizard.send(:ask_multiline, "question", "default")
        expect(result).to eq("default")
      end

      it "returns nil when 'clear' entered" do
        allow(prompt).to receive(:ask).and_return("clear")
        result = wizard.send(:ask_multiline, "question", "default")
        expect(result).to be_nil
      end

      it "joins multiple lines" do
        allow(prompt).to receive(:ask).and_return("line1", "line2", "")
        result = wizard.send(:ask_multiline, "question", nil)
        expect(result).to eq("line1\nline2")
      end
    end

    describe "#ask_list" do
      it "returns existing when answer is empty" do
        allow(prompt).to receive(:ask).and_return("")
        result = wizard.send(:ask_list, "question", ["a", "b"])
        expect(result).to eq(["a", "b"])
      end

      it "returns empty array when 'clear' and allow_empty" do
        allow(prompt).to receive(:ask).and_return("clear")
        result = wizard.send(:ask_list, "question", ["a"], allow_empty: true)
        expect(result).to eq([])
      end

      it "parses comma-separated values" do
        allow(prompt).to receive(:ask).and_return("x, y, z")
        result = wizard.send(:ask_list, "question", [])
        expect(result).to eq(["x", "y", "z"])
      end

      it "strips whitespace and rejects empty items" do
        allow(prompt).to receive(:ask).and_return("a,  , b  ,c")
        result = wizard.send(:ask_list, "question", [])
        expect(result).to eq(["a", "b", "c"])
      end
    end

    describe "#deep_symbolize" do
      it "symbolizes hash keys" do
        input = {"a" => "b", "c" => {"d" => "e"}}
        result = wizard.send(:deep_symbolize, input)
        expect(result).to eq({a: "b", c: {d: "e"}})
      end

      it "handles arrays" do
        input = [{"a" => "b"}, {"c" => "d"}]
        result = wizard.send(:deep_symbolize, input)
        expect(result).to eq([{a: "b"}, {c: "d"}])
      end

      it "handles non-hash/array values" do
        expect(wizard.send(:deep_symbolize, "string")).to eq("string")
        expect(wizard.send(:deep_symbolize, 123)).to eq(123)
      end
    end

    describe "#deep_stringify" do
      it "stringifies hash keys" do
        input = {a: "b", c: {d: "e"}}
        result = wizard.send(:deep_stringify, input)
        expect(result).to eq({"a" => "b", "c" => {"d" => "e"}})
      end

      it "handles arrays" do
        input = [{a: "b"}, {c: "d"}]
        result = wizard.send(:deep_stringify, input)
        expect(result).to eq([{"a" => "b"}, {"c" => "d"}])
      end
    end

    describe "#display_value" do
      it "joins arrays" do
        expect(wizard.send(:display_value, ["a", "b"])).to eq("a, b")
      end

      it "returns non-arrays as-is" do
        expect(wizard.send(:display_value, "string")).to eq("string")
        expect(wizard.send(:display_value, 123)).to eq(123)
      end
    end
  end

  describe "error handling" do
    it "handles invalid YAML in existing config" do
      config_dir = Aidp::ConfigPaths.config_dir(tmp_dir)
      FileUtils.mkdir_p(config_dir)
      File.write(Aidp::ConfigPaths.config_file(tmp_dir), "invalid: yaml: [[[")

      wizard = described_class.new(tmp_dir, prompt: prompt)
      expect(wizard.warnings).not_to be_empty
      expect(wizard.existing_config).to eq({})
    end

    it "handles provider loading errors gracefully" do
      wizard = described_class.new(tmp_dir, prompt: prompt)
      # discover_available_providers should not raise even if some providers fail to load
      expect { wizard.send(:discover_available_providers) }.not_to raise_error
    end
  end

  describe "model family normalization" do
    context "when normalizing legacy label values" do
      it "normalizes legacy label values to canonical value" do
        test_prompt = TestPrompt.new(responses: {
          select_map: {
            "Preferred model family for cursor:" => "Anthropic Claude (balanced)"
          }
        })
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)

        # Inject an existing config with a legacy label stored (simulating previous bug)
        wizard.config[:providers] = {
          cursor: {type: "usage_based", model_family: "Anthropic Claude (balanced)"}
        }

        # Run normalization
        wizard.send(:normalize_existing_model_families!)

        providers = wizard.config[:providers]
        expect(providers[:cursor][:model_family]).to eq("claude")
      end

      it "falls back to auto for unknown entries" do
        wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
        wizard.config[:providers] = {
          foo: {type: "usage_based", model_family: "Totally Unknown"}
        }
        wizard.send(:normalize_existing_model_families!)
        providers = wizard.config[:providers]
        expect(providers[:foo][:model_family]).to eq("auto")
      end

      it "leaves canonical values unchanged" do
        wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
        wizard.config[:providers] = {
          cursor: {type: "usage_based", model_family: "claude"},
          mistral: {type: "usage_based", model_family: "mistral"}
        }
        wizard.send(:normalize_existing_model_families!)
        providers = wizard.config[:providers]
        expect(providers[:cursor][:model_family]).to eq("claude")
        expect(providers[:mistral][:model_family]).to eq("mistral")
      end
    end
  end

  describe "fallback provider configuration" do
    context "when editing fallback provider" do
      it "edits fallback provider configuration" do
        test_prompt = TestPrompt.new(responses: {
          select_map: {
            "Select your primary provider:" => "cursor",
            "Billing model for cursor:" => "subscription",
            "Preferred model family for cursor:" => "Auto (let provider decide)",
            "Select a provider to edit or add:" => ["github_copilot", :done],
            "Billing model for github_copilot:" => "usage_based",
            "Preferred model family for github_copilot:" => "Anthropic Claude (balanced)"
          },
          multi_select_map: {
            "Select fallback providers (used if primary fails):" => ["github_copilot"]
          },
          yes_map: {
            "Edit provider configuration details (billing/model family)?" => true,
            "Add another fallback provider?" => false
          }
        })
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        wizard.run

        providers = wizard.config[:providers]
        expect(providers[:cursor][:type]).to eq("subscription")
        expect(providers[:github_copilot][:type]).to eq("usage_based")
        expect(providers[:github_copilot][:model_family]).to eq("claude")
      end
    end

    context "when configuring fallback immediately" do
      it "configures selected fallback provider immediately without edit loop" do
        test_prompt = TestPrompt.new(responses: {
          select_map: {
            "Select your primary provider:" => "cursor",
            "Billing model for cursor:" => "subscription",
            "Preferred model family for cursor:" => "Auto (let provider decide)",
            "Billing model for github_copilot:" => "usage_based",
            "Preferred model family for github_copilot:" => "Anthropic Claude (balanced)"
          },
          multi_select_map: {
            "Select fallback providers (used if primary fails):" => ["github_copilot"]
          },
          yes_map: {
            "Add another fallback provider?" => false,
            "Edit provider configuration details (billing/model family)?" => false
          }
        })
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)

        # Inject provider discovery to include github_copilot and cursor if not auto-detected
        allow(wizard).to receive(:discover_available_providers).and_return({
          "Cursor AI" => "cursor",
          "GitHub Copilot CLI" => "github_copilot"
        })

        wizard.run

        providers = wizard.config[:providers]
        expect(providers[:cursor][:type]).to eq("subscription")
        expect(providers[:cursor][:model_family]).to eq("auto")
        expect(providers[:github_copilot][:type]).to eq("usage_based")
        expect(providers[:github_copilot][:model_family]).to eq("claude")
      end
    end

    context "when forcing reconfiguration of existing fallback" do
      it "reconfigures existing fallback provider with force" do
        # Prepare existing config file to simulate rerun
        existing_yaml = <<~YML
          providers:
            github_copilot:
              type: subscription
              model_family: Auto (let provider decide)
        YML
        config_path = File.join(tmp_dir, ".aidp.yml")
        File.write(config_path, existing_yaml)

        test_prompt = TestPrompt.new(responses: {
          select_map: {
            "Select your primary provider:" => "cursor",
            "Billing model for cursor:" => "usage_based",
            "Preferred model family for cursor:" => "Anthropic Claude (balanced)",
            "Billing model for github_copilot:" => "usage_based",
            "Preferred model family for github_copilot:" => "OpenAI o-series (reasoning models)"
          },
          multi_select_map: {
            "Select fallback providers (used if primary fails):" => ["github_copilot"]
          },
          yes_map: {
            "Add another fallback provider?" => false,
            "Edit provider configuration details (billing/model family)?" => false
          }
        })
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        allow(wizard).to receive(:discover_available_providers).and_return({
          "Cursor AI" => "cursor",
          "GitHub Copilot CLI" => "github_copilot"
        })

        wizard.run

        providers = wizard.config[:providers]
        expect(providers[:github_copilot][:type]).to eq("usage_based")
        expect(providers[:github_copilot][:model_family]).to eq("openai_o")
      end
    end

    context "when adding fallback during interactive flow" do
      it "includes newly added fallback in edit menu" do
        test_prompt = TestPrompt.new(responses: {
          select_map: {
            "Select your primary provider:" => "cursor",
            "Billing model for cursor:" => "subscription",
            "Preferred model family for cursor:" => "Auto (let provider decide)",
            "Select additional fallback provider:" => ["anthropic", :done],
            "Billing model for anthropic:" => "usage_based",
            "Preferred model family for anthropic:" => "Auto (let provider decide)",
            "Select a provider to edit or add:" => ["anthropic", :done]
          },
          yes_map: {
            "Add another fallback provider?" => true,
            "Edit provider configuration details (billing/model family)?" => true
          }
        })

        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        allow(wizard).to receive(:discover_available_providers).and_return({
          "Cursor AI" => "cursor",
          "Anthropic Claude CLI" => "anthropic"
        })

        wizard.run

        # Find the edit selection log
        edit_selection = test_prompt.selections.find { |sel| sel[:title] == "Select a provider to edit or add:" }
        expect(edit_selection).not_to be_nil
        labels = edit_selection[:items].map { |c| c[:value] }
        expect(labels).to include("anthropic")
      end

      it "prompts for billing and model family when GitHub Copilot selected as initial fallback" do
        test_prompt = TestPrompt.new(responses: {
          select_map: {
            "Select your primary provider:" => "cursor",
            "Billing model for cursor:" => "subscription",
            "Preferred model family for cursor:" => "Auto (let provider decide)",
            "Billing model for github_copilot:" => "usage_based",
            "Preferred model family for github_copilot:" => "Anthropic Claude (balanced)"
          },
          multi_select_map: {
            "Select fallback providers (used if primary fails):" => ["github_copilot"]
          },
          yes_map: {
            "Add another fallback provider?" => false,
            "Edit provider configuration details (billing/model family)?" => false
          }
        })

        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        allow(wizard).to receive(:discover_available_providers).and_return({
          "Cursor AI" => "cursor",
          "GitHub Copilot CLI" => "github_copilot"
        })

        wizard.send(:configure_providers)

        # Verify that billing and model family prompts were asked
        billing_prompt = test_prompt.selections.find { |s| s[:title] == "Billing model for github_copilot:" }
        expect(billing_prompt).not_to be_nil, "Expected billing prompt for github_copilot but it was not called"

        model_family_prompt = test_prompt.selections.find { |s| s[:title] == "Preferred model family for github_copilot:" }
        expect(model_family_prompt).not_to be_nil, "Expected model family prompt for github_copilot but it was not called"

        # Verify the configuration was saved
        providers = wizard.config[:providers]
        expect(providers[:github_copilot][:type]).to eq("usage_based")
        expect(providers[:github_copilot][:model_family]).to eq("claude")
      end

      it "prompts for billing and model family for BOTH fallback providers when two are selected" do
        test_prompt = TestPrompt.new(responses: {
          select_map: {
            "Select your primary provider:" => "cursor",
            "Billing model for cursor:" => "subscription",
            "Preferred model family for cursor:" => "Auto (let provider decide)",
            "Billing model for github_copilot:" => "usage_based",
            "Preferred model family for github_copilot:" => "Anthropic Claude (balanced)",
            "Billing model for anthropic:" => "subscription",
            "Preferred model family for anthropic:" => "Auto (let provider decide)"
          },
          multi_select_map: {
            "Select fallback providers (used if primary fails):" => ["github_copilot", "anthropic"]
          },
          yes_map: {
            "Add another fallback provider?" => false,
            "Edit provider configuration details (billing/model family)?" => false
          }
        })

        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        allow(wizard).to receive(:discover_available_providers).and_return({
          "Cursor AI" => "cursor",
          "GitHub Copilot CLI" => "github_copilot",
          "Anthropic Claude CLI" => "anthropic"
        })

        wizard.send(:configure_providers)

        # Verify that billing and model family prompts were asked for FIRST fallback
        billing_prompt_ghc = test_prompt.selections.find { |s| s[:title] == "Billing model for github_copilot:" }
        expect(billing_prompt_ghc).not_to be_nil, "Expected billing prompt for github_copilot (first fallback) but it was not called"

        model_family_prompt_ghc = test_prompt.selections.find { |s| s[:title] == "Preferred model family for github_copilot:" }
        expect(model_family_prompt_ghc).not_to be_nil, "Expected model family prompt for github_copilot (first fallback) but it was not called"

        # Verify that billing and model family prompts were asked for SECOND fallback
        billing_prompt_anthropic = test_prompt.selections.find { |s| s[:title] == "Billing model for anthropic:" }
        expect(billing_prompt_anthropic).not_to be_nil, "Expected billing prompt for anthropic (second fallback) but it was not called"

        model_family_prompt_anthropic = test_prompt.selections.find { |s| s[:title] == "Preferred model family for anthropic:" }
        expect(model_family_prompt_anthropic).not_to be_nil, "Expected model family prompt for anthropic (second fallback) but it was not called"

        # Verify both configurations were saved
        providers = wizard.config[:providers]
        expect(providers[:github_copilot][:type]).to eq("usage_based")
        expect(providers[:github_copilot][:model_family]).to eq("claude")
        expect(providers[:anthropic][:type]).to eq("subscription")
        expect(providers[:anthropic][:model_family]).to eq("auto")
      end

      it "recovers when multi_select returns empty by offering single-select fallback" do
        test_prompt = TestPrompt.new(responses: {
          select_map: {
            "Select your primary provider:" => "cursor",
            "Select a fallback provider:" => "github_copilot",
            "Billing model for cursor:" => "usage_based",
            "Preferred model family for cursor:" => "Anthropic Claude (balanced)",
            "Billing model for github_copilot:" => "subscription",
            "Preferred model family for github_copilot:" => "Auto (let provider decide)"
          },
          # Simulate multi_select unexpectedly returning empty
          multi_select_map: {
            "Select fallback providers (used if primary fails):" => []
          },
          yes_map: {
            "No fallback selected. Add one?" => true,
            "Add another fallback provider?" => false,
            "Edit provider configuration details (billing/model family)?" => false
          }
        })

        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        allow(wizard).to receive(:discover_available_providers).and_return({
          "Cursor AI" => "cursor",
          "GitHub Copilot CLI" => "github_copilot"
        })

        wizard.send(:configure_providers)

        providers = wizard.config[:providers]
        expect(providers[:github_copilot][:type]).to eq("subscription")
        expect(providers[:github_copilot][:model_family]).to eq("auto")
      end
    end

    context "when removing a provider" do
      it "removes provider from fallback list when user confirms removal" do
        test_prompt = TestPrompt.new(responses: {
          select_map: {
            "Select your primary provider:" => "cursor",
            "Billing model for cursor:" => "subscription",
            "Preferred model family for cursor:" => "Auto (let provider decide)",
            "Billing model for anthropic:" => "usage_based",
            "Preferred model family for anthropic:" => "Anthropic Claude (balanced)",
            "Select a provider to edit or add:" => ["anthropic", :done],
            "What would you like to do with 'Anthropic Claude CLI'?" => :remove
          },
          multi_select_map: {
            "Select fallback providers (used if primary fails):" => ["anthropic"]
          },
          yes_map: {
            "Edit provider configuration details (billing/model family)?" => true,
            "Add another fallback provider?" => false,
            "Remove 'Anthropic Claude CLI' from fallback providers?" => true
          }
        })

        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        allow(wizard).to receive(:discover_available_providers).and_return({
          "Cursor AI" => "cursor",
          "Anthropic Claude CLI" => "anthropic"
        })

        wizard.run

        harness_config = wizard.config[:harness]
        fallback_providers = harness_config[:fallback_providers]
        expect(fallback_providers).not_to include("anthropic")
      end

      it "removes provider from fallback list when deleted from multi-fallback configuration" do
        test_prompt = TestPrompt.new(responses: {
          select_map: {
            "Select your primary provider:" => "cursor",
            "Billing model for cursor:" => "subscription",
            "Preferred model family for cursor:" => "Auto (let provider decide)",
            "Billing model for anthropic:" => "usage_based",
            "Preferred model family for anthropic:" => "Anthropic Claude (balanced)",
            "Billing model for github_copilot:" => "subscription",
            "Preferred model family for github_copilot:" => "Auto (let provider decide)",
            "Select a provider to edit or add:" => ["anthropic", :done],
            "What would you like to do with 'Anthropic Claude CLI'?" => :remove
          },
          multi_select_map: {
            "Select fallback providers (used if primary fails):" => ["anthropic", "github_copilot"]
          },
          yes_map: {
            "Edit provider configuration details (billing/model family)?" => true,
            "Add another fallback provider?" => false,
            "Remove 'Anthropic Claude CLI' from fallback providers?" => true
          }
        })

        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        allow(wizard).to receive(:discover_available_providers).and_return({
          "Cursor AI" => "cursor",
          "Anthropic Claude CLI" => "anthropic",
          "GitHub Copilot CLI" => "github_copilot"
        })

        wizard.run

        harness_config = wizard.config[:harness]
        fallback_providers = harness_config[:fallback_providers]
        expect(fallback_providers).not_to include("anthropic")
        expect(fallback_providers).to include("github_copilot")
      end

      it "keeps provider when user declines removal" do
        test_prompt = TestPrompt.new(responses: {
          select_map: {
            "Select your primary provider:" => "cursor",
            "Billing model for cursor:" => "subscription",
            "Preferred model family for cursor:" => "Auto (let provider decide)",
            "Billing model for anthropic:" => "usage_based",
            "Preferred model family for anthropic:" => "Anthropic Claude (balanced)",
            "Select a provider to edit or add:" => ["anthropic", :done],
            "What would you like to do with 'Anthropic Claude CLI'?" => :remove
          },
          multi_select_map: {
            "Select fallback providers (used if primary fails):" => ["anthropic"]
          },
          yes_map: {
            "Edit provider configuration details (billing/model family)?" => true,
            "Add another fallback provider?" => false,
            "Remove 'Anthropic Claude CLI' from fallback providers?" => false
          }
        })

        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        allow(wizard).to receive(:discover_available_providers).and_return({
          "Cursor AI" => "cursor",
          "Anthropic Claude CLI" => "anthropic"
        })

        wizard.run

        harness_config = wizard.config[:harness]
        fallback_providers = harness_config[:fallback_providers]
        expect(fallback_providers).to include("anthropic")
      end
    end

    context "with no fallbacks selected" do
      it "completes wizard successfully without fallback providers" do
        test_prompt = TestPrompt.new(responses: {
          select_map: {
            "Select your primary provider:" => "cursor",
            "Billing model for cursor:" => "subscription",
            "Preferred model family for cursor:" => "Auto (let provider decide)"
          },
          multi_select_map: {
            "Select fallback providers (used if primary fails):" => []
          },
          yes_map: {
            "No fallback selected. Add one?" => false,
            "Edit provider configuration details (billing/model family)?" => false
          }
        })

        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        allow(wizard).to receive(:discover_available_providers).and_return({
          "Cursor AI" => "cursor"
        })

        wizard.run

        harness_config = wizard.config[:harness]
        expect(harness_config[:fallback_providers]).to eq([])
      end

      it "does not prompt for additional fallback when user declines initial offer" do
        test_prompt = TestPrompt.new(responses: {
          select_map: {
            "Select your primary provider:" => "cursor",
            "Billing model for cursor:" => "subscription",
            "Preferred model family for cursor:" => "Auto (let provider decide)"
          },
          multi_select_map: {
            "Select fallback providers (used if primary fails):" => []
          },
          yes_map: {
            "No fallback selected. Add one?" => false,
            "Edit provider configuration details (billing/model family)?" => false,
            "Add another fallback provider?" => false
          }
        })

        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        allow(wizard).to receive(:discover_available_providers).and_return({
          "Cursor AI" => "cursor",
          "Anthropic Claude CLI" => "anthropic"
        })

        wizard.run

        add_another_calls = test_prompt.selections.count { |s| s[:title] == "Add another fallback provider?" }
        expect(add_another_calls).to eq(0)
      end
    end

    context "when editing is declined" do
      it "skips provider editing when user declines" do
        test_prompt = TestPrompt.new(responses: {
          select_map: {
            "Select your primary provider:" => "cursor",
            "Billing model for cursor:" => "subscription",
            "Preferred model family for cursor:" => "Auto (let provider decide)",
            "Billing model for anthropic:" => "usage_based",
            "Preferred model family for anthropic:" => "Anthropic Claude (balanced)"
          },
          multi_select_map: {
            "Select fallback providers (used if primary fails):" => ["anthropic"]
          },
          yes_map: {
            "Edit provider configuration details (billing/model family)?" => false,
            "Add another fallback provider?" => false
          }
        })

        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        allow(wizard).to receive(:discover_available_providers).and_return({
          "Cursor AI" => "cursor",
          "Anthropic Claude CLI" => "anthropic"
        })

        wizard.run

        # No edit menu should have been shown
        edit_calls = test_prompt.selections.count { |s| s[:title] == "Select a provider to edit or add:" }
        expect(edit_calls).to eq(0)
      end
    end

    context "with case-insensitive model family normalization" do
      it "normalizes uppercase model family values" do
        wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
        wizard.config[:providers] = {
          cursor: {type: "usage_based", model_family: "CLAUDE"}
        }
        wizard.send(:normalize_existing_model_families!)
        providers = wizard.config[:providers]
        expect(providers[:cursor][:model_family]).to eq("claude")
      end

      it "normalizes mixed-case model family values" do
        wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
        wizard.config[:providers] = {
          cursor: {type: "usage_based", model_family: "Gemini"},
          anthropic: {type: "usage_based", model_family: "LLaMA"}
        }
        wizard.send(:normalize_existing_model_families!)
        providers = wizard.config[:providers]
        expect(providers[:cursor][:model_family]).to eq("gemini")
        expect(providers[:anthropic][:model_family]).to eq("llama")
      end

      it "normalizes model family labels case-insensitively" do
        wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
        wizard.config[:providers] = {
          cursor: {type: "usage_based", model_family: "anthropic claude (balanced)"}
        }
        wizard.send(:normalize_existing_model_families!)
        providers = wizard.config[:providers]
        expect(providers[:cursor][:model_family]).to eq("claude")
      end
    end
  end

  describe "ProviderRegistry integration" do
    it "validates new model families are available" do
      expect(Aidp::Setup::ProviderRegistry.valid_model_family?("gemini")).to be true
      expect(Aidp::Setup::ProviderRegistry.valid_model_family?("llama")).to be true
      expect(Aidp::Setup::ProviderRegistry.valid_model_family?("deepseek")).to be true
    end

    it "provides labels for new model families" do
      expect(Aidp::Setup::ProviderRegistry.model_family_label("gemini")).to eq("Google Gemini (multimodal)")
      expect(Aidp::Setup::ProviderRegistry.model_family_label("llama")).to eq("Meta Llama (open-source)")
      expect(Aidp::Setup::ProviderRegistry.model_family_label("deepseek")).to eq("DeepSeek (efficient reasoning)")
    end

    it "includes new model families in choices" do
      choices = Aidp::Setup::ProviderRegistry.model_family_choices
      values = choices.map(&:last)
      expect(values).to include("gemini", "llama", "deepseek")
    end
  end

  describe "background model discovery" do
    describe "#finalize_background_discovery" do
      let(:wizard) { described_class.new(tmp_dir, prompt: prompt, dry_run: true) }

      it "saves configure: false when user declines NFR configuration" do
        test_prompt = TestPrompt.new(responses: {
          yes_map: {"Configure NFRs?" => false}
        })
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        wizard.send(:configure_nfrs)

        config = wizard.config
        expect(config.dig(:nfrs, :configure)).to be false
      end

      it "saves configure: true when user accepts NFR configuration" do
        test_prompt = TestPrompt.new(responses: {
          yes?: false,  # Default no for sub-questions
          yes_map: {"Configure NFRs?" => true}
        })
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        wizard.send(:configure_nfrs)

        config = wizard.config
        expect(config.dig(:nfrs, :configure)).to be true
      end

      it "uses existing configure value as default when present" do
        # Create config with configure: false
        config_dir = Aidp::ConfigPaths.config_dir(tmp_dir)
        FileUtils.mkdir_p(config_dir)
        File.write(Aidp::ConfigPaths.config_file(tmp_dir), <<~YAML)
          schema_version: 1
          nfrs:
            configure: false
        YAML

        test_prompt = TestPrompt.new(responses: {yes?: false})
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)

        # Expect prompt.yes? to be called with default: false
        expect(test_prompt).to receive(:yes?).with("Configure NFRs?", default: false).and_return(false)
        wizard.send(:configure_nfrs)
      end

      it "defaults to true when no existing configure value" do
        test_prompt = TestPrompt.new(responses: {yes?: false})
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)

        # Expect prompt.yes? to be called with default: true
        expect(test_prompt).to receive(:yes?).with("Configure NFRs?", default: true).and_return(false)
        wizard.send(:configure_nfrs)
      end
    end

    describe "#configure_devcontainer" do
      let(:wizard) { described_class.new(tmp_dir, prompt: prompt, dry_run: true) }

      it "saves manage: false when user declines devcontainer management" do
        test_prompt = TestPrompt.new(responses: {
          yes_map: {"Would you like AIDP to manage your devcontainer configuration?" => false}
        })
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        wizard.send(:configure_devcontainer)

        config = wizard.config
        expect(config.dig(:devcontainer, :manage)).to be false
      end

      it "saves manage: true when user accepts devcontainer management" do
        test_prompt = TestPrompt.new(responses: {
          yes?: false,  # Default no for sub-questions
          yes_map: {"Would you like AIDP to manage your devcontainer configuration?" => true}
        })
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        wizard.send(:configure_devcontainer)

        config = wizard.config
        expect(config.dig(:devcontainer, :manage)).to be true
      end

      it "uses existing manage value as default when present" do
        # Create config with manage: false
        config_dir = Aidp::ConfigPaths.config_dir(tmp_dir)
        FileUtils.mkdir_p(config_dir)
        File.write(Aidp::ConfigPaths.config_file(tmp_dir), <<~YAML)
          schema_version: 1
          devcontainer:
            manage: false
        YAML

        test_prompt = TestPrompt.new(responses: {yes?: false})
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)

        # Expect prompt.yes? to be called with default: false
        expect(test_prompt).to receive(:yes?).with(
          "Would you like AIDP to manage your devcontainer configuration?",
          default: false
        ).and_return(false)
        wizard.send(:configure_devcontainer)
      end

      it "defaults based on existing devcontainer when no config value" do
        # Create a .devcontainer directory to simulate existing devcontainer
        devcontainer_dir = File.join(tmp_dir, ".devcontainer")
        FileUtils.mkdir_p(devcontainer_dir)
        File.write(File.join(devcontainer_dir, "devcontainer.json"), "{}")

        test_prompt = TestPrompt.new(responses: {yes?: false})
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)

        # Should default to true because existing devcontainer.json exists
        expect(test_prompt).to receive(:yes?).with(
          "Would you like AIDP to manage your devcontainer configuration?",
          default: true
        ).and_return(false)
        wizard.send(:configure_devcontainer)
      end

      it "defaults to false when no existing config or devcontainer" do
        test_prompt = TestPrompt.new(responses: {yes?: false})
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)

        # Should default to false when neither config nor devcontainer exists
        expect(test_prompt).to receive(:yes?).with(
          "Would you like AIDP to manage your devcontainer configuration?",
          default: false
        ).and_return(false)
        wizard.send(:configure_devcontainer)
      end
    end
  end

  describe "#configure_watch_label_creation" do
    let(:wizard) { described_class.new(tmp_dir, prompt: prompt, dry_run: true) }

    before do
      # Set up watch labels configuration
      wizard.send(:set, [:watch, :labels], {
        plan_trigger: "aidp-plan",
        needs_input: "aidp-needs-input",
        ready_to_build: "aidp-ready",
        build_trigger: "aidp-build",
        review_trigger: "aidp-review",
        ci_fix_trigger: "aidp-fix-ci",
        change_request_trigger: "aidp-request-changes"
      })
    end

    context "when user declines label creation" do
      it "exits early without checking gh CLI" do
        test_prompt = TestPrompt.new(responses: {yes?: false})
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)

        expect(wizard).not_to receive(:gh_cli_available?)
        wizard.send(:configure_watch_label_creation)
      end
    end

    context "when gh CLI is not available" do
      it "warns and exits gracefully" do
        test_prompt = TestPrompt.new(responses: {yes?: true})
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)

        allow(wizard).to receive(:gh_cli_available?).and_return(false)
        expect(wizard).not_to receive(:extract_repo_info)

        wizard.send(:configure_watch_label_creation)
      end
    end

    context "when repository info cannot be extracted" do
      it "warns and exits gracefully" do
        test_prompt = TestPrompt.new(responses: {yes?: true})
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)

        allow(wizard).to receive(:gh_cli_available?).and_return(true)
        allow(wizard).to receive(:extract_repo_info).and_return(nil)
        expect(wizard).not_to receive(:fetch_existing_labels)

        wizard.send(:configure_watch_label_creation)
      end
    end

    context "when fetching existing labels fails" do
      it "warns and exits gracefully" do
        test_prompt = TestPrompt.new(responses: {yes?: true})
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        wizard.send(:set, [:watch, :labels], {plan_trigger: "aidp-plan"})

        allow(wizard).to receive(:gh_cli_available?).and_return(true)
        allow(wizard).to receive(:extract_repo_info).and_return(["owner", "repo"])
        allow(wizard).to receive(:fetch_existing_labels).and_return(nil)

        wizard.send(:configure_watch_label_creation)
      end
    end

    context "when all labels already exist" do
      it "displays success message and exits" do
        test_prompt = TestPrompt.new(responses: {yes?: true})
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        wizard.send(:set, [:watch, :labels], {plan_trigger: "aidp-plan"})

        allow(wizard).to receive(:gh_cli_available?).and_return(true)
        allow(wizard).to receive(:extract_repo_info).and_return(["owner", "repo"])
        # Include aidp-in-progress as existing since it's always added
        allow(wizard).to receive(:fetch_existing_labels).and_return(["aidp-plan", "aidp-in-progress"])
        expect(wizard).not_to receive(:create_labels)

        wizard.send(:configure_watch_label_creation)
      end
    end

    context "when labels need to be created" do
      it "prompts for confirmation and creates labels" do
        test_prompt = TestPrompt.new(responses: {
          yes_map: {
            "Auto-create GitHub labels if missing?" => true,
            "Create these labels?" => true
          }
        })
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        wizard.send(:set, [:watch, :labels], {
          plan_trigger: "aidp-plan",
          build_trigger: "aidp-build"
        })

        allow(wizard).to receive(:gh_cli_available?).and_return(true)
        allow(wizard).to receive(:extract_repo_info).and_return(["owner", "repo"])
        allow(wizard).to receive(:fetch_existing_labels).and_return(["aidp-plan"])

        expect(wizard).to receive(:create_labels) do |owner, repo, labels|
          expect(owner).to eq("owner")
          expect(repo).to eq("repo")
          expect(labels.size).to eq(2)  # aidp-build + aidp-in-progress
          expect(labels.map { |l| l[:name] }).to include("aidp-build", "aidp-in-progress")
        end

        wizard.send(:configure_watch_label_creation)
      end
    end

    context "when user declines label creation confirmation" do
      it "exits without creating labels" do
        test_prompt = TestPrompt.new(responses: {
          yes_map: {
            "Auto-create GitHub labels if missing?" => true,
            "Create these labels?" => false
          }
        })
        wizard = described_class.new(tmp_dir, prompt: test_prompt, dry_run: true)
        wizard.send(:set, [:watch, :labels], {plan_trigger: "aidp-plan"})

        allow(wizard).to receive(:gh_cli_available?).and_return(true)
        allow(wizard).to receive(:extract_repo_info).and_return(["owner", "repo"])
        allow(wizard).to receive(:fetch_existing_labels).and_return([])

        expect(wizard).not_to receive(:create_labels)
        wizard.send(:configure_watch_label_creation)
      end
    end
  end

  describe "#gh_cli_available?" do
    let(:wizard) { described_class.new(tmp_dir, prompt: prompt, dry_run: true) }

    it "returns true when gh is available" do
      allow(Open3).to receive(:capture3).with("gh", "--version").and_return(
        ["gh version 2.0.0", "", double(success?: true)]
      )
      expect(wizard.send(:gh_cli_available?)).to be true
    end

    it "returns false when gh is not found" do
      allow(Open3).to receive(:capture3).with("gh", "--version").and_raise(Errno::ENOENT)
      expect(wizard.send(:gh_cli_available?)).to be false
    end

    it "returns false when gh command fails" do
      allow(Open3).to receive(:capture3).with("gh", "--version").and_return(
        ["", "error", double(success?: false)]
      )
      expect(wizard.send(:gh_cli_available?)).to be false
    end
  end

  describe "#extract_repo_info" do
    let(:wizard) { described_class.new(tmp_dir, prompt: prompt, dry_run: true) }

    it "extracts owner and repo from HTTPS URL" do
      allow(Open3).to receive(:capture3).with("git", "remote", "get-url", "origin").and_return(
        ["https://github.com/viamin/aidp.git\n", "", double(success?: true)]
      )
      expect(wizard.send(:extract_repo_info)).to eq(["viamin", "aidp"])
    end

    it "extracts owner and repo from SSH URL" do
      allow(Open3).to receive(:capture3).with("git", "remote", "get-url", "origin").and_return(
        ["git@github.com:viamin/aidp.git\n", "", double(success?: true)]
      )
      expect(wizard.send(:extract_repo_info)).to eq(["viamin", "aidp"])
    end

    it "extracts owner and repo from URL without .git extension" do
      allow(Open3).to receive(:capture3).with("git", "remote", "get-url", "origin").and_return(
        ["https://github.com/viamin/aidp\n", "", double(success?: true)]
      )
      expect(wizard.send(:extract_repo_info)).to eq(["viamin", "aidp"])
    end

    it "returns nil when git remote fails" do
      allow(Open3).to receive(:capture3).with("git", "remote", "get-url", "origin").and_return(
        ["", "fatal: No such remote 'origin'", double(success?: false)]
      )
      expect(wizard.send(:extract_repo_info)).to be_nil
    end

    it "returns nil when URL is not a GitHub URL" do
      allow(Open3).to receive(:capture3).with("git", "remote", "get-url", "origin").and_return(
        ["https://gitlab.com/owner/repo.git\n", "", double(success?: true)]
      )
      expect(wizard.send(:extract_repo_info)).to be_nil
    end
  end

  describe "#fetch_existing_labels" do
    let(:wizard) { described_class.new(tmp_dir, prompt: prompt, dry_run: true) }

    it "fetches and parses label names" do
      allow(Open3).to receive(:capture3).with(
        "gh", "label", "list", "-R", "owner/repo", "--json", "name", "--jq", ".[].name"
      ).and_return(
        ["bug\nenhancement\naidp-plan\n", "", double(success?: true)]
      )
      expect(wizard.send(:fetch_existing_labels, "owner", "repo")).to eq(["bug", "enhancement", "aidp-plan"])
    end

    it "returns nil when gh command fails" do
      allow(Open3).to receive(:capture3).with(
        "gh", "label", "list", "-R", "owner/repo", "--json", "name", "--jq", ".[].name"
      ).and_return(
        ["", "error: authentication required", double(success?: false)]
      )
      expect(wizard.send(:fetch_existing_labels, "owner", "repo")).to be_nil
    end

    it "handles empty label list" do
      allow(Open3).to receive(:capture3).with(
        "gh", "label", "list", "-R", "owner/repo", "--json", "name", "--jq", ".[].name"
      ).and_return(
        ["", "", double(success?: true)]
      )
      expect(wizard.send(:fetch_existing_labels, "owner", "repo")).to eq([])
    end
  end

  describe "#collect_required_labels" do
    let(:wizard) { described_class.new(tmp_dir, prompt: prompt, dry_run: true) }

    it "collects labels with default colors" do
      labels_config = {
        plan_trigger: "aidp-plan",
        build_trigger: "aidp-build"
      }
      result = wizard.send(:collect_required_labels, labels_config)

      expect(result.size).to eq(3)  # Includes aidp-in-progress
      expect(result[0][:name]).to eq("aidp-plan")
      expect(result[0][:color]).to eq("0E8A16")
      expect(result[1][:name]).to eq("aidp-build")
      expect(result[1][:color]).to eq("5319E7")
      expect(result[2][:name]).to eq("aidp-in-progress")
      expect(result[2][:color]).to eq("1D76DB")
      expect(result[2][:internal]).to eq(true)
    end

    it "skips nil or empty label names" do
      labels_config = {
        plan_trigger: "aidp-plan",
        build_trigger: nil,
        review_trigger: ""
      }
      result = wizard.send(:collect_required_labels, labels_config)

      expect(result.size).to eq(2)  # aidp-plan + aidp-in-progress
      expect(result[0][:name]).to eq("aidp-plan")
      expect(result[1][:name]).to eq("aidp-in-progress")
    end

    it "uses fallback color for unknown label types" do
      labels_config = {
        custom_label: "custom"
      }
      result = wizard.send(:collect_required_labels, labels_config)

      expect(result.size).to eq(2)  # custom + aidp-in-progress
      expect(result[0][:name]).to eq("custom")
      expect(result[0][:color]).to eq("EDEDED")
      expect(result[1][:name]).to eq("aidp-in-progress")
    end
  end

  describe "#create_labels" do
    let(:wizard) { described_class.new(tmp_dir, prompt: prompt, dry_run: true) }

    it "creates labels successfully" do
      labels = [
        {name: "aidp-plan", color: "0E8A16"},
        {name: "aidp-build", color: "5319E7"}
      ]

      allow(Open3).to receive(:capture3).and_return(
        ["", "", double(success?: true)]
      )

      wizard.send(:create_labels, "owner", "repo", labels)

      expect(Open3).to have_received(:capture3).with(
        "gh", "label", "create", "aidp-plan", "--color", "0E8A16", "-R", "owner/repo"
      )
      expect(Open3).to have_received(:capture3).with(
        "gh", "label", "create", "aidp-build", "--color", "5319E7", "-R", "owner/repo"
      )
    end

    it "handles failures gracefully" do
      labels = [{name: "aidp-plan", color: "0E8A16"}]

      allow(Open3).to receive(:capture3).and_return(
        ["", "error: label already exists", double(success?: false)]
      )

      # Should not raise error
      expect { wizard.send(:create_labels, "owner", "repo", labels) }.not_to raise_error
    end

    it "continues creating labels after individual failures" do
      labels = [
        {name: "label1", color: "000000"},
        {name: "label2", color: "111111"}
      ]

      # First label fails, second succeeds
      call_count = 0
      allow(Open3).to receive(:capture3) do
        call_count += 1
        if call_count == 1
          ["", "error", double(success?: false)]
        else
          ["", "", double(success?: true)]
        end
      end

      wizard.send(:create_labels, "owner", "repo", labels)

      expect(Open3).to have_received(:capture3).twice
    end
  end
end
