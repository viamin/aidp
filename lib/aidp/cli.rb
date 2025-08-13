# frozen_string_literal: true

require 'thor'
require_relative 'steps'
require_relative 'runner'
require_relative 'sync'

module Aidp
  class CLI < Thor
    desc 'steps', 'List available steps'
    def steps
      puts Aidp::Steps.list.join("\n")
    end

    desc 'detect', 'Detect which provider will be used'
    def detect
      runner = Aidp::Runner.new
      puts "Provider: #{runner.detect_provider.name}"
    rescue StandardError => e
      warn e.message
      exit 1
    end

    desc 'execute STEP', 'Run a single step (e.g., prd, nfrs, arch, …)'
    def execute(step)
      Aidp::Runner.new.run_step(step)
    rescue StandardError => e
      warn e.message
      exit 1
    end

    desc 'execute_all', 'Run all steps sequentially'
    def execute_all
      Aidp::Steps.list.each do |s|
        say_status :step, s
        Aidp::Runner.new.run_step(s)
      end
    end

    desc 'sync [STEP]', 'Copy expected outputs for STEP (or all) into the current project (no-op if missing)'
    def sync(step = nil)
      cfg = Aidp::Config.load
      if step
        outs = cfg.dig('outputs', step) || Aidp::Steps.for(step)[:outs] || []
        Aidp::Sync.to_project(outs)
      else
        Aidp::Steps.list.each do |s|
          outs = cfg.dig('outputs', s) || Aidp::Steps.for(s)[:outs] || []
          Aidp::Sync.to_project(outs)
        end
      end
      puts 'Synced.'
    end
  end
end
