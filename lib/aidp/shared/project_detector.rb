# frozen_string_literal: true

require "json"
require "yaml"

module Aidp
  module Shared
    # Detects project type, language, framework, and other characteristics
    class ProjectDetector
      attr_reader :project_dir

      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
      end

      def detect
        {
          language: detect_language,
          framework: detect_framework,
          build_system: detect_build_system,
          package_manager: detect_package_manager,
          static_analysis_tools: detect_static_analysis_tools,
          test_framework: detect_test_framework,
          database: detect_database,
          deployment: detect_deployment
        }
      end

      private

      def detect_language
        return "ruby" if File.exist?(File.join(@project_dir, "Gemfile"))
        return "javascript" if File.exist?(File.join(@project_dir, "package.json"))
        return "python" if File.exist?(File.join(@project_dir, "requirements.txt")) || File.exist?(File.join(@project_dir, "pyproject.toml"))
        return "java" if File.exist?(File.join(@project_dir, "pom.xml")) || File.exist?(File.join(@project_dir, "build.gradle"))
        return "go" if File.exist?(File.join(@project_dir, "go.mod"))
        return "rust" if File.exist?(File.join(@project_dir, "Cargo.toml"))
        return "csharp" if File.exist?(File.join(@project_dir, "*.csproj"))
        "unknown"
      end

      def detect_framework
        case detect_language
        when "ruby"
          return "rails" if File.exist?(File.join(@project_dir, "config", "application.rb"))
          return "sinatra" if File.exist?(File.join(@project_dir, "app.rb")) && File.read(File.join(@project_dir, "app.rb")).include?("Sinatra")
        when "javascript"
          return "react" if File.exist?(File.join(@project_dir, "package.json")) && File.read(File.join(@project_dir, "package.json")).include?("react")
          return "vue" if File.exist?(File.join(@project_dir, "package.json")) && File.read(File.join(@project_dir, "package.json")).include?("vue")
          return "angular" if File.exist?(File.join(@project_dir, "angular.json"))
          return "express" if File.exist?(File.join(@project_dir, "package.json")) && File.read(File.join(@project_dir, "package.json")).include?("express")
        when "python"
          return "django" if File.exist?(File.join(@project_dir, "manage.py"))
          return "flask" if File.exist?(File.join(@project_dir, "app.py")) && File.read(File.join(@project_dir, "app.py")).include?("Flask")
        when "java"
          return "spring" if File.exist?(File.join(@project_dir, "pom.xml")) && File.read(File.join(@project_dir, "pom.xml")).include?("spring-boot")
        end
        "unknown"
      end

      def detect_build_system
        return "maven" if File.exist?(File.join(@project_dir, "pom.xml"))
        return "gradle" if File.exist?(File.join(@project_dir, "build.gradle"))
        return "npm" if File.exist?(File.join(@project_dir, "package.json"))
        return "bundler" if File.exist?(File.join(@project_dir, "Gemfile"))
        return "pip" if File.exist?(File.join(@project_dir, "requirements.txt"))
        return "cargo" if File.exist?(File.join(@project_dir, "Cargo.toml"))
        return "go" if File.exist?(File.join(@project_dir, "go.mod"))
        "unknown"
      end

      def detect_package_manager
        detect_build_system
      end

      def detect_static_analysis_tools
        tools = []
        tools << "rubocop" if File.exist?(File.join(@project_dir, ".rubocop.yml"))
        tools << "eslint" if File.exist?(File.join(@project_dir, ".eslintrc"))
        tools << "flake8" if File.exist?(File.join(@project_dir, ".flake8"))
        tools << "checkstyle" if File.exist?(File.join(@project_dir, "checkstyle.xml"))
        tools << "clippy" if File.exist?(File.join(@project_dir, "Cargo.toml"))
        tools
      end

      def detect_test_framework
        case detect_language
        when "ruby"
          return "rspec" if File.exist?(File.join(@project_dir, "spec"))
          return "minitest" if File.exist?(File.join(@project_dir, "test"))
        when "javascript"
          return "jest" if File.exist?(File.join(@project_dir, "package.json")) && File.read(File.join(@project_dir, "package.json")).include?("jest")
          return "mocha" if File.exist?(File.join(@project_dir, "package.json")) && File.read(File.join(@project_dir, "package.json")).include?("mocha")
        when "python"
          return "pytest" if File.exist?(File.join(@project_dir, "pytest.ini"))
          return "unittest" if Dir.exist?(File.join(@project_dir, "tests"))
        when "java"
          return "junit" if File.exist?(File.join(@project_dir, "src", "test"))
        end
        "unknown"
      end

      def detect_database
        return "postgresql" if File.exist?(File.join(@project_dir, "config", "database.yml")) && File.read(File.join(@project_dir, "config", "database.yml")).include?("postgresql")
        return "mysql" if File.exist?(File.join(@project_dir, "config", "database.yml")) && File.read(File.join(@project_dir, "config", "database.yml")).include?("mysql")
        return "sqlite" if File.exist?(File.join(@project_dir, "config", "database.yml")) && File.read(File.join(@project_dir, "config", "database.yml")).include?("sqlite")
        "unknown"
      end

      def detect_deployment
        return "docker" if File.exist?(File.join(@project_dir, "Dockerfile"))
        return "kubernetes" if File.exist?(File.join(@project_dir, "k8s")) || File.exist?(File.join(@project_dir, "kubernetes"))
        return "heroku" if File.exist?(File.join(@project_dir, "Procfile"))
        return "aws" if File.exist?(File.join(@project_dir, "serverless.yml")) || File.exist?(File.join(@project_dir, "template.yaml"))
        "unknown"
      end
    end
  end
end
