# frozen_string_literal: true

module Aidp
  module Harness
    # Checks completion criteria for the workflow
    class CompletionChecker
      def initialize(project_dir, workflow_type = :exploration)
        @project_dir = project_dir
        @workflow_type = workflow_type
        @completion_results = {}
      end

      # Check if all completion criteria are met
      def all_criteria_met?
        criteria = completion_criteria

        criteria.all? do |criterion, checker|
          result = send(checker)
          @completion_results[criterion] = result
          result
        end
      end

      # Get completion criteria based on workflow type
      def completion_criteria
        base_criteria = {
          steps_completed: :all_steps_completed?,
          tests_passing: :tests_passing?,
          linting_clean: :linting_clean?
        }

        if @workflow_type == :full
          base_criteria.merge({
            build_successful: :build_successful?,
            documentation_complete: :documentation_complete?
          })
        else
          base_criteria
        end
      end

      # Get completion status report
      def completion_status
        all_criteria_met? # This populates @completion_results

        {
          all_complete: @completion_results.values.all?,
          criteria: @completion_results,
          summary: generate_summary
        }
      end

      private

      def all_steps_completed?
        # This will be checked by the harness runner
        true
      end

      def tests_passing?
        return true unless has_tests?

        # Check common test commands
        test_commands = detect_test_commands
        return true if test_commands.empty?

        test_commands.any? { |cmd| run_project_command(cmd) }
      end

      def linting_clean?
        lint_commands = detect_lint_commands
        return true if lint_commands.empty?

        lint_commands.all? { |cmd| run_project_command(cmd) }
      end

      def build_successful?
        build_commands = detect_build_commands
        return true if build_commands.empty?

        build_commands.any? { |cmd| run_project_command(cmd) }
      end

      # Run a detected command in the project directory. The command line is
      # tokenized with Shellwords and executed in argument form, so the shell
      # never interprets the library-provided command string. The [cmdname,
      # argv0] pair forces argument form even for a single-token command,
      # which system would otherwise execute via /bin/sh -c.
      def run_project_command(cmd)
        require "shellwords"
        argv = Shellwords.split(cmd).flat_map { |arg| expand_arg(arg) }
        return false if argv.empty?

        system([argv[0], argv[0]], *argv.drop(1), chdir: @project_dir, out: File::NULL, err: File::NULL)
      end

      # Expand shell-style glob tokens (e.g. test/**/*_test.rb) within the
      # project directory, since argument-form execution skips shell globbing.
      def expand_arg(arg)
        return [arg] unless arg.match?(/[*?\[{}]/)

        matches = Dir.chdir(@project_dir) { Dir.glob(arg) }
        matches.empty? ? [arg] : matches
      end

      def documentation_complete?
        # Check if key documentation files exist
        required_docs = %w[README.md docs/PRD.md]
        required_docs.all? { |doc| File.exist?(File.join(@project_dir, doc)) }
      end

      def has_tests?
        test_dirs = %w[test tests spec]
        test_files = %w[*_test.rb *_spec.rb test_*.rb]

        test_dirs.any? { |dir| Dir.exist?(File.join(@project_dir, dir)) } ||
          test_files.any? { |pattern| Dir.glob(File.join(@project_dir, "**", pattern)).any? }
      end

      def detect_test_commands
        commands = []

        # Ruby
        if File.exist?(File.join(@project_dir, "Gemfile"))
          commands << "bundle exec rspec" if has_rspec?
          commands << "bundle exec rake test" if has_rake_test?
          commands << "ruby -Itest test/**/*_test.rb" if has_minitest?
        end

        # Node.js
        if File.exist?(File.join(@project_dir, "package.json"))
          package = begin
            JSON.parse(File.read(File.join(@project_dir, "package.json")))
          rescue
            {}
          end
          if package.dig("scripts", "test")
            commands << "npm test"
          end
        end

        # Python
        if File.exist?(File.join(@project_dir, "requirements.txt")) || File.exist?(File.join(@project_dir, "pyproject.toml"))
          commands << "pytest" if has_pytest?
          commands << "python -m unittest" if has_unittest?
        end

        commands
      end

      def detect_lint_commands
        commands = []

        # Ruby
        if File.exist?(File.join(@project_dir, "Gemfile"))
          commands << "bundle exec standardrb --no-fix" if has_standard?
          commands << "bundle exec rubocop" if has_rubocop?
        end

        # Node.js
        if File.exist?(File.join(@project_dir, "package.json"))
          package = begin
            JSON.parse(File.read(File.join(@project_dir, "package.json")))
          rescue
            {}
          end
          if package.dig("scripts", "lint")
            commands << "npm run lint"
          elsif has_eslint?
            commands << "npx eslint ."
          end
        end

        # Python
        if File.exist?(File.join(@project_dir, "requirements.txt")) || File.exist?(File.join(@project_dir, "pyproject.toml"))
          commands << "flake8 ." if has_flake8?
          commands << "black --check ." if has_black?
        end

        commands
      end

      def detect_build_commands
        commands = []

        # Ruby gem
        if File.exist?(File.join(@project_dir, "*.gemspec"))
          commands << "bundle exec rake build"
        end

        # Node.js
        if File.exist?(File.join(@project_dir, "package.json"))
          package = begin
            JSON.parse(File.read(File.join(@project_dir, "package.json")))
          rescue
            {}
          end
          if package.dig("scripts", "build")
            commands << "npm run build"
          end
        end

        # Python
        if File.exist?(File.join(@project_dir, "setup.py")) || File.exist?(File.join(@project_dir, "pyproject.toml"))
          commands << "python setup.py build" if File.exist?(File.join(@project_dir, "setup.py"))
          commands << "python -m build" if File.exist?(File.join(@project_dir, "pyproject.toml"))
        end

        commands
      end

      def has_rspec?
        gemfile_content = begin
          File.read(File.join(@project_dir, "Gemfile"))
        rescue
          ""
        end
        gemfile_content.include?("rspec") || Dir.exist?(File.join(@project_dir, "spec"))
      end

      def has_rake_test?
        File.exist?(File.join(@project_dir, "Rakefile")) && Dir.exist?(File.join(@project_dir, "test"))
      end

      def has_minitest?
        Dir.exist?(File.join(@project_dir, "test"))
      end

      def has_standard?
        gemfile_content = begin
          File.read(File.join(@project_dir, "Gemfile"))
        rescue
          ""
        end
        gemfile_content.include?("standard")
      end

      def has_rubocop?
        gemfile_content = begin
          File.read(File.join(@project_dir, "Gemfile"))
        rescue
          ""
        end
        gemfile_content.include?("rubocop")
      end

      def has_eslint?
        File.exist?(File.join(@project_dir, ".eslintrc")) ||
          File.exist?(File.join(@project_dir, ".eslintrc.js")) ||
          File.exist?(File.join(@project_dir, ".eslintrc.json"))
      end

      def has_pytest?
        File.exist?(File.join(@project_dir, "pytest.ini")) ||
          Dir.glob(File.join(@project_dir, "**", "*_test.py")).any?
      end

      def has_unittest?
        Dir.glob(File.join(@project_dir, "**", "test_*.py")).any?
      end

      def has_flake8?
        File.exist?(File.join(@project_dir, ".flake8")) ||
          File.exist?(File.join(@project_dir, "setup.cfg"))
      end

      def has_black?
        File.exist?(File.join(@project_dir, "pyproject.toml"))
      end

      def generate_summary
        passed = @completion_results.count { |_, result| result }
        total = @completion_results.size

        if passed == total
          "✅ All #{total} completion criteria met"
        else
          failed_criteria = @completion_results.select { |_, result| !result }.keys
          "❌ #{total - passed}/#{total} criteria failed: #{failed_criteria.join(", ")}"
        end
      end
    end
  end
end
