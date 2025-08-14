# frozen_string_literal: true

require "yaml"
require "json"
require "fileutils"

module Aidp
  class ToolConfiguration
    # Default configuration file names
    USER_CONFIG_FILE = File.expand_path("~/.aidp-tools.yml")
    PROJECT_CONFIG_FILE = ".aidp-tools.yml"

    # Default preferred tools by language
    DEFAULT_PREFERRED_TOOLS = {
      "ruby" => {
        "style" => "rubocop",
        "security" => "brakeman",
        "dependencies" => "bundler-audit",
        "quality" => "reek",
        "performance" => "fasterer"
      },
      "javascript" => {
        "style" => "eslint",
        "formatting" => "prettier",
        "security" => "npm-audit",
        "quality" => "eslint"
      },
      "python" => {
        "style" => "flake8",
        "security" => "bandit",
        "quality" => "pylint"
      },
      "java" => {
        "style" => "checkstyle",
        "quality" => "pmd",
        "security" => "spotbugs"
      },
      "go" => {
        "style" => "golangci-lint",
        "security" => "gosec",
        "quality" => "golangci-lint"
      },
      "rust" => {
        "style" => "clippy",
        "security" => "cargo-audit",
        "quality" => "clippy"
      }
    }.freeze

    def initialize(project_dir = Dir.pwd)
      @project_dir = project_dir
      @user_config = load_user_config
      @project_config = load_project_config
    end

    # Get preferred tools for a specific language and category
    def get_preferred_tools(language, category = nil)
      # Priority: project config > user config > defaults
      project_tools = @project_config.dig("preferred_tools", language) || {}
      user_tools = @user_config.dig("preferred_tools", language) || {}
      default_tools = DEFAULT_PREFERRED_TOOLS[language] || {}

      if category
        project_tools[category] || user_tools[category] || default_tools[category]
      else
        # Merge all configurations with project taking precedence
        default_tools.merge(user_tools).merge(project_tools)

      end
    end

    # Get all preferred tools for a language
    def get_all_preferred_tools(language)
      get_preferred_tools(language)
    end

    # Set preferred tool for a language and category
    def set_preferred_tool(language, category, tool_name, scope = :project)
      case scope
      when :project
        set_project_preferred_tool(language, category, tool_name)
      when :user
        set_user_preferred_tool(language, category, tool_name)
      else
        raise ArgumentError, "Invalid scope: #{scope}. Use :project or :user"
      end
    end

    # Get tool configuration (settings, options, etc.)
    def get_tool_config(tool_name, language = nil)
      # Priority: project config > user config > defaults
      project_tool_config = @project_config.dig("tool_configs", tool_name) || {}
      user_tool_config = @user_config.dig("tool_configs", tool_name) || {}

      merged_config = user_tool_config.merge(project_tool_config)

      # Add language-specific defaults if available
      if language && DEFAULT_PREFERRED_TOOLS[language]
        merged_config
      else
        merged_config
      end
    end

    # Set tool configuration
    def set_tool_config(tool_name, config, scope = :project)
      case scope
      when :project
        set_project_tool_config(tool_name, config)
      when :user
        set_user_tool_config(tool_name, config)
      else
        raise ArgumentError, "Invalid scope: #{scope}. Use :project or :user"
      end
    end

    # Get execution settings (timeout, parallel execution, etc.)
    def get_execution_settings
      # Priority: project config > user config > defaults
      project_settings = @project_config["execution_settings"] || {}
      user_settings = @user_config["execution_settings"] || {}

      default_settings = {
        "timeout" => 300, # 5 minutes
        "parallel_execution" => true,
        "max_parallel_jobs" => 4,
        "retry_failed" => true,
        "max_retries" => 2
      }

      default_settings.merge(user_settings).merge(project_settings)
    end

    # Set execution settings
    def set_execution_settings(settings, scope = :project)
      case scope
      when :project
        set_project_execution_settings(settings)
      when :user
        set_user_execution_settings(settings)
      else
        raise ArgumentError, "Invalid scope: #{scope}. Use :project or :user"
      end
    end

    # Get tool execution order for a language
    def get_tool_execution_order(language)
      # Priority: project config > user config > defaults
      project_order = @project_config.dig("execution_order", language) || []
      user_order = @user_config.dig("execution_order", language) || []

      if project_order.any?
        project_order
      elsif user_order.any?
        user_order
      else
        # Default order based on tool categories
        default_order = []
        tools = get_preferred_tools(language)

        # Order by category priority
        category_priority = %w[security dependencies quality style formatting performance]
        category_priority.each do |category|
          default_order << tools[category] if tools[category]
        end

        default_order
      end
    end

    # Set tool execution order for a language
    def set_tool_execution_order(language, order, scope = :project)
      case scope
      when :project
        set_project_execution_order(language, order)
      when :user
        set_user_execution_order(language, order)
      else
        raise ArgumentError, "Invalid scope: #{scope}. Use :project or :user"
      end
    end

    # Get tool integration settings (CI/CD, IDE integration, etc.)
    def get_integration_settings
      project_integrations = @project_config["integrations"] || {}
      user_integrations = @user_config["integrations"] || {}

      default_integrations = {
        "ci_cd" => {
          "enabled" => true,
          "fail_on_errors" => true,
          "fail_on_warnings" => false
        },
        "ide" => {
          "enabled" => true,
          "auto_fix" => false,
          "show_warnings" => true
        },
        "git_hooks" => {
          "enabled" => false,
          "pre_commit" => false,
          "pre_push" => false
        }
      }

      default_integrations.merge(user_integrations).merge(project_integrations)
    end

    # Set integration settings
    def set_integration_settings(integrations, scope = :project)
      case scope
      when :project
        set_project_integration_settings(integrations)
      when :user
        set_user_integration_settings(integrations)
      else
        raise ArgumentError, "Invalid scope: #{scope}. Use :project or :user"
      end
    end

    # Initialize default configuration files
    def initialize_config_files
      initialize_user_config unless File.exist?(USER_CONFIG_FILE)
      initialize_project_config unless File.exist?(project_config_path)
    end

    # Export configuration to different formats
    def export_config(format = :yaml, scope = :project)
      config_data = case scope
      when :project
        @project_config
      when :user
        @user_config
      when :merged
        merge_configurations
      else
        raise ArgumentError, "Invalid scope: #{scope}"
      end

      case format
      when :yaml
        config_data.to_yaml
      when :json
        config_data.to_json
      when :ruby
        config_data.inspect
      else
        raise ArgumentError, "Invalid format: #{format}"
      end
    end

    # Import configuration from file
    def import_config(file_path, scope = :project)
      return false unless File.exist?(file_path)

      begin
        config_data = case File.extname(file_path)
        when ".yml", ".yaml"
          YAML.load_file(file_path)
        when ".json"
          JSON.parse(File.read(file_path))
        else
          raise ArgumentError, "Unsupported file format: #{File.extname(file_path)}"
        end

        case scope
        when :project
          @project_config = config_data
          save_project_config
        when :user
          @user_config = config_data
          save_user_config
        else
          raise ArgumentError, "Invalid scope: #{scope}"
        end

        true
      rescue => e
        warn "Failed to import configuration: #{e.message}"
        false
      end
    end

    # Validate configuration
    def validate_config
      errors = []

      # Validate user config
      errors.concat(validate_config_structure(@user_config, "user"))

      # Validate project config
      errors.concat(validate_config_structure(@project_config, "project"))

      errors
    end

    private

    def load_user_config
      return {} unless File.exist?(USER_CONFIG_FILE)

      begin
        YAML.load_file(USER_CONFIG_FILE) || {}
      rescue => e
        warn "Failed to load user config: #{e.message}"
        {}
      end
    end

    def load_project_config
      config_path = project_config_path
      return {} unless File.exist?(config_path)

      begin
        YAML.load_file(config_path) || {}
      rescue => e
        warn "Failed to load project config: #{e.message}"
        {}
      end
    end

    def project_config_path
      File.join(@project_dir, PROJECT_CONFIG_FILE)
    end

    def set_project_preferred_tool(language, category, tool_name)
      @project_config["preferred_tools"] ||= {}
      @project_config["preferred_tools"][language] ||= {}
      @project_config["preferred_tools"][language][category] = tool_name
      save_project_config
    end

    def set_user_preferred_tool(language, category, tool_name)
      @user_config["preferred_tools"] ||= {}
      @user_config["preferred_tools"][language] ||= {}
      @user_config["preferred_tools"][language][category] = tool_name
      save_user_config
    end

    def set_project_tool_config(tool_name, config)
      @project_config["tool_configs"] ||= {}
      @project_config["tool_configs"][tool_name] = config
      save_project_config
    end

    def set_user_tool_config(tool_name, config)
      @user_config["tool_configs"] ||= {}
      @user_config["tool_configs"][tool_name] = config
      save_user_config
    end

    def set_project_execution_settings(settings)
      @project_config["execution_settings"] = settings
      save_project_config
    end

    def set_user_execution_settings(settings)
      @user_config["execution_settings"] = settings
      save_user_config
    end

    def set_project_execution_order(language, order)
      @project_config["execution_order"] ||= {}
      @project_config["execution_order"][language] = order
      save_project_config
    end

    def set_user_execution_order(language, order)
      @user_config["execution_order"] ||= {}
      @user_config["execution_order"][language] = order
      save_user_config
    end

    def set_project_integration_settings(integrations)
      @project_config["integrations"] = integrations
      save_project_config
    end

    def set_user_integration_settings(integrations)
      @user_config["integrations"] = integrations
      save_user_config
    end

    def save_user_config
      FileUtils.mkdir_p(File.dirname(USER_CONFIG_FILE))
      File.write(USER_CONFIG_FILE, @user_config.to_yaml)
    end

    def save_project_config
      File.write(project_config_path, @project_config.to_yaml)
    end

    def initialize_user_config
      default_user_config = {
        "preferred_tools" => DEFAULT_PREFERRED_TOOLS,
        "execution_settings" => {
          "timeout" => 300,
          "parallel_execution" => true,
          "max_parallel_jobs" => 4
        },
        "integrations" => {
          "ci_cd" => {"enabled" => true},
          "ide" => {"enabled" => true}
        }
      }

      @user_config = default_user_config
      save_user_config
    end

    def initialize_project_config
      default_project_config = {
        "preferred_tools" => {},
        "execution_settings" => {},
        "integrations" => {}
      }

      @project_config = default_project_config
      save_project_config
    end

    def merge_configurations
      merged = @user_config.dup

      # Merge project config with user config
      @project_config.each do |key, value|
        merged[key] = if merged[key].is_a?(Hash) && value.is_a?(Hash)
          merged[key].merge(value)
        else
          value
        end
      end

      merged
    end

    def validate_config_structure(config, config_name)
      errors = []

      # Validate preferred_tools structure
      if config["preferred_tools"] && !config["preferred_tools"].is_a?(Hash)
        errors << "#{config_name} config: preferred_tools must be a hash"
      end

      # Validate execution_settings structure
      if config["execution_settings"] && !config["execution_settings"].is_a?(Hash)
        errors << "#{config_name} config: execution_settings must be a hash"
      end

      # Validate integrations structure
      if config["integrations"] && !config["integrations"].is_a?(Hash)
        errors << "#{config_name} config: integrations must be a hash"
      end

      errors
    end
  end
end
