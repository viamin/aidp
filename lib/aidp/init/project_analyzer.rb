# frozen_string_literal: true

require "find"
require "json"

module Aidp
  module Init
    # Performs lightweight static analysis of the repository to detect languages,
    # frameworks, config files, and quality tooling. Designed to run quickly and
    # deterministically without external services.
    class ProjectAnalyzer
      IGNORED_DIRECTORIES = %w[
        .git
        .svn
        .hg
        node_modules
        vendor
        tmp
        log
        build
        dist
        coverage
        .yardoc
      ].freeze

      LANGUAGE_EXTENSIONS = {
        ".rb" => "Ruby",
        ".rake" => "Ruby",
        ".gemspec" => "Ruby",
        ".js" => "JavaScript",
        ".jsx" => "JavaScript",
        ".ts" => "TypeScript",
        ".tsx" => "TypeScript",
        ".py" => "Python",
        ".go" => "Go",
        ".java" => "Java",
        ".kt" => "Kotlin",
        ".cs" => "C#",
        ".php" => "PHP",
        ".rs" => "Rust",
        ".swift" => "Swift",
        ".scala" => "Scala",
        ".c" => "C",
        ".cpp" => "C++",
        ".hpp" => "C++",
        ".m" => "Objective-C",
        ".mm" => "Objective-C++",
        ".hs" => "Haskell",
        ".erl" => "Erlang",
        ".ex" => "Elixir",
        ".exs" => "Elixir",
        ".clj" => "Clojure",
        ".coffee" => "CoffeeScript"
      }.freeze

      CONFIG_FILES = %w[
        .editorconfig
        .rubocop.yml
        .rubocop_todo.yml
        .standardrb
        .eslintrc
        .eslintrc.js
        .eslintrc.cjs
        .eslintrc.json
        .prettierrc
        .prettierrc.js
        .prettierrc.cjs
        .prettierrc.json
        .stylelintrc
        .flake8
        pyproject.toml
        tox.ini
        setup.cfg
        package.json
        Gemfile
        Gemfile.lock
        mix.exs
        go.mod
        go.sum
        composer.json
        Cargo.toml
        Cargo.lock
        pom.xml
        build.gradle
        build.gradle.kts
      ].freeze

      KEY_DIRECTORIES = %w[
        app
        src
        lib
        spec
        test
        tests
        scripts
        bin
        config
        docs
        examples
        packages
        modules
      ].freeze

      TOOLING_HINTS = {
        rubocop: [".rubocop.yml", ".rubocop_todo.yml"],
        standardrb: [".standardrb"],
        eslint: [".eslintrc", ".eslintrc.js", ".eslintrc.cjs", ".eslintrc.json"],
        prettier: [".prettierrc", ".prettierrc.js", ".prettierrc.cjs", ".prettierrc.json"],
        stylelint: [".stylelintrc"],
        flake8: [".flake8"],
        black: ["pyproject.toml"],
        pytest: ["pytest.ini", "pyproject.toml"],
        jest: ["package.json"],
        rspec: ["spec", ".rspec"],
        minitest: ["test"],
        gofmt: ["go.mod"],
        cargo_fmt: ["Cargo.toml"]
      }.freeze

      FRAMEWORK_HINTS = {
        "Rails" => {files: ["config/application.rb"], contents: [/rails/i]},
        "Hanami" => {files: ["config/app.rb"], contents: [/hanami/i]},
        "Sinatra" => {files: ["config.ru"], contents: [/sinatra/i]},
        "React" => {files: ["package.json"], contents: [/react/]},
        "Next.js" => {files: ["package.json"], contents: [/next/]},
        "Express" => {files: ["package.json"], contents: [/express/]},
        "Angular" => {files: ["angular.json"]},
        "Vue" => {files: ["package.json"], contents: [/vue/]},
        "Django" => {files: ["manage.py"], contents: [/django/]},
        "Flask" => {files: ["requirements.txt"], contents: [/flask/]},
        "FastAPI" => {files: ["pyproject.toml", "requirements.txt"], contents: [/fastapi/]},
        "Phoenix" => {files: ["mix.exs"], contents: [/phoenix/]},
        "Spring" => {files: ["pom.xml", "build.gradle", "build.gradle.kts"], contents: [/spring/]},
        "Laravel" => {files: ["composer.json"], contents: [/laravel/]},
        "Go Gin" => {files: ["go.mod"], contents: [/gin-gonic/]},
        "Go Fiber" => {files: ["go.mod"], contents: [/github.com\/gofiber/]}
      }.freeze

      TEST_FRAMEWORK_HINTS = {
        "RSpec" => {directories: ["spec"], dependencies: [/rspec/]},
        "Minitest" => {directories: ["test"], dependencies: [/minitest/]},
        "Cucumber" => {directories: ["features"]},
        "Jest" => {dependencies: [/jest/]},
        "Mocha" => {dependencies: [/mocha/]},
        "Jasmine" => {dependencies: [/jasmine/]},
        "Pytest" => {directories: ["tests", "test"], dependencies: [/pytest/]},
        "NUnit" => {files: ["*.csproj"], contents: [/nunit/]},
        "JUnit" => {dependencies: [/junit/]},
        "Go test" => {files: ["*_test.go"]}
      }.freeze

      attr_reader :project_dir

      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
      end

      def analyze
        {
          languages: detect_languages,
          frameworks: detect_frameworks,
          key_directories: detect_key_directories,
          config_files: detect_config_files,
          test_frameworks: detect_test_frameworks,
          tooling: detect_tooling,
          repo_stats: collect_repo_stats
        }
      end

      private

      def detect_languages
        counts = Hash.new(0)

        traverse_files do |relative_path|
          ext = File.extname(relative_path)
          language = LANGUAGE_EXTENSIONS[ext]
          next unless language

          full_path = File.join(project_dir, relative_path)
          counts[language] += File.size(full_path)
        end

        counts.sort_by { |_lang, weight| -weight }.to_h
      end

      def detect_frameworks
        frameworks = Set.new

        FRAMEWORK_HINTS.each do |framework, rules|
          if rules[:files]&.any? { |file| project_glob?(file) }
            if rules[:contents]
              frameworks << framework if rules[:contents].any? { |pattern| search_files_for_pattern(rules[:files], pattern) }
            else
              frameworks << framework
            end
          elsif rules[:contents]&.any? { |pattern| search_project_for_pattern(pattern) }
            frameworks << framework
          end
        end

        frameworks.to_a.sort
      end

      def detect_key_directories
        KEY_DIRECTORIES.select { |dir| Dir.exist?(File.join(project_dir, dir)) }
      end

      def detect_config_files
        CONFIG_FILES.select { |file| project_glob?(file) }
      end

      def detect_test_frameworks
        results = []

        TEST_FRAMEWORK_HINTS.each do |framework, hints|
          has_directory = hints[:directories]&.any? { |dir| Dir.exist?(File.join(project_dir, dir)) }
          has_dependency = hints[:dependencies]&.any? { |pattern| search_project_for_pattern(pattern, limit_files: ["Gemfile", "Gemfile.lock", "package.json", "pyproject.toml", "requirements.txt", "go.mod", "mix.exs", "composer.json", "Cargo.toml"]) }
          has_files = hints[:files]&.any? { |glob| project_glob?(glob) }

          results << framework if has_directory || has_dependency || has_files
        end

        results.uniq.sort
      end

      def detect_tooling
        tooling = Hash.new { |hash, key| hash[key] = [] }

        TOOLING_HINTS.each do |tool, indicators|
          hit = indicators.any? do |indicator|
            if indicator.include?("*")
            end
            project_glob?(indicator)
          end
          tooling[tool] << "config" if hit
        end

        # Post-process for package.json to extract scripts referencing linters
        package_json_path = File.join(project_dir, "package.json")
        if File.exist?(package_json_path)
          begin
            json = JSON.parse(File.read(package_json_path))
            scripts = json.fetch("scripts", {})
            tooling[:eslint] << "package.json scripts" if scripts.values.any? { |cmd| cmd.include?("eslint") }
            tooling[:prettier] << "package.json scripts" if scripts.values.any? { |cmd| cmd.include?("prettier") }
            tooling[:jest] << "package.json scripts" if scripts.values.any? { |cmd| cmd.include?("jest") }
          rescue JSON::ParserError
            # ignore malformed package.json
          end
        end

        tooling.delete_if { |_tool, evidence| evidence.empty? }
      end

      def collect_repo_stats
        {
          total_files: counted_files.size,
          total_directories: counted_directories.size,
          docs_present: Dir.exist?(File.join(project_dir, "docs")),
          has_ci_config: project_glob?(".github/workflows/*.yml") || project_glob?(".gitlab-ci.yml"),
          has_containerization: project_glob?("Dockerfile") || project_glob?("docker-compose.yml")
        }
      end

      def counted_files
        @counted_files ||= begin
          files = []
          traverse_files { |path| files << path }
          files
        end
      end

      def counted_directories
        @counted_directories ||= begin
          dirs = Set.new
          traverse_files do |path|
            dirs << File.dirname(path)
          end
          dirs.to_a
        end
      end

      def traverse_files
        Find.find(project_dir) do |path|
          next if path == project_dir

          relative = path.sub("#{project_dir}/", "")
          if File.directory?(path)
            dirname = File.basename(path)
            if IGNORED_DIRECTORIES.include?(dirname)
              Find.prune
            else
              next
            end
          else
            yield relative
          end
        end
      end

      def project_glob?(pattern)
        Dir.glob(File.join(project_dir, pattern)).any?
      end

      def search_files_for_pattern(files, pattern)
        files.any? do |file|
          Dir.glob(File.join(project_dir, file)).any? do |path|
            File.read(path).match?(pattern)
          rescue Errno::ENOENT, Errno::EISDIR
            false
          end
        end
      end

      def search_project_for_pattern(pattern, limit_files: nil)
        if limit_files
          limit_files.any? do |file|
            path = File.join(project_dir, file)
            next false unless File.exist?(path)

            File.read(path).match?(pattern)
          rescue Errno::ENOENT
            false
          end
        else
          traverse_files do |relative_path|
            path = File.join(project_dir, relative_path)
            begin
              return true if File.read(path).match?(pattern)
            rescue Errno::ENOENT
              next
            end
          end
          false
        end
      end
    end
  end
end
