#!/usr/bin/env ruby
# frozen_string_literal: true

require "time"
require "tty-prompt"

module Aidp
  class CLI
    # Wrapper around Aidp::Setup::Wizard to preserve existing CLI entry points.
    class FirstRunWizard
      include Aidp::MessageDisplay

      def self.ensure_config(project_dir, non_interactive: false, prompt: TTY::Prompt.new)
        return true if Aidp::Config.config_exists?(project_dir)

        wizard = new(project_dir, prompt: prompt)

        if non_interactive
          wizard.create_minimal_config
          wizard.send(:display_message, "Created minimal configuration (non-interactive default)", type: :success)
          true
        else
          wizard.run
        end
      end

      def self.setup_config(project_dir, non_interactive: false, prompt: TTY::Prompt.new)
        if non_interactive
          new(project_dir, prompt: prompt).send(:display_message, "Configuration setup skipped in non-interactive environment", type: :info)
          return true
        end

        new(project_dir, prompt: prompt).run
      end

      def initialize(project_dir, prompt: TTY::Prompt.new)
        @project_dir = project_dir
        @prompt = prompt
      end

      def run
        wizard = Aidp::Setup::Wizard.new(@project_dir, prompt: @prompt)
        wizard.run
      end

      def create_minimal_config
        Aidp::ConfigPaths.ensure_config_dir(@project_dir)
        minimal = {
          "schema_version" => Aidp::Setup::Wizard::SCHEMA_VERSION,
          "generated_by" => "aidp setup wizard minimal",
          "generated_at" => Time.now.utc.iso8601,
          "providers" => {
            "llm" => {
              "name" => "cursor",
              "model" => "cursor-agent",
              "temperature" => 0.2,
              "max_tokens" => 1024
            }
          },
          "work_loop" => {
            "test" => {
              "unit" => "bundle exec rspec",
              "timeout_seconds" => 1800
            }
          }
        }

        File.write(Aidp::ConfigPaths.config_file(@project_dir), minimal.to_yaml)
      end
    end
  end
end
