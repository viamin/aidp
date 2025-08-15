# frozen_string_literal: true

require "fileutils"

module Aidp
  class StaticAnalysisDetector
    # Define static analysis tools by language/framework
    STATIC_ANALYSIS_TOOLS = {
      "ruby" => {
        "rubocop" => {
          name: "RuboCop",
          description: "Ruby static code analyzer and formatter",
          config_files: [".rubocop.yml", ".rubocop.yaml", ".rubocop.json"],
          gem_name: "rubocop",
          command: "bundle exec rubocop",
          categories: %w[style quality],
          priority: "high"
        },
        "reek" => {
          name: "Reek",
          description: "Code smell detector for Ruby",
          config_files: [".reek.yml", ".reek.yaml"],
          gem_name: "reek",
          command: "bundle exec reek",
          categories: %w[quality smells],
          priority: "medium"
        },
        "brakeman" => {
          name: "Brakeman",
          description: "Security vulnerability scanner for Ruby on Rails",
          config_files: ["config/brakeman.yml"],
          gem_name: "brakeman",
          command: "bundle exec brakeman",
          categories: %w[security],
          priority: "high"
        },
        "bundler-audit" => {
          name: "Bundler Audit",
          description: "Security vulnerability scanner for Ruby gems",
          gem_name: "bundler-audit",
          command: "bundle exec bundle-audit",
          categories: %w[security],
          priority: "high"
        },
        "fasterer" => {
          name: "Fasterer",
          description: "Performance optimization suggestions for Ruby",
          gem_name: "fasterer",
          command: "bundle exec fasterer",
          categories: %w[performance],
          priority: "medium"
        }
      },
      "javascript" => {
        "eslint" => {
          name: "ESLint",
          description: "JavaScript linting utility",
          config_files: [".eslintrc.js", ".eslintrc.json", ".eslintrc.yml", ".eslintrc.yaml"],
          package_name: "eslint",
          command: "npx eslint",
          categories: %w[style quality],
          priority: "high"
        },
        "prettier" => {
          name: "Prettier",
          description: "Code formatter for JavaScript",
          config_files: [".prettierrc", ".prettierrc.js", ".prettierrc.json"],
          package_name: "prettier",
          command: "npx prettier --check",
          categories: %w[style],
          priority: "medium"
        },
        "sonarqube" => {
          name: "SonarQube",
          description: "Code quality and security analysis platform",
          config_files: ["sonar-project.properties"],
          categories: %w[quality security],
          priority: "high"
        }
      },
      "python" => {
        "flake8" => {
          name: "Flake8",
          description: "Python linting utility",
          config_files: [".flake8", "setup.cfg", "tox.ini"],
          package_name: "flake8",
          command: "flake8",
          categories: %w[style quality],
          priority: "high"
        },
        "pylint" => {
          name: "Pylint",
          description: "Python code analysis tool",
          config_files: [".pylintrc", "pylintrc"],
          package_name: "pylint",
          command: "pylint",
          categories: %w[quality],
          priority: "medium"
        },
        "bandit" => {
          name: "Bandit",
          description: "Security linter for Python",
          config_files: [".bandit"],
          package_name: "bandit",
          command: "bandit",
          categories: %w[security],
          priority: "high"
        }
      },
      "java" => {
        "checkstyle" => {
          name: "Checkstyle",
          description: "Java code style checker",
          config_files: ["checkstyle.xml", "config/checkstyle.xml"],
          categories: %w[style],
          priority: "medium"
        },
        "pmd" => {
          name: "PMD",
          description: "Java static code analyzer",
          config_files: ["pmd.xml", "config/pmd.xml"],
          categories: %w[quality],
          priority: "medium"
        },
        "spotbugs" => {
          name: "SpotBugs",
          description: "Java bug finder",
          categories: %w[quality bugs],
          priority: "high"
        }
      },
      "go" => {
        "golangci-lint" => {
          name: "golangci-lint",
          description: "Fast Go linters runner",
          config_files: [".golangci.yml", ".golangci.yaml"],
          categories: %w[style quality],
          priority: "high"
        },
        "gosec" => {
          name: "Gosec",
          description: "Go security linter",
          categories: %w[security],
          priority: "high"
        }
      },
      "rust" => {
        "clippy" => {
          name: "Clippy",
          description: "Rust linter",
          command: "cargo clippy",
          categories: %w[style quality],
          priority: "high"
        },
        "cargo-audit" => {
          name: "Cargo Audit",
          description: "Rust security vulnerability scanner",
          command: "cargo audit",
          categories: %w[security],
          priority: "high"
        }
      }
    }.freeze

    def initialize(project_dir = Dir.pwd)
      @project_dir = project_dir
    end

    # Detect all static analysis tools in the project
    def detect_static_analysis_tools
      project_type = detect_project_type
      language = project_type[:language]

      {
        installed: detect_installed_tools(language),
        configured: detect_configured_tools(language),
        missing: detect_missing_tools(language),
        recommendations: generate_tool_recommendations(language)
      }
    end

    # Detect tools that are installed and available
    def detect_installed_tools(language)
      installed_tools = []

      tools = STATIC_ANALYSIS_TOOLS[language] || {}
      tools.each do |tool_id, tool_info|
        next unless tool_installed?(tool_id, tool_info)

        installed_tools << {
          id: tool_id,
          name: tool_info[:name],
          description: tool_info[:description],
          command: tool_info[:command],
          categories: tool_info[:categories],
          priority: tool_info[:priority],
          status: "installed"
        }
      end

      installed_tools
    end

    # Detect tools that have configuration files but may not be installed
    def detect_configured_tools(language)
      configured_tools = []

      tools = STATIC_ANALYSIS_TOOLS[language] || {}
      tools.each do |tool_id, tool_info|
        next unless tool_configured?(tool_id, tool_info)

        configured_tools << {
          id: tool_id,
          name: tool_info[:name],
          description: tool_info[:description],
          config_files: tool_info[:config_files],
          categories: tool_info[:categories],
          priority: tool_info[:priority],
          status: "configured"
        }
      end

      configured_tools
    end

    # Detect missing tools that should be installed
    def detect_missing_tools(language)
      missing_tools = []

      tools = STATIC_ANALYSIS_TOOLS[language] || {}
      tools.each do |tool_id, tool_info|
        next if tool_installed?(tool_id, tool_info) || tool_configured?(tool_id, tool_info)

        missing_tools << {
          id: tool_id,
          name: tool_info[:name],
          description: tool_info[:description],
          categories: tool_info[:categories],
          priority: tool_info[:priority],
          status: "missing"
        }
      end

      missing_tools
    end

    # Generate recommendations for tool installation
    def generate_tool_recommendations(language)
      recommendations = []

      # Get missing high-priority tools
      missing_tools = detect_missing_tools(language)
      high_priority_missing = missing_tools.select { |tool| tool[:priority] == "high" }

      high_priority_missing.each do |tool|
        recommendation = generate_installation_recommendation(tool, language)
        recommendations << recommendation if recommendation
      end

      # Add general recommendations
      recommendations.concat(generate_general_recommendations(language))

      recommendations
    end

    # Check if a tool is installed and available
    def tool_installed?(tool_id, tool_info)
      case tool_info[:command]
      when /^bundle exec/
        # Ruby tool - check if gem is available
        gem_name = tool_info[:gem_name]
        return false unless gem_name

        # Check if gem is in Gemfile
        gemfile_path = File.join(@project_dir, "Gemfile")
        return false unless File.exist?(gemfile_path)

        gemfile_content = File.read(gemfile_path)
        gemfile_content.include?("gem '#{gem_name}'") || gemfile_content.include?("gem \"#{gem_name}\"")
      when /^npx/
        # Node.js tool - check if package is available
        package_name = tool_info[:package_name]
        return false unless package_name

        package_json_path = File.join(@project_dir, "package.json")
        return false unless File.exist?(package_json_path)

        package_json_content = File.read(package_json_path)
        package_json_content.include?("\"#{package_name}\"")
      when /^cargo/
        # Rust tool - check if cargo is available
        system("cargo", "--version", out: File::NULL, err: File::NULL)
      else
        # Generic tool - check if command is available
        command = tool_info[:command]&.split(" ")&.first
        return false unless command

        system("which", command, out: File::NULL, err: File::NULL)
      end
    end

    # Check if a tool has configuration files
    def tool_configured?(tool_id, tool_info)
      config_files = tool_info[:config_files] || []
      return false if config_files.empty?

      config_files.any? do |config_file|
        File.exist?(File.join(@project_dir, config_file))
      end
    end

    # Detect the primary language/framework of the project
    def detect_project_type
      # Check for Ruby project
      if File.exist?(File.join(@project_dir, "Gemfile"))
        return {language: "ruby", framework: "rails"} if File.exist?(File.join(@project_dir, "config",
          "application.rb"))
        return {language: "ruby", framework: "sinatra"} if File.exist?(File.join(@project_dir, "app.rb"))
        return {language: "ruby", framework: "gem"} if File.exist?(File.join(@project_dir, "*.gemspec"))

        return {language: "ruby", framework: "unknown"}
      end

      # Check for JavaScript/Node.js project
      if File.exist?(File.join(@project_dir, "package.json"))
        package_json = JSON.parse(File.read(File.join(@project_dir, "package.json")))
        dependencies = package_json["dependencies"] || {}
        dev_dependencies = package_json["devDependencies"] || {}

        if dependencies["react"] || dev_dependencies["react"]
          return {language: "javascript", framework: "react"}
        elsif dependencies["vue"] || dev_dependencies["vue"]
          return {language: "javascript", framework: "vue"}
        elsif dependencies["angular"] || dev_dependencies["angular"]
          return {language: "javascript", framework: "angular"}
        else
          return {language: "javascript", framework: "node"}
        end
      end

      # Check for Python project
      if File.exist?(File.join(@project_dir, "requirements.txt")) || File.exist?(File.join(@project_dir, "setup.py"))
        return {language: "python", framework: "unknown"}
      end

      # Check for Java project
      if File.exist?(File.join(@project_dir, "pom.xml")) || File.exist?(File.join(@project_dir, "build.gradle"))
        return {language: "java", framework: "unknown"}
      end

      # Check for Go project
      return {language: "go", framework: "unknown"} if File.exist?(File.join(@project_dir, "go.mod"))

      # Check for Rust project
      return {language: "rust", framework: "unknown"} if File.exist?(File.join(@project_dir, "Cargo.toml"))

      # Default to unknown
      {language: "unknown", framework: "unknown"}
    end

    # Generate installation recommendation for a specific tool
    def generate_installation_recommendation(tool, language)
      case language
      when "ruby"
        generate_ruby_installation_recommendation(tool)
      when "javascript"
        generate_javascript_installation_recommendation(tool)
      when "python"
        generate_python_installation_recommendation(tool)
      when "java"
        generate_java_installation_recommendation(tool)
      when "go"
        generate_go_installation_recommendation(tool)
      when "rust"
        generate_rust_installation_recommendation(tool)
      end
    end

    # Generate general recommendations for the language
    def generate_general_recommendations(language)
      recommendations = []

      case language
      when "ruby"
        recommendations << {
          type: "general",
          title: "Ruby Static Analysis Setup",
          description: "Consider setting up a comprehensive Ruby static analysis pipeline",
          steps: [
            "Add RuboCop for code style and quality",
            "Add Brakeman for security scanning",
            "Add Bundler Audit for dependency security",
            "Configure tools in CI/CD pipeline"
          ],
          priority: "high"
        }
      when "javascript"
        recommendations << {
          type: "general",
          title: "JavaScript Static Analysis Setup",
          description: "Consider setting up a comprehensive JavaScript static analysis pipeline",
          steps: [
            "Add ESLint for code quality",
            "Add Prettier for code formatting",
            "Add security scanning tools",
            "Configure tools in CI/CD pipeline"
          ],
          priority: "high"
        }
      end

      recommendations
    end

    private

    def generate_ruby_installation_recommendation(tool)
      case tool[:id]
      when "rubocop"
        {
          type: "installation",
          tool: tool[:name],
          description: "Install RuboCop for Ruby code analysis",
          steps: [
            "Add 'gem \"rubocop\"' to Gemfile",
            "Run bundle install",
            "Initialize configuration: bundle exec rubocop --auto-gen-config",
            "Run analysis: bundle exec rubocop"
          ],
          priority: tool[:priority]
        }
      when "brakeman"
        {
          type: "installation",
          tool: tool[:name],
          description: "Install Brakeman for Rails security scanning",
          steps: [
            "Add 'gem \"brakeman\"' to Gemfile",
            "Run bundle install",
            "Run security scan: bundle exec brakeman"
          ],
          priority: tool[:priority]
        }
      when "bundler-audit"
        {
          type: "installation",
          tool: tool[:name],
          description: "Install Bundler Audit for gem security scanning",
          steps: [
            "Add 'gem \"bundler-audit\"' to Gemfile",
            "Run bundle install",
            "Run security audit: bundle exec bundle-audit"
          ],
          priority: tool[:priority]
        }
      end
    end

    def generate_javascript_installation_recommendation(tool)
      case tool[:id]
      when "eslint"
        {
          type: "installation",
          tool: tool[:name],
          description: "Install ESLint for JavaScript linting",
          steps: [
            "npm install --save-dev eslint",
            "npx eslint --init",
            "Run linting: npx eslint ."
          ],
          priority: tool[:priority]
        }
      when "prettier"
        {
          type: "installation",
          tool: tool[:name],
          description: "Install Prettier for JavaScript formatting",
          steps: [
            "npm install --save-dev prettier",
            "Create .prettierrc configuration",
            "Run formatting: npx prettier --write ."
          ],
          priority: tool[:priority]
        }
      end
    end

    def generate_python_installation_recommendation(tool)
      case tool[:id]
      when "flake8"
        {
          type: "installation",
          tool: tool[:name],
          description: "Install Flake8 for Python linting",
          steps: [
            "pip install flake8",
            "Create .flake8 configuration",
            "Run linting: flake8 ."
          ],
          priority: tool[:priority]
        }
      when "bandit"
        {
          type: "installation",
          tool: tool[:name],
          description: "Install Bandit for Python security scanning",
          steps: [
            "pip install bandit",
            "Run security scan: bandit -r ."
          ],
          priority: tool[:priority]
        }
      end
    end

    def generate_java_installation_recommendation(tool)
      case tool[:id]
      when "checkstyle"
        {
          type: "installation",
          tool: tool[:name],
          description: "Install Checkstyle for Java code style checking",
          steps: [
            "Download Checkstyle JAR",
            "Create checkstyle.xml configuration",
            "Run analysis: java -jar checkstyle.jar -c checkstyle.xml src/"
          ],
          priority: tool[:priority]
        }
      end
    end

    def generate_go_installation_recommendation(tool)
      case tool[:id]
      when "golangci-lint"
        {
          type: "installation",
          tool: tool[:name],
          description: "Install golangci-lint for Go linting",
          steps: [
            "go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest",
            "Create .golangci.yml configuration",
            "Run linting: golangci-lint run"
          ],
          priority: tool[:priority]
        }
      end
    end

    def generate_rust_installation_recommendation(tool)
      case tool[:id]
      when "clippy"
        {
          type: "installation",
          tool: tool[:name],
          description: "Clippy is included with Rust toolchain",
          steps: [
            "Run linting: cargo clippy",
            "Run with warnings as errors: cargo clippy -- -D warnings"
          ],
          priority: tool[:priority]
        }
      when "cargo-audit"
        {
          type: "installation",
          tool: tool[:name],
          description: "Install cargo-audit for Rust security scanning",
          steps: [
            "cargo install cargo-audit",
            "Run security audit: cargo audit"
          ],
          priority: tool[:priority]
        }
      end
    end
  end
end
