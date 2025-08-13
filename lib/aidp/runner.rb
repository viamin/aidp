# frozen_string_literal: true

require 'fileutils'
require_relative 'config'
require_relative 'steps'
require_relative 'util'
require_relative 'providers/base'
require_relative 'providers/cursor'
require_relative 'providers/anthropic'
require_relative 'providers/gemini'
require_relative 'providers/macos_ui'

module Aidp
  class Runner
    PROVIDERS = {
      'cursor' => Providers::Cursor,
      'anthropic' => Providers::Anthropic,
      'gemini' => Providers::Gemini,
      'macos' => Providers::MacOSUI
    }.freeze

    def initialize(project_dir: Dir.pwd, config: Config.load)
      @project_dir = project_dir
      @config = config
    end

    def detect_provider
      explicit = @config['provider']
      return PROVIDERS[explicit].new if explicit && PROVIDERS[explicit]
      return PROVIDERS['cursor'].new    if Providers::Cursor.available?
      return PROVIDERS['anthropic'].new if Providers::Anthropic.available?
      return PROVIDERS['gemini'].new    if Providers::Gemini.available?
      return PROVIDERS['macos'].new     if Providers::MacOSUI.available?

      raise 'No supported provider found. Install Cursor CLI (preferred), Claude/Gemini CLI, or run on macOS.'
    end

    def composed_prompt(step_name)
      spec = Steps.for(step_name)
      roots = [Config.templates_root]
      body = +''
      body << "# STEP: #{step_name}\n"
      spec[:templates].each do |t|
        full = File.join(roots.first, t)
        body << "\n--- BEGIN TEMPLATE: #{t} ---\n"
        body << File.read(full)
        body << "\n--- END TEMPLATE: #{t} ---\n"
      end

      # Provide project context and explicit output paths
      outs = @config.dig('outputs', step_name) || spec[:outs] || []
      body << "\n\n# CONTEXT\n"
      body << "Project workspace: #{@project_dir}\n"
      body << "Write outputs to these exact paths (create dirs if missing):\n"
      outs.each { |o| body << "- #{o}\n" }
      body << "\nIf this step is a gate (PRD/Architecture), ask concise questions first, wait for my answers, then proceed.\n"
      body
    end

    def run_step(step_name)
      spec = Steps.for(step_name)
      outs = @config.dig('outputs', step_name) || spec[:outs] || []
      Util.ensure_dirs(outs, @project_dir)

      provider = detect_provider
      prompt = composed_prompt(step_name)

      puts "Using provider: #{provider.name}"
      provider.send(prompt: prompt)
      puts "Prompt sent. After the model finishes writing files, run:  aidp sync #{step_name}"
    end
  end
end
