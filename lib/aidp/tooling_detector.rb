# frozen_string_literal: true

module Aidp
  # Detect basic project tooling to seed work loop test & lint commands.
  # Lightweight heuristic pass – prefers safety over guessing incorrectly.
  # Provides framework-aware command suggestions with optimal flags for output filtering.
  class ToolingDetector
    DETECTORS = [
      :ruby_bundle,
      :rspec,
      :minitest,
      :ruby_standardrb,
      :node_jest,
      :node_mocha,
      :node_eslint,
      :python_pytest,
      :python_ruff
    ].freeze

    # Framework identifiers for output filtering
    FRAMEWORKS = {
      rspec: :rspec,
      minitest: :minitest,
      jest: :jest,
      mocha: :jest, # Mocha uses similar output format
      pytest: :pytest
    }.freeze

    # Enhanced result with framework information
    Result = Struct.new(:test_commands, :lint_commands, :formatter_commands,
      :frameworks, keyword_init: true) do
      # Get test commands with their detected framework
      def test_command_frameworks
        @test_command_frameworks ||= {}
      end

      # Get the framework for a specific command
      def framework_for_command(command)
        test_command_frameworks[command] || :unknown
      end
    end

    # Information about a detected command
    CommandInfo = Struct.new(:command, :framework, :flags, keyword_init: true)

    def self.detect(root = Dir.pwd)
      new(root).detect
    end

    # Detect framework from a command string
    # @param command [String] Command to analyze
    # @return [Symbol] Framework identifier (:rspec, :minitest, :jest, :pytest, :unknown)
    def self.framework_from_command(command)
      return :unknown unless command.is_a?(String)

      case command.downcase
      when /\brspec\b/
        :rspec
      when /\bminitest\b/, /\bruby.*test/, /\brake test\b/
        :minitest
      when /\bjest\b/, /\bmocha\b/
        :jest
      when /\bpytest\b/
        :pytest
      else
        :unknown
      end
    end

    # Get recommended command flags for better output filtering
    # @param framework [Symbol] Framework identifier
    # @return [Hash] Recommended flags for different verbosity modes
    def self.recommended_flags(framework)
      case framework
      when :rspec
        {
          standard: "--format progress",
          verbose: "--format documentation",
          failures_only: "--format failures --format progress"
        }
      when :minitest
        {
          standard: "",
          verbose: "-v",
          failures_only: ""
        }
      when :jest
        {
          standard: "",
          verbose: "--verbose",
          failures_only: "--reporters=default --silent=false"
        }
      when :pytest
        {
          standard: "-q",
          verbose: "-v",
          failures_only: "-q --tb=short"
        }
      else
        {
          standard: "",
          verbose: "",
          failures_only: ""
        }
      end
    end

    def initialize(root = Dir.pwd)
      @root = root
    end

    def detect
      tests = []
      linters = []
      formatters = []
      frameworks = {}

      detect_ruby_tools(tests, linters, formatters, frameworks)
      detect_node_tools(tests, linters, formatters, frameworks)
      detect_python_tools(tests, linters, formatters, frameworks)

      result = Result.new(
        test_commands: tests.uniq,
        lint_commands: linters.uniq,
        formatter_commands: formatters.uniq,
        frameworks: frameworks
      )

      # Store framework mappings in the result
      frameworks.each do |cmd, framework|
        result.test_command_frameworks[cmd] = framework
      end

      result
    end

    # Get detailed command information including framework and suggested flags
    # @return [Array<CommandInfo>] Detailed information about detected commands
    def detect_with_details
      commands = []

      if ruby_project?
        if rspec?
          commands << CommandInfo.new(
            command: bundle_prefix("rspec"),
            framework: :rspec,
            flags: self.class.recommended_flags(:rspec)
          )
        end

        if minitest?
          commands << CommandInfo.new(
            command: bundle_prefix("ruby -Itest test"),
            framework: :minitest,
            flags: self.class.recommended_flags(:minitest)
          )
        end
      end

      if node_project?
        if jest?
          commands << CommandInfo.new(
            command: npm_or_yarn("test"),
            framework: :jest,
            flags: self.class.recommended_flags(:jest)
          )
        end
      end

      if python_pytest?
        commands << CommandInfo.new(
          command: "pytest",
          framework: :pytest,
          flags: self.class.recommended_flags(:pytest)
        )
      end

      commands
    end

    private

    def detect_ruby_tools(tests, linters, formatters, frameworks)
      return unless ruby_project?

      if rspec?
        cmd = bundle_prefix("rspec")
        tests << cmd
        frameworks[cmd] = :rspec
      end

      if minitest?
        cmd = bundle_prefix("ruby -Itest test")
        tests << cmd
        frameworks[cmd] = :minitest
      end

      if standard_rb?
        linters << bundle_prefix("standardrb")
        formatters << bundle_prefix("standardrb --fix")
      end

      if rubocop?
        linters << bundle_prefix("rubocop") unless standard_rb?
        formatters << bundle_prefix("rubocop -A") unless standard_rb?
      end
    end

    def detect_node_tools(tests, linters, formatters, frameworks)
      return unless node_project?

      if jest?
        cmd = npm_or_yarn("test")
        tests << cmd
        frameworks[cmd] = :jest
      elsif package_script?("test")
        tests << npm_or_yarn("test")
      end

      %w[lint eslint].each do |script|
        if package_script?(script)
          linters << npm_or_yarn(script)
          break
        end
      end

      %w[format prettier].each do |script|
        if package_script?(script)
          formatters << npm_or_yarn(script)
          break
        end
      end
    end

    def detect_python_tools(tests, linters, formatters, frameworks)
      if python_pytest?
        cmd = "pytest -q"
        tests << cmd
        frameworks[cmd] = :pytest
      end

      if python_ruff?
        linters << "ruff check ."
        formatters << "ruff format ."
      elsif python_flake8?
        linters << "flake8"
      end

      formatters << "black ." if python_black?
    end

    def bundle_prefix(cmd)
      File.exist?(File.join(@root, "Gemfile")) ? "bundle exec #{cmd}" : cmd
    end

    def ruby_project?
      File.exist?(File.join(@root, "Gemfile"))
    end

    def rspec?
      File.exist?(File.join(@root, "spec")) &&
        begin
          File.readlines(File.join(@root, "Gemfile")).grep(/rspec/).any?
        rescue
          false
        end
    end

    def minitest?
      test_dir = File.join(@root, "test")
      return false unless File.exist?(test_dir)

      # Check for minitest in Gemfile or test files
      gemfile_has_minitest = begin
        File.readlines(File.join(@root, "Gemfile")).grep(/minitest/).any?
      rescue
        false
      end

      return true if gemfile_has_minitest

      # Check for test files that use minitest
      test_files = Dir.glob(File.join(test_dir, "**", "*_test.rb"))
      test_files.any?
    end

    def standard_rb?
      File.exist?(File.join(@root, "Gemfile")) &&
        begin
          File.readlines(File.join(@root, "Gemfile")).grep(/standard/).any?
        rescue
          false
        end
    end

    def rubocop?
      File.exist?(File.join(@root, ".rubocop.yml")) ||
        (File.exist?(File.join(@root, "Gemfile")) &&
         begin
           File.readlines(File.join(@root, "Gemfile")).grep(/rubocop/).any?
         rescue
           false
         end)
    end

    def package_json
      @package_json ||= begin
        path = File.join(@root, "package.json")
        return nil unless File.exist?(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError
        nil
      end
    end

    def node_project?
      !!package_json
    end

    def package_script?(name)
      package_json&.dig("scripts", name)
    end

    def npm_or_yarn(script)
      if File.exist?(File.join(@root, "yarn.lock"))
        "yarn #{script}"
      else
        "npm run #{script}"
      end
    end

    def jest?
      return false unless node_project?

      # Check for jest in dependencies or devDependencies
      deps = package_json&.dig("dependencies") || {}
      dev_deps = package_json&.dig("devDependencies") || {}

      deps.key?("jest") || dev_deps.key?("jest") ||
        package_json&.dig("scripts", "test")&.include?("jest")
    end

    def python_pytest?
      Dir.glob(File.join(@root, "**", "pytest.ini")).any? ||
        Dir.glob(File.join(@root, "**", "conftest.py")).any? ||
        (File.exist?(File.join(@root, "pyproject.toml")) &&
         begin
           File.read(File.join(@root, "pyproject.toml")).include?("pytest")
         rescue
           false
         end)
    end

    def python_ruff?
      File.exist?(File.join(@root, "pyproject.toml")) &&
        begin
          File.read(File.join(@root, "pyproject.toml")).include?("[tool.ruff]")
        rescue
          false
        end
    end

    def python_flake8?
      File.exist?(File.join(@root, ".flake8")) ||
        File.exist?(File.join(@root, "setup.cfg")) &&
          begin
            File.read(File.join(@root, "setup.cfg")).include?("[flake8]")
          rescue
            false
          end
    end

    def python_black?
      File.exist?(File.join(@root, "pyproject.toml")) &&
        begin
          File.read(File.join(@root, "pyproject.toml")).include?("[tool.black]")
        rescue
          false
        end
    end
  end
end
