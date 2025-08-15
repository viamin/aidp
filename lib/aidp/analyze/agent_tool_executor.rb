# frozen_string_literal: true

require "open3"
require "json"
require "timeout"

module Aidp
  class AgentToolExecutor
    # Default timeout for tool execution (5 minutes)
    DEFAULT_TIMEOUT = 300

    # Default environment variables for tool execution
    DEFAULT_ENV = {
      "LANG" => "en_US.UTF-8",
      "LC_ALL" => "en_US.UTF-8"
    }.freeze

    def initialize(project_dir = Dir.pwd, config = {})
      @project_dir = project_dir
      @config = config
      @timeout = config[:timeout] || DEFAULT_TIMEOUT
      @env = DEFAULT_ENV.merge(config[:env] || {})
      @execution_log = []
    end

    # Execute a static analysis tool
    def execute_tool(tool_name, options = {})
      execution_id = generate_execution_id
      start_time = Time.now

      log_execution_start(execution_id, tool_name, options)

      begin
        result = execute_tool_with_timeout(tool_name, options)
        execution_time = Time.now - start_time

        log_execution_success(execution_id, tool_name, execution_time, result)
        result
      rescue => e
        execution_time = Time.now - start_time
        log_execution_error(execution_id, tool_name, execution_time, e)
        raise
      end
    end

    # Execute multiple tools in parallel
    def execute_tools_parallel(tools, options = {})
      results = {}
      threads = []

      tools.each do |tool_name, tool_options|
        thread = Thread.new do
          results[tool_name] = execute_tool(tool_name, tool_options)
        rescue => e
          results[tool_name] = {error: e.message, status: "failed"}
        end
        threads << thread
      end

      # Wait for all threads to complete
      threads.each(&:join)

      results
    end

    # Execute tools in sequence based on dependencies
    def execute_tools_sequence(tools, dependencies = {})
      results = {}
      executed = Set.new

      tools.each do |tool_name|
        # Check if dependencies are satisfied
        tool_deps = dependencies[tool_name] || []
        unless tool_deps.all? { |dep| executed.include?(dep) }
          raise "Dependencies not satisfied for #{tool_name}: #{tool_deps}"
        end

        results[tool_name] = execute_tool(tool_name)
        executed.add(tool_name)
      end

      results
    end

    # Get tool execution status
    def get_execution_status(execution_id)
      execution = @execution_log.find { |log| log[:execution_id] == execution_id }
      return nil unless execution

      {
        execution_id: execution_id,
        tool_name: execution[:tool_name],
        status: execution[:status],
        start_time: execution[:start_time],
        end_time: execution[:end_time],
        duration: execution[:duration],
        error: execution[:error]
      }
    end

    # Get execution history
    def get_execution_history(limit = 50)
      @execution_log.last(limit).map do |log|
        {
          execution_id: log[:execution_id],
          tool_name: log[:tool_name],
          status: log[:status],
          start_time: log[:start_time],
          duration: log[:duration],
          error: log[:error]
        }
      end
    end

    # Validate tool configuration
    def validate_tool_config(tool_name, options = {})
      errors = []

      # Check if tool is available
      errors << "Tool '#{tool_name}' is not available" unless tool_available?(tool_name)

      # Validate tool-specific options
      tool_errors = validate_tool_options(tool_name, options)
      errors.concat(tool_errors)

      errors
    end

    # Get available tools
    def get_available_tools
      available_tools = []

      # Check for Ruby tools
      available_tools.concat(check_ruby_tools) if ruby_project?

      # Check for JavaScript tools
      available_tools.concat(check_javascript_tools) if javascript_project?

      # Check for Python tools
      available_tools.concat(check_python_tools) if python_project?

      # Check for Java tools
      available_tools.concat(check_java_tools) if java_project?

      # Check for Go tools
      available_tools.concat(check_go_tools) if go_project?

      # Check for Rust tools
      available_tools.concat(check_rust_tools) if rust_project?

      available_tools
    end

    # Get tool execution statistics
    def get_execution_statistics
      return {} if @execution_log.empty?

      total_executions = @execution_log.length
      successful_executions = @execution_log.count { |log| log[:status] == "success" }
      failed_executions = @execution_log.count { |log| log[:status] == "error" }

      average_duration = @execution_log.sum { |log| log[:duration] || 0 } / total_executions

      {
        total_executions: total_executions,
        successful_executions: successful_executions,
        failed_executions: failed_executions,
        success_rate: (successful_executions.to_f / total_executions * 100).round(2),
        average_duration: average_duration.round(2),
        tools_used: @execution_log.map { |log| log[:tool_name] }.uniq
      }
    end

    private

    def execute_tool_with_timeout(tool_name, options)
      command = build_tool_command(tool_name, options)
      working_dir = options[:working_dir] || @project_dir

      Timeout.timeout(@timeout) do
        execute_command(command, working_dir, options)
      end
    end

    def execute_command(command, working_dir, options)
      stdout, stderr, status = Open3.capture3(@env, command, chdir: working_dir)

      {
        command: command,
        stdout: stdout,
        stderr: stderr,
        exit_code: status.exitstatus,
        success: status.success?,
        working_dir: working_dir,
        options: options
      }
    end

    def build_tool_command(tool_name, options)
      case tool_name
      when "rubocop"
        build_rubocop_command(options)
      when "reek"
        build_reek_command(options)
      when "brakeman"
        build_brakeman_command(options)
      when "bundler-audit"
        build_bundler_audit_command(options)
      when "eslint"
        build_eslint_command(options)
      when "flake8"
        build_flake8_command(options)
      when "bandit"
        build_bandit_command(options)
      when "golangci-lint"
        build_golangci_lint_command(options)
      when "clippy"
        build_clippy_command(options)
      else
        # Generic command building
        build_generic_command(tool_name, options)
      end
    end

    def build_rubocop_command(options)
      command = "bundle exec rubocop"
      command += " --format #{options[:format] || "json"}"
      command += " --out #{options[:output_file]}" if options[:output_file]
      command += " #{options[:paths] || "."}"
      command
    end

    def build_reek_command(options)
      command = "bundle exec reek"
      command += " --format #{options[:format] || "json"}"
      command += " --output #{options[:output_file]}" if options[:output_file]
      command += " #{options[:paths] || "."}"
      command
    end

    def build_brakeman_command(options)
      command = "bundle exec brakeman"
      command += " --format #{options[:format] || "json"}"
      command += " --output #{options[:output_file]}" if options[:output_file]
      command += " --quiet" if options[:quiet]
      command
    end

    def build_bundler_audit_command(options)
      command = "bundle exec bundle-audit"
      command += " --output #{options[:output_file]}" if options[:output_file]
      command += " --update" if options[:update]
      command
    end

    def build_eslint_command(options)
      command = "npx eslint"
      command += " --format #{options[:format] || "json"}"
      command += " --output-file #{options[:output_file]}" if options[:output_file]
      command += " #{options[:paths] || "."}"
      command
    end

    def build_flake8_command(options)
      command = "flake8"
      command += " --format #{options[:format] || "json"}"
      command += " --output-file #{options[:output_file]}" if options[:output_file]
      command += " #{options[:paths] || "."}"
      command
    end

    def build_bandit_command(options)
      command = "bandit"
      command += " -f #{options[:format] || "json"}"
      command += " -o #{options[:output_file]}" if options[:output_file]
      command += " -r #{options[:paths] || "."}"
      command
    end

    def build_golangci_lint_command(options)
      command = "golangci-lint run"
      command += " --out-format #{options[:format] || "json"}"
      command += " --out #{options[:output_file]}" if options[:output_file]
      command += " #{options[:paths] || "."}"
      command
    end

    def build_clippy_command(options)
      command = "cargo clippy"
      command += " --message-format #{options[:format] || "json"}"
      command += " --output-file #{options[:output_file]}" if options[:output_file]
      command
    end

    def build_generic_command(tool_name, options)
      command = tool_name
      command += " #{options[:args]}" if options[:args]
      command += " #{options[:paths] || "."}" unless options[:args]&.include?(".")
      command
    end

    def tool_available?(tool_name)
      case tool_name
      when /^bundle exec/
        # Ruby tool - check if bundle is available
        system("bundle", "--version", out: File::NULL, err: File::NULL)
      when /^npx/
        # Node.js tool - check if npm is available
        system("npm", "--version", out: File::NULL, err: File::NULL)
      when /^cargo/
        # Rust tool - check if cargo is available
        system("cargo", "--version", out: File::NULL, err: File::NULL)
      when /^go/
        # Go tool - check if go is available
        system("go", "version", out: File::NULL, err: File::NULL)
      else
        # Generic tool - check if command is available
        system("which", tool_name.split(" ").first, out: File::NULL, err: File::NULL)
      end
    end

    def validate_tool_options(tool_name, options)
      errors = []

      case tool_name
      when "rubocop"
        errors << "Invalid format" unless %w[json text html].include?(options[:format])
      when "eslint"
        errors << "Invalid format" unless %w[json text html].include?(options[:format])
      when "flake8"
        errors << "Invalid format" unless %w[json text html].include?(options[:format])
      end

      errors
    end

    def ruby_project?
      File.exist?(File.join(@project_dir, "Gemfile"))
    end

    def javascript_project?
      File.exist?(File.join(@project_dir, "package.json"))
    end

    def python_project?
      File.exist?(File.join(@project_dir, "requirements.txt")) || File.exist?(File.join(@project_dir, "setup.py"))
    end

    def java_project?
      File.exist?(File.join(@project_dir, "pom.xml")) || File.exist?(File.join(@project_dir, "build.gradle"))
    end

    def go_project?
      File.exist?(File.join(@project_dir, "go.mod"))
    end

    def rust_project?
      File.exist?(File.join(@project_dir, "Cargo.toml"))
    end

    def check_ruby_tools
      tools = []
      tools << "rubocop" if system("bundle", "exec", "rubocop", "--version", out: File::NULL, err: File::NULL)
      tools << "reek" if system("bundle", "exec", "reek", "--version", out: File::NULL, err: File::NULL)
      tools << "brakeman" if system("bundle", "exec", "brakeman", "--version", out: File::NULL, err: File::NULL)
      tools << "bundler-audit" if system("bundle", "exec", "bundle-audit", "--version", out: File::NULL,
        err: File::NULL)
      tools
    end

    def check_javascript_tools
      tools = []
      tools << "eslint" if system("npx", "eslint", "--version", out: File::NULL, err: File::NULL)
      tools << "prettier" if system("npx", "prettier", "--version", out: File::NULL, err: File::NULL)
      tools
    end

    def check_python_tools
      tools = []
      tools << "flake8" if system("flake8", "--version", out: File::NULL, err: File::NULL)
      tools << "bandit" if system("bandit", "--version", out: File::NULL, err: File::NULL)
      tools
    end

    def check_java_tools
      tools = []
      # Java tools typically require specific setup, so we'll check for common ones
      tools << "checkstyle" if File.exist?(File.join(@project_dir, "checkstyle.xml"))
      tools << "pmd" if File.exist?(File.join(@project_dir, "pmd.xml"))
      tools
    end

    def check_go_tools
      tools = []
      tools << "golangci-lint" if system("golangci-lint", "--version", out: File::NULL, err: File::NULL)
      tools << "gosec" if system("gosec", "--version", out: File::NULL, err: File::NULL)
      tools
    end

    def check_rust_tools
      tools = []
      tools << "clippy" if system("cargo", "clippy", "--version", out: File::NULL, err: File::NULL)
      tools << "cargo-audit" if system("cargo", "audit", "--version", out: File::NULL, err: File::NULL)
      tools
    end

    def generate_execution_id
      "exec_#{Time.now.to_i}_#{rand(1000)}"
    end

    def log_execution_start(execution_id, tool_name, options)
      @execution_log << {
        execution_id: execution_id,
        tool_name: tool_name,
        status: "running",
        start_time: Time.now,
        options: options
      }
    end

    def log_execution_success(execution_id, tool_name, duration, result)
      log_entry = @execution_log.find { |log| log[:execution_id] == execution_id }
      return unless log_entry

      log_entry.merge!(
        status: "success",
        end_time: Time.now,
        duration: duration,
        result: result
      )
    end

    def log_execution_error(execution_id, tool_name, duration, error)
      log_entry = @execution_log.find { |log| log[:execution_id] == execution_id }
      return unless log_entry

      log_entry.merge!(
        status: "error",
        end_time: Time.now,
        duration: duration,
        error: error.message
      )
    end
  end
end
