# frozen_string_literal: true

module Aidp
  class LanguageAnalysisStrategies
    # Define language-specific analysis strategies
    LANGUAGE_STRATEGIES = {
      "ruby" => {
        "analysis_phases" => [
          {
            phase: 1,
            name: "Code Style and Quality",
            tools: %w[rubocop reek],
            focus_areas: ["style violations", "code smells", "complexity metrics"],
            priority: "high"
          },
          {
            phase: 2,
            name: "Security Analysis",
            tools: %w[brakeman bundler-audit],
            focus_areas: ["security vulnerabilities", "dependency vulnerabilities"],
            priority: "high"
          },
          {
            phase: 3,
            name: "Performance Analysis",
            tools: %w[fasterer ruby-prof],
            focus_areas: ["performance bottlenecks", "memory usage"],
            priority: "medium"
          },
          {
            phase: 4,
            name: "Test Coverage",
            tools: %w[simplecov rspec],
            focus_areas: ["test coverage", "test quality"],
            priority: "medium"
          }
        ],
        "code_patterns" => {
          "complex_methods" => {
            pattern: "methods with high cyclomatic complexity",
            detection: "rubocop --only Metrics/CyclomaticComplexity",
            threshold: 10
          },
          "long_methods" => {
            pattern: "methods with excessive lines",
            detection: "rubocop --only Metrics/MethodLength",
            threshold: 20
          },
          "duplicate_code" => {
            pattern: "code duplication",
            detection: "reek --detect DuplicateMethodCall",
            threshold: 3
          },
          "security_issues" => {
            pattern: "SQL injection, XSS, CSRF vulnerabilities",
            detection: "brakeman --quiet --format json",
            threshold: 0
          }
        },
        "refactoring_priorities" => [
          "Extract complex methods",
          "Reduce method length",
          "Eliminate code duplication",
          "Improve naming conventions",
          "Add missing tests"
        ]
      },
      "javascript" => {
        "analysis_phases" => [
          {
            phase: 1,
            name: "Code Quality and Style",
            tools: %w[eslint prettier],
            focus_areas: ["linting errors", "code formatting", "best practices"],
            priority: "high"
          },
          {
            phase: 2,
            name: "Security Analysis",
            tools: %w[npm-audit eslint-plugin-security],
            focus_areas: ["dependency vulnerabilities", "security anti-patterns"],
            priority: "high"
          },
          {
            phase: 3,
            name: "Type Safety",
            tools: %w[typescript flow],
            focus_areas: ["type errors", "type coverage"],
            priority: "medium"
          },
          {
            phase: 4,
            name: "Performance Analysis",
            tools: %w[webpack-bundle-analyzer lighthouse],
            focus_areas: ["bundle size", "performance metrics"],
            priority: "medium"
          }
        ],
        "code_patterns" => {
          "callback_hell" => {
            pattern: "nested callbacks",
            detection: 'eslint --rule "callback-return: error"',
            threshold: 3
          },
          "memory_leaks" => {
            pattern: "event listeners not removed",
            detection: 'eslint --rule "no-unused-vars: error"',
            threshold: 0
          },
          "async_issues" => {
            pattern: "unhandled promises",
            detection: 'eslint --rule "no-floating-promises: error"',
            threshold: 0
          },
          "security_vulnerabilities" => {
            pattern: "XSS, CSRF, injection vulnerabilities",
            detection: "eslint-plugin-security",
            threshold: 0
          }
        },
        "refactoring_priorities" => [
          "Convert callbacks to async/await",
          "Add proper error handling",
          "Implement proper type safety",
          "Optimize bundle size",
          "Add comprehensive tests"
        ]
      },
      "python" => {
        "analysis_phases" => [
          {
            phase: 1,
            name: "Code Style and Quality",
            tools: %w[flake8 black pylint],
            focus_areas: ["PEP8 compliance", "code formatting", "code quality"],
            priority: "high"
          },
          {
            phase: 2,
            name: "Security Analysis",
            tools: %w[bandit safety],
            focus_areas: ["security vulnerabilities", "dependency vulnerabilities"],
            priority: "high"
          },
          {
            phase: 3,
            name: "Type Safety",
            tools: %w[mypy pyright],
            focus_areas: ["type checking", "type coverage"],
            priority: "medium"
          },
          {
            phase: 4,
            name: "Performance Analysis",
            tools: %w[py-spy memory-profiler],
            focus_areas: ["performance bottlenecks", "memory usage"],
            priority: "medium"
          }
        ],
        "code_patterns" => {
          "complex_functions" => {
            pattern: "functions with high complexity",
            detection: "pylint --disable=all --enable=too-complex",
            threshold: 10
          },
          "long_functions" => {
            pattern: "functions with excessive lines",
            detection: "pylint --disable=all --enable=too-many-lines",
            threshold: 50
          },
          "unused_imports" => {
            pattern: "unused imports",
            detection: "flake8 --select=F401",
            threshold: 0
          },
          "security_issues" => {
            pattern: "SQL injection, command injection",
            detection: "bandit -r .",
            threshold: 0
          }
        },
        "refactoring_priorities" => [
          "Simplify complex functions",
          "Remove unused imports",
          "Add type hints",
          "Improve error handling",
          "Add comprehensive tests"
        ]
      },
      "java" => {
        "analysis_phases" => [
          {
            phase: 1,
            name: "Code Quality",
            tools: %w[checkstyle pmd],
            focus_areas: ["code style", "code quality", "best practices"],
            priority: "high"
          },
          {
            phase: 2,
            name: "Security Analysis",
            tools: %w[spotbugs dependency-check],
            focus_areas: ["security vulnerabilities", "dependency vulnerabilities"],
            priority: "high"
          },
          {
            phase: 3,
            name: "Performance Analysis",
            tools: %w[jmh visualvm],
            focus_areas: ["performance bottlenecks", "memory leaks"],
            priority: "medium"
          },
          {
            phase: 4,
            name: "Test Coverage",
            tools: %w[jacoco junit],
            focus_areas: ["test coverage", "test quality"],
            priority: "medium"
          }
        ],
        "code_patterns" => {
          "complex_methods" => {
            pattern: "methods with high cyclomatic complexity",
            detection: "pmd --rulesets complexity",
            threshold: 10
          },
          "code_duplication" => {
            pattern: "duplicate code blocks",
            detection: "pmd --rulesets cpd",
            threshold: 50
          },
          "memory_leaks" => {
            pattern: "potential memory leaks",
            detection: "spotbugs --effort:max",
            threshold: 0
          },
          "security_vulnerabilities" => {
            pattern: "SQL injection, XSS, path traversal",
            detection: "spotbugs --effort:max",
            threshold: 0
          }
        },
        "refactoring_priorities" => [
          "Extract complex methods",
          "Eliminate code duplication",
          "Improve exception handling",
          "Add proper logging",
          "Increase test coverage"
        ]
      },
      "go" => {
        "analysis_phases" => [
          {
            phase: 1,
            name: "Code Quality",
            tools: %w[golangci-lint gofmt],
            focus_areas: ["code style", "code quality", "best practices"],
            priority: "high"
          },
          {
            phase: 2,
            name: "Security Analysis",
            tools: %w[gosec govet],
            focus_areas: ["security vulnerabilities", "common mistakes"],
            priority: "high"
          },
          {
            phase: 3,
            name: "Performance Analysis",
            tools: %w[pprof go-torch],
            focus_areas: ["performance bottlenecks", "memory usage"],
            priority: "medium"
          },
          {
            phase: 4,
            name: "Test Coverage",
            tools: %w[go test -cover],
            focus_areas: ["test coverage", "test quality"],
            priority: "medium"
          }
        ],
        "code_patterns" => {
          "complex_functions" => {
            pattern: "functions with high cyclomatic complexity",
            detection: "golangci-lint --enable=gocyclo",
            threshold: 15
          },
          "error_handling" => {
            pattern: "unhandled errors",
            detection: "golangci-lint --enable=errcheck",
            threshold: 0
          },
          "race_conditions" => {
            pattern: "potential race conditions",
            detection: "go test -race",
            threshold: 0
          },
          "security_issues" => {
            pattern: "security vulnerabilities",
            detection: "gosec ./...",
            threshold: 0
          }
        },
        "refactoring_priorities" => [
          "Simplify complex functions",
          "Improve error handling",
          "Add proper logging",
          "Eliminate race conditions",
          "Increase test coverage"
        ]
      },
      "rust" => {
        "analysis_phases" => [
          {
            phase: 1,
            name: "Code Quality",
            tools: %w[clippy rustfmt],
            focus_areas: ["code style", "code quality", "best practices"],
            priority: "high"
          },
          {
            phase: 2,
            name: "Security Analysis",
            tools: %w[cargo-audit cargo-geiger],
            focus_areas: ["dependency vulnerabilities", "unsafe code usage"],
            priority: "high"
          },
          {
            phase: 3,
            name: "Performance Analysis",
            tools: %w[cargo bench flamegraph],
            focus_areas: ["performance benchmarks", "memory usage"],
            priority: "medium"
          },
          {
            phase: 4,
            name: "Test Coverage",
            tools: %w[tarpaulin cargo test],
            focus_areas: ["test coverage", "test quality"],
            priority: "medium"
          }
        ],
        "code_patterns" => {
          "complex_functions" => {
            pattern: "functions with high cyclomatic complexity",
            detection: "clippy --all --warn clippy::cognitive_complexity",
            threshold: 25
          },
          "unsafe_code" => {
            pattern: "unsafe code blocks",
            detection: "cargo-geiger",
            threshold: 0
          },
          "unused_code" => {
            pattern: "unused functions and variables",
            detection: "clippy --all --warn dead_code",
            threshold: 0
          },
          "security_issues" => {
            pattern: "security vulnerabilities",
            detection: "cargo-audit",
            threshold: 0
          }
        },
        "refactoring_priorities" => [
          "Simplify complex functions",
          "Reduce unsafe code usage",
          "Remove unused code",
          "Improve error handling",
          "Add comprehensive tests"
        ]
      }
    }.freeze

    def initialize(project_dir = Dir.pwd)
      @project_dir = project_dir
    end

    # Get analysis strategy for a specific language
    def get_analysis_strategy(language)
      strategy = LANGUAGE_STRATEGIES[language]
      return nil unless strategy

      {
        language: language,
        phases: strategy["analysis_phases"],
        patterns: strategy["code_patterns"],
        refactoring_priorities: strategy["refactoring_priorities"],
        customizations: generate_customizations(language)
      }
    end

    # Get analysis phases for a language
    def get_analysis_phases(language)
      strategy = LANGUAGE_STRATEGIES[language]
      return [] unless strategy

      strategy["analysis_phases"]
    end

    # Get code patterns for a language
    def get_code_patterns(language)
      strategy = LANGUAGE_STRATEGIES[language]
      return {} unless strategy

      strategy["code_patterns"]
    end

    # Get refactoring priorities for a language
    def get_refactoring_priorities(language)
      strategy = LANGUAGE_STRATEGIES[language]
      return [] unless strategy

      strategy["refactoring_priorities"]
    end

    # Generate custom analysis plan for a language
    def generate_custom_analysis_plan(language, focus_areas = [])
      strategy = get_analysis_strategy(language)
      return nil unless strategy

      plan = {
        language: language,
        phases: [],
        focus_areas: focus_areas,
        estimated_duration: estimate_analysis_duration(language, focus_areas),
        tools_required: get_required_tools(language, focus_areas)
      }

      # Filter phases based on focus areas
      plan[:phases] = if focus_areas.any?
        strategy[:phases].select do |phase|
          focus_areas.any? { |area| phase[:focus_areas].any? { |fa| fa.include?(area) } }
        end
      else
        strategy[:phases]
      end

      plan
    end

    # Get language-specific recommendations
    def get_language_recommendations(language, analysis_results = {})
      recommendations = []

      case language
      when "ruby"
        recommendations.concat(generate_ruby_recommendations(analysis_results))
      when "javascript"
        recommendations.concat(generate_javascript_recommendations(analysis_results))
      when "python"
        recommendations.concat(generate_python_recommendations(analysis_results))
      when "java"
        recommendations.concat(generate_java_recommendations(analysis_results))
      when "go"
        recommendations.concat(generate_go_recommendations(analysis_results))
      when "rust"
        recommendations.concat(generate_rust_recommendations(analysis_results))
      end

      recommendations
    end

    # Get language-specific best practices
    def get_language_best_practices(language)
      case language
      when "ruby"
        {
          "style" => [
            "Follow Ruby style guide",
            "Use meaningful variable names",
            "Keep methods small and focused",
            "Use proper indentation"
          ],
          "security" => [
            "Use parameterized queries",
            "Validate user input",
            "Use HTTPS in production",
            "Keep gems updated"
          ],
          "performance" => [
            "Use appropriate data structures",
            "Avoid N+1 queries",
            "Use caching where appropriate",
            "Profile before optimizing"
          ]
        }
      when "javascript"
        {
          "style" => [
            "Use consistent formatting",
            "Follow ESLint rules",
            "Use meaningful variable names",
            "Avoid global variables"
          ],
          "security" => [
            "Validate user input",
            "Use HTTPS",
            "Avoid eval()",
            "Keep dependencies updated"
          ],
          "performance" => [
            "Minimize bundle size",
            "Use lazy loading",
            "Optimize images",
            "Use appropriate caching"
          ]
        }
      when "python"
        {
          "style" => [
            "Follow PEP 8",
            "Use meaningful variable names",
            "Keep functions small",
            "Use proper docstrings"
          ],
          "security" => [
            "Validate user input",
            "Use parameterized queries",
            "Keep packages updated",
            "Use virtual environments"
          ],
          "performance" => [
            "Use appropriate data structures",
            "Profile before optimizing",
            "Use list comprehensions",
            "Avoid global variables"
          ]
        }
      else
        {}
      end
    end

    # Get language-specific anti-patterns
    def get_language_anti_patterns(language)
      case language
      when "ruby"
        [
          "Monkey patching",
          "Global variables",
          "Complex conditionals",
          "Long methods",
          "Code duplication"
        ]
      when "javascript"
        [
          "Callback hell",
          "Global variables",
          "eval() usage",
          "Unhandled promises",
          "Memory leaks"
        ]
      when "python"
        [
          "Global variables",
          "Complex list comprehensions",
          "Unused imports",
          "Long functions",
          "Code duplication"
        ]
      else
        []
      end
    end

    private

    def generate_customizations(language)
      customizations = {}

      case language
      when "ruby"
        customizations = {
          "framework_specific" => detect_ruby_framework,
          "gem_analysis" => analyze_ruby_gems,
          "test_framework" => detect_test_framework
        }
      when "javascript"
        customizations = {
          "framework_specific" => detect_javascript_framework,
          "package_analysis" => analyze_javascript_packages,
          "build_tool" => detect_build_tool
        }
      when "python"
        customizations = {
          "framework_specific" => detect_python_framework,
          "package_analysis" => analyze_python_packages,
          "virtual_environment" => detect_virtual_environment
        }
      end

      customizations
    end

    def detect_ruby_framework
      if File.exist?(File.join(@project_dir, "config", "application.rb"))
        "rails"
      elsif File.exist?(File.join(@project_dir, "app.rb"))
        "sinatra"
      elsif File.exist?(File.join(@project_dir, "*.gemspec"))
        "gem"
      else
        "unknown"
      end
    end

    def analyze_ruby_gems
      gemfile_path = File.join(@project_dir, "Gemfile")
      return {} unless File.exist?(gemfile_path)

      gemfile_content = File.read(gemfile_path)
      {
        "total_gems" => gemfile_content.scan(/gem\s+['"]([^'"]+)['"]/).flatten.length,
        "development_gems" => gemfile_content.scan(/group\s+:development.*?end/m).any?,
        "test_gems" => gemfile_content.scan(/group\s+:test.*?end/m).any?,
        "production_gems" => gemfile_content.scan(/group\s+:production.*?end/m).any?
      }
    end

    def detect_test_framework
      if File.exist?(File.join(@project_dir, "spec"))
        "rspec"
      elsif File.exist?(File.join(@project_dir, "test"))
        "minitest"
      else
        "unknown"
      end
    end

    def detect_javascript_framework
      package_json_path = File.join(@project_dir, "package.json")
      return "unknown" unless File.exist?(package_json_path)

      package_json = JSON.parse(File.read(package_json_path))
      dependencies = package_json["dependencies"] || {}
      dev_dependencies = package_json["devDependencies"] || {}

      if dependencies["react"] || dev_dependencies["react"]
        "react"
      elsif dependencies["vue"] || dev_dependencies["vue"]
        "vue"
      elsif dependencies["angular"] || dev_dependencies["angular"]
        "angular"
      elsif dependencies["express"] || dev_dependencies["express"]
        "express"
      else
        "node"
      end
    end

    def analyze_javascript_packages
      package_json_path = File.join(@project_dir, "package.json")
      return {} unless File.exist?(package_json_path)

      package_json = JSON.parse(File.read(package_json_path))
      {
        "total_dependencies" => (package_json["dependencies"] || {}).length,
        "total_dev_dependencies" => (package_json["devDependencies"] || {}).length,
        "has_scripts" => (package_json["scripts"] || {}).any?,
        "has_type_definitions" => package_json["dependencies"]&.key?("@types") || false
      }
    end

    def detect_build_tool
      if File.exist?(File.join(@project_dir, "webpack.config.js"))
        "webpack"
      elsif File.exist?(File.join(@project_dir, "vite.config.js"))
        "vite"
      elsif File.exist?(File.join(@project_dir, "rollup.config.js"))
        "rollup"
      else
        "unknown"
      end
    end

    def detect_python_framework
      if File.exist?(File.join(@project_dir, "manage.py"))
        "django"
      elsif File.exist?(File.join(@project_dir, "app.py"))
        "flask"
      elsif File.exist?(File.join(@project_dir, "main.py"))
        "fastapi"
      else
        "unknown"
      end
    end

    def analyze_python_packages
      requirements_path = File.join(@project_dir, "requirements.txt")
      return {} unless File.exist?(requirements_path)

      requirements_content = File.read(requirements_path)
      {
        "total_packages" => requirements_content.lines.count { |line| line.strip != "" && !line.start_with?("#") },
        "has_dev_requirements" => File.exist?(File.join(@project_dir, "requirements-dev.txt")),
        "has_test_requirements" => File.exist?(File.join(@project_dir, "requirements-test.txt"))
      }
    end

    def detect_virtual_environment
      if File.exist?(File.join(@project_dir, "venv"))
        "venv"
      elsif File.exist?(File.join(@project_dir, ".venv"))
        ".venv"
      elsif File.exist?(File.join(@project_dir, "env"))
        "env"
      else
        "unknown"
      end
    end

    def estimate_analysis_duration(language, focus_areas)
      base_duration = case language
      when "ruby"
        30 # minutes
      when "javascript"
        45 # minutes
      when "python"
        25 # minutes
      when "java"
        60 # minutes
      when "go"
        20 # minutes
      when "rust"
        35 # minutes
      else
        30 # minutes
      end

      # Adjust based on focus areas
      base_duration += 15 if focus_areas.include?("security")
      base_duration += 20 if focus_areas.include?("performance")
      base_duration += 10 if focus_areas.include?("test_coverage")

      base_duration
    end

    def get_required_tools(language, focus_areas)
      strategy = LANGUAGE_STRATEGIES[language]
      return [] unless strategy

      required_tools = []
      strategy["analysis_phases"].each do |phase|
        if focus_areas.empty? || focus_areas.any? { |area| phase[:focus_areas].any? { |fa| fa.include?(area) } }
          required_tools.concat(phase[:tools])
        end
      end

      required_tools.uniq
    end

    def generate_ruby_recommendations(analysis_results)
      recommendations = []

      if analysis_results["style_violations"]&.> 10
        recommendations << {
          type: "style",
          priority: "high",
          message: "High number of style violations detected",
          action: "Run RuboCop and fix style issues"
        }
      end

      if analysis_results["security_vulnerabilities"]&.> 0
        recommendations << {
          type: "security",
          priority: "critical",
          message: "Security vulnerabilities found",
          action: "Run Brakeman and address security issues immediately"
        }
      end

      recommendations
    end

    def generate_javascript_recommendations(analysis_results)
      recommendations = []

      if analysis_results["linting_errors"]&.> 20
        recommendations << {
          type: "quality",
          priority: "high",
          message: "High number of linting errors",
          action: "Run ESLint and fix code quality issues"
        }
      end

      if analysis_results["security_vulnerabilities"]&.> 0
        recommendations << {
          type: "security",
          priority: "critical",
          message: "Security vulnerabilities in dependencies",
          action: "Run npm audit and update vulnerable packages"
        }
      end

      recommendations
    end

    def generate_python_recommendations(analysis_results)
      recommendations = []

      if analysis_results["pep8_violations"]&.> 15
        recommendations << {
          type: "style",
          priority: "medium",
          message: "PEP8 violations detected",
          action: "Run flake8 and fix style issues"
        }
      end

      if analysis_results["security_issues"]&.> 0
        recommendations << {
          type: "security",
          priority: "critical",
          message: "Security issues found",
          action: "Run bandit and address security vulnerabilities"
        }
      end

      recommendations
    end

    def generate_java_recommendations(analysis_results)
      recommendations = []

      if analysis_results["checkstyle_violations"]&.> 25
        recommendations << {
          type: "style",
          priority: "medium",
          message: "Checkstyle violations detected",
          action: "Run Checkstyle and fix code style issues"
        }
      end

      if analysis_results["security_vulnerabilities"]&.> 0
        recommendations << {
          type: "security",
          priority: "critical",
          message: "Security vulnerabilities found",
          action: "Run SpotBugs and address security issues"
        }
      end

      recommendations
    end

    def generate_go_recommendations(analysis_results)
      recommendations = []

      if analysis_results["linting_errors"]&.> 10
        recommendations << {
          type: "quality",
          priority: "high",
          message: "Go linting errors detected",
          action: "Run golangci-lint and fix code quality issues"
        }
      end

      if analysis_results["security_issues"]&.> 0
        recommendations << {
          type: "security",
          priority: "critical",
          message: "Security issues found",
          action: "Run gosec and address security vulnerabilities"
        }
      end

      recommendations
    end

    def generate_rust_recommendations(analysis_results)
      recommendations = []

      if analysis_results["clippy_warnings"]&.> 15
        recommendations << {
          type: "quality",
          priority: "medium",
          message: "Clippy warnings detected",
          action: "Run cargo clippy and address code quality issues"
        }
      end

      if analysis_results["security_vulnerabilities"]&.> 0
        recommendations << {
          type: "security",
          priority: "critical",
          message: "Security vulnerabilities in dependencies",
          action: "Run cargo audit and update vulnerable dependencies"
        }
      end

      recommendations
    end
  end
end
