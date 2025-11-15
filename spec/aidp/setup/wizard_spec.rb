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
      threads = wizard.instance_variable_get(:@discovery_threads)
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
      expect(wizard.instance_variable_get(:@warnings)).to include(/Command 'nonexistent-command' not found/)
    end

    it "does not warn for nil commands" do
      wizard = described_class.new(tmp_dir, prompt: prompt)
      wizard.send(:validate_command, nil)
      expect(wizard.instance_variable_get(:@warnings)).to be_empty
    end

    it "does not warn for empty commands" do
      wizard = described_class.new(tmp_dir, prompt: prompt)
      wizard.send(:validate_command, "  ")
      expect(wizard.instance_variable_get(:@warnings)).to be_empty
    end

    it "does not warn for echo commands" do
      wizard = described_class.new(tmp_dir, prompt: prompt)
      wizard.send(:validate_command, "echo 'test'")
      expect(wizard.instance_variable_get(:@warnings)).to be_empty
    end

    it "does not warn when command is found" do
      allow(Aidp::Util).to receive(:which).and_return("/usr/bin/found")
      wizard = described_class.new(tmp_dir, prompt: prompt)
      wizard.send(:validate_command, "found-command")
      expect(wizard.instance_variable_get(:@warnings)).to be_empty
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
      expect(wizard.instance_variable_get(:@warnings)).not_to be_empty
      expect(wizard.instance_variable_get(:@existing_config)).to eq({})
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
        wizard.instance_variable_get(:@config)[:providers] = {
          cursor: {type: "usage_based", model_family: "Anthropic Claude (balanced)"}
        }

        # Run normalization
        wizard.send(:normalize_existing_model_families!)

        providers = wizard.instance_variable_get(:@config)[:providers]
        expect(providers[:cursor][:model_family]).to eq("claude")
      end

      it "falls back to auto for unknown entries" do
        wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
        wizard.instance_variable_get(:@config)[:providers] = {
          foo: {type: "usage_based", model_family: "Totally Unknown"}
        }
        wizard.send(:normalize_existing_model_families!)
        providers = wizard.instance_variable_get(:@config)[:providers]
        expect(providers[:foo][:model_family]).to eq("auto")
      end

      it "leaves canonical values unchanged" do
        wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
        wizard.instance_variable_get(:@config)[:providers] = {
          cursor: {type: "usage_based", model_family: "claude"},
          mistral: {type: "usage_based", model_family: "mistral"}
        }
        wizard.send(:normalize_existing_model_families!)
        providers = wizard.instance_variable_get(:@config)[:providers]
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

        providers = wizard.instance_variable_get(:@config)[:providers]
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

        providers = wizard.instance_variable_get(:@config)[:providers]
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

        providers = wizard.instance_variable_get(:@config)[:providers]
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
        providers = wizard.instance_variable_get(:@config)[:providers]
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
        providers = wizard.instance_variable_get(:@config)[:providers]
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

        providers = wizard.instance_variable_get(:@config)[:providers]
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

        harness_config = wizard.instance_variable_get(:@config)[:harness]
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

        harness_config = wizard.instance_variable_get(:@config)[:harness]
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

        harness_config = wizard.instance_variable_get(:@config)[:harness]
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

        harness_config = wizard.instance_variable_get(:@config)[:harness]
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
        wizard.instance_variable_get(:@config)[:providers] = {
          cursor: {type: "usage_based", model_family: "CLAUDE"}
        }
        wizard.send(:normalize_existing_model_families!)
        providers = wizard.instance_variable_get(:@config)[:providers]
        expect(providers[:cursor][:model_family]).to eq("claude")
      end

      it "normalizes mixed-case model family values" do
        wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
        wizard.instance_variable_get(:@config)[:providers] = {
          cursor: {type: "usage_based", model_family: "Gemini"},
          anthropic: {type: "usage_based", model_family: "LLaMA"}
        }
        wizard.send(:normalize_existing_model_families!)
        providers = wizard.instance_variable_get(:@config)[:providers]
        expect(providers[:cursor][:model_family]).to eq("gemini")
        expect(providers[:anthropic][:model_family]).to eq("llama")
      end

      it "normalizes model family labels case-insensitively" do
        wizard = described_class.new(tmp_dir, prompt: prompt, dry_run: true)
        wizard.instance_variable_get(:@config)[:providers] = {
          cursor: {type: "usage_based", model_family: "anthropic claude (balanced)"}
        }
        wizard.send(:normalize_existing_model_families!)
        providers = wizard.instance_variable_get(:@config)[:providers]
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
    describe "#trigger_background_discovery" do
      let(:wizard) { described_class.new(tmp_dir, prompt: prompt, dry_run: true) }

      before do
        # Mock provider availability check
        allow(wizard).to receive(:provider_available_for_discovery?).and_return(true)
        allow(wizard).to receive(:discover_and_cache_models)
      end

      it "starts background discovery thread for provider" do
        wizard.send(:trigger_background_discovery, "anthropic")

        # Verify thread was created
        threads = wizard.instance_variable_get(:@discovery_threads)
        expect(threads).to be_a(Array)
        expect(threads.size).to eq(1)
        expect(threads.first[:provider]).to eq("anthropic")
        expect(threads.first[:thread]).to be_a(Thread)

        # Clean up thread
        threads.first[:thread].kill if threads.first[:thread].alive?
      end

      it "does not start discovery when provider not available" do
        allow(wizard).to receive(:provider_available_for_discovery?).and_return(false)

        wizard.send(:trigger_background_discovery, "anthropic")

        threads = wizard.instance_variable_get(:@discovery_threads)
        expect(threads).to be_nil
      end

      it "handles discovery errors gracefully" do
        allow(wizard).to receive(:discover_and_cache_models).and_raise(StandardError.new("Discovery failed"))

        expect do
          wizard.send(:trigger_background_discovery, "anthropic")
          threads = wizard.instance_variable_get(:@discovery_threads)
          threads.first[:thread].join if threads&.first
        end.not_to raise_error

        # Clean up
        threads = wizard.instance_variable_get(:@discovery_threads)
        threads&.first&.dig(:thread)&.kill if threads&.first&.dig(:thread)&.alive?
      end
    end

    describe "#finalize_background_discovery" do
      let(:wizard) { described_class.new(tmp_dir, prompt: prompt, dry_run: true) }

      context "when discovery threads completed successfully" do
        before do
          # Create a completed thread
          thread = Thread.new { sleep 0.01 }
          thread.join
          wizard.instance_variable_set(:@discovery_threads, [{thread: thread, provider: "anthropic"}])

          # Mock cache with discovered models
          cache = instance_double(Aidp::Harness::ModelCache)
          allow(Aidp::Harness::ModelCache).to receive(:new).and_return(cache)
          allow(cache).to receive(:get_cached_models).with("anthropic").and_return([
            {name: "claude-3-5-sonnet-20241022", family: "claude-3-5-sonnet"}
          ])
        end

        it "shows notification for discovered models" do
          expect(prompt).to receive(:say).with(/Discovered 1 model/)
          wizard.send(:finalize_background_discovery)
        end

        it "clears discovery threads" do
          wizard.send(:finalize_background_discovery)
          threads = wizard.instance_variable_get(:@discovery_threads)
          expect(threads).to eq([])
        end
      end

      context "when discovery threads still running" do
        before do
          # Create a long-running thread (longer than test timeout)
          thread = Thread.new { sleep 1 }
          wizard.instance_variable_set(:@discovery_threads, [{thread: thread, provider: "anthropic"}])
        end

        after do
          # Clean up thread
          threads = wizard.instance_variable_get(:@discovery_threads)
          threads&.first&.dig(:thread)&.kill if threads&.first&.dig(:thread)&.alive?
        end

        it "waits for timeout duration" do
          start_time = Time.now
          wizard.send(:finalize_background_discovery, timeout: 0.1)
          elapsed = Time.now - start_time

          # Should wait around 0.1 seconds (with some tolerance)
          expect(elapsed).to be_within(0.05).of(0.1)
        end

        it "does not crash when thread still running" do
          expect { wizard.send(:finalize_background_discovery, timeout: 0.1) }.not_to raise_error
        end

        it "uses custom timeout value" do
          start_time = Time.now
          wizard.send(:finalize_background_discovery, timeout: 0.05)
          elapsed = Time.now - start_time

          # Should wait around 0.05 seconds (with some tolerance)
          expect(elapsed).to be < 0.15
        end

        it "clears discovery threads after completion" do
          wizard.send(:finalize_background_discovery, timeout: 0.1)
          threads = wizard.instance_variable_get(:@discovery_threads)
          expect(threads).to eq([])
        end
      end

      context "when no discovery threads exist" do
        it "does nothing without error" do
          wizard.instance_variable_set(:@discovery_threads, nil)
          expect { wizard.send(:finalize_background_discovery) }.not_to raise_error
        end
      end

      context "when cache check fails" do
        before do
          thread = Thread.new { sleep 0.01 }
          thread.join
          wizard.instance_variable_set(:@discovery_threads, [{thread: thread, provider: "anthropic"}])

          # Mock cache to raise error
          allow(Aidp::Harness::ModelCache).to receive(:new).and_raise(StandardError.new("Cache error"))
        end

        it "handles error gracefully" do
          expect { wizard.send(:finalize_background_discovery) }.not_to raise_error
        end
      end
    end

    describe "#provider_available_for_discovery?" do
      let(:wizard) { described_class.new(tmp_dir, prompt: prompt, dry_run: true) }

      before do
        # Mock provider class
        provider_class = class_double("Aidp::Providers::Anthropic")
        allow(provider_class).to receive(:available?).and_return(true)
        stub_const("Aidp::Providers::Anthropic", provider_class)
      end

      it "returns true when provider is available" do
        result = wizard.send(:provider_available_for_discovery?, "anthropic")
        expect(result).to be true
      end

      it "returns false when provider not available" do
        provider_class = class_double("Aidp::Providers::Cursor")
        allow(provider_class).to receive(:available?).and_return(false)
        stub_const("Aidp::Providers::Cursor", provider_class)

        result = wizard.send(:provider_available_for_discovery?, "cursor")
        expect(result).to be false
      end

      it "returns false when provider class not found" do
        result = wizard.send(:provider_available_for_discovery?, "nonexistent")
        expect(result).to be false
      end
    end

    describe "#discover_and_cache_models" do
      let(:wizard) { described_class.new(tmp_dir, prompt: prompt, dry_run: true) }

      before do
        # Load the class before mocking
        require_relative "../../../lib/aidp/harness/model_discovery_service"

        # Mock discovery service
        discovery_service = instance_double(Aidp::Harness::ModelDiscoveryService)
        allow(Aidp::Harness::ModelDiscoveryService).to receive(:new).and_return(discovery_service)
        allow(discovery_service).to receive(:discover_models).with("anthropic", use_cache: false).and_return([
          {name: "claude-3-5-sonnet-20241022", family: "claude-3-5-sonnet"}
        ])
      end

      it "calls discovery service for provider" do
        discovery_service = Aidp::Harness::ModelDiscoveryService.new
        allow(Aidp::Harness::ModelDiscoveryService).to receive(:new).and_return(discovery_service)

        expect(discovery_service).to receive(:discover_models).with("anthropic", use_cache: false)
        wizard.send(:discover_and_cache_models, "anthropic")
      end

      it "does not raise error on discovery failure" do
        discovery_service = instance_double(Aidp::Harness::ModelDiscoveryService)
        allow(Aidp::Harness::ModelDiscoveryService).to receive(:new).and_return(discovery_service)
        allow(discovery_service).to receive(:discover_models).and_raise(StandardError.new("Discovery failed"))

        expect { wizard.send(:discover_and_cache_models, "anthropic") }.not_to raise_error
      end

      it "returns empty array on discovery failure" do
        discovery_service = instance_double(Aidp::Harness::ModelDiscoveryService)
        allow(Aidp::Harness::ModelDiscoveryService).to receive(:new).and_return(discovery_service)
        allow(discovery_service).to receive(:discover_models).and_raise(StandardError.new("Discovery failed"))

        result = wizard.send(:discover_and_cache_models, "anthropic")
        expect(result).to eq([])
      end

      it "logs debug message on failure" do
        discovery_service = instance_double(Aidp::Harness::ModelDiscoveryService)
        allow(Aidp::Harness::ModelDiscoveryService).to receive(:new).and_return(discovery_service)
        allow(discovery_service).to receive(:discover_models).and_raise(StandardError.new("Discovery failed"))

        expect(Aidp).to receive(:log_debug).with("setup_wizard", "background discovery failed",
          hash_including(provider: "anthropic", error: "Discovery failed"))

        wizard.send(:discover_and_cache_models, "anthropic")
      end

      it "returns models when discovery succeeds" do
        models = [{name: "test-model", tier: "standard"}]
        discovery_service = instance_double(Aidp::Harness::ModelDiscoveryService)
        allow(Aidp::Harness::ModelDiscoveryService).to receive(:new).and_return(discovery_service)
        allow(discovery_service).to receive(:discover_models).and_return(models)

        result = wizard.send(:discover_and_cache_models, "anthropic")
        expect(result).to eq(models)
      end

      it "logs info when models are discovered" do
        models = [{name: "test-model", tier: "standard"}]
        discovery_service = instance_double(Aidp::Harness::ModelDiscoveryService)
        allow(Aidp::Harness::ModelDiscoveryService).to receive(:new).and_return(discovery_service)
        allow(discovery_service).to receive(:discover_models).and_return(models)

        expect(Aidp).to receive(:log_info).with("setup_wizard", "discovered models in background",
          hash_including(provider: "anthropic", count: 1))

        wizard.send(:discover_and_cache_models, "anthropic")
      end
    end

    describe "#get_provider_class" do
      let(:wizard) { described_class.new(tmp_dir, prompt: prompt, dry_run: true) }

      it "returns provider class for known provider" do
        result = wizard.send(:get_provider_class, "anthropic")
        expect(result).to eq(Aidp::Providers::Anthropic)
      end

      it "returns nil for unknown provider" do
        result = wizard.send(:get_provider_class, "nonexistent")
        expect(result).to be_nil
      end

      it "handles provider names with different cases" do
        result = wizard.send(:get_provider_class, "ANTHROPIC")
        expect(result).to eq(Aidp::Providers::Anthropic)
      end
    end
  end
end
