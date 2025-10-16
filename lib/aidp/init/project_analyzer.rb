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

      def analyze(options = {})
        @explain_detection = options[:explain_detection] || false

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
        results = []

        FRAMEWORK_HINTS.each do |framework, rules|
          evidence = []
          confidence = 0.0

          # Check for required files
          matched_files = []
          if rules[:files]
            matched_files = rules[:files].select { |file| project_glob?(file) }
            if matched_files.any?
              evidence << "Found files: #{matched_files.join(", ")}"
              confidence += 0.3
            end
          end

          # Check for content patterns in specific files or across project
          if rules[:contents]
            rules[:contents].each do |pattern|
              if matched_files.any?
                # Search only in the matched files
                if search_files_for_pattern(matched_files, pattern)
                  evidence << "Found pattern '#{pattern.inspect}' in #{matched_files.join(", ")}"
                  confidence += 0.7
                end
              else
                # Search across all project files (less confident)
                if search_project_for_pattern(pattern)
                  evidence << "Found pattern '#{pattern.inspect}' in project files"
                  confidence += 0.4
                end
              end
            end
          elsif matched_files.any?
            # Files exist but no content check needed - moderately confident
            confidence = 0.6
          end

          # Only include frameworks with evidence
          if evidence.any? && confidence > 0.0
            # Cap confidence at 1.0
            confidence = [confidence, 1.0].min

            results << {
              name: framework,
              confidence: confidence,
              evidence: evidence
            }
          end
        end

        # Sort by confidence (descending) then name
        results.sort_by { |r| [-r[:confidence], r[:name]] }
      end

      def detect_key_directories
        KEY_DIRECTORIES.select { |dir| Dir.exist?(File.join(project_dir, dir)) }
      end

      def detect_config_files
        CONFIG_FILES.select { |file| project_glob?(file) }
      end

      def detect_test_frameworks
        results = []
        dependency_files = ["Gemfile", "Gemfile.lock", "package.json", "pyproject.toml", "requirements.txt", "go.mod", "mix.exs", "composer.json", "Cargo.toml"]

        TEST_FRAMEWORK_HINTS.each do |framework, hints|
          evidence = []
          confidence = 0.0

          # Check for test directories
          if hints[:directories]
            found_dirs = hints[:directories].select { |dir| Dir.exist?(File.join(project_dir, dir)) }
            if found_dirs.any?
              evidence << "Found directories: #{found_dirs.join(", ")}"
              confidence += 0.5
            end
          end

          # Check for dependencies in lockfiles/manifests
          if hints[:dependencies]
            hints[:dependencies].each do |pattern|
              matched_files = []
              dependency_files.each do |dep_file|
                path = File.join(project_dir, dep_file)
                next unless File.exist?(path)

                begin
                  if File.read(path).match?(pattern)
                    matched_files << dep_file
                  end
                rescue Errno::ENOENT, ArgumentError, Encoding::InvalidByteSequenceError
                  next
                end
              end

              if matched_files.any?
                evidence << "Found dependency pattern '#{pattern.inspect}' in #{matched_files.join(", ")}"
                confidence += 0.6
              end
            end
          end

          # Check for test files
          if hints[:files]
            matched_globs = hints[:files].select { |glob| project_glob?(glob) }
            if matched_globs.any?
              evidence << "Found test files matching: #{matched_globs.join(", ")}"
              confidence += 0.4
            end
          end

          # Only include test frameworks with evidence
          if evidence.any? && confidence > 0.0
            confidence = [confidence, 1.0].min

            results << {
              name: framework,
              confidence: confidence,
              evidence: evidence
            }
          end
        end

        # Sort by confidence (descending) then name
        results.sort_by { |r| [-r[:confidence], r[:name]] }
      end

      def detect_tooling
        results = []

        TOOLING_HINTS.each do |tool, indicators|
          evidence = []
          confidence = 0.0

          matched_indicators = indicators.select { |indicator| project_glob?(indicator) }
          if matched_indicators.any?
            evidence << "Found config files: #{matched_indicators.join(", ")}"
            confidence += 0.8
          end

          results << {tool: tool, evidence: evidence, confidence: confidence} if evidence.any?
        end

        # Post-process for package.json to extract scripts referencing linters
        package_json_path = File.join(project_dir, "package.json")
        if File.exist?(package_json_path)
          begin
            json = JSON.parse(File.read(package_json_path))
            scripts = json.fetch("scripts", {})

            [:eslint, :prettier, :jest].each do |tool|
              tool_str = tool.to_s
              if scripts.values.any? { |cmd| cmd.include?(tool_str) }
                # Check if we already have this tool from config detection
                existing = results.find { |r| r[:tool] == tool }
                if existing
                  existing[:evidence] << "Referenced in package.json scripts"
                  existing[:confidence] = [existing[:confidence] + 0.3, 1.0].min
                else
                  results << {
                    tool: tool,
                    evidence: ["Referenced in package.json scripts"],
                    confidence: 0.6
                  }
                end
              end
            end
          rescue JSON::ParserError
            # ignore malformed package.json
          end
        end

        # Sort by confidence (descending) then tool name
        results.sort_by { |r| [-r[:confidence], r[:tool].to_s] }
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
            # Special handling for package.json - only search in dependencies
            if File.basename(path) == "package.json"
              check_package_json_dependency(path, pattern)
            else
              File.read(path).match?(pattern)
            end
          rescue Errno::ENOENT, Errno::EISDIR
            false
          end
        end
      end

      def check_package_json_dependency(path, pattern)
        json = JSON.parse(File.read(path))
        deps = json.fetch("dependencies", {})
        dev_deps = json.fetch("devDependencies", {})
        peer_deps = json.fetch("peerDependencies", {})

        all_deps = deps.keys + dev_deps.keys + peer_deps.keys
        all_deps.any? { |dep| dep.match?(pattern) }
      rescue JSON::ParserError, Errno::ENOENT
        # Fallback to simple text search if JSON parsing fails
        File.read(path).match?(pattern)
      rescue
        false
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
            rescue ArgumentError, Encoding::InvalidByteSequenceError => e
              warn "[AIDP] Skipping file with invalid encoding: #{path} (#{e.class})"
              next
            end
          end
          false
        end
      end
    end
  end
end
