# frozen_string_literal: true

module Aidp
  # Detect basic project tooling to seed work loop test & lint commands.
  # Lightweight heuristic pass – prefers safety over guessing incorrectly.
  class ToolingDetector
    DETECTORS = [
      :ruby_bundle,
      :rspec,
      :ruby_standardrb,
      :node_jest,
      :node_mocha,
      :node_eslint,
      :python_pytest
    ].freeze

    Result = Struct.new(:test_commands, :lint_commands, keyword_init: true)

    def self.detect(root = Dir.pwd)
      new(root).detect
    end

    def initialize(root = Dir.pwd)
      @root = root
    end

    def detect
      tests = []
      linters = []

      if ruby_project?
        tests << bundle_prefix("rspec") if rspec?
        linters << bundle_prefix("standardrb") if standard_rb?
      end

      if node_project?
        tests << npm_or_yarn("test") if package_script?("test")
        %w[lint eslint].each do |script|
          if package_script?(script)
            linters << npm_or_yarn(script)
            break
          end
        end
      end

      if python_pytest?
        tests << "pytest -q"
      end

      Result.new(
        test_commands: tests.uniq,
        lint_commands: linters.uniq
      )
    end

    private

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

    def standard_rb?
      File.exist?(File.join(@root, "Gemfile")) &&
        begin
          File.readlines(File.join(@root, "Gemfile")).grep(/standard/).any?
        rescue
          false
        end
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

    def python_pytest?
      Dir.glob(File.join(@root, "**", "pytest.ini")).any? ||
        Dir.glob(File.join(@root, "**", "conftest.py")).any?
    end
  end
end
