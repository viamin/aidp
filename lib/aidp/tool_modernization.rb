# frozen_string_literal: true

require "json"

module Aidp
  class ToolModernization
    # Define tool modernization mappings
    TOOL_MODERNIZATION_MAP = {
      "ruby" => {
        "outdated_tools" => {
          "ruby-lint" => {
            name: "Ruby-Lint",
            status: "deprecated",
            reason: "No longer maintained, replaced by RuboCop",
            modern_alternative: "rubocop",
            migration_notes: "RuboCop provides better performance and more comprehensive analysis"
          },
          "flay" => {
            name: "Flay",
            status: "deprecated",
            reason: "Limited maintenance, replaced by Reek",
            modern_alternative: "reek",
            migration_notes: "Reek provides better code smell detection and is actively maintained"
          },
          "flog" => {
            name: "Flog",
            status: "deprecated",
            reason: "Limited maintenance, replaced by RuboCop complexity metrics",
            modern_alternative: "rubocop",
            migration_notes: "RuboCop includes complexity analysis and is more comprehensive"
          }
        },
        "modern_tools" => {
          "rubocop" => {
            name: "RuboCop",
            status: "active",
            description: "Ruby static code analyzer and formatter",
            features: %w[style quality complexity formatting],
            version: "latest"
          },
          "reek" => {
            name: "Reek",
            status: "active",
            description: "Code smell detector for Ruby",
            features: %w[quality smells],
            version: "latest"
          },
          "brakeman" => {
            name: "Brakeman",
            status: "active",
            description: "Security vulnerability scanner for Ruby on Rails",
            features: %w[security],
            version: "latest"
          }
        }
      },
      "javascript" => {
        "outdated_tools" => {
          "jshint" => {
            name: "JSHint",
            status: "deprecated",
            reason: "Limited maintenance, replaced by ESLint",
            modern_alternative: "eslint",
            migration_notes: "ESLint provides better configurability and plugin ecosystem"
          },
          "jslint" => {
            name: "JSLint",
            status: "deprecated",
            reason: "Limited configurability, replaced by ESLint",
            modern_alternative: "eslint",
            migration_notes: "ESLint offers better customization and community support"
          },
          "coffeescript" => {
            name: "CoffeeScript",
            status: "deprecated",
            reason: "Declining usage, replaced by modern JavaScript",
            modern_alternative: "es6+",
            migration_notes: "Modern JavaScript provides better tooling and ecosystem support"
          }
        },
        "modern_tools" => {
          "eslint" => {
            name: "ESLint",
            status: "active",
            description: "JavaScript linting utility",
            features: %w[style quality],
            version: "latest"
          },
          "prettier" => {
            name: "Prettier",
            status: "active",
            description: "Code formatter for JavaScript",
            features: %w[style formatting],
            version: "latest"
          },
          "typescript" => {
            name: "TypeScript",
            status: "active",
            description: "Typed JavaScript",
            features: %w[types safety],
            version: "latest"
          }
        }
      },
      "python" => {
        "outdated_tools" => {
          "pep8" => {
            name: "PEP8",
            status: "deprecated",
            reason: "Renamed to pycodestyle, replaced by flake8",
            modern_alternative: "flake8",
            migration_notes: "Flake8 includes PEP8 checking plus additional features"
          },
          "pylint1" => {
            name: "Pylint 1.x",
            status: "deprecated",
            reason: "Old version, replaced by Pylint 2.x+",
            modern_alternative: "pylint",
            migration_notes: "Pylint 2.x+ provides better performance and Python 3 support"
          }
        },
        "modern_tools" => {
          "flake8" => {
            name: "Flake8",
            status: "active",
            description: "Python linting utility",
            features: %w[style quality],
            version: "latest"
          },
          "black" => {
            name: "Black",
            status: "active",
            description: "Uncompromising Python code formatter",
            features: %w[style formatting],
            version: "latest"
          },
          "mypy" => {
            name: "MyPy",
            status: "active",
            description: "Static type checker for Python",
            features: %w[types safety],
            version: "latest"
          }
        }
      },
      "java" => {
        "outdated_tools" => {
          "findbugs" => {
            name: "FindBugs",
            status: "deprecated",
            reason: "No longer maintained, replaced by SpotBugs",
            modern_alternative: "spotbugs",
            migration_notes: "SpotBugs is the active fork of FindBugs with Java 8+ support"
          },
          "pmd4" => {
            name: "PMD 4.x",
            status: "deprecated",
            reason: "Old version, replaced by PMD 6.x+",
            modern_alternative: "pmd",
            migration_notes: "PMD 6.x+ provides better Java 8+ support and performance"
          }
        },
        "modern_tools" => {
          "spotbugs" => {
            name: "SpotBugs",
            status: "active",
            description: "Java bug finder",
            features: %w[quality bugs],
            version: "latest"
          },
          "pmd" => {
            name: "PMD",
            status: "active",
            description: "Java static code analyzer",
            features: %w[quality],
            version: "latest"
          },
          "checkstyle" => {
            name: "Checkstyle",
            status: "active",
            description: "Java code style checker",
            features: %w[style],
            version: "latest"
          }
        }
      }
    }.freeze

    def initialize(project_dir = Dir.pwd)
      @project_dir = project_dir
    end

    # Detect outdated tools in the project
    def detect_outdated_tools(language)
      outdated_tools = []

      language_map = TOOL_MODERNIZATION_MAP[language]
      return outdated_tools unless language_map

      outdated_definitions = language_map["outdated_tools"] || {}

      outdated_definitions.each do |tool_id, tool_info|
        next unless tool_detected?(tool_id, language)

        outdated_tools << {
          id: tool_id,
          name: tool_info[:name],
          status: tool_info[:status],
          reason: tool_info[:reason],
          modern_alternative: tool_info[:modern_alternative],
          migration_notes: tool_info[:migration_notes],
          detected_in: detect_tool_location(tool_id, language)
        }
      end

      outdated_tools
    end

    # Generate modernization recommendations
    def generate_modernization_recommendations(language)
      recommendations = []

      outdated_tools = detect_outdated_tools(language)

      outdated_tools.each do |tool|
        recommendation = {
          type: "tool_modernization",
          tool: tool[:name],
          status: tool[:status],
          reason: tool[:reason],
          modern_alternative: tool[:modern_alternative],
          migration_notes: tool[:migration_notes],
          priority: determine_migration_priority(tool),
          migration_steps: generate_migration_steps(tool, language),
          benefits: generate_migration_benefits(tool)
        }

        recommendations << recommendation
      end

      # Add general modernization recommendations
      recommendations.concat(generate_general_modernization_recommendations(language))

      recommendations
    end

    # Get modern tool recommendations for a language
    def get_modern_tool_recommendations(language)
      language_map = TOOL_MODERNIZATION_MAP[language]
      return [] unless language_map

      modern_tools = language_map["modern_tools"] || {}
      modern_tools.map do |tool_id, tool_info|
        {
          id: tool_id,
          name: tool_info[:name],
          status: tool_info[:status],
          description: tool_info[:description],
          features: tool_info[:features],
          version: tool_info[:version],
          installation_guide: generate_installation_guide(tool_id, language)
        }
      end
    end

    # Generate migration plan for outdated tools
    def generate_migration_plan(language)
      outdated_tools = detect_outdated_tools(language)

      return {message: "No outdated tools detected"} if outdated_tools.empty?

      plan = {
        language: language,
        outdated_tools: outdated_tools,
        migration_phases: [],
        timeline: estimate_migration_timeline(outdated_tools),
        risks: identify_migration_risks(outdated_tools),
        benefits: calculate_migration_benefits(outdated_tools)
      }

      # Generate migration phases
      plan[:migration_phases] = generate_migration_phases(outdated_tools, language)

      plan
    end

    # Check if a specific tool is outdated
    def tool_outdated?(tool_id, language)
      language_map = TOOL_MODERNIZATION_MAP[language]
      return false unless language_map

      outdated_tools = language_map["outdated_tools"] || {}
      outdated_tools.key?(tool_id)
    end

    # Get modern alternative for an outdated tool
    def get_modern_alternative(tool_id, language)
      language_map = TOOL_MODERNIZATION_MAP[language]
      return nil unless language_map

      outdated_tools = language_map["outdated_tools"] || {}
      outdated_tools.dig(tool_id, :modern_alternative)
    end

    private

    def tool_detected?(tool_id, language)
      case language
      when "ruby"
        detect_ruby_tool(tool_id)
      when "javascript"
        detect_javascript_tool(tool_id)
      when "python"
        detect_python_tool(tool_id)
      when "java"
        detect_java_tool(tool_id)
      else
        false
      end
    end

    def detect_ruby_tool(tool_id)
      case tool_id
      when "ruby-lint"
        # Check for ruby-lint gem in Gemfile
        gemfile_path = File.join(@project_dir, "Gemfile")
        return false unless File.exist?(gemfile_path)

        gemfile_content = File.read(gemfile_path)
        gemfile_content.include?("gem 'ruby-lint'") || gemfile_content.include?('gem "ruby-lint"')
      when "flay"
        # Check for flay gem in Gemfile
        gemfile_path = File.join(@project_dir, "Gemfile")
        return false unless File.exist?(gemfile_path)

        gemfile_content = File.read(gemfile_path)
        gemfile_content.include?("gem 'flay'") || gemfile_content.include?('gem "flay"')
      when "flog"
        # Check for flog gem in Gemfile
        gemfile_path = File.join(@project_dir, "Gemfile")
        return false unless File.exist?(gemfile_path)

        gemfile_content = File.read(gemfile_path)
        gemfile_content.include?("gem 'flog'") || gemfile_content.include?('gem "flog"')
      else
        false
      end
    end

    def detect_javascript_tool(tool_id)
      case tool_id
      when "jshint"
        # Check for jshint in package.json
        package_json_path = File.join(@project_dir, "package.json")
        return false unless File.exist?(package_json_path)

        package_json_content = File.read(package_json_path)
        package_json_content.include?('"jshint"')
      when "jslint"
        # Check for jslint in package.json
        package_json_path = File.join(@project_dir, "package.json")
        return false unless File.exist?(package_json_path)

        package_json_content = File.read(package_json_path)
        package_json_content.include?('"jslint"')
      when "coffeescript"
        # Check for coffeescript files or package
        coffee_files = Dir.glob(File.join(@project_dir, "**", "*.coffee"))
        return true if coffee_files.any?

        package_json_path = File.join(@project_dir, "package.json")
        if File.exist?(package_json_path)
          package_json_content = File.read(package_json_path)
          package_json_content.include?('"coffeescript"')
        else
          false
        end
      else
        false
      end
    end

    def detect_python_tool(tool_id)
      case tool_id
      when "pep8"
        # Check for pep8 in requirements or setup
        requirements_files = ["requirements.txt", "setup.py", "pyproject.toml"]
        requirements_files.each do |file|
          file_path = File.join(@project_dir, file)
          next unless File.exist?(file_path)

          content = File.read(file_path)
          return true if content.include?("pep8")
        end
        false
      when "pylint1"
        # Check for old pylint version
        requirements_files = ["requirements.txt", "setup.py", "pyproject.toml"]
        requirements_files.each do |file|
          file_path = File.join(@project_dir, file)
          next unless File.exist?(file_path)

          content = File.read(file_path)
          return true if /pylint[<>=]?\s*1\./.match?(content)
        end
        false
      else
        false
      end
    end

    def detect_java_tool(tool_id)
      case tool_id
      when "findbugs"
        # Check for findbugs in build files
        build_files = ["pom.xml", "build.gradle", "build.gradle.kts"]
        build_files.each do |file|
          file_path = File.join(@project_dir, file)
          next unless File.exist?(file_path)

          content = File.read(file_path)
          return true if content.include?("findbugs")
        end
        false
      when "pmd4"
        # Check for old PMD version
        build_files = ["pom.xml", "build.gradle", "build.gradle.kts"]
        build_files.each do |file|
          file_path = File.join(@project_dir, file)
          next unless File.exist?(file_path)

          content = File.read(file_path)
          return true if /pmd[<>=]?\s*4\./.match?(content)
        end
        false
      else
        false
      end
    end

    def detect_tool_location(tool_id, language)
      locations = []

      case language
      when "ruby"
        gemfile_path = File.join(@project_dir, "Gemfile")
        locations << "Gemfile" if File.exist?(gemfile_path)
      when "javascript"
        package_json_path = File.join(@project_dir, "package.json")
        locations << "package.json" if File.exist?(package_json_path)
      when "python"
        ["requirements.txt", "setup.py", "pyproject.toml"].each do |file|
          locations << file if File.exist?(File.join(@project_dir, file))
        end
      when "java"
        ["pom.xml", "build.gradle", "build.gradle.kts"].each do |file|
          locations << file if File.exist?(File.join(@project_dir, file))
        end
      end

      locations
    end

    def determine_migration_priority(tool)
      case tool[:status]
      when "deprecated"
        "high"
      when "limited"
        "medium"
      else
        "low"
      end
    end

    def generate_migration_steps(tool, language)
      case language
      when "ruby"
        generate_ruby_migration_steps(tool)
      when "javascript"
        generate_javascript_migration_steps(tool)
      when "python"
        generate_python_migration_steps(tool)
      when "java"
        generate_java_migration_steps(tool)
      else
        ["Consult documentation for migration steps"]
      end
    end

    def generate_ruby_migration_steps(tool)
      case tool[:id]
      when "ruby-lint"
        [
          "Remove ruby-lint gem from Gemfile",
          "Add rubocop gem to Gemfile",
          "Run bundle install",
          "Initialize RuboCop configuration: bundle exec rubocop --auto-gen-config",
          "Update CI/CD pipeline to use RuboCop",
          "Remove ruby-lint configuration files"
        ]
      when "flay"
        [
          "Remove flay gem from Gemfile",
          "Add reek gem to Gemfile",
          "Run bundle install",
          "Initialize Reek configuration: bundle exec reek --init",
          "Update CI/CD pipeline to use Reek",
          "Remove flay configuration files"
        ]
      else
        ["Remove outdated tool", "Install modern alternative", "Update configuration"]
      end
    end

    def generate_javascript_migration_steps(tool)
      case tool[:id]
      when "jshint"
        [
          "Remove jshint from package.json",
          "Install ESLint: npm install --save-dev eslint",
          "Initialize ESLint configuration: npx eslint --init",
          "Update .eslintrc to match JSHint rules",
          "Update CI/CD pipeline to use ESLint",
          "Remove .jshintrc configuration file"
        ]
      when "coffeescript"
        [
          "Convert .coffee files to .js files",
          "Update import/require statements",
          "Remove coffeescript dependency",
          "Update build scripts to handle .js files",
          "Update CI/CD pipeline",
          "Test converted code thoroughly"
        ]
      else
        ["Remove outdated tool", "Install modern alternative", "Update configuration"]
      end
    end

    def generate_python_migration_steps(tool)
      case tool[:id]
      when "pep8"
        [
          "Remove pep8 from requirements",
          "Install flake8: pip install flake8",
          "Create .flake8 configuration file",
          "Update CI/CD pipeline to use flake8",
          "Remove pep8 configuration files"
        ]
      when "pylint1"
        [
          "Update pylint to latest version",
          "Update requirements.txt or setup.py",
          "Review and update pylint configuration",
          "Test with new pylint version",
          "Update CI/CD pipeline if needed"
        ]
      else
        ["Remove outdated tool", "Install modern alternative", "Update configuration"]
      end
    end

    def generate_java_migration_steps(tool)
      case tool[:id]
      when "findbugs"
        [
          "Remove findbugs from build configuration",
          "Add spotbugs to build configuration",
          "Update build scripts and CI/CD pipeline",
          "Review and update configuration files",
          "Test with spotbugs"
        ]
      when "pmd4"
        [
          "Update PMD to latest version",
          "Update build configuration",
          "Review and update PMD rules",
          "Test with new PMD version",
          "Update CI/CD pipeline if needed"
        ]
      else
        ["Remove outdated tool", "Install modern alternative", "Update configuration"]
      end
    end

    def generate_migration_benefits(tool)
      benefits = []

      case tool[:modern_alternative]
      when "rubocop"
        benefits.concat(["Better performance", "More comprehensive analysis", "Active maintenance", "Large community"])
      when "eslint"
        benefits.concat(["Better configurability", "Plugin ecosystem", "Active maintenance", "TypeScript support"])
      when "flake8"
        benefits.concat(["Includes PEP8 checking", "Additional features", "Better Python 3 support",
          "Active maintenance"])
      when "spotbugs"
        benefits.concat(["Java 8+ support", "Active maintenance", "Better performance", "Modern Java features"])
      end

      benefits
    end

    def generate_general_modernization_recommendations(language)
      recommendations = []

      case language
      when "ruby"
        recommendations << {
          type: "general_modernization",
          title: "Ruby Tool Modernization",
          description: "Consider modernizing your Ruby development tools",
          recommendations: [
            "Use RuboCop for code style and quality",
            "Use Reek for code smell detection",
            "Use Brakeman for security scanning",
            "Consider using Bundler for dependency management",
            "Use RSpec for testing"
          ]
        }
      when "javascript"
        recommendations << {
          type: "general_modernization",
          title: "JavaScript Tool Modernization",
          description: "Consider modernizing your JavaScript development tools",
          recommendations: [
            "Use ESLint for linting",
            "Use Prettier for code formatting",
            "Consider TypeScript for type safety",
            "Use modern JavaScript features (ES6+)",
            "Use Jest for testing"
          ]
        }
      end

      recommendations
    end

    def estimate_migration_timeline(outdated_tools)
      total_effort = outdated_tools.sum { |tool| get_migration_effort(tool) }

      case total_effort
      when 0..2
        "1-2 days"
      when 3..5
        "3-5 days"
      when 6..10
        "1-2 weeks"
      else
        "2+ weeks"
      end
    end

    def get_migration_effort(tool)
      case tool[:id]
      when "coffeescript"
        5 # High effort - requires code conversion
      when "ruby-lint", "jshint", "pep8"
        2 # Medium effort - configuration changes
      else
        1 # Low effort - simple replacement
      end
    end

    def identify_migration_risks(outdated_tools)
      risks = []

      outdated_tools.each do |tool|
        case tool[:id]
        when "coffeescript"
          risks << "Code conversion may introduce bugs"
        when "ruby-lint"
          risks << "Different rule sets may require code changes"
        when "jshint"
          risks << "ESLint may have different default rules"
        end
      end

      risks
    end

    def calculate_migration_benefits(outdated_tools)
      benefits = []

      outdated_tools.each do |tool|
        benefits.concat(generate_migration_benefits(tool))
      end

      benefits.uniq
    end

    def generate_migration_phases(outdated_tools, language)
      phases = []

      # Phase 1: Low-risk migrations
      low_risk_tools = outdated_tools.select { |tool| get_migration_effort(tool) <= 2 }
      if low_risk_tools.any?
        phases << {
          phase: 1,
          name: "Low-Risk Tool Migration",
          tools: low_risk_tools,
          duration: "1-3 days",
          risk: "low"
        }
      end

      # Phase 2: High-risk migrations
      high_risk_tools = outdated_tools.select { |tool| get_migration_effort(tool) > 2 }
      if high_risk_tools.any?
        phases << {
          phase: 2,
          name: "High-Risk Tool Migration",
          tools: high_risk_tools,
          duration: "1-2 weeks",
          risk: "high"
        }
      end

      phases
    end

    def generate_installation_guide(tool_id, language)
      case language
      when "ruby"
        case tool_id
        when "rubocop"
          "Add 'gem \"rubocop\"' to Gemfile and run bundle install"
        when "reek"
          "Add 'gem \"reek\"' to Gemfile and run bundle install"
        when "brakeman"
          "Add 'gem \"brakeman\"' to Gemfile and run bundle install"
        end
      when "javascript"
        case tool_id
        when "eslint"
          "npm install --save-dev eslint"
        when "prettier"
          "npm install --save-dev prettier"
        when "typescript"
          "npm install --save-dev typescript"
        end
      when "python"
        case tool_id
        when "flake8"
          "pip install flake8"
        when "black"
          "pip install black"
        when "mypy"
          "pip install mypy"
        end
      else
        "Consult tool documentation for installation instructions"
      end
    end
  end
end
