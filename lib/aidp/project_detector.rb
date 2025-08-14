# frozen_string_literal: true

require "fileutils"

module Aidp
  class ProjectDetector
    def initialize(project_dir = Dir.pwd)
      @project_dir = project_dir
    end

    # Detect the primary language and framework of the project
    def detect_project_type
      {
        language: detect_language,
        framework: detect_framework,
        build_system: detect_build_system,
        package_manager: detect_package_manager,
        static_analysis_tools: detect_static_analysis_tools,
        project_structure: analyze_project_structure,
        build_configuration: detect_build_configuration,
        deployment_configuration: detect_deployment_configuration
      }
    end

    # Detect the primary programming language
    def detect_language
      file_counts = count_files_by_extension

      # Return the language with the most files
      return "unknown" if file_counts.empty?

      primary_extension = file_counts.max_by { |_, count| count }[0]
      extension_to_language(primary_extension)
    end

    # Detect the framework being used
    def detect_framework
      return "rails" if rails_project?
      return "sinatra" if sinatra_project?
      return "node" if node_project?
      return "react" if react_project?
      return "vue" if vue_project?
      return "angular" if angular_project?
      return "django" if django_project?
      return "flask" if flask_project?
      return "spring" if spring_project?
      return "express" if express_project?
      return "fastapi" if fastapi_project?

      "unknown"
    end

    # Detect the build system
    def detect_build_system
      return "bundler" if File.exist?(File.join(@project_dir, "Gemfile"))
      return "npm" if File.exist?(File.join(@project_dir, "package.json"))
      return "maven" if File.exist?(File.join(@project_dir, "pom.xml"))
      return "gradle" if File.exist?(File.join(@project_dir, "build.gradle"))
      return "pip" if File.exist?(File.join(@project_dir, "requirements.txt"))
      return "poetry" if File.exist?(File.join(@project_dir, "pyproject.toml"))
      return "cargo" if File.exist?(File.join(@project_dir, "Cargo.toml"))
      return "go_modules" if File.exist?(File.join(@project_dir, "go.mod"))

      "unknown"
    end

    # Detect the package manager
    def detect_package_manager
      return "bundler" if File.exist?(File.join(@project_dir, "Gemfile.lock"))
      return "npm" if File.exist?(File.join(@project_dir, "package-lock.json"))
      return "yarn" if File.exist?(File.join(@project_dir, "yarn.lock"))
      return "pnpm" if File.exist?(File.join(@project_dir, "pnpm-lock.yaml"))
      return "maven" if File.exist?(File.join(@project_dir, "pom.xml"))
      return "gradle" if File.exist?(File.join(@project_dir, "build.gradle"))
      return "pip" if File.exist?(File.join(@project_dir, "requirements.txt"))
      return "poetry" if File.exist?(File.join(@project_dir, "poetry.lock"))
      return "cargo" if File.exist?(File.join(@project_dir, "Cargo.lock"))
      return "go" if File.exist?(File.join(@project_dir, "go.sum"))

      "unknown"
    end

    # Detect existing static analysis tools
    def detect_static_analysis_tools
      tools = []

      # Ruby tools
      tools << "rubocop" if File.exist?(File.join(@project_dir, ".rubocop.yml"))
      tools << "reek" if File.exist?(File.join(@project_dir, ".reek"))
      tools << "brakeman" if File.exist?(File.join(@project_dir, "brakeman.yml"))

      # JavaScript/TypeScript tools
      tools << "eslint" if File.exist?(File.join(@project_dir, ".eslintrc"))
      tools << "prettier" if File.exist?(File.join(@project_dir, ".prettierrc"))
      tools << "typescript" if File.exist?(File.join(@project_dir, "tsconfig.json"))

      # Python tools
      tools << "flake8" if File.exist?(File.join(@project_dir, ".flake8"))
      tools << "pylint" if File.exist?(File.join(@project_dir, ".pylintrc"))
      tools << "mypy" if File.exist?(File.join(@project_dir, "mypy.ini"))

      # Java tools
      tools << "checkstyle" if File.exist?(File.join(@project_dir, "checkstyle.xml"))
      tools << "spotbugs" if File.exist?(File.join(@project_dir, "spotbugs.xml"))

      # General tools
      tools << "sonarqube" if File.exist?(File.join(@project_dir, "sonar-project.properties"))
      tools << "codeclimate" if File.exist?(File.join(@project_dir, ".codeclimate.yml"))

      tools
    end

    # Analyze the project structure
    def analyze_project_structure
      structure = {
        has_tests: has_test_directory?,
        has_docs: has_documentation?,
        has_config: has_config_files?,
        has_scripts: has_scripts_directory?,
        has_docker: has_docker_files?,
        has_ci: has_ci_configuration?,
        directories: get_main_directories
      }

      structure[:structure_type] = determine_structure_type(structure)
      structure
    end

    # Get recommended static analysis tools for the detected language/framework
    def get_recommended_tools
      language = detect_language
      framework = detect_framework

      recommendations = {
        language: language,
        framework: framework,
        tools: []
      }

      case language
      when "ruby"
        recommendations[:tools] = %w[rubocop reek brakeman bundler-audit]
      when "javascript"
        recommendations[:tools] = %w[eslint prettier sonarqube]
      when "typescript"
        recommendations[:tools] = %w[eslint prettier typescript-eslint sonarqube]
      when "python"
        recommendations[:tools] = %w[flake8 pylint mypy bandit]
      when "java"
        recommendations[:tools] = %w[checkstyle spotbugs pmd sonarqube]
      when "go"
        recommendations[:tools] = %w[golangci-lint staticcheck govet]
      when "rust"
        recommendations[:tools] = %w[clippy rustfmt cargo-audit]
      end

      # Add framework-specific tools
      case framework
      when "rails"
        recommendations[:tools] += %w[brakeman bundler-audit]
      when "react"
        recommendations[:tools] += %w[react-hooks jsx-a11y]
      when "django"
        recommendations[:tools] += ["django-check"]
      end

      recommendations[:tools].uniq
    end

    private

    def count_files_by_extension
      extensions = {}

      Dir.glob(File.join(@project_dir, "**", "*")).each do |file|
        next unless File.file?(file)
        next if file.include?(".git/") || file.include?("node_modules/") || file.include?("vendor/")

        ext = File.extname(file)
        extensions[ext] ||= 0
        extensions[ext] += 1
      end

      extensions
    end

    def extension_to_language(extension)
      case extension.downcase
      when ".rb"
        "ruby"
      when ".js", ".jsx"
        "javascript"
      when ".ts", ".tsx"
        "typescript"
      when ".py"
        "python"
      when ".java"
        "java"
      when ".go"
        "go"
      when ".rs"
        "rust"
      when ".php"
        "php"
      when ".cs"
        "csharp"
      when ".cpp", ".cc", ".cxx"
        "cpp"
      when ".c"
        "c"
      when ".swift"
        "swift"
      when ".kt"
        "kotlin"
      when ".scala"
        "scala"
      when ".clj"
        "clojure"
      when ".hs"
        "haskell"
      when ".ml"
        "ocaml"
      when ".fs"
        "fsharp"
      else
        "unknown"
      end
    end

    def rails_project?
      File.exist?(File.join(@project_dir, "config", "application.rb")) &&
        File.exist?(File.join(@project_dir, "Gemfile")) &&
        File.exist?(File.join(@project_dir, "config", "routes.rb"))
    end

    def sinatra_project?
      File.exist?(File.join(@project_dir, "app.rb")) &&
        File.read(File.join(@project_dir, "app.rb")).include?("Sinatra")
    end

    def node_project?
      File.exist?(File.join(@project_dir, "package.json"))
    end

    def react_project?
      return false unless node_project?

      package_json = File.read(File.join(@project_dir, "package.json"))
      package_json.include?("react") || package_json.include?("@types/react")
    end

    def vue_project?
      return false unless node_project?

      package_json = File.read(File.join(@project_dir, "package.json"))
      package_json.include?("vue")
    end

    def angular_project?
      return false unless node_project?

      package_json = File.read(File.join(@project_dir, "package.json"))
      package_json.include?("@angular")
    end

    def django_project?
      File.exist?(File.join(@project_dir, "manage.py")) &&
        Dir.exist?(File.join(@project_dir, "settings.py"))
    end

    def flask_project?
      File.exist?(File.join(@project_dir, "app.py")) &&
        File.read(File.join(@project_dir, "app.py")).include?("Flask")
    end

    def spring_project?
      File.exist?(File.join(@project_dir, "pom.xml")) &&
        File.read(File.join(@project_dir, "pom.xml")).include?("spring-boot")
    end

    def express_project?
      return false unless node_project?

      package_json = File.read(File.join(@project_dir, "package.json"))
      package_json.include?("express")
    end

    def fastapi_project?
      File.exist?(File.join(@project_dir, "main.py")) &&
        File.read(File.join(@project_dir, "main.py")).include?("FastAPI")
    end

    def has_test_directory?
      test_dirs = ["test", "tests", "spec", "specs", "__tests__", "test_*"]
      test_dirs.any? { |dir| Dir.exist?(File.join(@project_dir, dir)) }
    end

    def has_documentation?
      doc_files = ["README.md", "README.txt", "docs/", "documentation/"]
      doc_files.any? { |file| File.exist?(File.join(@project_dir, file)) }
    end

    def has_config_files?
      config_files = [".env", "config.yml", "config.yaml", "config.json", "settings.py"]
      config_files.any? { |file| File.exist?(File.join(@project_dir, file)) }
    end

    def has_scripts_directory?
      Dir.exist?(File.join(@project_dir, "scripts")) || Dir.exist?(File.join(@project_dir, "bin"))
    end

    def has_docker_files?
      docker_files = ["Dockerfile", "docker-compose.yml", "docker-compose.yaml"]
      docker_files.any? { |file| File.exist?(File.join(@project_dir, file)) }
    end

    def has_ci_configuration?
      ci_files = [".github/workflows/", ".gitlab-ci.yml", ".travis.yml", ".circleci/"]
      ci_files.any? { |file| File.exist?(File.join(@project_dir, file)) }
    end

    def get_main_directories
      Dir.entries(@project_dir)
        .select { |entry| Dir.exist?(File.join(@project_dir, entry)) }
        .reject { |entry| entry.start_with?(".") || entry == "node_modules" || entry == "vendor" }
    end

    def determine_structure_type(structure)
      if structure[:has_tests] && structure[:has_docs] && structure[:has_config]
        "well_organized"
      elsif structure[:has_tests] && structure[:has_config]
        "standard"
      elsif structure[:has_tests]
        "basic"
      else
        "minimal"
      end
    end

    # Detect build configuration and settings
    def detect_build_configuration
      build_config = {}

      # Detect build tools and their configurations
      build_system = detect_build_system

      case build_system
      when "maven"
        build_config = detect_maven_configuration
      when "gradle"
        build_config = detect_gradle_configuration
      when "npm"
        build_config = detect_npm_configuration
      when "yarn"
        build_config = detect_yarn_configuration
      when "bundler"
        build_config = detect_bundler_configuration
      when "cargo"
        build_config = detect_cargo_configuration
      when "go_modules"
        build_config = detect_go_configuration
      when "pip"
        build_config = detect_pip_configuration
      when "poetry"
        build_config = detect_poetry_configuration
      end

      build_config
    end

    # Detect deployment configuration
    def detect_deployment_configuration
      deployment_config = {}

      # Detect deployment platforms and configurations
      deployment_files = [
        "Dockerfile", "docker-compose.yml", "docker-compose.yaml",
        ".github/workflows/", ".gitlab-ci.yml", "Jenkinsfile",
        "deploy.yml", "deploy.yaml", "deployment.yml",
        "kubernetes/", "k8s/", "helm/",
        "terraform/", "ansible/", "puppet/",
        "Heroku", "vercel.json", "netlify.toml"
      ]

      deployment_files.each do |file|
        deployment_config[file] = true if File.exist?(File.join(@project_dir, file))
      end

      # Detect specific deployment platforms
      deployment_config[:platforms] = detect_deployment_platforms

      deployment_config
    end

    private

    def detect_maven_configuration
      config = {}

      pom_xml = File.join(@project_dir, "pom.xml")
      if File.exist?(pom_xml)
        config[:build_file] = "pom.xml"
        config[:has_tests] = Dir.exist?(File.join(@project_dir, "src/test"))
        config[:has_integration_tests] = Dir.exist?(File.join(@project_dir, "src/it"))
        config[:has_web_resources] = Dir.exist?(File.join(@project_dir, "src/main/webapp"))
      end

      config
    end

    def detect_gradle_configuration
      config = {}

      gradle_files = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
      gradle_files.each do |file|
        if File.exist?(File.join(@project_dir, file))
          config[:build_file] = file
          break
        end
      end

      config[:has_tests] = Dir.exist?(File.join(@project_dir, "src/test"))
      config[:has_integration_tests] = Dir.exist?(File.join(@project_dir, "src/integrationTest"))

      config
    end

    def detect_npm_configuration
      config = {}

      package_json = File.join(@project_dir, "package.json")
      if File.exist?(package_json)
        config[:build_file] = "package.json"

        # Parse package.json for scripts and dependencies
        begin
          package_data = JSON.parse(File.read(package_json))
          config[:scripts] = package_data["scripts"] || {}
          config[:dependencies] = package_data["dependencies"] || {}
          config[:dev_dependencies] = package_data["devDependencies"] || {}
          config[:has_tests] = config[:scripts].key?("test")
          config[:has_build] = config[:scripts].key?("build")
        rescue JSON::ParserError
          # Handle invalid JSON
        end
      end

      config
    end

    def detect_yarn_configuration
      config = {}

      yarn_lock = File.join(@project_dir, "yarn.lock")
      if File.exist?(yarn_lock)
        config[:package_manager] = "yarn"
        config[:lock_file] = "yarn.lock"
      end

      # Also check package.json
      npm_config = detect_npm_configuration
      config.merge!(npm_config)

      config
    end

    def detect_bundler_configuration
      config = {}

      gemfile = File.join(@project_dir, "Gemfile")
      if File.exist?(gemfile)
        config[:build_file] = "Gemfile"
        config[:lock_file] = "Gemfile.lock" if File.exist?(File.join(@project_dir, "Gemfile.lock"))

        # Parse Gemfile for groups and gems
        gemfile_content = File.read(gemfile)
        config[:has_test_group] = gemfile_content.include?("group :test")
        config[:has_development_group] = gemfile_content.include?("group :development")
        config[:has_production_group] = gemfile_content.include?("group :production")
      end

      config
    end

    def detect_cargo_configuration
      config = {}

      cargo_toml = File.join(@project_dir, "Cargo.toml")
      if File.exist?(cargo_toml)
        config[:build_file] = "Cargo.toml"
        config[:lock_file] = "Cargo.lock" if File.exist?(File.join(@project_dir, "Cargo.lock"))

        # Parse Cargo.toml for dependencies and features
        begin
          cargo_content = File.read(cargo_toml)
          config[:has_dev_dependencies] = cargo_content.include?("[dev-dependencies]")
          config[:has_features] = cargo_content.include?("[features]")
        rescue
          # Handle parsing errors
        end
      end

      config
    end

    def detect_go_configuration
      config = {}

      go_mod = File.join(@project_dir, "go.mod")
      if File.exist?(go_mod)
        config[:build_file] = "go.mod"
        config[:lock_file] = "go.sum" if File.exist?(File.join(@project_dir, "go.sum"))

        # Parse go.mod for module name and dependencies
        begin
          go_mod_content = File.read(go_mod)
          config[:module_name] = go_mod_content.match(/^module\s+(.+)$/)&.[](1)
          config[:go_version] = go_mod_content.match(/^go\s+(.+)$/)&.[](1)
        rescue
          # Handle parsing errors
        end
      end

      config
    end

    def detect_pip_configuration
      config = {}

      requirements_files = ["requirements.txt", "requirements-dev.txt", "requirements-test.txt"]
      requirements_files.each do |file|
        if File.exist?(File.join(@project_dir, file))
          config[:requirements_files] ||= []
          config[:requirements_files] << file
        end
      end

      setup_py = File.join(@project_dir, "setup.py")
      config[:build_file] = "setup.py" if File.exist?(setup_py)

      pyproject_toml = File.join(@project_dir, "pyproject.toml")
      config[:build_file] = "pyproject.toml" if File.exist?(pyproject_toml)

      config
    end

    def detect_poetry_configuration
      config = {}

      pyproject_toml = File.join(@project_dir, "pyproject.toml")
      if File.exist?(pyproject_toml)
        config[:build_file] = "pyproject.toml"
        config[:lock_file] = "poetry.lock" if File.exist?(File.join(@project_dir, "poetry.lock"))

        # Parse pyproject.toml for Poetry configuration
        begin
          pyproject_content = File.read(pyproject_toml)
          config[:has_dev_dependencies] = pyproject_content.include?("[tool.poetry.group.dev.dependencies]")
          config[:has_test_dependencies] = pyproject_content.include?("[tool.poetry.group.test.dependencies]")
        rescue
          # Handle parsing errors
        end
      end

      config
    end

    def detect_deployment_platforms
      platforms = []

      # Detect various deployment platforms
      platforms << "docker" if File.exist?(File.join(@project_dir, "Dockerfile"))

      platforms << "github_actions" if Dir.exist?(File.join(@project_dir, ".github/workflows"))

      platforms << "gitlab_ci" if File.exist?(File.join(@project_dir, ".gitlab-ci.yml"))

      platforms << "jenkins" if File.exist?(File.join(@project_dir, "Jenkinsfile"))

      if Dir.exist?(File.join(@project_dir, "kubernetes")) || Dir.exist?(File.join(@project_dir, "k8s"))
        platforms << "kubernetes"
      end

      platforms << "terraform" if Dir.exist?(File.join(@project_dir, "terraform"))

      platforms << "vercel" if File.exist?(File.join(@project_dir, "vercel.json"))

      platforms << "netlify" if File.exist?(File.join(@project_dir, "netlify.toml"))

      platforms << "heroku" if File.exist?(File.join(@project_dir, "Heroku"))

      platforms
    end
  end
end
