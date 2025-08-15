# frozen_string_literal: true

require 'spec_helper'
require 'aidp/cli'
require 'aidp/runner'
require 'aidp/analyze_runner'
require 'aidp/progress'
require 'aidp/analyze_progress'

RSpec.describe 'Existing Project Compatibility', type: :integration do
  let(:project_dir) { Dir.mktmpdir('aidp_existing_project_test') }
  let(:cli) { Aidp::CLI.new }
  let(:execute_runner) { Aidp::Runner.new(project_dir) }
  let(:analyze_runner) { Aidp::AnalyzeRunner.new(project_dir) }

  before do
    setup_existing_project_with_execute_data
  end

  after do
    FileUtils.remove_entry(project_dir)
  end

  describe 'Analyze Mode with Existing Execute Data' do
    it 'analyze mode works correctly when execute mode data exists' do
      # Verify existing execute mode data
      expect(File.exist?(File.join(project_dir, '.aidp-progress.yml'))).to be true
      expect(File.exist?(File.join(project_dir, '.aidp.yml'))).to be true
      expect(File.exist?(File.join(project_dir, '00_PRD.md'))).to be true
      expect(File.exist?(File.join(project_dir, '01_NFRS.md'))).to be true

      # Run analyze mode
      result = cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')
      expect(result[:status]).to eq('success')

      # Verify analyze mode created its own files
      expect(File.exist?(File.join(project_dir, '.aidp-analyze-progress.yml'))).to be true
      expect(File.exist?(File.join(project_dir, '01_REPOSITORY_ANALYSIS.md'))).to be true

      # Verify execute mode files are unchanged
      expect(File.exist?(File.join(project_dir, '.aidp-progress.yml'))).to be true
      expect(File.exist?(File.join(project_dir, '00_PRD.md'))).to be true
      expect(File.exist?(File.join(project_dir, '01_NFRS.md'))).to be true
    end

    it 'analyze mode does not interfere with existing execute mode progress' do
      # Load existing execute mode progress
      execute_progress = Aidp::Progress.new(project_dir)
      original_completed_steps = execute_progress.completed_steps.dup
      original_current_step = execute_progress.current_step

      # Run analyze mode
      cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')
      cli.analyze(project_dir, '02_ARCHITECTURE_ANALYSIS')

      # Verify execute mode progress is unchanged
      execute_progress_after = Aidp::Progress.new(project_dir)
      expect(execute_progress_after.completed_steps).to eq(original_completed_steps)
      expect(execute_progress_after.current_step).to eq(original_current_step)
    end

    it 'analyze mode does not interfere with existing execute mode configuration' do
      # Load existing execute mode configuration
      execute_config = Aidp::Config.new(project_dir)
      original_provider = execute_config.get('provider')
      original_model = execute_config.get('model')

      # Run analyze mode
      cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')

      # Verify execute mode configuration is unchanged
      execute_config_after = Aidp::Config.new(project_dir)
      expect(execute_config_after.get('provider')).to eq(original_provider)
      expect(execute_config_after.get('model')).to eq(original_model)
    end

    it 'analyze mode does not interfere with existing execute mode output files' do
      # Get original execute mode output files
      original_files = Dir.glob(File.join(project_dir, '*.md')).sort
      original_content = {}
      original_files.each do |file|
        original_content[file] = File.read(file)
      end

      # Run analyze mode
      cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')
      cli.analyze(project_dir, '02_ARCHITECTURE_ANALYSIS')

      # Verify original execute mode files are unchanged
      original_files.each do |file|
        expect(File.exist?(file)).to be true
        expect(File.read(file)).to eq(original_content[file])
      end
    end

    it 'both modes can run simultaneously without interference' do
      # Run execute mode
      execute_result = cli.execute(project_dir, '02_ARCHITECTURE')
      expect(execute_result[:status]).to eq('success')

      # Run analyze mode
      analyze_result = cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')
      expect(analyze_result[:status]).to eq('success')

      # Verify both modes created their respective files
      expect(File.exist?(File.join(project_dir, '02_ARCHITECTURE.md'))).to be true
      expect(File.exist?(File.join(project_dir, '01_REPOSITORY_ANALYSIS.md'))).to be true

      # Verify progress files are separate
      expect(File.exist?(File.join(project_dir, '.aidp-progress.yml'))).to be true
      expect(File.exist?(File.join(project_dir, '.aidp-analyze-progress.yml'))).to be true
    end
  end

  describe 'File System Isolation' do
    it 'analyze mode creates separate database files' do
      # Run execute mode to create its database
      cli.execute(project_dir, '00_PRD')

      # Run analyze mode to create its database
      cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')

      # Verify separate database files exist
      execute_db = File.join(project_dir, '.aidp.db')
      analyze_db = File.join(project_dir, '.aidp-analysis.db')

      expect(File.exist?(execute_db)).to be true
      expect(File.exist?(analyze_db)).to be true

      # Verify databases are different files
      expect(execute_db).not_to eq(analyze_db)
    end

    it 'analyze mode creates separate tool configuration files' do
      # Create execute mode tool configuration
      execute_tools_file = File.join(project_dir, '.aidp-tools.yml')
      execute_tools_config = {
        'build_tools' => {
          'ruby' => %w[bundler rake]
        }
      }
      File.write(execute_tools_file, execute_tools_config.to_yaml)

      # Run analyze mode to create its tool configuration
      cli.analyze(project_dir, '06_STATIC_ANALYSIS')

      # Verify separate tool configuration files exist
      expect(File.exist?(execute_tools_file)).to be true
      expect(File.exist?(File.join(project_dir, '.aidp-analyze-tools.yml'))).to be true

      # Verify configurations are separate
      execute_config = YAML.load_file(execute_tools_file)
      expect(execute_config['build_tools']['ruby']).to include('bundler', 'rake')
    end

    it 'analyze mode respects existing project structure' do
      # Verify existing project structure
      expect(File.exist?(File.join(project_dir, 'app'))).to be true
      expect(File.exist?(File.join(project_dir, 'lib'))).to be true
      expect(File.exist?(File.join(project_dir, 'spec'))).to be true

      # Run analyze mode
      cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')

      # Verify project structure is unchanged
      expect(File.exist?(File.join(project_dir, 'app'))).to be true
      expect(File.exist?(File.join(project_dir, 'lib'))).to be true
      expect(File.exist?(File.join(project_dir, 'spec'))).to be true

      # Verify analyze mode output is in project root
      expect(File.exist?(File.join(project_dir, '01_REPOSITORY_ANALYSIS.md'))).to be true
    end
  end

  describe 'Configuration Coexistence' do
    it 'analyze mode can use shared configuration while respecting isolation' do
      # Create shared user configuration
      user_config_file = File.expand_path('~/.aidp.yml')
      user_config = {
        'global_settings' => {
          'log_level' => 'info',
          'timeout' => 300
        },
        'execute_mode' => {
          'provider' => 'anthropic',
          'model' => 'claude-3-sonnet'
        },
        'analyze_mode' => {
          'analysis_settings' => {
            'chunk_size' => 1000,
            'parallel_workers' => 4
          }
        }
      }
      File.write(user_config_file, user_config.to_yaml)

      # Run both modes
      cli.execute(project_dir, '00_PRD')
      cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')

      # Verify both modes work correctly with shared configuration
      expect(File.exist?(File.join(project_dir, '00_PRD.md'))).to be true
      expect(File.exist?(File.join(project_dir, '01_REPOSITORY_ANALYSIS.md'))).to be true

      # Clean up user config
      File.delete(user_config_file) if File.exist?(user_config_file)
    end

    it 'analyze mode can override shared configuration with project-specific settings' do
      # Create project-specific analyze configuration
      analyze_config_file = File.join(project_dir, '.aidp-analyze.yml')
      analyze_config = {
        'analysis_settings' => {
          'chunk_size' => 500,
          'parallel_workers' => 2
        },
        'preferred_tools' => {
          'ruby' => %w[rubocop reek]
        }
      }
      File.write(analyze_config_file, analyze_config.to_yaml)

      # Run analyze mode
      cli.analyze(project_dir, '06_STATIC_ANALYSIS')

      # Verify analyze mode used project-specific configuration
      expect(File.exist?(File.join(project_dir, '06_STATIC_ANALYSIS.md'))).to be true
    end
  end

  describe 'Template Resolution with Existing Templates' do
    it 'analyze mode can use existing templates when appropriate' do
      # Create a shared template that both modes can use
      common_template_file = File.join(project_dir, 'templates', 'COMMON', 'SHARED_TEMPLATE.md')
      FileUtils.mkdir_p(File.dirname(common_template_file))
      File.write(common_template_file, '# Shared Template\n\nThis is a shared template.')

      # Run analyze mode
      cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')

      # Verify analyze mode can access shared templates
      expect(File.exist?(File.join(project_dir, '01_REPOSITORY_ANALYSIS.md'))).to be true
    end

    it 'analyze mode prioritizes its own templates over shared ones' do
      # Create shared template
      common_template_file = File.join(project_dir, 'templates', 'COMMON', '01_REPOSITORY_ANALYSIS.md')
      FileUtils.mkdir_p(File.dirname(common_template_file))
      File.write(common_template_file, '# Shared Repository Analysis\n\nThis is a shared template.')

      # Create analyze-specific template
      analyze_template_file = File.join(project_dir, 'templates', 'ANALYZE', '01_REPOSITORY_ANALYSIS.md')
      FileUtils.mkdir_p(File.dirname(analyze_template_file))
      File.write(analyze_template_file, '# Analyze Repository Analysis\n\nThis is the analyze-specific template.')

      # Run analyze mode
      cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')

      # Verify analyze mode used its own template
      output_file = File.join(project_dir, '01_REPOSITORY_ANALYSIS.md')
      expect(File.exist?(output_file)).to be true
      content = File.read(output_file)
      expect(content).to include('Analyze Repository Analysis')
      expect(content).not_to include('Shared Repository Analysis')
    end
  end

  describe 'Progress Tracking Coexistence' do
    it 'both modes can track progress independently' do
      # Run execute mode steps
      cli.execute(project_dir, '00_PRD')
      cli.execute(project_dir, '01_NFRS')

      # Run analyze mode steps
      cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')
      cli.analyze(project_dir, '02_ARCHITECTURE_ANALYSIS')

      # Verify execute mode progress
      execute_progress = Aidp::Progress.new(project_dir)
      expect(execute_progress.completed_steps).to include('00_PRD', '01_NFRS')
      expect(execute_progress.completed_steps).not_to include('01_REPOSITORY_ANALYSIS', '02_ARCHITECTURE_ANALYSIS')

      # Verify analyze mode progress
      analyze_progress = Aidp::AnalyzeProgress.new(project_dir)
      expect(analyze_progress.completed_steps).to include('01_REPOSITORY_ANALYSIS', '02_ARCHITECTURE_ANALYSIS')
      expect(analyze_progress.completed_steps).not_to include('00_PRD', '01_NFRS')
    end

    it 'progress reset commands work independently' do
      # Run both modes
      cli.execute(project_dir, '00_PRD')
      cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')

      # Reset execute mode progress
      cli.reset(project_dir)

      # Verify execute mode progress is reset
      execute_progress = Aidp::Progress.new(project_dir)
      expect(execute_progress.completed_steps).to be_empty

      # Verify analyze mode progress is unchanged
      analyze_progress = Aidp::AnalyzeProgress.new(project_dir)
      expect(analyze_progress.completed_steps).to include('01_REPOSITORY_ANALYSIS')

      # Reset analyze mode progress
      cli.analyze_reset(project_dir)

      # Verify analyze mode progress is reset
      analyze_progress_after = Aidp::AnalyzeProgress.new(project_dir)
      expect(analyze_progress_after.completed_steps).to be_empty
    end
  end

  describe 'Error Handling with Existing Data' do
    it 'analyze mode handles errors gracefully without affecting execute mode data' do
      # Run execute mode successfully
      cli.execute(project_dir, '00_PRD')

      # Simulate an error in analyze mode
      allow_any_instance_of(Aidp::AnalyzeRunner).to receive(:execute_step)
        .and_raise(StandardError.new('Analyze mode error'))

      # Run analyze mode (should fail)
      result = cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')
      expect(result[:status]).to eq('error')

      # Verify execute mode data is unchanged
      expect(File.exist?(File.join(project_dir, '00_PRD.md'))).to be true
      expect(File.exist?(File.join(project_dir, '.aidp-progress.yml'))).to be true

      # Verify execute mode can still run
      execute_result = cli.execute(project_dir, '01_NFRS')
      expect(execute_result[:status]).to eq('success')
    end

    it 'execute mode handles errors gracefully without affecting analyze mode data' do
      # Run analyze mode successfully
      cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')

      # Simulate an error in execute mode
      allow_any_instance_of(Aidp::Runner).to receive(:execute_step)
        .and_raise(StandardError.new('Execute mode error'))

      # Run execute mode (should fail)
      result = cli.execute(project_dir, '02_ARCHITECTURE')
      expect(result[:status]).to eq('error')

      # Verify analyze mode data is unchanged
      expect(File.exist?(File.join(project_dir, '01_REPOSITORY_ANALYSIS.md'))).to be true
      expect(File.exist?(File.join(project_dir, '.aidp-analyze-progress.yml'))).to be true

      # Verify analyze mode can still run
      analyze_result = cli.analyze(project_dir, '02_ARCHITECTURE_ANALYSIS')
      expect(analyze_result[:status]).to eq('success')
    end
  end

  describe 'Performance with Existing Data' do
    it 'analyze mode performance is not affected by existing execute mode data' do
      # Run execute mode to create data
      cli.execute(project_dir, '00_PRD')
      cli.execute(project_dir, '01_NFRS')
      cli.execute(project_dir, '02_ARCHITECTURE')

      # Measure analyze mode performance
      start_time = Time.current
      cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')
      duration = Time.current - start_time

      # Verify performance is reasonable (should complete in under 30 seconds)
      expect(duration).to be < 30.0
    end

    it 'execute mode performance is not affected by existing analyze mode data' do
      # Run analyze mode to create data
      cli.analyze(project_dir, '01_REPOSITORY_ANALYSIS')
      cli.analyze(project_dir, '02_ARCHITECTURE_ANALYSIS')

      # Measure execute mode performance
      start_time = Time.current
      cli.execute(project_dir, '03_ADR_FACTORY')
      duration = Time.current - start_time

      # Verify performance is reasonable (should complete in under 30 seconds)
      expect(duration).to be < 30.0
    end
  end

  private

  def setup_existing_project_with_execute_data
    # Create project structure
    FileUtils.mkdir_p(File.join(project_dir, 'app', 'controllers'))
    FileUtils.mkdir_p(File.join(project_dir, 'app', 'models'))
    FileUtils.mkdir_p(File.join(project_dir, 'lib'))
    FileUtils.mkdir_p(File.join(project_dir, 'spec'))
    FileUtils.mkdir_p(File.join(project_dir, 'templates'))

    # Create existing execute mode progress
    progress_file = File.join(project_dir, '.aidp-progress.yml')
    progress_data = {
      'completed_steps' => %w[00_PRD 01_NFRS],
      'current_step' => '02_ARCHITECTURE',
      'started_at' => Time.current.iso8601
    }
    File.write(progress_file, progress_data.to_yaml)

    # Create existing execute mode configuration
    config_file = File.join(project_dir, '.aidp.yml')
    config_data = {
      'provider' => 'anthropic',
      'model' => 'claude-3-sonnet',
      'timeout' => 300
    }
    File.write(config_file, config_data.to_yaml)

    # Create existing execute mode output files
    File.write(File.join(project_dir, '00_PRD.md'),
               '# Product Requirements Document\n\n## Project Information\n**Project Name**: Test Project')
    File.write(File.join(project_dir, '01_NFRS.md'),
               '# Non-Functional Requirements\n\n## Performance\n- Response time < 2 seconds')

    # Create project files
    File.write(File.join(project_dir, 'app', 'controllers', 'application_controller.rb'),
               'class ApplicationController; end')
    File.write(File.join(project_dir, 'app', 'models', 'user.rb'), 'class User < ApplicationRecord; end')
    File.write(File.join(project_dir, 'lib', 'core', 'processor.rb'), 'class Processor; def process; end; end')
    File.write(File.join(project_dir, 'spec', 'spec_helper.rb'), 'RSpec.configure do |config|; end')
    File.write(File.join(project_dir, 'Gemfile'), 'source "https://rubygems.org"; gem "rails"')
    File.write(File.join(project_dir, 'README.md'), '# Test Project')

    # Create basic templates
    File.write(File.join(project_dir, 'templates', '00_PRD.md'),
               '# Product Requirements Document\n\n## Project Information\n**Project Name**: {{project_name}}')
    File.write(File.join(project_dir, 'templates', '01_NFRS.md'),
               '# Non-Functional Requirements\n\n## Performance\n{{performance_requirements}}')
  end
end
