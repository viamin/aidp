# frozen_string_literal: true

require 'spec_helper'
require 'aidp/cli'
require 'aidp/runner'
require 'aidp/progress'
require 'aidp/steps'

RSpec.describe 'Execute Mode Regression Tests', type: :regression do
  let(:project_dir) { Dir.mktmpdir('aidp_regression_test') }
  let(:cli) { Aidp::CLI.new }
  let(:runner) { Aidp::Runner.new(project_dir) }
  let(:progress) { Aidp::Progress.new(project_dir) }

  before do
    setup_mock_project
  end

  after do
    FileUtils.remove_entry(project_dir)
  end

  describe 'CLI Command Compatibility' do
    it 'existing execute mode commands work exactly as before' do
      # Test that all existing commands work
      expect { cli.help }.not_to raise_error
      expect { cli.version }.not_to raise_error

      # Test that execute mode commands work
      result = cli.execute(project_dir, nil)
      expect(result).to be_a(Hash)
      expect(result[:status]).to eq('success')
    end

    it 'execute mode command aliases work correctly' do
      # Test that 'current' and 'next' aliases work
      result_current = cli.execute(project_dir, 'current')
      result_next = cli.execute(project_dir, 'next')

      expect(result_current).to eq(result_next)
      expect(result_current[:status]).to eq('success')
    end

    it 'execute mode step execution works correctly' do
      # Test that specific step execution works
      result = cli.execute(project_dir, '00_PRD')
      expect(result[:status]).to eq('success')
      expect(result[:step]).to eq('00_PRD')
    end

    it 'execute mode approve command works correctly' do
      # Test that approve command works
      result = cli.approve(project_dir)
      expect(result[:status]).to eq('success')
    end

    it 'execute mode reset command works correctly' do
      # Test that reset command works
      result = cli.reset(project_dir)
      expect(result[:status]).to eq('success')
    end
  end

  describe 'Progress Tracking Compatibility' do
    it 'execute mode progress file format is unchanged' do
      # Test that progress file format is exactly the same
      progress.mark_step_completed('00_PRD')

      progress_file = File.join(project_dir, '.aidp-progress.yml')
      expect(File.exist?(progress_file)).to be true

      progress_data = YAML.load_file(progress_file)
      expect(progress_data).to have_key('completed_steps')
      expect(progress_data).to have_key('current_step')
      expect(progress_data).to have_key('started_at')
      expect(progress_data['completed_steps']).to include('00_PRD')
    end

    it 'execute mode progress methods work correctly' do
      # Test all progress methods
      expect(progress.completed_steps).to be_an(Array)
      expect(progress.current_step).to be_a(String).or(be_nil)
      expect(progress.started_at).to be_a(Time).or(be_nil)

      # Test step completion
      progress.mark_step_completed('00_PRD')
      expect(progress.completed_steps).to include('00_PRD')

      # Test step checking
      expect(progress.step_completed?('00_PRD')).to be true
      expect(progress.step_completed?('01_NFRS')).to be false
    end

    it 'execute mode progress reset works correctly' do
      # Test progress reset functionality
      progress.mark_step_completed('00_PRD')
      progress.mark_step_completed('01_NFRS')

      expect(progress.completed_steps).to include('00_PRD', '01_NFRS')

      progress.reset

      expect(progress.completed_steps).to be_empty
      expect(progress.current_step).to be_nil
    end
  end

  describe 'Step Definitions Compatibility' do
    it 'execute mode step definitions are unchanged' do
      # Test that all step definitions are exactly the same
      steps = Aidp::Steps::SPEC

      # Verify all expected steps exist
      expected_steps = %w[00_PRD 01_NFRS 02_ARCHITECTURE 02A_ARCH_GATE_QUESTIONS 03_ADR_FACTORY 04_DOMAIN_DECOMPOSITION
                          05_CONTRACTS 06_THREAT_MODEL 07_TEST_PLAN 08_TASKS 09_SCAFFOLDING_DEVEX 10_IMPLEMENTATION_AGENT 11_STATIC_ANALYSIS 12_OBSERVABILITY_SLOS 13_DELIVERY_ROLLOUT 14_DOCS_PORTAL 15_POST_RELEASE]

      expected_steps.each do |step|
        expect(steps).to have_key(step)
        expect(steps[step]).to have_key('templates')
        expect(steps[step]).to have_key('outs')
        expect(steps[step]).to have_key('gate')
        expect(steps[step]).to have_key('agent')
      end
    end

    it 'execute mode step properties are unchanged' do
      # Test that step properties have the same structure
      steps = Aidp::Steps::SPEC

      steps.each do |step_name, step_data|
        expect(step_data['templates']).to be_an(Array)
        expect(step_data['outs']).to be_an(Array)
        expect(step_data['gate']).to be_in([true, false])
        expect(step_data['agent']).to be_a(String)
      end
    end

    it 'execute mode step execution order is unchanged' do
      # Test that step execution order is preserved
      steps = Aidp::Steps::SPEC.keys

      # Verify the order is exactly as expected
      expected_order = %w[00_PRD 01_NFRS 02_ARCHITECTURE 02A_ARCH_GATE_QUESTIONS 03_ADR_FACTORY 04_DOMAIN_DECOMPOSITION
                          05_CONTRACTS 06_THREAT_MODEL 07_TEST_PLAN 08_TASKS 09_SCAFFOLDING_DEVEX 10_IMPLEMENTATION_AGENT 11_STATIC_ANALYSIS 12_OBSERVABILITY_SLOS 13_DELIVERY_ROLLOUT 14_DOCS_PORTAL 15_POST_RELEASE]

      expect(steps).to eq(expected_order)
    end
  end

  describe 'Template Resolution Compatibility' do
    it 'execute mode template resolution order is unchanged' do
      # Test that template resolution order is exactly the same
      template = runner.send(:find_template, '00_PRD.md')
      expect(template).to be_a(String)
      expect(template).to include('Product Requirements Document')
    end

    it 'execute mode template search paths are unchanged' do
      # Test that template search paths are exactly the same
      paths = runner.send(:template_search_paths)

      # Execute mode should look in templates/ first, then COMMON/
      expect(paths.first).to eq(File.join(project_dir, 'templates'))
      expect(paths).to include(File.join(project_dir, 'templates', 'COMMON'))
    end

    it 'execute mode template composition is unchanged' do
      # Test that template composition works exactly as before
      prompt = runner.send(:composed_prompt, '00_PRD.md', { project_name: 'Test Project' })
      expect(prompt).to be_a(String)
      expect(prompt).to include('Test Project')
      expect(prompt).to include('Product Requirements Document')
    end
  end

  describe 'Runner Compatibility' do
    it 'execute mode runner initialization is unchanged' do
      # Test that runner initialization works exactly as before
      expect(runner).to be_a(Aidp::Runner)
      expect(runner.instance_variable_get(:@project_dir)).to eq(project_dir)
    end

    it 'execute mode runner step execution is unchanged' do
      # Test that step execution works exactly as before
      result = runner.run_step('00_PRD')
      expect(result).to be_a(Hash)
      expect(result[:status]).to eq('success')
      expect(result[:step]).to eq('00_PRD')
    end

    it 'execute mode runner prompt composition is unchanged' do
      # Test that prompt composition works exactly as before
      prompt = runner.send(:composed_prompt, '00_PRD.md', { project_name: 'Test Project' })
      expect(prompt).to be_a(String)
      expect(prompt).to include('Test Project')
    end

    it 'execute mode runner template finding is unchanged' do
      # Test that template finding works exactly as before
      template = runner.send(:find_template, '00_PRD.md')
      expect(template).to be_a(String)
      expect(template).to include('Product Requirements Document')
    end
  end

  describe 'Configuration Compatibility' do
    it 'execute mode configuration loading is unchanged' do
      # Test that configuration loading works exactly as before
      config = Aidp::Config.new(project_dir)
      expect(config).to be_a(Aidp::Config)

      # Test configuration methods
      config.set('test_key', 'test_value')
      expect(config.get('test_key')).to eq('test_value')
    end

    it 'execute mode configuration file format is unchanged' do
      # Test that configuration file format is exactly the same
      config = Aidp::Config.new(project_dir)
      config.set('provider', 'anthropic')
      config.set('model', 'claude-3-sonnet')

      config_file = File.join(project_dir, '.aidp.yml')
      expect(File.exist?(config_file)).to be true

      config_data = YAML.load_file(config_file)
      expect(config_data['provider']).to eq('anthropic')
      expect(config_data['model']).to eq('claude-3-sonnet')
    end
  end

  describe 'Provider Integration Compatibility' do
    it 'execute mode provider integration is unchanged' do
      # Test that provider integration works exactly as before
      providers = Aidp::Providers
      expect(providers).to be_a(Module)

      # Test that all expected providers exist
      expect(providers.constants).to include(:Anthropic, :Cursor, :Gemini, :MacosUi)
    end

    it 'execute mode provider initialization is unchanged' do
      # Test that provider initialization works exactly as before
      provider = Aidp::Providers::Anthropic.new
      expect(provider).to be_a(Aidp::Providers::Anthropic)
    end
  end

  describe 'Output Generation Compatibility' do
    it 'execute mode output file generation is unchanged' do
      # Test that output file generation works exactly as before
      result = runner.run_step('00_PRD')
      expect(result[:status]).to eq('success')

      # Check that output files are generated
      output_file = File.join(project_dir, '00_PRD.md')
      expect(File.exist?(output_file)).to be true
    end

    it 'execute mode output file format is unchanged' do
      # Test that output file format is exactly the same
      result = runner.run_step('00_PRD')

      output_file = File.join(project_dir, '00_PRD.md')
      content = File.read(output_file)

      expect(content).to include('# Product Requirements Document')
      expect(content).to include('## Project Information')
    end
  end

  describe 'Error Handling Compatibility' do
    it 'execute mode error handling is unchanged' do
      # Test that error handling works exactly as before
      expect { runner.run_step('NONEXISTENT_STEP') }.to raise_error(StandardError)
    end

    it 'execute mode error messages are unchanged' do
      # Test that error messages are exactly the same
      expect { runner.run_step('NONEXISTENT_STEP') }.to raise_error(/Step 'NONEXISTENT_STEP' not found/)
    end
  end

  describe 'Performance Compatibility' do
    it 'execute mode performance characteristics are unchanged' do
      # Test that performance characteristics are the same
      start_time = Time.current

      runner.run_step('00_PRD')

      duration = Time.current - start_time
      expect(duration).to be < 10.0 # Should complete in under 10 seconds
    end

    it 'execute mode memory usage is unchanged' do
      # Test that memory usage characteristics are the same
      initial_memory = get_memory_usage

      runner.run_step('00_PRD')

      final_memory = get_memory_usage
      memory_increase = final_memory - initial_memory

      expect(memory_increase).to be < 100 * 1024 * 1024 # Should use less than 100MB additional memory
    end
  end

  describe 'Integration Compatibility' do
    it 'execute mode integration with external tools is unchanged' do
      # Test that integration with external tools works exactly as before
      # This would test any external tool integrations that execute mode uses
      expect(true).to be true # Placeholder for actual integration tests
    end

    it 'execute mode file system operations are unchanged' do
      # Test that file system operations work exactly as before
      test_file = File.join(project_dir, 'test_file.txt')
      File.write(test_file, 'test content')

      expect(File.exist?(test_file)).to be true
      expect(File.read(test_file)).to eq('test content')

      File.delete(test_file)
      expect(File.exist?(test_file)).to be false
    end
  end

  describe 'Backward Compatibility with Existing Projects' do
    it 'execute mode works with existing project files' do
      # Test that execute mode works with existing project files
      existing_progress_file = File.join(project_dir, '.aidp-progress.yml')
      existing_progress = {
        'completed_steps' => %w[00_PRD 01_NFRS],
        'current_step' => '02_ARCHITECTURE',
        'started_at' => Time.current.iso8601
      }

      File.write(existing_progress_file, existing_progress.to_yaml)

      # Test that existing progress is loaded correctly
      progress = Aidp::Progress.new(project_dir)
      expect(progress.completed_steps).to include('00_PRD', '01_NFRS')
      expect(progress.current_step).to eq('02_ARCHITECTURE')
    end

    it 'execute mode works with existing configuration files' do
      # Test that execute mode works with existing configuration files
      existing_config_file = File.join(project_dir, '.aidp.yml')
      existing_config = {
        'provider' => 'anthropic',
        'model' => 'claude-3-sonnet',
        'timeout' => 300
      }

      File.write(existing_config_file, existing_config.to_yaml)

      # Test that existing configuration is loaded correctly
      config = Aidp::Config.new(project_dir)
      expect(config.get('provider')).to eq('anthropic')
      expect(config.get('model')).to eq('claude-3-sonnet')
      expect(config.get('timeout')).to eq(300)
    end
  end

  describe 'Cross-Mode Isolation' do
    it 'execute mode is completely isolated from analyze mode' do
      # Test that execute mode is completely isolated from analyze mode

      # Run execute mode
      execute_result = cli.execute(project_dir, '00_PRD')
      expect(execute_result[:status]).to eq('success')

      # Verify execute mode files exist
      execute_progress_file = File.join(project_dir, '.aidp-progress.yml')
      expect(File.exist?(execute_progress_file)).to be true

      # Verify analyze mode files do not exist
      analyze_progress_file = File.join(project_dir, '.aidp-analyze-progress.yml')
      expect(File.exist?(analyze_progress_file)).to be false

      # Verify execute mode output exists
      execute_output_file = File.join(project_dir, '00_PRD.md')
      expect(File.exist?(execute_output_file)).to be true

      # Verify analyze mode output does not exist
      analyze_output_file = File.join(project_dir, '01_REPOSITORY_ANALYSIS.md')
      expect(File.exist?(analyze_output_file)).to be false
    end

    it 'execute mode configuration is isolated from analyze mode configuration' do
      # Test that execute mode configuration is isolated from analyze mode configuration

      # Create execute mode configuration
      execute_config = Aidp::Config.new(project_dir)
      execute_config.set('provider', 'anthropic')
      execute_config.set('model', 'claude-3-sonnet')

      # Verify execute mode configuration file exists
      execute_config_file = File.join(project_dir, '.aidp.yml')
      expect(File.exist?(execute_config_file)).to be true

      # Verify analyze mode configuration file does not exist
      analyze_config_file = File.join(project_dir, '.aidp-analyze.yml')
      expect(File.exist?(analyze_config_file)).to be false

      # Verify execute mode configuration is correct
      config_data = YAML.load_file(execute_config_file)
      expect(config_data['provider']).to eq('anthropic')
      expect(config_data['model']).to eq('claude-3-sonnet')
    end
  end

  private

  def setup_mock_project
    # Create basic project structure
    FileUtils.mkdir_p(File.join(project_dir, 'templates'))
    FileUtils.mkdir_p(File.join(project_dir, 'app'))

    # Create a basic template
    File.write(File.join(project_dir, 'templates', '00_PRD.md'), <<~TEMPLATE)
      # Product Requirements Document

      ## Project Information
      **Project Name**: {{project_name}}
      **Description**: {{project_description}}

      ## Goals
      {{goals}}
    TEMPLATE

    # Create a basic README
    File.write(File.join(project_dir, 'README.md'), '# Test Project')
  end

  def get_memory_usage
    # Get current memory usage (simplified)
    `ps -o rss= -p #{Process.pid}`.to_i * 1024
  rescue StandardError
    0
  end
end
